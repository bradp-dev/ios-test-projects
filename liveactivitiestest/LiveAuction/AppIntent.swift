//
//  AppIntent.swift
//  LiveAuction
//
//  Created by Zenun Vucetovic on 1/3/25.
//  Copyright © 2025 Cars and Bids. All rights reserved.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("This is an example widget.")

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
