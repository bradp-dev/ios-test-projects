//
//  ActivityManager.swift
//  liveactivitiestest
//
//  Created by Brad Priddy on 10/29/25.
//

import Foundation
import ActivityKit
import Combine
import OSLog
import UserNotifications
import UIKit

/// A manager for handling Live Activities for auctions.
/// Responsible for starting, updating, ending activities, and managing tokens and registrations.
public final class ActivityManager: ObservableObject {
    // MARK: - Published State (Public Read / Internal Write)

    /// The ID of the most recently started activity (if any).
    @MainActor @Published private(set) var activityID: String?

    /// The most recent update token (hex string) for the current activity (if any).
    @MainActor @Published private(set) var activityToken: String?

    /// Mapping from activity IDs to their update tokens.
    @MainActor @Published var activityTokens: [String: String] = [:]

    /// The currently running Live Activities.
    @MainActor @Published var runningActivities: [Activity<LiveAuctionAttributes>] = []

    /// Tokens received from push‑to‑start (pending registration).
    @MainActor @Published var pushToStartTokens: [String: String] = [:]

    /// Already registered push‑to‑start tokens (to avoid duplicate registration).
    @MainActor @Published public var registeredPushToStartTokens: Set<String> = []

    /// Tracks registration and token state per auction ID.
    @MainActor @Published private var auctionActivityTracking: [String: ActivityTracking] = [:]

    private var ptsListenerTask: Task<Void, Never>?
    private var updatesListenerTask: Task<Void, Never>?
    private var ptsRetryTask: Task<Void, Never>?
    private var ptsRetryAttempts = 0
    private let ptsRetryMaxAttempts = 3
    private let ptsRetryDelayNs: UInt64 = 10_000_000_000 // 10 seconds
    
    private let primeCooldown: TimeInterval = 60 // 1 minutes
    
    // MARK: - Singleton Instance

    /// Shared singleton instance of `ActivityManager`.
    static let shared = ActivityManager()

    // MARK: - Internal Types / Helpers

    /// Internal struct to track token registration state for a given auction’s activity.
    private struct ActivityTracking {
        let activityID: String
        var updateToken: String?
        var isTokenRegistered: Bool
        var isRegistering: Bool
        let startedAt: Date

        init(
            activityID: String,
            updateToken: String? = nil,
            isTokenRegistered: Bool = false,
            isRegistering: Bool = false,
            startedAt: Date = Date()
        ) {
            self.activityID = activityID
            self.updateToken = updateToken
            self.isTokenRegistered = isTokenRegistered
            self.isRegistering = isRegistering
            self.startedAt = startedAt
        }

        /// Set the update token and registration status.
        mutating func setToken(_ token: String, registered: Bool) {
            self.updateToken = token
            self.isTokenRegistered = registered
        }
    }

    /// Enum to decide how to act when a new token arrives.
    private enum RegistrationAction {
        case skip
        case endNewActivity
        case endOldAndRegisterNew(oldActivityId: String)
        case register
    }
    
    private enum RegistrationResult {
        case success
        case unauthorized
        case otherError
    }

    // MARK: - Initialization
    /// Update your init to start listeners properly
    init() {
        print("ActivityManager init")
        
        // Start listeners immediately but they won't receive tokens until after priming
        startPersistentListeners()
    }
    private func startPersistentListeners() {
        if ptsListenerTask == nil || ptsListenerTask?.isCancelled == true {
            ptsListenerTask = Task(priority: .high) { [weak self] in
                guard let self else { return }
                print("Starting push-to-start listener")
                await self.listenForPushToStartTokens()
                // If we ever leave the loop, mark task as gone so we can restart later.
                await MainActor.run { self.ptsListenerTask = nil }
            }
        }

        if updatesListenerTask == nil || updatesListenerTask?.isCancelled == true {
            updatesListenerTask = Task(priority: .background) { [weak self] in
                guard let self else { return }
                print("Starting activity updates listener")
                await self.refreshRunningActivities()
                await self.listenForActivityUpdates()
                await MainActor.run { self.updatesListenerTask = nil }
            }
        }
    }
    
