import AppKit
import CoreGraphics
import PointerCore

public enum MarkRenderer {
    public static func draw(
        marks: [Mark],
        in bounds: CGRect,
        context: CGContext
    ) {
        for mark in marks {
            draw(mark: mark, in: bounds, context: context)
        }
    }

    public static func draw(
        committedMarks: [Mark],
        activeDraft: Mark?,
        in bounds: CGRect,
        context: CGContext
    ) {
        draw(marks: committedMarks, in: bounds, context: context)
        if let activeDraft {
            draw(mark: activeDraft, in: bounds, context: context)
        }
    }

    public static func draw(
        plan: RenderPlan,
        in bounds: CGRect,
        context: CGContext
    ) {
        draw(marks: plan.committedMarks, in: bounds, context: context)
        if let activeDraft = plan.activeDraft {
            draw(mark: activeDraft, in: bounds, context: context)
        }
        guard plan.handles.resize.isVisible,
              let selectedID = plan.handles.selection.selectedMarkID,
              let selectedMark = plan.committedMarks.first(where: { $0.id == selectedID })
        else {
            return
        }
        drawResizeHandles(
            plan.handles.resize.handles,
            for: selectedMark,
            in: bounds,
            context: context
        )
    }

    public static func draw(
        canvas: Canvas,
        selectedID: Mark.ID? = nil,
        in bounds: CGRect,
        context: CGContext
    ) {
        draw(marks: canvas.marks, in: bounds, context: context)
        guard let selectedID,
              let selectedMark = canvas.marks.first(where: { $0.id == selectedID })
        else {
            return
        }
        drawSelectionHandles(for: selectedMark, in: bounds, context: context)
    }

    public static func visibleHandles(for mark: Mark, selectedID: Mark.ID?) -> [ResizeHandle] {
        guard mark.id == selectedID else { return [] }
        return ResizeGeometry.handles(for: mark.geometry)
    }

    private static func draw(mark: Mark, in bounds: CGRect, context: CGContext) {
        switch mark.geometry {
        case let .spotlight(center, radius, dimness):
            drawSpotlight(center: center, radius: radius, dimness: dimness, in: bounds, context: context)
        case let .arrow(start, end):
            drawArrow(start: start, end: end, style: mark.style, in: bounds, context: context)
        case let .rectangle(rect):
            drawShape(rect: rect, style: mark.style, in: bounds, context: context) { path, mapped in
                path.addRect(mapped)
            }
        case let .ellipse(rect):
            drawShape(rect: rect, style: mark.style, in: bounds, context: context) { path, mapped in
                path.addEllipse(in: mapped)
            }
        case let .freehand(points):
            drawFreehand(points: points, style: mark.style, in: bounds, context: context)
        case let .emoji(text, rect):
            drawEmoji(text: text, rect: rect, style: mark.style, in: bounds, context: context)
        }
    }

    private static func drawShape(
        rect: NormalizedRect,
        style: MarkStyle,
        in bounds: CGRect,
        context: CGContext,
        _ addPath: (CGMutablePath, CGRect) -> Void
    ) {
        let path = CGMutablePath()
        let mapped = map(rect, in: bounds)
        addPath(path, mapped)
        context.saveGState()
        apply(style: style, to: context)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(
        start: NormalizedPoint,
        end: NormalizedPoint,
        style: MarkStyle,
        in bounds: CGRect,
        context: CGContext
    ) {
        let startPoint = map(start, in: bounds)
        let endPoint = map(end, in: bounds)
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let headLength = max(style.strokeWidth * 3, 8)
        let headAngle = Double.pi / 7
        let left = CGPoint(
            x: endPoint.x - CGFloat(cos(angle - headAngle)) * headLength,
            y: endPoint.y - CGFloat(sin(angle - headAngle)) * headLength
        )
        let right = CGPoint(
            x: endPoint.x - CGFloat(cos(angle + headAngle)) * headLength,
            y: endPoint.y - CGFloat(sin(angle + headAngle)) * headLength
        )
        let path = CGMutablePath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        path.move(to: left)
        path.addLine(to: endPoint)
        path.addLine(to: right)
        context.saveGState()
        apply(style: style, to: context)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawFreehand(
        points: [NormalizedPoint],
        style: MarkStyle,
        in bounds: CGRect,
        context: CGContext
    ) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: map(first, in: bounds))
        for point in points.dropFirst() {
            path.addLine(to: map(point, in: bounds))
        }
        context.saveGState()
        apply(style: style, to: context)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawEmoji(
        text: String,
        rect: NormalizedRect,
        style: MarkStyle,
        in bounds: CGRect,
        context: CGContext
    ) {
        let mapped = map(rect, in: bounds)
        let font = NSFont.systemFont(ofSize: max(1, mapped.height * 0.85))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(
                calibratedRed: style.color.red,
                green: style.color.green,
                blue: style.color.blue,
                alpha: style.color.alpha * style.opacity
            ),
        ]
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        (text as NSString).draw(in: mapped, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawSpotlight(
        center: NormalizedPoint,
        radius: Double,
        dimness: Double,
        in bounds: CGRect,
        context: CGContext
    ) {
        let focusCenter = map(center, in: bounds)
        let focusRadius = CGFloat(radius) * min(bounds.width, bounds.height)
        let focusRect = CGRect(
            x: focusCenter.x - focusRadius,
            y: focusCenter.y - focusRadius,
            width: focusRadius * 2,
            height: focusRadius * 2
        )

        context.saveGState()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: dimness))
        let dimmedRegion = CGMutablePath()
        dimmedRegion.addRect(bounds)
        dimmedRegion.addEllipse(in: focusRect)
        context.addPath(dimmedRegion)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    private static func drawSelectionHandles(
        for mark: Mark,
        in bounds: CGRect,
        context: CGContext
    ) {
        let handles = visibleHandles(for: mark, selectedID: mark.id)
        drawResizeHandles(handles, for: mark, in: bounds, context: context)
    }

    private static func drawResizeHandles(
        _ handles: [ResizeHandle],
        for mark: Mark,
        in bounds: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(1.5)
        for handle in handles {
            guard let point = ResizeGeometry.point(for: handle, in: mark.geometry) else { continue }
            let center = map(point, in: bounds)
            let radius: CGFloat = 5
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
        context.restoreGState()
    }

    private static func apply(style: MarkStyle, to context: CGContext) {
        context.setStrokeColor(CGColor(
            red: style.color.red,
            green: style.color.green,
            blue: style.color.blue,
            alpha: style.color.alpha * style.opacity
        ))
        context.setLineWidth(style.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private static func map(_ point: NormalizedPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.minX + CGFloat(point.x) * bounds.width,
            y: bounds.minY + CGFloat(point.y) * bounds.height
        )
    }

    private static func map(_ rect: NormalizedRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + CGFloat(rect.x) * bounds.width,
            y: bounds.minY + CGFloat(rect.y) * bounds.height,
            width: CGFloat(rect.width) * bounds.width,
            height: CGFloat(rect.height) * bounds.height
        )
    }
}
