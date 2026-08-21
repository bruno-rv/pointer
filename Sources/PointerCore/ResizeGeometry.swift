import Foundation

public enum ResizeHandle: Equatable, Sendable {
    case arrowStart
    case arrowEnd
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight
    case spotlightCenter
    case spotlightRadius
}

public enum ResizeGeometry {
    public static func handles(for geometry: MarkGeometry) -> [ResizeHandle] {
        switch geometry {
        case .arrow:
            return [.arrowStart, .arrowEnd]
        case .rectangle, .ellipse:
            return [
                .topLeft, .topCenter, .topRight,
                .middleLeft, .middleRight,
                .bottomLeft, .bottomCenter, .bottomRight,
            ]
        case .freehand, .emoji:
            return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .spotlight:
            return [.spotlightCenter, .spotlightRadius]
        }
    }

    public static func point(for handle: ResizeHandle, in geometry: MarkGeometry) -> NormalizedPoint? {
        switch (geometry, handle) {
        case let (.arrow(start, _), .arrowStart):
            return start
        case let (.arrow(_, end), .arrowEnd):
            return end
        case let (.spotlight(center, _, _), .spotlightCenter):
            return center
        case let (.spotlight(center, radius, _), .spotlightRadius):
            return NormalizedPoint(x: center.x + radius, y: center.y)
        case (.rectangle, _), (.ellipse, _), (.freehand, _), (.emoji, _):
            guard let bounds = boundingRect(of: geometry) else { return nil }
            return point(for: handle, in: bounds)
        default:
            return nil
        }
    }

    public static func boundingRect(of geometry: MarkGeometry) -> NormalizedRect? {
        switch geometry {
        case let .arrow(start, end):
            return NormalizedRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case let .rectangle(rect), let .ellipse(rect), let .emoji(_, rect):
            return rect
        case let .freehand(points):
            return axisAlignedBounds(of: points)
        case let .spotlight(center, radius, _):
            return NormalizedRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        }
    }

    public static func translate(_ geometry: MarkGeometry, dx: Double, dy: Double) -> MarkGeometry {
        switch geometry {
        case let .arrow(start, end):
            return .arrow(start: start.offsetBy(dx: dx, dy: dy), end: end.offsetBy(dx: dx, dy: dy))
        case let .rectangle(rect):
            return .rectangle(rect.offsetBy(dx: dx, dy: dy))
        case let .ellipse(rect):
            return .ellipse(rect.offsetBy(dx: dx, dy: dy))
        case let .freehand(points):
            return .freehand(points.map { $0.offsetBy(dx: dx, dy: dy) })
        case let .emoji(text, rect):
            return .emoji(text: text, rect: rect.offsetBy(dx: dx, dy: dy))
        case let .spotlight(center, radius, dimness):
            return .spotlight(center: center.offsetBy(dx: dx, dy: dy), radius: radius, dimness: dimness)
        }
    }

    public static func resize(
        _ geometry: MarkGeometry,
        using handle: ResizeHandle,
        to point: NormalizedPoint,
        original: MarkGeometry
    ) -> MarkGeometry {
        switch original {
        case let .arrow(start, end):
            switch handle {
            case .arrowStart:
                return .arrow(start: point, end: end)
            case .arrowEnd:
                return .arrow(start: start, end: point)
            default:
                return geometry
            }

        case let .spotlight(_, _, dimness):
            switch handle {
            case .spotlightCenter:
                if case let .spotlight(_, radius, _) = original {
                    return .spotlight(center: point, radius: radius, dimness: dimness)
                }
                return geometry
            case .spotlightRadius:
                if case let .spotlight(center, _, _) = original {
                    let radius = hypot(point.x - center.x, point.y - center.y)
                    return .spotlight(center: center, radius: max(0, radius), dimness: dimness)
                }
                return geometry
            default:
                return geometry
            }

        case .rectangle, .ellipse:
            guard let bounds = boundingRect(of: original) else { return geometry }
            let newBounds = resizeBounds(bounds, using: handle, to: point, uniform: false)
            switch original {
            case .rectangle:
                return .rectangle(newBounds)
            case .ellipse:
                return .ellipse(newBounds)
            default:
                return geometry
            }

        case let .freehand(points):
            guard let bounds = boundingRect(of: original) else { return geometry }
            let newBounds = resizeBounds(bounds, using: handle, to: point, uniform: true)
            return .freehand(mapPoints(points, from: bounds, to: newBounds))

        case let .emoji(text, rect):
            let newBounds = resizeBounds(rect, using: handle, to: point, uniform: true)
            return .emoji(text: text, rect: newBounds)

        }
    }

