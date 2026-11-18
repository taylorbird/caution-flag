import AppKit
import SwiftUI

/// A full-width welcome banner: the app icon large and centered over a brand
/// colored band with a faint drawn pattern, then the app name and a tagline.
///
/// Self-contained on purpose (only AppKit + SwiftUI, no app types) so it can be
/// copied into other apps: pass that app's colors and keep or swap the pattern.
/// Everything is drawn in code, so it stays sharp at any size and needs no
/// image assets.
struct WelcomeHero: View {
    var icon: NSImage = NSApp.applicationIconImage
    let title: String
    let tagline: String
    var background: Color
    var foreground: Color
    var pattern: Pattern = .racing

    enum Pattern {
        /// Diagonal speed stripes plus a checkered strip along the bottom edge.
        case racing
        /// Plain band.
        case none
    }

    var body: some View {
        ZStack {
            background
            if pattern == .racing {
                Canvas { context, size in
                    drawStripes(in: &context, size: size)
                    drawCheckers(in: &context, size: size)
                }
                .accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                Text(tagline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(foreground.opacity(0.75))
            }
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }

    /// Wide diagonal bands at very low contrast: motion without noise.
    private func drawStripes(in context: inout GraphicsContext, size: CGSize) {
        let band: CGFloat = 26, gap: CGFloat = 46, slant = size.height * 0.6
        var x = -slant
        while x < size.width + slant {
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x + band, y: size.height))
            path.addLine(to: CGPoint(x: x + band + slant, y: 0))
            path.addLine(to: CGPoint(x: x + slant, y: 0))
            path.closeSubpath()
            context.fill(path, with: .color(foreground.opacity(0.05)))
            x += band + gap
        }
    }

    /// Two rows of small checks hugging the bottom edge, like a track marking.
    private func drawCheckers(in context: inout GraphicsContext, size: CGSize) {
        let cell: CGFloat = 8
        let rows = 2
        let top = size.height - cell * CGFloat(rows)
        for row in 0..<rows {
            var col = 0
            var x: CGFloat = 0
            while x < size.width {
                if (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: x, y: top + CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(foreground.opacity(0.85)))
                }
                col += 1
                x += cell
            }
        }
    }
}
