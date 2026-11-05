import SwiftUI

/// Esthétique "Apple Fitness" : noir OLED, cartes translucides, chiffres en SF Pro Rounded.
enum Theme {
    static let background = Color.black
    static let accent = Color(red: 0.69, green: 1.0, blue: 0.24)      // vert "anneau Bouger"
    static let rest = Color(red: 0.25, green: 0.85, blue: 1.0)        // cyan repos
    static let pause = Color.orange
    static let warmup = Color(red: 1.0, green: 0.78, blue: 0.2)
    static let assisted = Color(red: 0.75, green: 0.55, blue: 1.0)
    static let up = Color.green
    static let down = Color.orange
    static let flat = Color.gray

    static func color(for loadType: LoadType) -> Color {
        switch loadType {
        case .assisted: assisted
        case .bodyweight: .mint
        case .dumbbell: accent
        case .machine: .cyan
        }
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Chiffres : arrondis + chasse fixe (pas de "saut" pendant les comptes à rebours).
    func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded)).monospacedDigit()
    }
}

enum Format {
    static func weight(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR")))
    }

    /// Accepte "12,5" et "12.5".
    static func parseWeight(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Badge de tendance (vert / gris / orange).
struct TrendBadge: View {
    let trend: Trend
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.symbol)
                .contentTransition(.symbolEffect(.replace))
            if !compact { Text(trend.label) }
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .foregroundStyle(trend.color)
        .background(trend.color.opacity(0.18), in: Capsule())
        .accessibilityLabel(trend.label)
    }
}