    public static func rect(from start: NormalizedPoint, to end: NormalizedPoint) -> NormalizedRect {
        NormalizedRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public static func clampedSquare(centeredAt center: NormalizedPoint, side: Double) -> NormalizedRect {
        let side = max(0, side)
        var x = center.x - side / 2
        var y = center.y - side / 2
        var width = side
        var height = side
        if x < 0 {
            width += x
            x = 0
        }
        if y < 0 {
            height += y
            y = 0
        }
        if x + width > 1 {
            width = 1 - x
        }
        if y + height > 1 {
            height = 1 - y
        }
        let finalSide = max(0, min(width, height))
        return NormalizedRect(x: x, y: y, width: finalSide, height: finalSide)
    }

    private static func point(for handle: ResizeHandle, in bounds: NormalizedRect) -> NormalizedPoint? {
        let minX = bounds.x
        let minY = bounds.y
        let maxX = bounds.x + bounds.width
        let maxY = bounds.y + bounds.height
        let midX = bounds.x + bounds.width / 2
        let midY = bounds.y + bounds.height / 2

        switch handle {
        case .topLeft: return NormalizedPoint(x: minX, y: maxY)
        case .topCenter: return NormalizedPoint(x: midX, y: maxY)
        case .topRight: return NormalizedPoint(x: maxX, y: maxY)
        case .middleLeft: return NormalizedPoint(x: minX, y: midY)
        case .middleRight: return NormalizedPoint(x: maxX, y: midY)
        case .bottomLeft: return NormalizedPoint(x: minX, y: minY)
        case .bottomCenter: return NormalizedPoint(x: midX, y: minY)
        case .bottomRight: return NormalizedPoint(x: maxX, y: minY)
        case .arrowStart, .arrowEnd, .spotlightCenter, .spotlightRadius:
            return nil
        }
    }

    private static func oppositeCorner(for handle: ResizeHandle, in bounds: NormalizedRect) -> NormalizedPoint {
        let minX = bounds.x
        let minY = bounds.y
        let maxX = bounds.x + bounds.width
        let maxY = bounds.y + bounds.height

        switch handle {
        case .topLeft: return NormalizedPoint(x: maxX, y: minY)
        case .topRight: return NormalizedPoint(x: minX, y: minY)
        case .bottomLeft: return NormalizedPoint(x: maxX, y: maxY)
        case .bottomRight: return NormalizedPoint(x: minX, y: maxY)
        case .topCenter: return NormalizedPoint(x: (minX + maxX) / 2, y: minY)
        case .bottomCenter: return NormalizedPoint(x: (minX + maxX) / 2, y: maxY)
        case .middleLeft: return NormalizedPoint(x: maxX, y: (minY + maxY) / 2)
        case .middleRight: return NormalizedPoint(x: minX, y: (minY + maxY) / 2)
        case .arrowStart, .arrowEnd, .spotlightCenter, .spotlightRadius:
            return NormalizedPoint(x: minX, y: minY)
        }
    }

    private static func resizeBounds(
        _ bounds: NormalizedRect,
        using handle: ResizeHandle,
        to point: NormalizedPoint,
        uniform: Bool
    ) -> NormalizedRect {
        if uniform {
            return uniformCornerResize(bounds, using: handle, to: point)
        }

        var minX = bounds.x
        var minY = bounds.y
        var maxX = bounds.x + bounds.width
        var maxY = bounds.y + bounds.height

        switch handle {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .topCenter:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .middleLeft:
            minX = point.x
        case .middleRight:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .bottomCenter:
            minY = point.y
        case .bottomRight:
            maxX = point.x
            minY = point.y
        case .arrowStart, .arrowEnd, .spotlightCenter, .spotlightRadius:
            break
        }

        return NormalizedRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func uniformCornerResize(
        _ bounds: NormalizedRect,
        using handle: ResizeHandle,
        to point: NormalizedPoint
    ) -> NormalizedRect {
        let anchor = oppositeCorner(for: handle, in: bounds)
        let width = max(bounds.width, 1e-12)
        let height = max(bounds.height, 1e-12)
        let scale = max(
            abs(point.x - anchor.x) / width,
            abs(point.y - anchor.y) / height
        )
        let newWidth = bounds.width * scale
        let newHeight = bounds.height * scale

        switch handle {
        case .topRight:
            return NormalizedRect(x: anchor.x, y: anchor.y, width: newWidth, height: newHeight)
        case .topLeft:
            return NormalizedRect(x: anchor.x - newWidth, y: anchor.y, width: newWidth, height: newHeight)
        case .bottomRight:
            return NormalizedRect(x: anchor.x, y: anchor.y - newHeight, width: newWidth, height: newHeight)
        case .bottomLeft:
            return NormalizedRect(
                x: anchor.x - newWidth,
                y: anchor.y - newHeight,
                width: newWidth,
                height: newHeight
            )
        default:
            return resizeBounds(bounds, using: handle, to: point, uniform: false)
        }
    }

    private static func mapPoints(
        _ points: [NormalizedPoint],
        from oldBounds: NormalizedRect,
        to newBounds: NormalizedRect
    ) -> [NormalizedPoint] {
        points.map { point in
            NormalizedPoint(
                x: scale(
                    point.x,
                    oldMin: oldBounds.x,
                    oldSize: oldBounds.width,
                    newMin: newBounds.x,
                    newSize: newBounds.width
                ),
                y: scale(
                    point.y,
                    oldMin: oldBounds.y,
                    oldSize: oldBounds.height,
                    newMin: newBounds.y,
                    newSize: newBounds.height
                )
            )
        }
    }

    private static func scale(
        _ value: Double,
        oldMin: Double,
        oldSize: Double,
        newMin: Double,
        newSize: Double
    ) -> Double {
        guard oldSize > 0 else { return newMin + newSize / 2 }
        return newMin + ((value - oldMin) / oldSize) * newSize
    }

    private static func axisAlignedBounds(of points: [NormalizedPoint]) -> NormalizedRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension NormalizedPoint {
    func offsetBy(dx: Double, dy: Double) -> NormalizedPoint {
        NormalizedPoint(x: x + dx, y: y + dy)
    }
}

extension NormalizedRect {
    func offsetBy(dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    func contains(_ point: NormalizedPoint, tolerance: Double = 0) -> Bool {
        let t = max(0, tolerance)
        return point.x >= x - t
            && point.x <= x + width + t
            && point.y >= y - t
            && point.y <= y + height + t
    }
}
