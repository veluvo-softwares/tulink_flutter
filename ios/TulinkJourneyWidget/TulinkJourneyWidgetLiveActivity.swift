//
//  TulinkJourneyWidgetLiveActivity.swift
//  TulinkJourneyWidget
//
//  Journey Live Activity: lock-screen / Dynamic Island surface showing the
//  driver's ETA and up to three convoy members with their distance to the
//  destination (nearest first, arrived last) — fed by the Flutter side via
//  the live_activities plugin (JourneyStatusNotifier).
//

import ActivityKit
import WidgetKit
import SwiftUI

/// Name is a hard contract with the live_activities Flutter plugin — the
/// plugin creates activities of exactly this type; renaming it makes
/// activities silently not appear.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {}

    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        "\(id)_\(key)"
    }
}

/// Data written by JourneyStatusNotifier through the shared app group.
private let sharedDefault = UserDefaults(suiteName: "group.xyz.tulink.app")!

private struct JourneyState {
    let title: String
    let subtitle: String
    let members: [MemberRow]
    let extraMembers: Int

    init(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) {
        title =
            sharedDefault.string(forKey: context.attributes.prefixedKey("title"))
            ?? "TuLink journey"
        subtitle =
            sharedDefault.string(forKey: context.attributes.prefixedKey("subtitle"))
            ?? ""
        var rows: [MemberRow] = []
        for index in 0..<3 {
            if let raw = sharedDefault.string(
                forKey: context.attributes.prefixedKey("member\(index)")
            ), let row = MemberRow.decode(raw, id: index) {
                rows.append(row)
            }
        }
        members = rows
        extraMembers = sharedDefault.integer(
            forKey: context.attributes.prefixedKey("extraMembers")
        )
    }
}

struct TulinkJourneyWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            LockScreenView(state: JourneyState(context))
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            let state = JourneyState(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(Color.tulinkRed)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        ForEach(state.members.prefix(2)) { member in
                            MemberRowView(member: member)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color.tulinkRed)
            } compactTrailing: {
                Text(state.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color.tulinkRed)
            }
            .keylineTint(Color.tulinkRed)
        }
    }
}

private struct LockScreenView: View {
    let state: JourneyState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color.tulinkRed)
                Text(state.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            if !state.subtitle.isEmpty {
                Text(state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(state.members) { member in
                MemberRowView(member: member)
            }
            if state.extraMembers > 0 {
                Text("+\(state.extraMembers) more")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
    }
}

private struct MemberRowView: View {
    let member: MemberRow

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(member.color)
                    .frame(width: 22, height: 22)
                Text(member.initials)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(member.line)
                .font(.caption)
                .foregroundStyle(.white.opacity(member.arrived ? 0.6 : 0.9))
                .lineLimit(1)
            Spacer()
            if member.arrived {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}
