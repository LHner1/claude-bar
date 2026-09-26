import SwiftUI

/// Section title in the style of the Stats popups.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if let trailing {
                HStack {
                    Spacer()
                    trailing
                }
            }
        }
        .frame(height: 22)
        .padding(.top, 6)
    }
}

/// "● Label ……… Value" row like in the Stats details.
struct DetailRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .frame(height: 16)
    }
}

/// Ring gauge for a limit window (modelled after the Stats dashboard circles).
struct LimitGauge: View {
    let title: String
    let window: LimitWindow?
    let now: Date

    private var pct: Double? { window?.effectivePct(at: now) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.1), lineWidth: 7)
                if let pct {
                    Circle()
                        .trim(from: 0, to: min(1, pct / 100))
                        .stroke(Fmt.percentColor(pct).gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
                VStack(spacing: 0) {
                    Text(pct.map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    Text("used")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resetText: String {
        guard let window else { return "no data" }
        guard window.resetsAt > now else { return "reset" }
        return "resets \(Fmt.resetTime(window.resetsAt, now: now))"
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 1)
    }
}
