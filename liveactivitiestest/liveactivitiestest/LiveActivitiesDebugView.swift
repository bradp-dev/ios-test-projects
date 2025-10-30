//
//  LiveActivitiesDebugView.swift
//  liveactivitiestest
//
//  Created by Brad Priddy on 10/30/25.
//


import SwiftUI
import ActivityKit


enum ActivityLink: String, CaseIterable, Identifiable {
    case leaderboard = "https://www.carsandbids.com/leaderboard"
    case auctions = "https://www.carsandbids.com/auctions"
    case custom = "https://www.carsandbids.com/"
    
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leaderboard: return "Leaderboard"
        case .auctions: return "Auctions"
        case .custom: return "Custom /*"
        }
    }

    var url: URL? {
        return URL(string: self.rawValue)
    }
}

extension ActivityLink {
    init?(from urlString: String) {
        self.init(rawValue: urlString)
    }
}

// MARK: - Presets
enum PresetCarNames: String, CaseIterable {
    case long1 = "2016 Lamborghini Huracan LP610-4 Coupe"
    case long2 = "2025 Toyota 4Runner TRD Off-Road Premium 4x4"
    case long3 = "2019 Ford F-150 Raptor Hennessey VelociRaptor V8"
    case long4 = "2023 Chevrolet Silverado 1500 High Country Crew Cab 4x4"
}

enum PresetBids: Double, CaseIterable {
    case low  = 23_450
    case medium = 230_500
    case high  = 1_150_500
}

/// Quick “Start” scenarios for demos.
enum StartPreset: String, CaseIterable, Identifiable {
    case standard20m     = "Start • Standard (20m)"
    case owner10m        = "Start • Owner View (10m)"
    case lastMinute      = "Start • Last Minute (60s)"
    case highBid5m       = "Start • High Bid (5m)"

    var id: String { rawValue }

    /// Execute this start preset.
    func run() async {
        // Compose attributes/state per preset
        let carName: String
        let isOwner: Bool
        let bid: Double
        let minutes: Int
        let lastMinute: Bool
        let link: String
        let hasReserve: Bool
        
        switch self {
        case .standard20m:
            carName     = PresetCarNames.long4.rawValue
            isOwner     = false
            bid         = PresetBids.low.rawValue
            minutes     = 20
            lastMinute  = false
            link        = ActivityLink.auctions.rawValue
            hasReserve  = false

        case .owner10m:
            carName     = PresetCarNames.long4.rawValue
            isOwner     = true
            bid         = PresetBids.low.rawValue
            minutes     = 10
            lastMinute  = false
            link        = ActivityLink.auctions.rawValue
            hasReserve  = false

        case .lastMinute:
            carName     = PresetCarNames.long4.rawValue
            isOwner     = false
            bid         = PresetBids.low.rawValue
            minutes     = 1
            lastMinute  = true
            link        = ActivityLink.auctions.rawValue
            hasReserve  = false

        case .highBid5m:
            carName     = PresetCarNames.long4.rawValue
            isOwner     = false
            bid         = PresetBids.low.rawValue
            minutes     = 5
            lastMinute  = false
            link        = ActivityLink.auctions.rawValue
            hasReserve  = false
        }

        let endDate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!

        // Unique-ish demo auction id
        let auctionId = String(UUID().uuidString.prefix(8))

        _ = await ActivityManager.shared.startAuctionActivity(
            relevanceScore: 50,
            carName: carName,
            isUserOwner: isOwner,
            auctionId: auctionId,
            currentBid: bid,
            endDate: endDate,
            linkedURL: link,
            lastMinute: lastMinute,
            hasReserve: hasReserve
        )
    }
}

