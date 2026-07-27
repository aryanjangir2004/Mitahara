import SwiftUI

/// Shown in place of the rings/table while today is a cheat day. The top bar
/// and date bar stay; this fills the space below them.
struct CheatDayContent: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var appeared = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            // Soft breathing glow behind the title.
            RadialGradient(
                colors: [Color.orange.opacity(glowPulse ? 0.26 : 0.10), .clear],
                center: .center,
                startRadius: 10,
                endRadius: glowPulse ? 300 : 230
            )
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glowPulse)

            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.pulse)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.05), value: appeared)

                Text("Cheat Day")
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: .orange.opacity(0.45), radius: 22)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.18), value: appeared)

                Text("Relax — your streak is safe today.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.34), value: appeared)

                Button(action: onContinue) {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle.fill")
                        Text("Count calories anyway")
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .padding(.top, 26)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: appeared)

                Button(action: onCancel) {
                    Text("Cancel cheat day")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.62), value: appeared)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 480)
        .onAppear {
            appeared = true
            glowPulse = true
        }
    }
}
