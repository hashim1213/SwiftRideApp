import SwiftUI

enum Theme {
    /// Transit-signage yellow — the SwiftRide accent.
    static let accent = Color("AccentColor")
    static let signal = Color(hex: "FFC21A")!
    static let live = Color(hex: "1FC46B")!
    static let late = Color(hex: "FF5A4E")!
    static let early = Color(hex: "3E8BFF")!

    static let cardRadius: CGFloat = 22
    static let badgeRadius: CGFloat = 8
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Relative luminance (0–1) of a hex colour, for picking readable text.
    static func luminance(hex: String) -> Double? {
        var s = hex.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        func ch(_ x: UInt32) -> Double {
            let c = Double(x) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch((v >> 16) & 0xFF) + 0.7152 * ch((v >> 8) & 0xFF) + 0.0722 * ch(v & 0xFF)
    }

    /// Softens pure primaries some feeds publish (#0000FF, #00FF00 …) into transit-friendly tones.
    static func tamedHex(_ hex: String) -> String {
        switch hex.uppercased() {
        case "0000FF": return "1F5FD1"
        case "00FF00": return "1FA34A"
        case "00FFFF": return "0AA5B5"
        case "FFFF00": return "F2C500"
        case "FF0000": return "D7262E"
        case "FF00FF": return "B5179E"
        case "FFFFFF", "": return ""
        default: return hex.uppercased()
        }
    }
}

// MARK: - Shared view modifiers

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius) -> some View { modifier(CardBackground(radius: radius)) }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
