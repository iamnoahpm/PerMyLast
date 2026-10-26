import SwiftUI
import AppKit

// MARK: - Empty-state illustrations
//
// The four scenes ship as SVG files (Illustrations/empty-*.svg) and are drawn as vectors with
// Canvas, so colours stay inside the assets. The renderer understands the small SVG subset the
// scenes use. The CSS animations in each file are mirrored by `Motion` below, keyed by class name.

enum EmptyScene: String {
    case reply, write, understand, ask

    init(mode: String, isAsk: Bool) {
        if isAsk { self = .ask; return }
        switch mode {
        case "Write": self = .write
        case "Understand": self = .understand
        default: self = .reply
        }
    }
}

/// The scene for the current mode at 200 × 110 pt (20:11), shrinking to no less than 160 pt wide.
/// Animates only while visible and the app is active; static under Reduce Motion.
struct EmptyIllustration: View {
    let scene: EmptyScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var occluded = false
    @State private var available: CGFloat = 400

    /// 200 pt wide; below 380 pt of available width it shrinks proportionally, never under 160.
    private var width: CGFloat { available >= 380 ? 200 : max(160, 200 * available / 380) }

    private var animating: Bool { !reduceMotion && activeState != .inactive && !occluded }

    var body: some View {
        let svg = SVGScene.load(scene)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { timeline in
            let t = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                svg.draw(in: &ctx, size: size, time: t)
            }
        }
        .frame(width: width, height: width * 11 / 20)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeOcclusionStateNotification)) { _ in
            occluded = !NSApp.occlusionState.contains(.visible)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

private struct Motion {
    enum Kind { case scaleY(CGFloat, CGFloat), translateX(CGFloat), rotate(Double, Double), drift(CGFloat, CGFloat) }
    let kind: Kind
    let duration: Double

    static let table: [String: Motion] = [
        "flap": Motion(kind: .scaleY(1, 1.12), duration: 2.4),
        "wave": Motion(kind: .translateX(-6), duration: 4),
        "sway": Motion(kind: .rotate(0, -1.5), duration: 5),
        "swing": Motion(kind: .rotate(-0.8, 0.8), duration: 4),
        "frondL": Motion(kind: .rotate(0, 2.5), duration: 5),
        "frondR": Motion(kind: .rotate(0, -2.5), duration: 5.4),
        "bird": Motion(kind: .drift(-6, -2), duration: 6),
    ]
    static let delays: [String: Double] = ["bird2": 1.5]

    /// 0 → 1 → 0 with ease-in-out on each half, like the CSS keyframes.
    func progress(_ time: Double, delay: Double) -> Double {
        let local = max(0, time - delay) / duration
        return 0.5 - 0.5 * cos(2 * .pi * local)
    }
}

// MARK: - Scene

private final class SVGNode {
    var tag: String
    var attrs: [String: String]
    var children: [SVGNode] = []
    init(tag: String, attrs: [String: String]) { self.tag = tag; self.attrs = attrs }
    var classes: [String] { (attrs["class"] ?? "").split(separator: " ").map(String.init) }
}

private struct Paint {
    var fill: String? = "#000000"
    var fillOpacity: Double = 1
    var stroke: String?
    var strokeWidth: CGFloat = 1
    var cap: CGLineCap = .butt
    var join: CGLineJoin = .miter
    var opacity: Double = 1

    func applying(_ n: SVGNode) -> Paint {
        var p = self
        if let v = n.attrs["fill"] { p.fill = v == "none" ? nil : v }
        if let v = n.attrs["fill-opacity"], let d = Double(v) { p.fillOpacity = d }
        if let v = n.attrs["stroke"] { p.stroke = v == "none" ? nil : v }
        if let v = n.attrs["stroke-width"], let d = Double(v) { p.strokeWidth = d }
        if let v = n.attrs["stroke-linecap"] { p.cap = v == "round" ? .round : (v == "square" ? .square : .butt) }
        if let v = n.attrs["stroke-linejoin"] { p.join = v == "round" ? .round : (v == "bevel" ? .bevel : .miter) }
        if let v = n.attrs["opacity"], let d = Double(v) { p.opacity *= d }
        return p
    }
}

private final class SVGScene: NSObject, XMLParserDelegate {
    private static var cache: [EmptyScene: SVGScene] = [:]

    static func load(_ scene: EmptyScene) -> SVGScene {
        if let s = cache[scene] { return s }
        let s = SVGScene(resource: "empty-\(scene.rawValue)")
        cache[scene] = s
        return s
    }

    private var root = SVGNode(tag: "root", attrs: [:])
    private var stack: [SVGNode] = []
    private var gradients: [String: [(offset: Double, color: String)]] = [:]
    private var clips: [String: CGRect] = [:]
    private var clipRadius: [String: CGFloat] = [:]
    private var currentGradient: String?
    private var currentClip: String?
    private var styleText = ""
    private var inStyle = false
    private var origins: [String: CGPoint] = [:]
    private var viewBox = CGSize(width: 240, height: 132)

    init(resource: String) {
        super.init()
        guard let url = Bundle.main.url(forResource: resource, withExtension: "svg"),
              let parser = XMLParser(contentsOf: url) else { return }
        parser.delegate = self
        stack = [root]
        parser.parse()
        parseOrigins()
    }

    // MARK: XML

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "svg":
            let nums = (a["viewBox"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if nums.count == 4 { viewBox = CGSize(width: nums[2], height: nums[3]) }
        case "style": inStyle = true
        case "linearGradient": currentGradient = a["id"]; if let id = a["id"] { gradients[id] = [] }
        case "stop":
            if let g = currentGradient {
                gradients[g, default: []].append((Double(a["offset"] ?? "0") ?? 0, a["stop-color"] ?? "#000000"))
            }
        case "clipPath": currentClip = a["id"]
        case "defs": break
        default:
            if let c = currentClip, name == "rect" {
                clips[c] = CGRect(x: num(a["x"]), y: num(a["y"]), width: num(a["width"]), height: num(a["height"]))
                clipRadius[c] = num(a["rx"])
                return
            }
            let node = SVGNode(tag: name, attrs: a)
            stack.last?.children.append(node)
            stack.append(node)
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "style": inStyle = false
        case "linearGradient": currentGradient = nil
        case "clipPath": currentClip = nil
        case "svg", "defs", "stop": break
        default:
            if currentClip == nil, stack.count > 1, stack.last?.tag == name { stack.removeLast() }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inStyle { styleText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inStyle { styleText += String(decoding: CDATABlock, as: UTF8.self) }
    }

    /// `.sway{transform-origin:168px 124px;…}` → origins["sway"].
    private func parseOrigins() {
        guard let re = try? NSRegularExpression(pattern: #"\.(\w+)\{transform-origin:\s*(-?[\d.]+)px\s+(-?[\d.]+)px"#) else { return }
        let s = styleText as NSString
        for m in re.matches(in: styleText, range: NSRange(location: 0, length: s.length)) {
            origins[s.substring(with: m.range(at: 1))] = CGPoint(x: Double(s.substring(with: m.range(at: 2))) ?? 0,
                                                                  y: Double(s.substring(with: m.range(at: 3))) ?? 0)
        }
    }

    // MARK: Drawing

    func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let k = size.width / viewBox.width
        ctx.scaleBy(x: k, y: k)
        for child in root.children { draw(child, &ctx, Paint(), time) }
    }

    private func draw(_ n: SVGNode, _ parent: inout GraphicsContext, _ inherited: Paint, _ time: Double) {
        var ctx = parent
        let paint = inherited.applying(n)

        if let t = n.attrs["transform"] { applyTransform(t, &ctx) }
        applyMotion(n, &ctx, time)
        if let ref = n.attrs["clip-path"], let id = urlID(ref), let r = clips[id] {
            ctx.clip(to: Path(roundedRect: r, cornerRadius: clipRadius[id] ?? 0, style: .continuous))
        }

        switch n.tag {
        case "g": for c in n.children { draw(c, &ctx, paint, time) }
        case "rect":
            let r = CGRect(x: num(n.attrs["x"]), y: num(n.attrs["y"]), width: num(n.attrs["width"]), height: num(n.attrs["height"]))
            let rx = num(n.attrs["rx"])
            paintShape(rx > 0 ? Path(roundedRect: r, cornerRadius: rx) : Path(r), paint, &ctx)
        case "circle":
            let c = CGPoint(x: num(n.attrs["cx"]), y: num(n.attrs["cy"])), r = num(n.attrs["r"])
            paintShape(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), paint, &ctx)
        case "ellipse":
            let c = CGPoint(x: num(n.attrs["cx"]), y: num(n.attrs["cy"])), rx = num(n.attrs["rx"]), ry = num(n.attrs["ry"])
            paintShape(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)), paint, &ctx)
        case "line":
            var p = Path()
            p.move(to: CGPoint(x: num(n.attrs["x1"]), y: num(n.attrs["y1"])))
            p.addLine(to: CGPoint(x: num(n.attrs["x2"]), y: num(n.attrs["y2"])))
            var noFill = paint; noFill.fill = nil
            paintShape(p, noFill, &ctx)
        case "path":
            paintShape(Self.path(from: n.attrs["d"] ?? ""), paint, &ctx)
        default: break
        }
    }

    private func paintShape(_ path: Path, _ paint: Paint, _ ctx: inout GraphicsContext) {
        if let fill = paint.fill {
            let alpha = paint.opacity * paint.fillOpacity
            if let id = urlID(fill), let stops = gradients[id] {
                let box = path.boundingRect
                let g = Gradient(stops: stops.map { .init(color: Self.color($0.color), location: $0.offset) })
                var c = ctx; c.opacity *= alpha
                c.fill(path, with: .linearGradient(g, startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.minX, y: box.maxY)))
            } else {
                var c = ctx; c.opacity *= alpha
                c.fill(path, with: .color(Self.color(fill)))
            }
        }
        if let stroke = paint.stroke {
            var c = ctx; c.opacity *= paint.opacity
            c.stroke(path, with: .color(Self.color(stroke)),
                     style: StrokeStyle(lineWidth: paint.strokeWidth, lineCap: paint.cap, lineJoin: paint.join))
        }
    }

    private func applyMotion(_ n: SVGNode, _ ctx: inout GraphicsContext, _ time: Double) {
        let classes = n.classes
        guard let name = classes.first(where: { Motion.table[$0] != nil }), let m = Motion.table[name] else { return }
        let delay = classes.compactMap { Motion.delays[$0] }.first ?? 0
        let p = m.progress(time, delay: delay)
        let o = origins[name] ?? .zero
        switch m.kind {
        case .scaleY(let a, let b):
            ctx.translateBy(x: o.x, y: o.y)
            ctx.scaleBy(x: 1, y: a + (b - a) * p)
            ctx.translateBy(x: -o.x, y: -o.y)
        case .translateX(let dx): ctx.translateBy(x: dx * p, y: 0)
        case .drift(let dx, let dy): ctx.translateBy(x: dx * p, y: dy * p)
        case .rotate(let a, let b):
            ctx.translateBy(x: o.x, y: o.y)
            ctx.rotate(by: .degrees(a + (b - a) * p))
            ctx.translateBy(x: -o.x, y: -o.y)
        }
    }

    // MARK: Parsing helpers

    private func num(_ s: String?) -> CGFloat { CGFloat(Double(s ?? "") ?? 0) }

    private func urlID(_ s: String) -> String? {
        guard s.hasPrefix("url(#"), let end = s.firstIndex(of: ")") else { return nil }
        return String(s[s.index(s.startIndex, offsetBy: 5)..<end])
    }

    private func applyTransform(_ t: String, _ ctx: inout GraphicsContext) {
        guard let re = try? NSRegularExpression(pattern: #"(\w+)\(([^)]*)\)"#) else { return }
        let s = t as NSString
        for m in re.matches(in: t, range: NSRange(location: 0, length: s.length)) {
            let name = s.substring(with: m.range(at: 1))
            let v = s.substring(with: m.range(at: 2)).split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            switch name {
            case "translate": ctx.translateBy(x: v.first ?? 0, y: v.count > 1 ? v[1] : 0)
            case "scale": ctx.scaleBy(x: v.first ?? 1, y: v.count > 1 ? v[1] : (v.first ?? 1))
            case "rotate": ctx.rotate(by: .degrees(v.first ?? 0))
            default: break
            }
        }
    }

    private static func color(_ s: String) -> Color {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard let v = UInt32(h, radix: 16) else { return .clear }
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// SVG path data: M L H V C S Q T Z in absolute and relative forms.
    private static func path(from d: String) -> Path {
        var tokens: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter { flush(); tokens.append(String(ch)) }
            else if ch == " " || ch == "," { flush() }
            else if ch == "-" { flush(); cur = "-" }
            else if ch == "." && cur.contains(".") { flush(); cur = "." }
            else { cur.append(ch) }
        }
        flush()

        var p = Path()
        var i = 0
        var cmd: Character = "M"
        var pt = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        var lastCmd: Character = "M"

        func next() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        func hasNumber() -> Bool { i < tokens.count && !(tokens[i].first?.isLetter ?? false) }

        while i < tokens.count {
            if let f = tokens[i].first, f.isLetter { cmd = f; i += 1 }
            else if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }
            let rel = cmd.isLowercase
            let o = rel ? pt : .zero
            var newCtrl: CGPoint?
            switch cmd.uppercased().first! {
            case "M":
                pt = CGPoint(x: o.x + next(), y: o.y + next()); start = pt; p.move(to: pt)
            case "L":
                pt = CGPoint(x: o.x + next(), y: o.y + next()); p.addLine(to: pt)
            case "H":
                pt = CGPoint(x: (rel ? pt.x : 0) + next(), y: pt.y); p.addLine(to: pt)
            case "V":
                pt = CGPoint(x: pt.x, y: (rel ? pt.y : 0) + next()); p.addLine(to: pt)
            case "C":
                let c1 = CGPoint(x: o.x + next(), y: o.y + next()), c2 = CGPoint(x: o.x + next(), y: o.y + next())
                pt = CGPoint(x: o.x + next(), y: o.y + next()); p.addCurve(to: pt, control1: c1, control2: c2); newCtrl = c2
            case "S":
                let c1 = reflect(lastCtrl, pt, "CS".contains(lastCmd.uppercased()))
                let c2 = CGPoint(x: o.x + next(), y: o.y + next())
                pt = CGPoint(x: o.x + next(), y: o.y + next()); p.addCurve(to: pt, control1: c1, control2: c2); newCtrl = c2
            case "Q":
                let c = CGPoint(x: o.x + next(), y: o.y + next())
                pt = CGPoint(x: o.x + next(), y: o.y + next()); p.addQuadCurve(to: pt, control: c); newCtrl = c
            case "T":
                let c = reflect(lastCtrl, pt, "QT".contains(lastCmd.uppercased()))
                pt = CGPoint(x: o.x + next(), y: o.y + next()); p.addQuadCurve(to: pt, control: c); newCtrl = c
            case "Z":
                p.closeSubpath(); pt = start
            default:
                i = tokens.count
            }
            lastCtrl = newCtrl
            lastCmd = cmd
            if cmd.uppercased() == "Z" && !hasNumber() { continue }
        }
        return p
    }

    private static func reflect(_ ctrl: CGPoint?, _ pt: CGPoint, _ valid: Bool) -> CGPoint {
        guard valid, let c = ctrl else { return pt }
        return CGPoint(x: 2 * pt.x - c.x, y: 2 * pt.y - c.y)
    }
}
