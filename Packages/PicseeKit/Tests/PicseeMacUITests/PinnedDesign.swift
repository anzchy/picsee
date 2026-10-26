import Foundation
import CryptoKit

/// Reads values from a SHA-pinned HTML state. Test support only; this is a deliberately small CSS reader.
struct PinnedDesign {
    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = "Pinned design: \(description)" }
    }
    struct Edges: Equatable { let top: Double; let right: Double; let bottom: Double; let left: Double }
    struct Font: Equatable { let size: Double; let weight: Int; let lineHeight: Double? }
    struct Color: Equatable { let red: Double; let green: Double; let blue: Double; let alpha: Double }
    private struct Rule { let selector: String; let declarations: [String: String]; let min: Double?; let max: Double?; let order: Int }
    private let name: String
    private let rules: [Rule]
    private let appearance: String

    static func page(_ name: String, source: String = #filePath) throws -> Self {
        let tests = URL(fileURLWithPath: source).deletingLastPathComponent()
        let root = tests.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("design/prototypes/picsee-browser/states")
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: manifestData)
        guard let entry = catalog.states.first(where: { $0.name == name }),
              !entry.file.contains("/"), !entry.file.contains("..") else {
            throw Error("unknown page '\(name)' in manifest.json")
        }
        let data = try Data(contentsOf: directory.appendingPathComponent(entry.file))
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == entry.sha256 else {
            throw Error("\(entry.file) SHA256 mismatch: manifest expected \(entry.sha256), actual \(actual). Re-pin the design deliberately.")
        }
        guard let html = String(data: data, encoding: .utf8) else { throw Error("\(entry.file) is not UTF-8") }
        let styles = matches("(?s)<style\\b[^>]*>(.*?)</style>", in: html).compactMap { $0.first }
        guard !styles.isEmpty else { throw Error("\(entry.file) has no inline CSS") }
        var rules: [Rule] = []
        for style in styles { parse(style, min: nil, max: nil, into: &rules) }
        let appearance = html.contains("class=\"theme-dark\"") ? "dark" : "light"
        return Self(name: name, rules: rules, appearance: appearance)
    }

    func raw(_ selector: String, _ property: String, viewport: Double) throws -> String {
        let candidates = rules.filter { rule in
            rule.selector == selector && (rule.min == nil || viewport >= rule.min!) &&
                (rule.max == nil || viewport <= rule.max!)
        }
        guard let value = candidates.sorted(by: { ($0.selector.count, $0.order) < ($1.selector.count, $1.order) })
            .last(where: { $0.declarations[property] != nil })?.declarations[property] else {
            throw Error("\(name) selector '\(selector)' property '\(property)' at \(viewport)pt: no matching declaration")
        }
        return try resolveVars(value, viewport: viewport, context: "\(selector) \(property)", tokenSelector: selector)
    }

    func length(_ selector: String, _ property: String, viewport: Double, percentageBase: Double? = nil) throws -> Double {
        let value = try raw(selector, property, viewport: viewport)
        guard let result = evaluate(value, viewport: viewport, percentageBase: percentageBase) else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected length, got '\(value)'")
        }
        return result
    }

    func lineHeight(_ selector: String, viewport: Double) throws -> Double {
        let size = try length(selector, "font-size", viewport: viewport)
        let value = try raw(selector, "line-height", viewport: viewport)
        guard let number = evaluate(value, viewport: viewport) else {
            throw Error("\(name) \(selector) line-height at \(viewport)pt: unresolved '\(value)'")
        }
        return value.hasSuffix("px") ? number : size * number
    }

    func lengthValue(_ expression: String, viewport: Double, percentageBase: Double? = nil) throws -> Double {
        guard let number = evaluate(expression, viewport: viewport, percentageBase: percentageBase) else {
            throw Error("\(name) length expression at \(viewport)pt: expected a resolvable length, got '\(expression)'")
        }
        return number
    }

    func edges(_ selector: String, _ property: String, viewport: Double) throws -> Edges {
        let value = try raw(selector, property, viewport: viewport)
        let parts = Self.splitWhitespace(value)
        guard (1...4).contains(parts.count) else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected 1–4 sides, got '\(value)'")
        }
        let numbers = try parts.map { part -> Double in
            guard let number = evaluate(part, viewport: viewport) else {
                throw Error("\(name) \(selector) \(property) at \(viewport)pt: unresolved side '\(part)' in '\(value)'")
            }
            return number
        }
        switch numbers.count {
        case 1: return Edges(top: numbers[0], right: numbers[0], bottom: numbers[0], left: numbers[0])
        case 2: return Edges(top: numbers[0], right: numbers[1], bottom: numbers[0], left: numbers[1])
        case 3: return Edges(top: numbers[0], right: numbers[1], bottom: numbers[2], left: numbers[1])
        default: return Edges(top: numbers[0], right: numbers[1], bottom: numbers[2], left: numbers[3])
        }
    }

    func font(_ selector: String, viewport: Double) throws -> Font {
        let size = try length(selector, "font-size", viewport: viewport)
        let weightText = try raw(selector, "font-weight", viewport: viewport)
        guard let weight = Int(weightText) else {
            throw Error("\(name) \(selector) font-weight at \(viewport)pt: expected numeric weight, got '\(weightText)'")
        }
        let lineHeight: Double?
        if let rawLine = try? raw(selector, "line-height", viewport: viewport) {
            if let points = evaluate(rawLine, viewport: viewport) {
                lineHeight = rawLine.hasSuffix("px") ? points : points * size
            } else {
                throw Error("\(name) \(selector) line-height at \(viewport)pt: unresolved '\(rawLine)'")
            }
        } else { lineHeight = nil }
        return Font(size: size, weight: weight, lineHeight: lineHeight)
    }

    func color(_ selector: String, _ property: String, viewport: Double) throws -> Color {
        let value = try raw(selector, property, viewport: viewport)
        let colorText = property.hasPrefix("border") ? String(value.components(separatedBy: " solid ").last ?? value) : value
        guard let parsed = parseColor(colorText) else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected sRGB color, got '\(value)'")
        }
        return parsed
    }

    func assertLength(_ actual: Double, _ selector: String, _ property: String, viewport: Double,
                      tolerance: Double = 0.01) throws {
        let expected = try length(selector, property, viewport: viewport)
        guard abs(actual - expected) <= tolerance else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected \(expected)pt from CSS, actual \(actual)pt (tolerance \(tolerance)pt)")
        }
    }

    func assertEdges(_ actual: Edges, _ selector: String, _ property: String, viewport: Double,
                     tolerance: Double = 0.01) throws {
        let expected = try edges(selector, property, viewport: viewport)
        let differences = [abs(actual.top - expected.top), abs(actual.right - expected.right),
                           abs(actual.bottom - expected.bottom), abs(actual.left - expected.left)]
        guard differences.allSatisfy({ $0 <= tolerance }) else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected \(expected)pt from CSS, actual \(actual)pt")
        }
    }

    func assertFont(_ actual: Font, _ selector: String, viewport: Double, tolerance: Double = 0.01) throws {
        let expected = try font(selector, viewport: viewport)
        guard abs(actual.size - expected.size) <= tolerance, actual.weight == expected.weight,
              (actual.lineHeight == nil && expected.lineHeight == nil ||
               actual.lineHeight != nil && expected.lineHeight != nil &&
               abs(actual.lineHeight! - expected.lineHeight!) <= tolerance) else {
            throw Error("\(name) \(selector) font at \(viewport)pt: expected \(expected) from CSS, actual \(actual)")
        }
    }

    func assertColor(_ actual: Color, _ selector: String, _ property: String, viewport: Double,
                     tolerance: Double = 1.0 / 255) throws {
        let expected = try color(selector, property, viewport: viewport)
        let differences = [abs(actual.red - expected.red), abs(actual.green - expected.green),
                           abs(actual.blue - expected.blue), abs(actual.alpha - expected.alpha)]
        guard differences.allSatisfy({ $0 <= tolerance }) else {
            throw Error("\(name) \(selector) \(property) at \(viewport)pt: expected \(expected) sRGB from CSS, actual \(actual) sRGB")
        }
    }

    private func resolveVars(_ text: String, viewport: Double, context: String, tokenSelector: String, depth: Int = 0) throws -> String {
        guard depth < 20 else { throw Error("\(name) \(context) at \(viewport)pt: cyclic var() in '\(text)'") }
        var result = text
        while let range = result.range(of: "var(") {
            guard let close = result[range.upperBound...].firstIndex(of: ")") else {
                throw Error("\(name) \(context) at \(viewport)pt: unterminated var() in '\(text)'")
            }
            let token = String(result[range.upperBound..<close])
            let selectors = [tokenSelector, appearance == "dark" ? ".theme-dark" : ".theme-light", ":root"]
            var found: String?
            for selector in selectors {
                found = try? rawToken(selector, token, viewport: viewport)
                if found != nil { break }
            }
            guard let found else { throw Error("\(name) \(context) at \(viewport)pt: missing token \(token) in '\(text)'") }
            result.replaceSubrange(range.lowerBound...close, with: try resolveVars(found, viewport: viewport, context: context, tokenSelector: tokenSelector, depth: depth + 1))
        }
        return result
    }

    private func rawToken(_ selector: String, _ token: String, viewport: Double) throws -> String {
        guard let rule = rules.last(where: { $0.selector == selector && $0.declarations[token] != nil &&
            ($0.min == nil || viewport >= $0.min!) && ($0.max == nil || viewport <= $0.max!) }) else {
            throw Error("missing token \(token)")
        }
        return rule.declarations[token]!
    }

    private struct Catalog: Decodable {
        let states: [Entry]
        struct Entry: Decodable { let name: String; let file: String; let sha256: String }
    }

    private static func parse(_ css: String, min: Double?, max: Double?, into rules: inout [Rule]) {
        let clean = css.replacingOccurrences(of: "(?s)/\\*.*?\\*/", with: "", options: .regularExpression)
        let chars = Array(clean)
        var i = 0
        while i < chars.count {
            while i < chars.count && (chars[i].isWhitespace || chars[i] == "}") { i += 1 }
            let start = i
            while i < chars.count && chars[i] != "{" { i += 1 }
            guard i < chars.count else { break }
            let header = String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            i += 1
            let bodyStart = i
            var depth = 1
            while i < chars.count && depth > 0 {
                if chars[i] == "{" { depth += 1 }
                if chars[i] == "}" { depth -= 1 }
                i += 1
            }
            guard depth == 0 else { break }
            let body = String(chars[bodyStart..<(i - 1)])
            if header.hasPrefix("@media") {
                let maxWidth = matches("max-width\\s*:\\s*([0-9.]+)px", in: header).first?.first.flatMap(Double.init)
                let minWidth = matches("min-width\\s*:\\s*([0-9.]+)px", in: header).first?.first.flatMap(Double.init)
                if maxWidth != nil || minWidth != nil {
                    parse(body, min: minWidth ?? min, max: maxWidth ?? max, into: &rules)
                }
            } else if !header.hasPrefix("@") {
                var declarations: [String: String] = [:]
                for declaration in split(body, separator: ";") {
                    guard let colon = declaration.firstIndex(of: ":") else { continue }
                    let key = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    declarations[key] = value
                }
                for selector in split(header, separator: ",") {
                    rules.append(Rule(selector: selector.trimmingCharacters(in: .whitespacesAndNewlines),
                                      declarations: declarations, min: min, max: max, order: rules.count))
                }
            }
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
        }
    }

    private static func split(_ input: String, separator: Character) -> [String] {
        var result: [String] = []; var depth = 0; var start = input.startIndex
        for index in input.indices {
            if input[index] == "(" { depth += 1 }
            if input[index] == ")" { depth -= 1 }
            if input[index] == separator && depth == 0 {
                result.append(String(input[start..<index]))
                start = input.index(after: index)
            }
        }
        result.append(String(input[start...]))
        return result
    }

    private static func splitWhitespace(_ input: String) -> [String] {
        var result: [String] = []; var depth = 0; var current = ""
        for char in input {
            if char == "(" { depth += 1 }
            if char == ")" { depth -= 1 }
            if char.isWhitespace && depth == 0 {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(char) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func evaluate(_ expression: String, viewport: Double, percentageBase: Double? = nil) -> Double? {
        let value = expression.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("clamp("), value.hasSuffix(")") {
            let parts = Self.split(String(value.dropFirst(6).dropLast()), separator: ",")
            guard parts.count == 3, let low = evaluate(parts[0], viewport: viewport, percentageBase: percentageBase),
                  let preferred = evaluate(parts[1], viewport: viewport, percentageBase: percentageBase), let high = evaluate(parts[2], viewport: viewport, percentageBase: percentageBase) else { return nil }
            return Swift.min(Swift.max(preferred, low), high)
        }
        if value.hasPrefix("min("), value.hasSuffix(")") {
            let numbers = Self.split(String(value.dropFirst(4).dropLast()), separator: ",").compactMap { evaluate($0, viewport: viewport, percentageBase: percentageBase) }
            return numbers.count >= 2 ? numbers.min() : nil
        }
        if value.hasPrefix("calc("), value.hasSuffix(")") {
            let body = String(value.dropFirst(5).dropLast())
            for op in [" + ", " - "] {
                if let range = body.range(of: op), let left = evaluate(String(body[..<range.lowerBound]), viewport: viewport, percentageBase: percentageBase),
                   let right = evaluate(String(body[range.upperBound...]), viewport: viewport, percentageBase: percentageBase) {
                    return op == " + " ? left + right : left - right
                }
            }
            return evaluate(body, viewport: viewport, percentageBase: percentageBase)
        }
        if value.hasSuffix("%"), let base = percentageBase, let n = Double(value.dropLast()) { return n * base / 100 }
        if value.hasSuffix("vw"), let n = Double(value.dropLast(2)) { return n * viewport / 100 }
        if value.hasSuffix("px"), let n = Double(value.dropLast(2)) { return n }
        return Double(value)
    }

    private func parseColor(_ text: String) -> Color? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value == "transparent" { return Color(red: 0, green: 0, blue: 0, alpha: 0) }
        if value == "black" { return Color(red: 0, green: 0, blue: 0, alpha: 1) }
        if value == "white" { return Color(red: 1, green: 1, blue: 1, alpha: 1) }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            let expanded = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
            guard expanded.count == 6, let number = Int(expanded, radix: 16) else { return nil }
            return Color(red: Double((number >> 16) & 255) / 255,
                         green: Double((number >> 8) & 255) / 255,
                         blue: Double(number & 255) / 255, alpha: 1)
        }
        if value.hasPrefix("rgba("), value.hasSuffix(")") {
            let parts = Self.split(String(value.dropFirst(5).dropLast()), separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else { return nil }
            return Color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts[3])
        }
        if value.hasPrefix("color-mix(in srgb,"), value.hasSuffix(")") {
            let body = String(value.dropFirst("color-mix(in srgb,".count).dropLast())
            let parts = Self.split(body, separator: ",")
            guard parts.count == 2 else { return nil }
            func component(_ string: String) -> (Color, Double)? {
                let bits = Self.splitWhitespace(string.trimmingCharacters(in: .whitespaces))
                guard bits.count >= 1 else { return nil }
                let percent = bits.last?.hasSuffix("%") == true ? Double(bits.last!.dropLast()).map { $0 / 100 } : nil
                let colorString = percent == nil ? string.trimmingCharacters(in: .whitespaces) : bits.dropLast().joined(separator: " ")
                guard let color = parseColor(colorString) else { return nil }
                return (color, percent ?? -1)
            }
            guard let (a, firstWeight) = component(parts[0]), let (b, secondWeight) = component(parts[1]) else { return nil }
            var wa = firstWeight; var wb = secondWeight
            if wa < 0 { wa = 1 - wb }; if wb < 0 { wb = 1 - wa }
            let alpha = a.alpha * wa + b.alpha * wb
            guard alpha > 0 else { return Color(red: 0, green: 0, blue: 0, alpha: 0) }
            return Color(red: (a.red * a.alpha * wa + b.red * b.alpha * wb) / alpha,
                         green: (a.green * a.alpha * wa + b.green * b.alpha * wb) / alpha,
                         blue: (a.blue * a.alpha * wa + b.blue * b.alpha * wb) / alpha, alpha: alpha)
        }
        return nil
    }
}
