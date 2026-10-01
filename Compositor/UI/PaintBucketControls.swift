import SwiftUI

struct PaintBucketControls: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 12) {
            Text("Paint Bucket").font(ToolHeaderStyle.titleFont)
            Text("Tolerance").scrubbable(sensitivity: 1, value: $session.paintBucketSettings.tolerance, range: 0...255)
            TextField("Tolerance", value: Binding(get: { session.paintBucketSettings.tolerance },
                set: { session.paintBucketSettings.tolerance = min(255, max(0, $0)) }), format: .number)
                .frame(width: 44).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("paintBucketTolerance")
                .arrowSteps(value: { Double(session.paintBucketSettings.tolerance) },
                            change: { session.paintBucketSettings.tolerance = Int(min(255, max(0, $0.rounded()))) })
                .help("How far each color channel may differ from the clicked color (0–255)")
            Toggle("Contiguous", isOn: $session.paintBucketSettings.contiguous)
                .accessibilityIdentifier("paintBucketContiguous")
                .help("Fill connected matching pixels; turn off to fill matching colors everywhere")
            Text("Opacity").scrubbable(sensitivity: 0.01, value: $session.paintBucketSettings.opacity, range: 0...1)
            Slider(value: $session.paintBucketSettings.opacity, in: 0...1).frame(width: 100)
                .accessibilityLabel("Opacity")
            TextField("Opacity", value: Binding<Double>(get: { Double(session.paintBucketSettings.opacity * 100) },
                set: { session.paintBucketSettings.opacity = $0.isFinite ? CGFloat(min(100, max(0, $0)) / 100) : 1 }),
                format: .number.precision(.fractionLength(0)))
                .frame(width: 42).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("paintBucketOpacity")
                .arrowSteps(value: { Double(session.paintBucketSettings.opacity * 100) },
                            change: { session.paintBucketSettings.opacity = CGFloat(min(100, max(0, $0)) / 100) })
                .unitSuffix("%")
                .help("Press 1–9 for 10–90%, 0 for 100%")
            Spacer(minLength: 0)
            if session.isMaskSelected { Text("Mask").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }
}

/// A tilted bucket with a drop, in the same monochrome style as the other tool icons.
struct PaintBucketToolIcon: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 18, y: size.height / 18)
            var bucket = Path()
            bucket.move(to: CGPoint(x: 6, y: 2))
            bucket.addLine(to: CGPoint(x: 13, y: 9))
            bucket.addLine(to: CGPoint(x: 7, y: 15))
            bucket.addQuadCurve(to: CGPoint(x: 5, y: 15), control: CGPoint(x: 6, y: 16))
            bucket.addLine(to: CGPoint(x: 1, y: 11))
            bucket.addQuadCurve(to: CGPoint(x: 1, y: 9), control: CGPoint(x: 0, y: 10))
            bucket.closeSubpath()
            bucket.move(to: CGPoint(x: 2, y: 8))
            bucket.addLine(to: CGPoint(x: 12, y: 8))
            context.stroke(bucket, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            var drop = Path()
            drop.move(to: CGPoint(x: 15, y: 9))
            drop.addCurve(to: CGPoint(x: 15, y: 17), control1: CGPoint(x: 10, y: 15), control2: CGPoint(x: 12, y: 17))
            drop.addCurve(to: CGPoint(x: 15, y: 9), control1: CGPoint(x: 18, y: 17), control2: CGPoint(x: 20, y: 15))
            context.fill(drop, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
