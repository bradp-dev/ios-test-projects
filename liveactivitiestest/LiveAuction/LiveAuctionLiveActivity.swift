//
//  LiveAuctionLiveActivity.swift
//  LiveAuction
//
//  Created by Zenun Vucetovic on 1/3/25.
//  Copyright © 2025 Cars and Bids.
//  ------------------------------------------------------------
//  Live Activity widget for auctions, including Dynamic Island
//  layouts (expanded/compact/minimal) and composable subviews.
//  ------------------------------------------------------------
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - UI Constants

private enum UIConst {
    static let headerHeight: CGFloat      = 28
    static let compactBarHeight: CGFloat  = 22
    static let expandedBarHeight: CGFloat = 38
  
    static let iconSize: CGFloat          = 28
    static let iconSizeMinimal: CGFloat   = 26

    static let compactTextSize: CGFloat   = 14
    static let standardTextSize: CGFloat  = 17
}

// MARK: - Widget

struct LiveAuctionLiveActivity: Widget {
    let defaultLinkURL: URL = URL(string: "https://www.carsandbids.com/auctions/")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveAuctionAttributes.self) { context in
            NotificationConfigurationView(attributes: context.attributes, state: context.state)
                .widgetURL(context.state.linkedURL ?? defaultLinkURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LeadingHeaderView(state: context.state, smallFont: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingHeaderView(attributes: context.attributes, smallFont: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AuctionStatusView(attributes: context.attributes, state: context.state)
                    HStack(alignment: .center, spacing: 0) {
                        Spacer()
                        AuctionInfoView(carName: context.attributes.carName, compact: true)
                            .padding(.top, 3)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                        Spacer()
                    }
                }
            } compactLeading: {
                CountdownBarView(attributes: context.attributes, state: context.state, compact: true)
            } compactTrailing: {
                Text("\(context.state.currentBid)")
                    .font(.system(size: UIConst.compactTextSize, weight: .black, design: .monospaced))
                    .lineLimit(1)
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } minimal: {
                FastCarImageView(minimal: true)
            }
            .widgetURL(context.state.linkedURL ?? defaultLinkURL)
        }
    }
}

// MARK: - Notification Content

struct NotificationConfigurationView: View {
    let attributes: LiveAuctionAttributes
    let state: LiveAuctionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                LeadingHeaderView(state: state, smallFont: false)
                Spacer()
                TrailingHeaderView(attributes: attributes, smallFont: false)
            }

            AuctionStatusView(attributes: attributes, state: state)

            AuctionInfoView(carName: attributes.carName, compact: false)
                .padding(.top, 3)
                .padding(.bottom, 2)
        }
        .padding(16)
        .activityBackgroundTint(Color.gray.opacity(0.8))
    }
}

// MARK: - Headers

/// Left header (“AUCTION ENDED / LAST MINUTE / AUCTION ENDING”)
struct LeadingHeaderView: View {
    let state: LiveAuctionAttributes.ContentState
    let smallFont: Bool

    var body: some View {
        Text(state.headerTitle)
            .font(smallFont ? .caption : .subheadline)
            .foregroundColor(Color.gray)
            .frame(height: UIConst.headerHeight, alignment: .center)
    }
}

/// Right header (“YOUR AUCTION” for owners, or icon for others)
struct TrailingHeaderView: View {
    let attributes: LiveAuctionAttributes
    let smallFont: Bool

    var body: some View {
        if attributes.isUserOwner {
            YourAuctionTextView(smallFont: smallFont)
        } else {
            FastCarImageView(minimal: false)
        }
    }
}

struct YourAuctionTextView: View {
    let smallFont: Bool

    var body: some View {
        Text("YOUR AUCTION")
            .font(smallFont ? .caption : .subheadline)
            .foregroundColor(Color.yellow)
            .frame(height: UIConst.headerHeight, alignment: .center)
    }
}

struct FastCarImageView: View {
    let minimal: Bool

    private var size: CGFloat { minimal ? UIConst.iconSizeMinimal : UIConst.iconSize }

    var body: some View {
        Image(.fastcar1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .opacity(0.5)
    }
}

// MARK: - Body Sections

struct AuctionInfoView: View {
    let carName: String
    let compact: Bool
  