/// Quick “Update” scenarios; target FIRST running activity.
enum UpdatePreset: String, CaseIterable, Identifiable {
    case bumpBidPlus1000    = "Update • Bump Bid +$1000"
    case lastMinute         = "Update • Last Minute"
    case extend1m           = "Update • Last Minute - Extend By Bid +$1000"
    case addReserve         = "Update • Add Reserve"
    case removeReserve      = "Update • Remove Reserve"
    case endAsWon           = "Update • End (Won)"
    case endAsLostSold      = "Update • End (Lost Sold)"
    case endAsLostRNM       = "Update • End (Lost Not Met)"
    case endAsSellerSold    = "Update • End (Seller Sold)"

    var id: String { rawValue }

    /// Execute this update on the first running activity, if any.
    func run(on manager: ActivityManager) async {
        Task {
            guard let activity = await ActivityManager.shared.runningActivities.first else {
                print("⚠️ No running activities to update.")
                return
            }
            let id = activity.id
            let current = activity.content.state
            let link = ActivityLink.auctions.rawValue

            switch self {
            case .bumpBidPlus1000:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid + 1000,
                    endDate: current.endDate,
                    isAuctionLive: true,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: current.lastMinute,
                    hasReserve: (current.hasReserve ?? false)
                )

            case .lastMinute:
                let endDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: endDate,
                    isAuctionLive: true,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: true,
                    hasReserve: (current.hasReserve ?? false)
                )

            case .extend1m:
                var newEnd: Date
                if (current.endDate < Date()) {
                    newEnd = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                } else {
                    newEnd = Calendar.current.date(byAdding: .minute, value: 1, to: current.endDate)!
                }
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid + 1000,
                    endDate: newEnd,
                    isAuctionLive: true,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: true, //Can only run this update in last minute
                    hasReserve: (current.hasReserve ?? false)
                )
                
            case .addReserve:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: current.endDate,
                    isAuctionLive: true,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: current.lastMinute,
                    hasReserve: true
                )
                
            case .removeReserve:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: current.endDate,
                    isAuctionLive: true,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: current.lastMinute,
                    hasReserve: false
                )
                
            case .endAsWon:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: Date(), // now
                    isAuctionLive: false,
                    didWinAuction: true,
                    auctionCloseStatusText: "You won! View the winner's page",
                    linkedURL: link,
                    lastMinute: false,
                    hasReserve: (current.hasReserve ?? false)
                )

            case .endAsLostSold:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: Date(), // now
                    isAuctionLive: false,
                    didWinAuction: false,
                    auctionCloseStatusText: "Sold for \(current.currentBid)",
                    linkedURL: link,
                    lastMinute: false,
                    hasReserve: (current.hasReserve ?? false)
                )
                
            case .endAsLostRNM:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: Date(), // now
                    isAuctionLive: false,
                    didWinAuction: false,
                    auctionCloseStatusText: "Bid to \(current.currentBid)",
                    linkedURL: link,
                    lastMinute: false,
                    hasReserve: (current.hasReserve ?? false),
                )
                
            case .endAsSellerSold:
                await manager.updateAuctionActivity(
                    relevanceScore: 50,
                    activityID: id,
                    newBid: current.currentBid,
                    endDate: Date(), // now
                    isAuctionLive: false,
                    didWinAuction: false,
                    auctionCloseStatusText: "",
                    linkedURL: link,
                    lastMinute: false,
                    hasReserve: (current.hasReserve ?? false)
                )
            }
            
        }
    }
}


struct LiveActivitiesDebugView: View {
    var body: some View {
        Form {
            LiveActivitiesSectionView()
        }
        .navigationTitle("Live Activities")
        .toolbar {
            // Toolbar dropdown with all presets
            ToolbarItem(placement: .primaryAction) {
                PresetsMenu()
            }
        }
    }
}

// MARK: - Presets Menu UI

struct PresetsMenu: View {
    @ObservedObject private var manager = ActivityManager.shared

    var body: some View {
        Menu {
            // START PRESETS
            Section("Start Presets") {
                ForEach(StartPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        Task { await preset.run() }
                    }
                }
            }

            // UPDATE PRESETS
            Section("Update First Activity") {
                ForEach(UpdatePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        Task { await preset.run(on: manager) }
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "wand.and.stars")
        }
    }
}

