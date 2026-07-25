import SwiftUI

// MARK: - Brand palette

extension Color {
    /// Iris's signature indigo-violet, sampled from the icon's inner spectrum rings.
    static let irisIndigo = Color(red: 0.42, green: 0.31, blue: 0.86)   // ~#6C4FDB
    /// Cool companion hues for the thinking-dots triad.
    static let irisBlue = Color(red: 0.31, green: 0.61, blue: 0.86)     // ~#4F9BDB
    static let irisTeal = Color(red: 0.25, green: 0.80, blue: 0.78)     // ~#40CCC7
}

// MARK: - Icon asset

enum IrisAsset {
    /// The app icon, loaded once from the bundled resource (same file the app uses for its
    /// dock icon). `nil` only if the resource is missing.
    static let icon: NSImage? = {
        guard let path = Bundle.module.path(forResource: "iris-icon", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: path)
    }()
}

// MARK: - Spectrum hairline

/// A thin rainbow accent line that gently drifts. It always drifts slowly; while Iris is
/// working (`active`) the drift speeds up, so the line quietly "comes alive."
struct SpectrumLine: View {
    var active: Bool
    @State private var phase: CGFloat = 0

    // First and last colors match so the doubled bar loops seamlessly.
    private let colors: [Color] = [.irisIndigo, .irisBlue, .irisTeal, .green, .yellow, .orange, .pink, .irisIndigo]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                bar(width: w)
                bar(width: w)
            }
            .offset(x: -phase * w)
        }
        .frame(height: 2)
        .clipShape(Capsule())
        .opacity(0.7)
        .onAppear { restart() }
        .onChange(of: active) { _, _ in restart() }
    }

    private func bar(width: CGFloat) -> some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
    }

    private func restart() {
        phase = 0
        withAnimation(.linear(duration: active ? 3.0 : 8.0).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

// MARK: - Empty-conversation welcome

/// Shown when a conversation has no messages: the Iris icon over a soft indigo glow that
/// gently breathes, with a quiet greeting.
struct IrisWelcomeView: View {
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [Color.irisIndigo.opacity(0.45), .clear]),
                        center: .center, startRadius: 2, endRadius: 140))
                    .frame(width: 320, height: 320)
                    .blur(radius: 14)
                    .scaleEffect(breathe ? 1.06 : 0.9)
                    .opacity(breathe ? 0.9 : 0.5)

                if let icon = IrisAsset.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .scaleEffect(breathe ? 1.03 : 1.0)
                        .shadow(color: Color.irisIndigo.opacity(0.5), radius: 18)
                }
            }
            Text("Iris is watching.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