    var body: some View {
        Text(carName)
            .font(.headline.weight(.semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .layoutPriority(1)
    }
}

struct AuctionStatusView: View {
    let attributes: LiveAuctionAttributes
    let state: LiveAuctionAttributes.ContentState

    var body: some View {
        // The expanded bar height used when the button is shown alongside it
        let barHeight = UIConst.expandedBarHeight

        HStack(spacing: 8) {
            CountdownBarView(attributes: attributes, state: state, compact: false)

            if state.isAuctionLive {
                ActionButtonView(attributes: attributes, state: state, targetHeight: barHeight)
            }
        }
    }
}

struct ActionButtonView: View {
    let attributes: LiveAuctionAttributes
    let state: LiveAuctionAttributes.ContentState
    let targetHeight: CGFloat

    var body: some View {
        // CASE: Owner but no reserve – hide the button
        if attributes.isUserOwner && !(state.hasReserve ?? false) {
            EmptyView()
        }
        // CASE: Show button for either slider or bid
        else {
            Button(action: {}) {
                buttonContent
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .frame(height: targetHeight)
            .background(Color.gray)
            .cornerRadius(20)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        if attributes.isUserOwner {
            Image(systemName: "slider.vertical.3")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Text("Bid")
                .font(.system(size: UIConst.standardTextSize, weight: .medium))
        }
    }
}



// MARK: - Countdown Bar + Content

struct CountdownBarView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let attributes: LiveAuctionAttributes
    let state: LiveAuctionAttributes.ContentState
    let compact: Bool

    // Choose background color with luminance in mind
    private var backgroundColor: Color {
        // When luminance is reduced and it's the last minute of a live auction, force cbRed
        if isLuminanceReduced && state.isAuctionLive && state.lastMinute {
            return .red
        }
        // Otherwise use the original logic from your extension
        return state.countdownBackgroundColor
    }
    
    private var barHeight: CGFloat { compact ? UIConst.compactBarHeight : UIConst.expandedBarHeight }

    var body: some View {
        // Build the bar content once (identical visuals to original)
        let bar = ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(backgroundColor)
                .cornerRadius(20)

            // Progress countdown (only last minute while live)
            if state.isAuctionLive && state.lastMinute && !isLuminanceReduced {
                ProgressView(
                    timerInterval: Date.now...state.endDate,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .tint(.red)
                .frame(height: barHeight)
                .scaleEffect(x: 1, y: 10, anchor: .center)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .progressViewStyle(.linear)
            }

            // Internal content
            if compact {
                HStack(spacing: 1) {
                    Spacer()
                    if !state.lastMinute && state.isAuctionLive {
                        Image(systemName: "clock")
                            .font(.body)
                            .fontWeight(.light)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    CompactProgressBarContentView(state: state)
                    Spacer()
                }
            } else {
                ProgressBarContentView(state: state)
            }
        }
        .frame(height: barHeight)

        // Preserve the original container differences between compact / expanded
        if compact {
            HStack(spacing: 0) {
                Spacer()
                bar
                Spacer()
            }
        } else {
            bar
        }
    }
}

/// Compact content used inside the compact countdown bar.
struct CompactProgressBarContentView: View {
    let state: LiveAuctionAttributes.ContentState
    var lastMinuteText: String = "<1 min"
    var endedText: String = "Ended"
    var youWonText: String = "You won!"

    private enum Content {
        case timer(Date)
        case text(String)
    }

    private var content: Content {
        if state.isAuctionLive {
            return state.lastMinute ? .text(lastMinuteText) : .timer(state.endDate)
        } else {
            return state.didWinAuction ? .text(youWonText) : .text(endedText)
        }
    }

    /// Only black if the user won; otherwise white.
    private var contentColor: Color { state.didWinAuction ? .black : .white }

    @ViewBuilder
    private var label: some View {
        switch content {
        case .timer(let endDate):
            Text(timerInterval: Date.now...endDate, countsDown: true)
                .monospacedDigit()
                .font(.system(size: UIConst.compactTextSize, weight: .bold))
        case .text(let message):
            Text(message)
                .font(.system(size: UIConst.compactTextSize, weight: .bold))
        }
    }

    var body: some View {
        label
            .foregroundColor(contentColor)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }
}

/// Expanded content used inside the expanded countdown bar.
struct ProgressBarContentView: View {
    let state: LiveAuctionAttributes.ContentState
    var lastMinuteText: String = "<1 min"

    var body: some View {
        if state.isAuctionLive {
            HStack {
                HStack(spacing: 8) {
                    if state.lastMinute {
                        Text(lastMinuteText)
                            .font(.system(size: UIConst.standardTextSize))

                            .foregroundColor(.white)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: UIConst.standardTextSize, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                        Text(timerInterval: Date.now...state.endDate, countsDown: true)
                            .font(.system(size: UIConst.standardTextSize, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                .padding(.leading, 16)

                Spacer()

                Text("Bid")
                    .font(.system(size: UIConst.standardTextSize))
                    .foregroundColor(.white.opacity(0.7))

                Text("\(state.currentBid)")
                    .font(.system(size: UIConst.standardTextSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.trailing, 16)
            }
        } else {
            HStack {
                Spacer()
                // E.g. “You won! View winners page”, “Sold for XX”, “Bid to XX”, “Your car sold!”
                Text(state.auctionCloseStatusText)
                    .font(.system(size: UIConst.standardTextSize, weight: .bold))
                    .foregroundColor(state.didWinAuction ? .black : .white)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }
}