// MARK: - Main Editing Section (unchanged except for custom-URL row tweaks)

public struct LiveActivitiesSectionView: View {
    @ObservedObject var activityManager = ActivityManager.shared
    
    @State private var mode: Mode = .start
    @State private var selectedActivityID: String = ""
    
    // Fields
    @State private var relevanceScore: String = "50"  // Default score
    @State private var carName: String = "2025 Porsche 911"
    @State private var auctionId: String = UUID().uuidString.prefix(8).description
    @State private var endDate: Date = Date()
    @State private var isUserOwner: Bool = false
    @State private var currentBid: String = "12345.00"
    @State private var formattedCalculatedEndDate: String = ""
    @State private var hoursFromNow: Int = 0
    @State private var minutesFromNow: Int = 2
    @State private var isAuctionLive: Bool = true
    @State private var hasReserve: Bool = false
    @State private var didWinAuction: Bool = false
    @State private var auctionCloseStatusText: String = ""
    @State private var selectedLink: ActivityLink = .leaderboard
    @State private var showCustomLinkEntryField: Bool = false
    @State private var customUrlPath: String = ""
    @State private var lastMinute: Bool = false
    
    enum Mode: String, CaseIterable, Identifiable {
        case start = "Start"
        case update = "Update"
        var id: String { rawValue }
    }
    
    public var body: some View {
        Section {
            modePicker
            if mode == .update { activityPicker }
            carInfoFields
            HStack {
                Text("Relevance Score:")
                Spacer()
                TextField("", text: $relevanceScore)
                    .keyboardType(.numberPad)
                    .frame(alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: relevanceScore) { _, newValue in
                        relevanceScore = newValue.filter { $0.isNumber }
                    }
            }
            auctionStateFields
            auctionEndDateSection
            executeButton
        } header: {
            Text("Live Activities")
        }
        
        activeActivitiesList
        pushToStartList
        cancelAllButton
        
        .onChange(of: mode) { oldMode, newMode in
            if newMode == .start {
                // Reset to defaults for new activity
                relevanceScore = "50"
                carName = "2025 Porsche 911"
                auctionId = UUID().uuidString.prefix(8).description
                isUserOwner = false
                currentBid = "12345.00"
                hoursFromNow = 0
                minutesFromNow = 2
                isAuctionLive = true
                didWinAuction = false
                auctionCloseStatusText = ""
                selectedActivityID = ""
                selectedLink = .auctions
                lastMinute = false
                hasReserve = false
            } else if newMode == .update {
                // Prefill with first running activity
                selectedActivityID = activityManager.runningActivities.first?.id ?? ""
            }
        }
        .onChange(of: selectedActivityID) { oldActivity, newActivity in
            if let activity = activityManager.getActivity(by: newActivity) {
                carName = activity.attributes.carName
                auctionId = activity.attributes.auctionId
                isUserOwner = activity.attributes.isUserOwner
                currentBid = activity.content.state.currentBid.description
                isAuctionLive = activity.content.state.isAuctionLive
                didWinAuction = activity.content.state.didWinAuction
                auctionCloseStatusText = activity.content.state.auctionCloseStatusText
                endDate = activity.content.state.endDate
                selectedLink = ActivityLink(from: activity.content.state.linkedURL?.absoluteString ?? "") ?? ActivityLink.auctions
                lastMinute = activity.content.state.lastMinute
                hasReserve = (activity.content.state.hasReserve ?? false)
            }
        
        }

    }
    
}

