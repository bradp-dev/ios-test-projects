//
//  NotificationManager.swift
//  liveactivitiestest
//
//  Created by Brad Priddy on 10/29/25.
//


import Combine
import Foundation
import OSLog
import SwiftUI
import UserNotifications

protocol NavigationNotificationDelegate: AnyObject {
    @MainActor
    func updateRouting(with navigationData: [String: AnyHashable])
}

public final class NotificationManager: NSObject {
    private var cancellables = Set<AnyCancellable>()

    var navigationDelegates = [NavigationNotificationDelegate]()
    var initialNotification: [AnyHashable: Any]? = nil

    public static let shared = NotificationManager()

    var authOptions: UNAuthorizationOptions {
        [.alert, .badge, .sound]
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        UNUserNotificationCenter.current().delegate = Self.shared

        _ = ActivityManager.shared
        Self.shared.requestAuthorization()

        application.registerForRemoteNotifications()
    }


    public func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Unable to register for remote notifications: \(error.localizedDescription)")
    }

    public func requestAuthorization() {
        let authOptions: UNAuthorizationOptions = Self.shared.authOptions
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            print("requestAuthorization granted: \(granted)")
            if let error {
                print("requestAuthorization failed. \(error)")
            }
        }
    }

    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("APNs token retrieved: \(deviceToken)")

        Task {
            //await ActivityManager.shared.apnsBecameReady()
        }
    }


    func addNavigationDelegate(_ delegate: NavigationNotificationDelegate) {
        self.navigationDelegates.append(delegate)
    }

    @MainActor
    public func processNotification(userInfo: [AnyHashable: Any]) {
        print("Notification Received \(userInfo)")
        if let aps = userInfo["aps"] {
            
            
            print("Notification received with APS Payload: \(String(describing: aps))")
        }
        
        
        
        if let navString = userInfo["navigation"] as? String {
            
            if let navigation = navString.convertToDictionary() {
                
                
                navigationDelegates.forEach { delegate in
                    delegate.updateRouting(with: navigation)
                }
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    @MainActor
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo

        if NotificationManager.shared.navigationDelegates.isEmpty {
            self.initialNotification = userInfo
        } else {
            processNotification(userInfo: userInfo)
        }
    }

    @MainActor
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler(.banner)
    }
}


extension String {
    func convertToDictionary() -> [String: AnyHashable]? {
        if let data = data(using: .utf8) {
            return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyHashable]
        }
        return nil
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else {
            return nil
        }
        
        let chars = hex.map { $0 }
        let bytes = stride(from: 0, to: chars.count, by: 2)
            .map { String(chars[$0]) + String(chars[$0 + 1]) }
            .compactMap { UInt8($0, radix: 16) }
        
        guard hex.count / bytes.count == 2 else { return nil }
        self.init(bytes)
    }
}
