//
//  TulinkJourneyWidget.swift
//  TulinkJourneyWidget
//
//  Shared helpers for the journey Live Activity. The static home-screen
//  widget template that lived here was removed — TuLink's glanceable
//  surface is the Live Activity only (OS refresh budgets make static
//  widgets wrong for live convoy data).
//

import SwiftUI

/// One convoy member row decoded from the Flutter side.
///
/// Wire format (shared UserDefaults, written by JourneyStatusNotifier):
///   "INITIALS|Name — 2.1 km|#RRGGBB|arrivedFlag"
struct MemberRow: Identifiable {
    let id: Int
    let initials: String
    let line: String
    let color: Color
    let arrived: Bool

    static func decode(_ raw: String, id: Int) -> MemberRow? {
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }
        return MemberRow(
            id: id,
            initials: parts[0],
            line: parts[1],
            color: Color(hex: parts[2]),
            arrived: parts[3] == "1"
        )
    }
}

extension Color {
    /// "#RRGGBB" → Color; falls back to TuLink red on malformed input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = Color(red: 0.91, green: 0.0, blue: 0.18)
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    static let tulinkRed = Color(red: 0.91, green: 0.0, blue: 0.18)
}