private extension LiveActivitiesSectionView {
    // MARK: - Mode Picker
    var modePicker: some View {
        Picker("Action", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                if (mode == .update) {
                    if (!activityManager.runningActivities.isEmpty) {
                        Text(mode.rawValue).tag(mode)
                    }
                } else {
                    Text(mode.rawValue).tag(mode)
                }
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Activity Picker
    var activityPicker: some View {
        Picker("Activity", selection: $selectedActivityID) {
            ForEach(activityManager.runningActivities, id: \.id) { activity in
                Text("\(activity.attributes.carName) (\(activity.id.prefix(6)))")
                    .tag(activity.id)
            }
        }
    }
    
    var linkPicker: some View {
        Picker("URL to link", selection: $selectedLink) {
            ForEach(ActivityLink.allCases) { link in
                Text(link.displayName).tag(link)
            }
        }
    }
    
    // MARK: - Car Info Fields
    var carInfoFields: some View {
        
        Group {
            HStack {
                Text("Car Name:")
                Spacer()
                TextField("", text: $carName)
                    .foregroundStyle(mode == .update ? .gray : .primary)
                    .disabled(mode == .update)
                    .frame(alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Auction ID:")
                Spacer()
                TextField("", text: $auctionId)
                    .foregroundStyle(mode == .update ? .gray : .primary)
                    .disabled(mode == .update)
                    .frame(alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }

            Toggle("User is Owner", isOn: $isUserOwner)
                .disabled(mode == .update)
        }
        
    }
    
    // MARK: - Auction State
    var auctionStateFields: some View {
        Group {
            HStack {
                Text("Current Bid: ")
                Spacer()
                TextField("", text: $currentBid)
                    .keyboardType(.numberPad)
                    .frame(alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: currentBid) { oldValue, newValue in
                        // Only allow numbers
                        currentBid = newValue.filter { $0.isNumber }
                    }
            }
            
            linkPicker
            if (showCustomLinkEntryField) {
                HStack(spacing: 6) {
                    // Non-clickable base URL (verbatim + gray)
                    Text(verbatim: "https://www.carsandbids.com/")
                        .foregroundColor(.secondary)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))

                    // Editable path after the domain
                    TextField("path-or-slug", text: $customUrlPath)
                        .foregroundStyle(mode == .update ? .gray : .primary)
                        .disabled(mode == .update)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder) // makes it look editable
                }
                // Swallow any link taps in just this row (belt & suspenders)
                .environment(\.openURL, OpenURLAction { _ in .discarded })
            }
            
            Toggle("Has Reserve", isOn: $hasReserve)
            
            if (mode == .update) {
                Toggle("Auction Live", isOn: $isAuctionLive)
                if (!isAuctionLive) {
                    Toggle("Did Win Auction", isOn: $didWinAuction)
                    HStack {
                        Text("Close Status:")
                        Spacer()
                        TextField("Enter close status", text: $auctionCloseStatusText)
                            .frame(alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    Toggle("Last Minute", isOn: $lastMinute)
                }
                
                
            }
            
        }
        .onChange(of: selectedLink) {
            showCustomLinkEntryField = selectedLink == .custom
        }
    }
    
    private var calculatedEndDate: Date {
        Calendar.current.date(byAdding: .hour, value: hoursFromNow, to: Date())!
            .addingTimeInterval(Double(minutesFromNow * 60))
    }
    
    private var formattedExistingEndDate: String {
        endDate.formatted(date: .abbreviated, time: .shortened)
    }
    
    private func updateFormattedEndDate() {
        let date = Calendar.current.date(byAdding: .hour, value: hoursFromNow, to: Date())!
            .addingTimeInterval(Double(minutesFromNow * 60))
        formattedCalculatedEndDate = date.formatted(date: .abbreviated, time: .shortened)
    }
    
    // MARK: - Auction End Date Group
    var auctionEndDateSection: some View {
        // Slider wants a Double binding; bridge your Int minutes state
        let minutesBinding = Binding<Double>(
            get: { Double(minutesFromNow) },
            set: { minutesFromNow = Int($0) }
        )

        return VStack(alignment: .leading, spacing: 12) {
            if mode == .update {
                HStack {
                    Text("Current End Time")
                    Spacer()
                    Text(formattedExistingEndDate)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Auction End Date")
                Spacer()
                Text(formattedCalculatedEndDate)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Minutes From Now")
                    Spacer()
                    Text("\(minutesFromNow) min")
                        .foregroundColor(.secondary)
                }
                Slider(value: minutesBinding, in: 1...20, step: 1) {
                    Text("Minutes From Now")
                } minimumValueLabel: {
                    Text("1").font(.caption2).foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("20").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { updateFormattedEndDate() }
        .onChange(of: minutesFromNow) { _, _ in updateFormattedEndDate() }
    }

    
    // MARK: - Execute Button
    var executeButton: some View {
        HStack {
            Spacer()
            Button(mode == .start ? "Start Activity" : "Update Activity") {
                Task {
                    let newEndDate = Calendar.current.date(byAdding: .hour, value: hoursFromNow, to: Date())!
                        .addingTimeInterval(Double(minutesFromNow * 60))
                    
                    let bidValue = Double(currentBid) ?? 0
                    let fullURLString: String
                    if selectedLink == .custom {
                        fullURLString = selectedLink.rawValue + customUrlPath.lowercased()
                    } else {
                        fullURLString = selectedLink.rawValue
                    }

                    if mode == .start {
                        _ = await activityManager.startAuctionActivity(
                            relevanceScore: Double(relevanceScore) ?? 50,
                            carName: carName,
                            isUserOwner: isUserOwner,
                            auctionId: auctionId,
                            currentBid: bidValue,
                            endDate: newEndDate,
                            linkedURL: fullURLString,
                            lastMinute: lastMinute,
                            hasReserve: hasReserve
                        )
                    } else if mode == .update, !selectedActivityID.isEmpty {
                        await activityManager.updateAuctionActivity(
                            relevanceScore: Double(relevanceScore) ?? 50,
                            activityID: selectedActivityID,
                            newBid: bidValue,
                            endDate: newEndDate,
                            isAuctionLive: isAuctionLive,
                            didWinAuction: didWinAuction,
                            auctionCloseStatusText: auctionCloseStatusText,
                            linkedURL: fullURLString,
                            lastMinute: lastMinute,
                            hasReserve: hasReserve
                        )
                        
                        if let updatedActivity = activityManager.getActivity(by: selectedActivityID) {
                            await MainActor.run {
                                endDate = updatedActivity.content.state.endDate
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        
    }
    
    // MARK: - Running Activities
    var activeActivitiesList: some View {
        Section("Running Activities") {
            ForEach(activityManager.runningActivities, id: \.id) { activity in
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.attributes.auctionId) // Show Auction ID as primary
                        .font(.headline)
                    Text(activity.attributes.carName)
                        .font(.subheadline)
                    Text("Activity ID: \(activity.id)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    if let token = activityManager.activityTokens[activity.id] {
                        Text("Push Token: \(token)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    // MARK: - Push-to-Start
    var pushToStartList: some View {
        Section("Push-to-Start Tokens") {
            ForEach(activityManager.pushToStartTokens.sorted(by: { $0.key < $1.key }), id: \.key) { token, auctionId in
                CopyableTokenRow(auctionId: auctionId, token: token)
            }
        }
    }
    
    // MARK: - Cancel All
    var cancelAllButton: some View {
        Button("Cancel All Activities", role: .destructive) {
            mode = .start
            Task { await activityManager.cancelAllRunningActivities() }
        }
    }
    
    struct CopyableTokenRow: View {
        let auctionId: String
        let token: String
        @State private var didCopy = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(auctionId)
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Push Token:")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(token)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = token
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            didCopy = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { didCopy = false }
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy push token")
                }
            }
            .overlay(alignment: .topTrailing) {
                if didCopy {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                        .padding(.trailing, 4)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = token
                } label: {
                    Label("Copy token", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
