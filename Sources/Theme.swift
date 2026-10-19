import SwiftUI

// Instrument-panel palette. The app is a precision readout, not a fitness card deck,
// so the look is a lit dial: deep green-ink ground, a single warm amber readout accent,
// mint used only to signal a live/locked measurement.
enum T {
    static let ink     = Color(hex: 0x0D1513)   // ground
    static let surface = Color(hex: 0x15211E)   // raised panel
    static let line    = Color(hex: 0x27352F)   // hairline
    static let text    = Color(hex: 0xECF2EE)   // primary
    static let muted   = Color(hex: 0x7E918B)   // secondary
    static let amber   = Color(hex: 0xE8B15A)   // the one bold color
    static let mint    = Color(hex: 0x4FD6A6)   // live/locked signal
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
