import SwiftUI

enum Setting {
    static let showFiveHour = "showFiveHour"
    static let showSevenDay = "showSevenDay"
    static let showTodayTokens = "showTodayTokens"
}

/// Status item content: traffic light plus small Stats-style value widgets.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage(Setting.showFiveHour) private var showFiveHour = true
    @AppStorage(Setting.showSevenDay) private var showSevenDay = true
    @AppStorage(Setting.showTodayTokens) private var showTodayTokens = false

    var body: some View {
        HStack(spacing: 5) {
            TrafficLightView(light: model.light)
            if showFiveHour {
                MiniWidget(title: "5H", value: percent(model.limits?.fiveHour))
            }
            if showSevenDay {
                MiniWidget(title: "7D", value: percent(model.limits?.sevenDay))
            }
            if showTodayTokens {
                MiniWidget(title: "TODAY", value: model.isScanning ? "…" : Fmt.tokensShort(model.todayTokens))
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .fixedSize()
    }

    private func percent(_ window: LimitWindow?) -> String {
        guard let window else { return "–" }
        return "\(Int(window.effectivePct(at: model.now).rounded()))%"
    }
}

/// Like the "mini" widget in Stats: tiny label on top, value below.
struct MiniWidget: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(title)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 26, alignment: .leading)
    }
}

/// Vertical traffic light: red = a session needs you, yellow = working, green = ready.
/// Several lamps can be lit at the same time.
struct TrafficLightView: View {
    let light: TrafficLight
    var lampSize: CGFloat = 5
    var spacing: CGFloat = 1.5

    var body: some View {
        VStack(spacing: spacing) {
            lamp(on: light.red, color: .red)
            lamp(on: light.yellow, color: .yellow)
            lamp(on: light.green, color: .green)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: lampSize * 0.7, style: .continuous)
                .strokeBorder(.primary.opacity(0.45), lineWidth: 1)
        }
    }

    private func lamp(on: Bool, color: Color) -> some View {
        Circle()
            .fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.primary.opacity(0.2)))
            .frame(width: lampSize, height: lampSize)
            .shadow(color: on ? color.opacity(0.8) : .clear, radius: on ? 1.5 : 0)
    }
}
