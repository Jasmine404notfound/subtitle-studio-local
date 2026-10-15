import Foundation

enum Vocabulary {
    static func terms(_ text: String) -> [String] {
        var result: [String] = []
        // Chinese entries may be separated by spaces. Consecutive English
        // words stay one entry, e.g. Fly By Jing.
        let pattern = #"[\p{Han}]+[A-Za-z0-9]*|[A-Za-z0-9]+(?:[ '\-][A-Za-z0-9]+)*"#
        let regex = try! NSRegularExpression(pattern: pattern)
        for field in text.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n\r")) {
            let ns = field as NSString
            for m in regex.matches(in: field, range: NSRange(location: 0, length: ns.length)) {
                let term = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                if !term.isEmpty && !result.contains(term) { result.append(term) }
            }
        }
        return result
    }
    static func normalize(_ cues: [SubtitleCue], vocabulary: String) -> ProofreadingResult {
        let terms = terms(vocabulary).sorted { $0.count > $1.count }
        var readings: [Character: String] = [:]
        func han(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) } }
        func reading(_ c: Character) -> String {
            if let value = readings[c] { return value }
            let value = String(c).applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false)?.lowercased() ?? String(c)
            readings[c] = value; return value
        }
        var phonetic: [String: [String]] = [:]
        for term in terms where term.count >= 3 && term.count <= 20 && term.allSatisfy(han) {
            let key = term.map(reading).joined(separator: "|")
            phonetic[key, default: []].append(term)
        }
        let sizes = Set(terms.filter { $0.count >= 3 && $0.count <= 20 && $0.allSatisfy(han) }.map(\.count)).sorted(by: >)
        var notes: [String] = [], output = cues
        for index in output.indices {
            let before = output[index].text
            var text = before
            for term in terms where term.unicodeScalars.allSatisfy({ $0.isASCII }) && term.filter({ $0.isLetter }).count >= 2 {
                let pattern = "(?<![A-Za-z])" + term.filter { !$0.isWhitespace }.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s*") + "(?![A-Za-z])"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches.reversed() {
                        if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: term) }
                    }
                }
            }
            let chars = Array(text)
            var fixed = "", cursor = 0
            while cursor < chars.count {
                var replacement: (Int,String)?
                for size in sizes where cursor+size <= chars.count {
                    let window = chars[cursor..<cursor+size]
                    guard window.allSatisfy(han) else { continue }
                    let key = window.map(reading).joined(separator: "|")
                    if let values = phonetic[key], values.count == 1 { replacement = (size, values[0]); break }
                }
                if let (size, term) = replacement { fixed += term; cursor += size }
                else { fixed.append(chars[cursor]); cursor += 1 }
            }
            output[index].text = fixed
            if fixed != before { notes.append("[\(output[index].timing)] 词库归一\n原文：\(before)\n结果：\(fixed)\n") }
        }
        return ProofreadingResult(cues: output, report: "词库归一：修改 \(notes.count) 条。英文统一大小写和空格；中文仅匹配至少三字的整词同音候选，同音歧义保留。专名仍请复核。\n" + notes.joined(separator: "\n"))
    }
}
