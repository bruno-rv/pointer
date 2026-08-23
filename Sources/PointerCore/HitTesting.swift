import Foundation

public enum HitTestTarget: Equatable, Sendable {
    case none
    case mark(Mark.ID)
    case handle(ResizeHandle)
}

public enum HitTesting {
    public static let defaultTolerance: Double = 0.02

    public static func hitTest(
        at point: NormalizedPoint,
        in marks: [Mark],
        selectedID: Mark.ID?,
        tolerance: Double = defaultTolerance,
        handleTolerance: Double = 0.03
    ) -> HitTestTarget {
        if let selectedID,
           let selected = marks.first(where: { $0.id == selectedID }),
           let handle = handle(at: point, in: selected.geometry, tolerance: handleTolerance)
        {
            return .handle(handle)
        }

        for mark in marks.reversed() {
            if intersects(mark: mark, at: point, tolerance: tolerance) {
                return .mark(mark.id)
            }
        }
        return .none
    }

    public static func handle(
        at point: NormalizedPoint,
        in geometry: MarkGeometry,
        tolerance: Double
    ) -> ResizeHandle? {
        for handle in ResizeGeometry.handles(for: geometry) {
            guard let handlePoint = ResizeGeometry.point(for: handle, in: geometry) else {
                continue
            }
            if hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= tolerance {
                return handle
            }
        }
        return nil
    }

    public static func intersects(mark: Mark, at point: NormalizedPoint, tolerance: Double) -> Bool {
        intersects(geometry: mark.geometry, at: point, tolerance: tolerance)
    }

    public static func intersects(
        mark: Mark,
        segmentFrom start: NormalizedPoint,
        to end: NormalizedPoint,
        tolerance: Double
    ) -> Bool {
        intersects(geometry: mark.geometry, segmentFrom: start, to: end, tolerance: tolerance)
    }

    public static func intersects(
        geometry: MarkGeometry,
        at point: NormalizedPoint,
        tolerance: Double
    ) -> Bool {
        switch geometry {
        case let .arrow(start, end):
            return distance(from: point, toSegmentFrom: start, to: end) <= tolerance
        case let .rectangle(rect), let .emoji(_, rect):
            return rect.contains(point, tolerance: tolerance)
        case let .ellipse(rect):
            return ellipseContains(point, in: rect, tolerance: tolerance)
        case let .freehand(points):
            return freehandContains(point, points: points, tolerance: tolerance)
        case let .spotlight(center, radius, _):
            return hypot(point.x - center.x, point.y - center.y) <= radius + tolerance
        }
    }

    public static func intersects(
        geometry: MarkGeometry,
        segmentFrom start: NormalizedPoint,
        to end: NormalizedPoint,
        tolerance: Double
    ) -> Bool {
        if intersects(geometry: geometry, at: start, tolerance: tolerance)
            || intersects(geometry: geometry, at: end, tolerance: tolerance)
        {
            return true
        }

        switch geometry {
        case let .arrow(a, b):
            return segmentDistance(start, end, a, b) <= tolerance
        case let .rectangle(rect), let .emoji(_, rect):
            return segmentIntersectsRect(start, end, rect.insetBy(dx: -tolerance, dy: -tolerance))
        case let .ellipse(rect):
            return segmentIntersectsEllipse(start, end, rect, tolerance: tolerance)
        case let .freehand(points):
            if points.count < 2 {
                if let only = points.first {
                    return distance(from: only, toSegmentFrom: start, to: end) <= tolerance
                }
                return false
            }
            return zip(points, points.dropFirst()).contains {
                segmentDistance(start, end, $0.0, $0.1) <= tolerance
            }
        case let .spotlight(center, radius, _):
            return distance(from: center, toSegmentFrom: start, to: end) <= radius + tolerance
        }
    }

    private static func freehandContains(
        _ point: NormalizedPoint,
        points: [NormalizedPoint],
        tolerance: Double
    ) -> Bool {
        if points.count == 1 {
            return hypot(point.x - points[0].x, point.y - points[0].y) <= tolerance
        }
        return zip(points, points.dropFirst()).contains {
            distance(from: point, toSegmentFrom: $0.0, to: $0.1) <= tolerance
        }
    }

