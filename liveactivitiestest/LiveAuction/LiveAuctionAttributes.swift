//
//  LiveAuctionAttributes.swift
//  Cars and Bids
//
//  Created by Zenun Vucetovic on 1/3/25.
//  Copyright © 2025 Cars and Bids. All rights reserved.
//

import Foundation
import ActivityKit
import WidgetKit
import SwiftUI

struct LiveAuctionAttributes: ActivityAttributes {
    var carName: String
    var isUserOwner: Bool
    var auctionId: String   //Unique identifier that will help locate the correct update token
    var notificationTypeId: Int //12 for watcher, 5 for seller
    
    public struct ContentState: Codable, Hashable {
        var currentBid: Double
        var endDateUnix: Double //End time stamp in UNIX time (seconds since 1970)
        var isAuctionLive: Bool //True until the auction is ended
        var didWinAuction: Bool //Mutually exclusive with isUserOwner
        var auctionCloseStatusText: String //Sold for... Bid to...
        var linkedURL: URL? //https://www.carsandbids.com url linking to desired activity
        var lastMinute: Bool // Update property for when the auction is entering the last minute
        var hasReserve: Bool? // True if the auction has a reserve, false otherwise
    }
}

extension LiveAuctionAttributes {
    static let previewValue = LiveAuctionAttributes(
        carName: "2025 Porsche 911",
        isUserOwner: false,
        auctionId: "123",
        notificationTypeId: 12
    )
}

extension LiveAuctionAttributes.ContentState {
    /// Background color of the countdown bar based on state.
    var countdownBackgroundColor: Color {
        if isAuctionLive && lastMinute { return Color.gray.opacity(0.3) }
        if isAuctionLive { return .red }
        return didWinAuction ? .green : Color.gray.opacity(0.3)
    }

    /// Leading header title string.
    var headerTitle: String {
        if !isAuctionLive { return "AUCTION ENDED" }
        return lastMinute ? "LAST MINUTE" : "AUCTION ENDING"
    }
    
    var endDate: Date {
        return Date(timeIntervalSince1970: endDateUnix)
    }
}

enum PreviewScenario: String, CaseIterable, Identifiable {
    case liveNotLastMinute
    case liveLastMinute
    case endedWon
    case endedLost
    case longCopyLastMinute // shows height growth / wrapping

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liveNotLastMinute: return "Live • T-5m"
        case .liveLastMinute:    return "Live • Last Minute"
        case .endedWon:          return "Ended • Won"
        case .endedLost:         return "Ended • Lost"
        case .longCopyLastMinute:return "Live • Last Minute (Long)"
        }
    }

    var state: LiveAuctionAttributes.ContentState {
        switch self {
        case .liveNotLastMinute:
            return .make(bid: 150_000, endsIn: 5*60,  live: true,  won: false, text: "", lastMinute: false)
        case .liveLastMinute:
            return .make(bid: 151_500, endsIn: 45,    live: true,  won: false, text: "", lastMinute: true)
        case .endedWon:
            return .make(bid: 152_000, endsIn: 0,     live: false, won: true,
                         text: "You won! View your checklist", lastMinute: false)
        case .endedLost:
            return .make(bid: 152_000, endsIn: 0,     live: false, won: false,
                         text: "Sold for $152,000", lastMinute: false)
        case .longCopyLastMinute:
            return .make(bid: 153_000, endsIn: 40,    live: true,  won: false,
                         text: "Last minute! Tap to open the app and place your final bid before time expires.",
                         lastMinute: true)
        }
    }
}

extension LiveAuctionAttributes.ContentState {
    static func make(
        bid: Double,
        endsIn seconds: Int,
        live: Bool,
        won: Bool,
        text: String,
        lastMinute: Bool,
        link: URL? = URL(string: "https://www.carsandbids.com/leaderboard/123")
    ) -> Self {
        .init(
            currentBid: bid,
            endDateUnix: Calendar.current.date(byAdding: .second, value: seconds, to: .now)!.timeIntervalSince1970,
            isAuctionLive: live,
            didWinAuction: won,
            auctionCloseStatusText: text,
            linkedURL: link,
            lastMinute: lastMinute,
            hasReserve: false
        )
    }
}