    // MARK: - Public nudge when APNs is ready
    @MainActor
    public func apnsBecameReady() async {
        print("APNS ready - ensuring push-to-start tokens")

        if !pushToStartTokens.isEmpty {
            print("Push-to-start tokens already exist: \(pushToStartTokens.count)")
            return
        }

        if hasRecentlyPrimed(cooldown: primeCooldown) {
            print("Recently primed (<= \(Int(primeCooldown))s), skipping")
            return
        }

        await primePushToStartSystem()
    }

    // MARK: - Priming
    /// Create a minimal activity to trigger push-to-start token generation
    /// This is necessary because iOS doesn't generate tokens until it "sees" an activity
    private func primePushToStartSystem() async {
        print("Priming push-to-start system...")
        
        // Create minimal attributes
        let attributes = LiveAuctionAttributes(
            carName: "",
            isUserOwner: false,
            auctionId: "sys-prime-\(Int.random(in: 10000...99999))",
            notificationTypeId: 12
        )
        
        let state = LiveAuctionAttributes.ContentState(
            currentBid: 0,
            endDateUnix: Date().timeIntervalSince1970,
            isAuctionLive: false,
            didWinAuction: false,
            auctionCloseStatusText: "",
            linkedURL: nil,
            lastMinute: false,
            hasReserve: false
        )
        
        do {
            // Create with .token to ensure push infrastructure initializes
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date()),
                pushType: .token
            )
            
            print("Primer activity created: \(activity.id)")
            
            // End immediately - we just need to trigger the system
            await activity.end(
                ActivityContent(state: state, staleDate: Date()),
                dismissalPolicy: .immediate
            )
            
            // Mark that we've primed
            UserDefaults.standard.set(Date(), forKey: "com.carsandbids.lastPTSPrime")
            
