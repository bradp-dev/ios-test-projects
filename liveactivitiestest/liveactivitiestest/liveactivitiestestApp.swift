//
//  liveactivitiestestApp.swift
//  liveactivitiestest
//
//  Created by Brad Priddy on 10/29/25.
//

import SwiftUI

@main
struct liveactivitiestestApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    var body: some Scene {
        WindowGroup {
            LiveActivitiesDebugView()
        }
    }
}
