import SwiftUI

/// 界面放大倍数。字体、图标、间距、控件都按它逐个放大（不是整体位图缩放），所以保持矢量清晰。
enum UIScale {
    static let factor: CGFloat = 1.5
}

/// 把基础尺寸（pt）按倍数放大
func S(_ value: CGFloat) -> CGFloat { value * UIScale.factor }

extension Font {
    /// 基础字号 × 放大倍数
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: S(size), weight: weight)
    }
}

/// 放大后的按钮；`prominent` 为主按钮（强调色填充）。
struct UIButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, prominent: prominent)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.ui(13))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, S(12))
                .padding(.vertical, S(6))
                .background(
                    RoundedRectangle(cornerRadius: S(8))
                        .fill(prominent ? Color.accentColor : Color.secondary.opacity(0.18))
                )
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
        }
    }
}

/// 放大后的复选框
struct UICheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: S(6)) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.ui(15))
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

/// 放大后的滑块
struct UISlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            let knob = S(18)
            let span = max(1, geo.size.width - knob)
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: S(4))
                Capsule().fill(Color.accentColor).frame(width: span * fraction + knob / 2, height: S(4))
                Circle().fill(Color.white).overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .offset(x: span * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(1, max(0, (drag.location.x - knob / 2) / span))
                let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                value = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
            })
        }
        .frame(height: S(24))
    }
}