            print("Primer complete - tokens should start flowing within seconds")
        } catch {
            print("Primer failed: \(error)")
        }
    }
    
    /// Check if we've primed recently (within last hour)
    private func hasRecentlyPrimed(cooldown: TimeInterval? = nil) -> Bool {
        let window = cooldown ?? primeCooldown
        guard let lastPrime = UserDefaults.standard.object(forKey: "com.carsandbids.lastPTSPrime") as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastPrime) < window
    }
    
    // MARK: - Listeners
    /// Enhanced listener that logs properly and handles edge cases
    private func listenForPushToStartTokens() async {
        var tokenCount = 0
        let startTime = Date()
        
        // Monitor for timeout
        var timeoutMonitor = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            if tokenCount == 0 {
                print("No push-to-start token after 30s")
                print("This is normal on first launch - token will arrive after APNS priming")
            }
        }
        
        // Main listener loop
        for await pushToken in Activity<LiveAuctionAttributes>.pushToStartTokenUpdates {
            tokenCount += 1
            timeoutMonitor.cancel()
            
            let elapsed = Date().timeIntervalSince(startTime)
            let pushTokenString = pushToken.map { String(format: "%02x", $0) }.joined()
            
            print("Received push-to-start token #\(tokenCount) after \(elapsed)s")
            print("Token: \(pushTokenString)")
            
            // Store token
            await MainActor.run {
                self.pushToStartTokens[pushTokenString] = "Pending"
                self.ptsRetryTask?.cancel()
                self.ptsRetryTask = nil
                self.ptsRetryAttempts = 0
            }

            await attemptTokenRegistration(pushTokenString)

            
            // Reset timeout monitor for next token
            let newMonitor = Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                print("No new tokens for 5 minutes (normal)")
            }
            timeoutMonitor = newMonitor
        }
        
        print("Push-to-start iterator ended unexpectedly after \(tokenCount) tokens")
    }
    
    
    /// Continuously listens to incoming Live Activity updates and delegates token updates.
    private func listenForActivityUpdates() async {
        for await activityData in Activity<LiveAuctionAttributes>.activityUpdates {
print("Update Listener - New activity detected for auction \(activityData.attributes.auctionId)")

            Task.detached { [weak self] in
                guard let self else {
                    print("Update listener - Lost reference to self in init, aborting...")
                    return
                }
                for await tokenData in activityData.pushTokenUpdates {
                    print("Update listener - handle token update")
                    await self.handleUpdateToken(tokenData, for: activityData)
                }
            }
        }
    }
    
    // MARK: - Push‑to‑Start Token Handling
    
    /// Returns the first push-to-start token we’ve seen (if any).
    @MainActor
    public func currentPushToStartToken() -> String? {
        // You said “first one and should be only one”; pick the first key deterministically.
        return pushToStartTokens.keys.sorted().first
    }
    
    /// Register the first push-to-start token if available.
    /// Useful to call right after login completes.
    public func registerFirstPushToStartTokenIfAvailable() async {
        let token = await MainActor.run { self.currentPushToStartToken() }
        guard let token else {
            print("No PTS token available to register")
            return
        }
        await attemptTokenRegistration(token)
    }

    /// Register any deferred PTS tokens (those we received while logged out).
    /// Safe to call multiple times; uses `registeredPushToStartTokens` to avoid duplicates.
    // Update existing method to accept a watchdog flag and wire cancellation
    public func registerAnyDeferredPushToStartTokens(withWatchdog: Bool = true) async {
        // Snapshot tokens that aren’t registered yet
        let tokensToTry = await MainActor.run {
            pushToStartTokens
                .filter { !registeredPushToStartTokens.contains($0.key) }
                .map { $0.key }
        }

        if tokensToTry.isEmpty {
            print("No deferred PTS tokens to register")

            if withWatchdog {
                // Start a guarded retry loop (no-ops if already running)
                schedulePTSWatchdogRetry()
            }
            return
        }

        // If we have tokens, stop any running watchdog before registering
        await MainActor.run {
            ptsRetryTask?.cancel()
            ptsRetryTask = nil
            ptsRetryAttempts = 0
        }

        print("Registering \(tokensToTry.count) deferred PTS token(s)")
        for token in tokensToTry {
            await attemptTokenRegistration(token)
        }
    }
    
    private func schedulePTSWatchdogRetry() {
        if ptsRetryTask != nil { return }
        ptsRetryAttempts = 0

        ptsRetryTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, ptsRetryAttempts < ptsRetryMaxAttempts {
                ptsRetryAttempts += 1
                print("PTS watchdog attempt \(ptsRetryAttempts)/\(ptsRetryMaxAttempts)")

                // Ensure the listener tasks are alive.
                self.startPersistentListeners()

                // Re-prime the APNs/PTS path.
                await self.primePushToStartSystem()

                try? await Task.sleep(nanoseconds: ptsRetryDelayNs)

                let hasToken = await MainActor.run { !self.pushToStartTokens.isEmpty }
                if hasToken {
                    print("PTS watchdog: token detected, registering…")
                    await self.registerAnyDeferredPushToStartTokens(withWatchdog: false)
                    break
                }
            }

            await MainActor.run { self.ptsRetryTask = nil }
            if self.ptsRetryAttempts >= self.ptsRetryMaxAttempts {
                print("PTS watchdog exhausted attempts")
            }
        }
    }
    
    private func attemptTokenRegistration(_ token: String) async {
        let alreadyRegistered = await MainActor.run {
            self.registeredPushToStartTokens.contains(token)
        }
        
        guard !alreadyRegistered else {
            print("Token already registered")
            return
        }
        
        do {
            print("Registering push-to-start token...")
   
            await MainActor.run {
                self.registeredPushToStartTokens.insert(token)
                self.pushToStartTokens[token] = "Registered"
            }
            
            print("Token registered successfully")
            
        } catch {
            print("Registration failed: \(error)")
            
            await MainActor.run {
                self.pushToStartTokens[token] = "Failed"
            }
        }
    }

    /// Clears all registered push-to-start tokens (e.g. on logout).
    public func clearRegisteredPushToStartTokens() async {
        await MainActor.run {
            self.registeredPushToStartTokens.removeAll()
print("Cleared all registered push-to-start tokens")
        }
    }
    
    // MARK: - Update Token Handling
    /// Handle a token update from ActivityKit, register it if needed, and update tracking state.
    private func handleUpdateToken(_ tokenData: Data?, for activityData: Activity<LiveAuctionAttributes>) async {
        guard let tokenData else {
print("Handle Update Token - Token data is nil aborting...")
            return
        }
        let updateToken = tokenData.map { String(format: "%02x", $0) }.joined()
        let auctionId = activityData.attributes.auctionId
        let currentActivityId = activityData.id

        // Atomically check and claim registration lock
        let registrationResult = await MainActor.run { () -> RegistrationAction in
            // Check if we already have an activity for this auction
            if let existing = self.auctionActivityTracking[auctionId] {
                if existing.activityID != currentActivityId {
                    // Different activity exists for this auction
                    print("Duplicate activity detected! Auction \(auctionId) already has activity \(existing.activityID), but got token for \(currentActivityId)")

                    if !existing.isTokenRegistered && !existing.isRegistering {
                        // Old activity's token was never registered - end old, register new
                        print("Old activity \(existing.activityID) not registered. Will end it.")
                        return .endOldAndRegisterNew(oldActivityId: existing.activityID)
                    } else {
                        // Old activity registered or registering - ignore new
                        print("Old activity \(existing.activityID) has precedence. Ignoring new activity.")
                        return .endNewActivity
                    }
                }

                // Same activity - check if already handled
                if existing.isTokenRegistered {
                    print("Token already registered")
                    return .skip
                }
                if existing.isRegistering {
                    print("Registration in progress")
                    return .skip
                }
                // Check if same token
                if let existingToken = self.activityTokens[currentActivityId],
                   existingToken == updateToken {
                    print("Token already saved")
                    return .skip
                }
            }

            // Claim the registration lock
            self.activityTokens[currentActivityId] = updateToken
            self.auctionActivityTracking[auctionId] = ActivityTracking(
                activityID: currentActivityId,
                updateToken: updateToken,
                isTokenRegistered: false,
                isRegistering: true
            )

            return .register
        }

        // Handle the action
        switch registrationResult {
        case .skip:
            return

        case .endNewActivity:
            await endActivity(activityID: currentActivityId)
            return

        case .endOldAndRegisterNew(let oldActivityId):
            // Remove old activity tracking first
            await MainActor.run {
                self.auctionActivityTracking.removeValue(forKey: auctionId)
                self.activityTokens.removeValue(forKey: oldActivityId)
            }
            await endActivity(activityID: oldActivityId)

            // Now claim lock for new activity
            await MainActor.run {
                self.activityTokens[currentActivityId] = updateToken
                self.auctionActivityTracking[auctionId] = ActivityTracking(
                    activityID: currentActivityId,
                    updateToken: updateToken,
                    isTokenRegistered: false,
                    isRegistering: true
                )
            }
            // Fall through to registration

        case .register:
            break
        }

        // Perform registration with auth retry
        await registerTokenWithAuthRetry(
            updateToken: updateToken,
            auctionId: auctionId,
            currentActivityId: currentActivityId,
            activityData: activityData
        )
        
        await self.refreshRunningActivities()
    }

    // NEW: Helper method with auth-aware retry
    private func registerTokenWithAuthRetry(
        updateToken: String,
        auctionId: String,
        currentActivityId: String,
        activityData: Activity<LiveAuctionAttributes>
    ) async {
        print("Registering update token: \(updateToken) for auction \(auctionId)")

    }

    private func attemptUpdateTokenRegistration(
        updateToken: String,
        notificationType: Int,
        auctionId: String
    ) async -> RegistrationResult {
        return .success
    }

    // NEW: Helper to release lock on failure
    private func releaseLock(auctionId: String, activityId: String) async {
        await MainActor.run {
            if var tracking = self.auctionActivityTracking[auctionId],
               tracking.activityID == activityId {
                tracking.isTokenRegistered = false
                tracking.isRegistering = false
                self.auctionActivityTracking[auctionId] = tracking
            }
        }
    }

    // MARK: - Running Activity State
    /// Refresh the `runningActivities` and `activityTokens` based on ActivityKit.
    @MainActor
    private func refreshRunningActivities() async {
        runningActivities = Activity<LiveAuctionAttributes>.activities
        activityTokens = Dictionary(uniqueKeysWithValues:
            runningActivities.map {
                ($0.id, $0.pushToken?.map { String(format: "%02x", $0) }.joined() ?? "")
            })
    }

    // MARK: - Start / Update / End Activities

    /// Start (or reuse) a Live Activity tied to an auction.
    ///
    /// - Parameters:
    ///   - relevanceScore: The score determining ranking of this activity.
    ///   - carName: Name of the car being auctioned.
    ///   - isUserOwner: Whether the current user is the owner of auction.
    ///   - auctionId: Unique identifier for the auction.
    ///   - currentBid: The current highest bid.
    ///   - endDate: When the auction ends.
    ///   - linkedURL: Deep link to view auction.
    ///   - lastMinute: Whether auction is in final minute.
    ///   - onTokenReceived: Callback when push token is delivered.
    /// - Returns: Activity ID (existing or newly created), or `nil` if starting failed.
    @discardableResult
    func startAuctionActivity(
        relevanceScore: Double,
        carName: String,
        isUserOwner: Bool,
        auctionId: String,
        currentBid: Double,
        endDate: Date,
        linkedURL: String,
        lastMinute: Bool,
        hasReserve: Bool,
        onTokenReceived: ((String, String) -> Void)? = nil
    ) async -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not authorized.")
            return nil
        }

        // Check for existing activity for this auction
        let existingTracking = await MainActor.run {
            self.auctionActivityTracking[auctionId]
        }

        if let existing = existingTracking {
print("Found existing activity \(existing.activityID) for auction \(auctionId)")

            if !existing.isTokenRegistered, let oldToken = existing.updateToken {
                // Token exists but was never successfully registered
                print("Old activity \(existing.activityID) has unregistered token. Retrying registration.")
                // Retry registration of old token
                do {
                    print("Successfully registered old token on retry: \(oldToken)")

                    // Mark as registered
                    await MainActor.run {
                        if var tracking = self.auctionActivityTracking[auctionId] {
                            tracking.isTokenRegistered = true
                            self.auctionActivityTracking[auctionId] = tracking
                        }
                    }

                    // Don’t start new activity — old one is now valid
                    print("Using existing activity after successful token registration")
                    return existing.activityID

                } catch {
                    print("Retry registration failed: \(error.localizedDescription). Ending old activity.")
                    // End the old broken activity
                    await endActivity(activityID: existing.activityID)
                }
            } else if existing.isTokenRegistered {
                // Activity exists and token is already registered — reuse it
                print("Activity already exists with registered token. Using existing activity.")
                return existing.activityID
            }
        }

        // Create new activity
        let attributes = LiveAuctionAttributes(
            carName: carName,
            isUserOwner: isUserOwner,
            auctionId: auctionId,
            notificationTypeId: isUserOwner ? 5 : 12
        )

        let state = LiveAuctionAttributes.ContentState(
            currentBid: currentBid,
            endDateUnix: endDate.timeIntervalSince1970,
            isAuctionLive: true,
            didWinAuction: false,
            auctionCloseStatusText: "",
            linkedURL: URL(string: linkedURL),
            lastMinute: lastMinute,
            hasReserve: hasReserve
        )

        print("Starting new live activity for auction \(auctionId) with relevance: \(relevanceScore)")

        guard let activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil, relevanceScore: relevanceScore),
            pushType: .token
        ) else {
            print("Failed to create activity")
            return nil
        }

        // Track the new activity
        await MainActor.run {
            self.activityID = activity.id
            self.auctionActivityTracking[auctionId] = ActivityTracking(
                activityID: activity.id,
                updateToken: nil,
                isTokenRegistered: false
            )
        }

        // Listen for token updates
        Task.detached { [weak self] in
            guard let self else { return }
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    print("Received update token: \(token)")
                    self.activityTokens[activity.id] = token
                    onTokenReceived?(activity.id, token)
                }
            }
        }

        await refreshRunningActivities()
        return activity.id
    }

    /// Retrieves an active `Activity` by its ID.
    ///
    /// - Parameter id: The activity ID to search for.
    /// - Returns: The `Activity<LiveAuctionAttributes>` if found, else `nil`.
    func getActivity(by id: String) -> Activity<LiveAuctionAttributes>? {
        Activity<LiveAuctionAttributes>.activities.first { $0.id == id }
    }

    /// Update an existing auction Live Activity with new state values.
    ///
    /// - Parameters:
    ///   - relevanceScore: Updated relevance score.
    ///   - activityID: ID of the activity to update.
    ///   - newBid: Updated current bid.
    ///   - endDate: Updated end date.
    ///   - isAuctionLive: Whether the auction is still running.
    ///   - didWinAuction: Whether the user won (if closed).
    ///   - auctionCloseStatusText: Text to display when auction closes.
    ///   - linkedURL: Deep link to auction.
    ///   - lastMinute: Whether it is in the last minute.
    func updateAuctionActivity(
        relevanceScore: Double,
        activityID: String,
        newBid: Double,
        endDate: Date,
        isAuctionLive: Bool,
        didWinAuction: Bool,
        auctionCloseStatusText: String,
        linkedURL: String,
        lastMinute: Bool,
        hasReserve: Bool
    ) async {
        print("Updating activity \(activityID)")
        guard let runningActivity = Activity<LiveAuctionAttributes>.activities
            .first(where: { $0.id == activityID }) else { return }

        let updatedState = LiveAuctionAttributes.ContentState(
            currentBid: newBid,
            endDateUnix: endDate.timeIntervalSince1970,
            isAuctionLive: isAuctionLive,
            didWinAuction: didWinAuction,
            auctionCloseStatusText: auctionCloseStatusText,
            linkedURL: URL(string: linkedURL),
            lastMinute: lastMinute,
            hasReserve: hasReserve
        )

        await runningActivity.update(
            ActivityContent(state: updatedState, staleDate: nil, relevanceScore: relevanceScore)
        )
        await refreshRunningActivities()
    }

    /// Ends (or dismisses) a specific Live Activity by its ID.
    ///
    /// - Parameter activityID: The ID of the activity to end.
    func endActivity(activityID: String) async {
        print("Ending activity \(activityID)")
        guard let runningActivity = Activity<LiveAuctionAttributes>.activities
            .first(where: { $0.id == activityID }) else { return }

        let auctionId = runningActivity.attributes.auctionId

        let endingState = LiveAuctionAttributes.ContentState(
            currentBid: 0,
            endDateUnix: Date().timeIntervalSince1970,
            isAuctionLive: false,
            didWinAuction: false,
            auctionCloseStatusText: "",
            linkedURL: URL(string: ""),
            lastMinute: false,
            hasReserve: false
        )

        await runningActivity.end(
            ActivityContent(state: endingState, staleDate: Date()),
            dismissalPolicy: .immediate
        )

        await MainActor.run {
            self.activityTokens.removeValue(forKey: activityID)
            self.auctionActivityTracking.removeValue(forKey: auctionId)

            if self.activityID == activityID {
                self.activityID = nil
                self.activityToken = nil
            }
        }

        await refreshRunningActivities()
    }

    /// Cancels all currently running Live Activities and clears internal tracking state.
    func cancelAllRunningActivities() async {
        print("Cancelling all running activities")

        for activity in Activity<LiveAuctionAttributes>.activities {
            let endingState = LiveAuctionAttributes.ContentState(
                currentBid: 0,
                endDateUnix: Date().timeIntervalSince1970,
                isAuctionLive: false,
                didWinAuction: false,
                auctionCloseStatusText: "",
                linkedURL: URL(string: ""),
                lastMinute: false,
                hasReserve: false
            )
            await activity.end(
                ActivityContent(state: endingState, staleDate: Date()),
                dismissalPolicy: .immediate
            )
        }

        await MainActor.run {
            self.activityTokens.removeAll()
            self.auctionActivityTracking.removeAll()
            self.activityID = nil
            self.activityToken = nil
        }

        await refreshRunningActivities()
    }
}
