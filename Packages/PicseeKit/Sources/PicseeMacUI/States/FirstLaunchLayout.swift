import AppKit

/// Geometry from B4's pinned 960×640 prototype. Coordinates returned in AppKit's bottom-left system.
struct FirstLaunchLayout {
    struct Print: Equatable {
        let name: String
        let frame: NSRect
        let angle: CGFloat
        let push: CGFloat
        let hidden: Bool
    }
    private struct Spec {
        let anchor: String
        let a: CGFloat
        let b: CGFloat
        let angle: CGFloat
        let name: String
    }
    private static let specs = [
        Spec(anchor: "TL", a: 70, b: 60, angle: -7, name: "alley"),
        Spec(anchor: "T", a: 196, b: 26, angle: 4, name: "lakeside"),
        Spec(anchor: "R", a: 30, b: 26, angle: 8, name: "hillside"),
        Spec(anchor: "BR", a: 176, b: 14, angle: -5, name: "gate"),
        Spec(anchor: "BL", a: 52, b: 30, angle: 6, name: "temple"),
        Spec(anchor: "L", a: 26, b: -34, angle: -4, name: "lakehouse")
    ]
    static func scale(_ size: NSSize) -> CGFloat {
        min(1.25, max(0.8, min(size.width / 960, size.height / 640)))
    }
    static func prints(in size: NSSize, centre: NSRect) -> [Print] {
        let width = size.width, height = size.height, s = scale(size)
        let pw = 150 * s, ph = 110 * s
        let keepWidth = max(420, centre.width)
        let keep = NSRect(x: centre.midX - keepWidth / 2 - 16, y: centre.minY - 16,
                          width: keepWidth + 32, height: centre.height + 32)
        let traffic = NSRect(x: 0, y: height - 34, width: 84, height: 34)
        let window = NSRect(origin: .zero, size: size)
        func rotatedBox(_ frame: NSRect, angle: CGFloat) -> NSRect {
            let radians = abs(angle) * .pi / 180
            let bw = frame.width + 12, bh = frame.height + 12
            let halfW = (bw * cos(radians) + bh * sin(radians)) / 2
            let halfH = (bw * sin(radians) + bh * cos(radians)) / 2
            return NSRect(x: frame.midX - halfW, y: frame.midY - halfH,
                          width: halfW * 2, height: halfH * 2)
        }
        func area(_ rect: NSRect) -> CGFloat { max(0, rect.width) * max(0, rect.height) }
        return specs.map { spec in
            func place(_ push: CGFloat, axis: String) -> (NSRect, NSRect, CGFloat) {
                let gx = spec.a * s - (axis == "x" ? push : 0)
                let gy = spec.b * s - (axis == "y" ? push : 0)
                let top: CGFloat
                let x: CGFloat
                switch spec.anchor {
                case "TL": x = gx; top = gy
                case "TR": x = width - gx - pw; top = gy
                case "BL": x = gx; top = height - gy - ph
                case "BR": x = width - gx - pw; top = height - gy - ph
                case "L": x = gx; top = height / 2 + spec.b * s - ph / 2
                case "R": x = width - gx - pw; top = height / 2 + spec.b * s - ph / 2
                case "T": x = width / 2 + spec.a * s - pw / 2; top = gy
                default: x = width / 2 + spec.a * s - pw / 2; top = height - gy - ph
                }
                let frame = NSRect(x: x, y: height - top - ph, width: pw, height: ph)
                let box = rotatedBox(frame, angle: spec.angle)
                return (frame, box, area(box.intersection(window)) / area(box))
            }
            var chosen = place(0, axis: "x"), push: CGFloat = 0
            if chosen.1.intersects(keep) {
                let axes = ["L", "R"].contains(spec.anchor) ? ["x"] :
                    ["T", "B"].contains(spec.anchor) ? ["y"] : ["x", "y"]
                search: for step in stride(from: CGFloat(2), through: 60, by: 2) {
                    for axis in axes {
                        let candidate = place(step, axis: axis)
                        if candidate.2 >= 0.75 && !candidate.1.intersects(traffic) && !candidate.1.intersects(keep) {
                            chosen = candidate; push = step; break search
                        }
                    }
                }
            }
            let hidden = width < 720 || height < 480 || chosen.1.intersects(keep) ||
                chosen.2 < 0.75 || chosen.1.intersects(traffic)
            return Print(name: spec.name, frame: chosen.0, angle: spec.angle, push: push, hidden: hidden)
        }
    }
}
