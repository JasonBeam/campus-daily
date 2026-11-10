import SwiftUI

/// The orange droplet mascot, drawn in a 64×64 box and scaled to the frame.
struct MascotPart: Shape {
    enum Part { case body, eyes, smile }
    let part: Part
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64
        let ox = rect.midX - 32 * s, oy = rect.midY - 32 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x:ox + x * s, y:oy + y * s) }
        var path = Path()
        switch part {
        case .body:
            path.move(to:p(32,4))
            path.addCurve(to:p(34.5,5.3), control1:p(33,4), control2:p(33.9,4.5))
            path.addCurve(to:p(54,41), control1:p(40,12.6), control2:p(54,30.6))
            // A22 22 0 0 1 10 41: lower half circle centred at (32,41), through the bottom.
            path.addRelativeArc(center:p(32,41), radius:22 * s, startAngle:.degrees(0), delta:.degrees(180))
            path.addCurve(to:p(29.5,5.3), control1:p(10,30.6), control2:p(24,12.6))
            path.addCurve(to:p(32,4), control1:p(30.1,4.5), control2:p(31,4))
            path.closeSubpath()
        case .eyes:
            for x in [24.5, 39.5] as [CGFloat] {
                path.addEllipse(in:CGRect(x:ox + (x - 3.4) * s, y:oy + (40 - 3.4) * s, width:6.8 * s, height:6.8 * s))
            }
        case .smile:
            path.move(to:p(27.5,49))
            path.addCurve(to:p(36.5,49), control1:p(30.1,51.4), control2:p(33.9,51.4))
        }
        return path
    }
}

/// Static droplet (no hop). Shared with the widget, which has no asset catalog: pass the colour in.
struct MascotGlyph: View {
    var size: CGFloat
    var color: Color
    var body: some View {
        ZStack {
            MascotPart(part:.body).fill(color)
            MascotPart(part:.eyes).fill(.white)
            MascotPart(part:.smile).stroke(.white, style:StrokeStyle(lineWidth:2.6 * size / 64, lineCap:.round))
        }
        .frame(width:size, height:size)
        .accessibilityHidden(true)
    }
}