    private static func ellipseContains(
        _ point: NormalizedPoint,
        in rect: NormalizedRect,
        tolerance: Double
    ) -> Bool {
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        guard expanded.width > 0, expanded.height > 0 else {
            return expanded.contains(point)
        }
        let nx = (point.x - (expanded.x + expanded.width / 2)) / (expanded.width / 2)
        let ny = (point.y - (expanded.y + expanded.height / 2)) / (expanded.height / 2)
        return nx * nx + ny * ny <= 1
    }

    static func distance(
        from point: NormalizedPoint,
        toSegmentFrom start: NormalizedPoint,
        to end: NormalizedPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let projection = max(
            0,
            min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
        )
        let nearest = NormalizedPoint(
            x: start.x + projection * dx,
            y: start.y + projection * dy
        )
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }

    private static func segmentDistance(
        _ a1: NormalizedPoint,
        _ a2: NormalizedPoint,
        _ b1: NormalizedPoint,
        _ b2: NormalizedPoint
    ) -> Double {
        if segmentsIntersect(a1, a2, b1, b2) {
            return 0
        }
        return min(
            distance(from: a1, toSegmentFrom: b1, to: b2),
            distance(from: a2, toSegmentFrom: b1, to: b2),
            distance(from: b1, toSegmentFrom: a1, to: a2),
            distance(from: b2, toSegmentFrom: a1, to: a2)
        )
    }

    private static func segmentsIntersect(
        _ p1: NormalizedPoint,
        _ p2: NormalizedPoint,
        _ q1: NormalizedPoint,
        _ q2: NormalizedPoint
    ) -> Bool {
        func cross(_ a: NormalizedPoint, _ b: NormalizedPoint, _ c: NormalizedPoint) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        func orientation(
            _ a: NormalizedPoint,
            _ b: NormalizedPoint,
            _ c: NormalizedPoint
        ) -> Int {
            let value = cross(a, b, c)
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }

        func contains(
            _ a: NormalizedPoint,
            _ b: NormalizedPoint,
            _ point: NormalizedPoint
        ) -> Bool {
            point.x >= min(a.x, b.x)
                && point.x <= max(a.x, b.x)
                && point.y >= min(a.y, b.y)
                && point.y <= max(a.y, b.y)
        }

        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)

        if o1 != o2, o3 != o4 {
            return true
        }

        return (o1 == 0 && contains(p1, p2, q1))
            || (o2 == 0 && contains(p1, p2, q2))
            || (o3 == 0 && contains(q1, q2, p1))
            || (o4 == 0 && contains(q1, q2, p2))
    }

    private static func segmentIntersectsRect(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        _ rect: NormalizedRect
    ) -> Bool {
        if rect.contains(start) || rect.contains(end) {
            return true
        }

        let corners = [
            NormalizedPoint(x: rect.x, y: rect.y),
            NormalizedPoint(x: rect.x + rect.width, y: rect.y),
            NormalizedPoint(x: rect.x + rect.width, y: rect.y + rect.height),
            NormalizedPoint(x: rect.x, y: rect.y + rect.height),
        ]
        for index in corners.indices {
            let next = corners[(index + 1) % corners.count]
            if segmentsIntersect(start, end, corners[index], next) {
                return true
            }
        }
        return false
    }

    private static func segmentIntersectsEllipse(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        _ rect: NormalizedRect,
        tolerance: Double
    ) -> Bool {
        let radiusX = rect.width / 2 + tolerance
        let radiusY = rect.height / 2 + tolerance
        guard radiusX > 0, radiusY > 0 else {
            return distance(from: rect.center, toSegmentFrom: start, to: end) <= tolerance
        }

        let center = rect.center
        let sx = (start.x - center.x) / radiusX
        let sy = (start.y - center.y) / radiusY
        let dx = (end.x - start.x) / radiusX
        let dy = (end.y - start.y) / radiusY
        let a = dx * dx + dy * dy
        guard a > 0 else {
            return sx * sx + sy * sy <= 1
        }

        let t = max(0, min(1, -(sx * dx + sy * dy) / a))
        let x = sx + t * dx
        let y = sy + t * dy
        return x * x + y * y <= 1
    }
}

extension NormalizedRect {
    func insetBy(dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(
            x: x + dx,
            y: y + dy,
            width: max(0, width - 2 * dx),
            height: max(0, height - 2 * dy)
        )
    }

    var center: NormalizedPoint {
        NormalizedPoint(x: x + width / 2, y: y + height / 2)
    }
}
