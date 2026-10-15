import Foundation
import NaturalLanguage

struct CaptionScheme: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var limits: [String: Int]
    static let ratios = ["16:9", "9:16", "3:4", "4:3", "1:1", "4:5", "21:9"]
    static let defaults = ["16:9": 25, "9:16": 16, "3:4": 18, "4:3": 22, "1:1": 18, "4:5": 17, "21:9": 30]
    func limit(for ratio: String) -> Int { min(60, max(4, limits[ratio] ?? Self.defaults[ratio] ?? 25)) }
    static func load(from defaults: UserDefaults = .standard) -> [CaptionScheme] {
        guard let data = defaults.data(forKey: "captionSchemes"),
              let schemes = try? JSONDecoder().decode([CaptionScheme].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(schemes.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.prefix(3))
    }
    static func save(_ schemes: [CaptionScheme], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(Array(schemes.prefix(3))) { defaults.set(data, forKey: "captionSchemes") }
    }
}

struct ProcessingOptions {
    var enabled = true
    var ratio = "16:9"
    var maxCharacters = 25
    var expandYears = true
    var contextualCorrection = true
    var translateForeign = false
    var recordingYear = Calendar.current.component(.year, from: Date())
    var vocabulary = ""
    var keepPunctuation = false
    var saveExtras = false
}

struct SubtitleCue: Codable {
    var id: Int
    var number: String
    var timing: String
    var text: String
}

enum SubtitleDocument {
    static func parse(_ source: String) throws -> [SubtitleCue] {
        // The original file remains untouched; enhanced output uses UTF-8/LF.
        _ = try Subtitles.clean(source)
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: "\n")
        var cues: [SubtitleCue] = [], i = 0
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            let number = lines[i]; i += 1
            guard i < lines.count else { throw ToolError(message: "SRT 缺少时间轴") }
            let timing = lines[i]; i += 1
            var body: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { body.append(lines[i]); i += 1 }
            // Chinese wrapped lines join directly; English word boundaries retain spaces.
            var text = ""
            for line in body {
                if let a = text.last, let b = line.first, a.isASCII && b.isASCII && a.isLetter && b.isLetter { text += " " }
                text += line
            }
            cues.append(SubtitleCue(id: cues.count, number: number, timing: timing, text: text))
        }
        return cues
    }
    static func serialize(_ cues: [SubtitleCue]) -> String {
        cues.map { "\($0.number)\n\($0.timing)\n\($0.text)\n" }.joined(separator: "\n") + "\n"
    }
}

enum SemanticWrapping {
    static func wrap(_ text: String, limit: Int, vocabulary: String = "") -> String {
        guard !text.isEmpty else { return text }
        let chars = Array(text)
        let n = chars.count, cap = max(4, min(60, limit))
        if n <= cap { return text }
        var boundary = Set<Int>(), protected = Set<Int>(), translationProtected = Set<Int>()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            boundary.insert(start); boundary.insert(end)
            return true
        }
        // Preserve dates, numbers, English terms, and vocabulary unless a term
        // itself exceeds the hard per-line limit.
        let patterns = ["[A-Za-z0-9]+(?:[.'’:/_-][A-Za-z0-9]+)*(?:年|月|日|%)?"]
        let ns = text as NSString
        // Layout runs after translation. Keep a foreign phrase and its gloss
        // together whenever their combined length (including brackets) fits.
        let translatedPhrase = #"[A-Za-zÀ-ɏͰ-ϿЀ-ӿ぀-ヿ가-힣؀-ۿ][A-Za-zÀ-ɏͰ-ϿЀ-ӿ぀-ヿ가-힣؀-ۿ0-9 '’./_-]*（[^（）\n]+）"#
        if let regex = try? NSRegularExpression(pattern: translatedPhrase) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let range = Range(match.range, in: text) else { continue }
                let phrase = String(text[range])
                if phrase.count <= cap {
                    protect(range, text: text, cap: cap, into: &translationProtected)
                } else if let open = text[range].firstIndex(of: "（") {
                    // Long bilingual phrases may span lines, but a short gloss
                    // remains intact and attached to its own parentheses.
                    protect(open..<range.upperBound, text: text, cap: cap, into: &translationProtected)
                }
            }
        }
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    if let range = Range(match.range, in: text) { protect(range, text: text, cap: cap, into: &protected) }
                }
            }
        }
        let terms = Vocabulary.terms(vocabulary)
        for term in terms {
            var search = text.startIndex..<text.endIndex
            while let range = text.range(of: term, range: search) {
                protect(range, text: text, cap: cap, into: &protected)
                if range.upperBound == text.endIndex { break }
                search = range.upperBound..<text.endIndex
            }
        }
        let punctuation = CharacterSet.punctuationCharacters
        func isPunctuation(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { punctuation.contains($0) } }
        func cost(_ end: Int) -> Double {
            if end == n { return 0 }
            let previous = chars[end - 1], next = chars[end]
            if "（(".contains(previous) || "）)".contains(next) { return 1000 }
            if protected.contains(end) { return 10000 }
            if isPunctuation(next) { return 300 }
            if "。！？!?；;，,、：:".contains(previous) { return 0 }
            let remainder = String(chars[end..<min(n, end + 3)])
            if ["但是", "因为", "所以", "而且", "不过", "然后", "如果", "我们", "他们", "她们", "它们"].contains(where: { remainder.hasPrefix($0) }) { return 3 }
            if "的地得与和把被在".contains(previous) { return 90 }
            if previous.isWhitespace || next.isWhitespace { return 5 }
            return boundary.contains(end) ? 18 : 80
        }
        var dp = Array(repeating: Double.infinity, count: n + 1)
        var nextBreak = Array(repeating: n, count: n + 1)
        dp[n] = 0
        for start in stride(from: n - 1, through: 0, by: -1) {
            for end in (start + 1)...min(n, start + cap) {
                if translationProtected.contains(end) { continue }
                let length = end - start
                // Each output line must contain actual subtitle content.
                if !chars[start..<end].contains(where: { !$0.isWhitespace && !isPunctuation($0) }) { continue }
                let ragged = Double(cap - length) / Double(cap)
                let short = length < min(4, cap) ? Double(4 - length) * 18 : 0
                let candidate = 12 + ragged * ragged * 10 + short + cost(end) + dp[end]
                if candidate < dp[start] { dp[start] = candidate; nextBreak[start] = end }
            }
        }
        guard dp[0].isFinite else {
            return stride(from: 0, to: n, by: cap).map { String(chars[$0..<min(n, $0 + cap)]) }.joined(separator: "\n")
        }
        var lines: [String] = [], start = 0
        while start < n {
            let end = nextBreak[start]
            lines.append(String(chars[start..<end])); start = end
        }
        return lines.joined(separator: "\n")
    }
    private static func protect(_ range: Range<String.Index>, text: String, cap: Int, into set: inout Set<Int>) {
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        if end - start <= cap && end - start > 1 { set.formUnion((start + 1)..<end) }
    }
}

struct ProofreadingPayload: Codable {
    var cues: [SubtitleCue]
    var reference_year: Int
    var expand_years: Bool
    var correct_homophones: Bool
    var vocabulary: String
    var translate_foreign: Bool
}

struct ProofreadingResult: Codable {
    var cues: [SubtitleCue]
    var report: String
}

enum ProcessedOutput {
    static func save(originalData: Data, cues: [SubtitleCue], report: String,
                     options: ProcessingOptions, directory: URL, stem: String) throws -> [URL] {
        let fm = FileManager.default
        var serial = 1, name = stem + "_最终字幕"
        while fm.fileExists(atPath: directory.appendingPathComponent(name + ".srt").path)
            || (options.saveExtras && fm.fileExists(atPath: directory.appendingPathComponent("字幕备份/" + name).path)) {
            serial += 1; name = stem + "_最终字幕_" + String(serial)
        }
        let final = directory.appendingPathComponent(name + ".srt")
        let rendered = CaptionExport.prepare(cues, options: options)
        guard !rendered.isEmpty else { throw ToolError(message: "没有可输出的字幕正文") }
        try Subtitles.writeExclusive(Data(SubtitleDocument.serialize(rendered).utf8), to: final)
        if options.saveExtras {
            let backup = directory.appendingPathComponent("字幕备份/" + name)
            do {
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try Subtitles.writeExclusive(originalData, to: backup.appendingPathComponent("原始识别.srt"))
                try Subtitles.writeExclusive(Data(CaptionExport.report(report, options: options).utf8), to: backup.appendingPathComponent("处理记录.txt"))
            } catch { throw ToolError(message: "最终字幕已保存：\(final.path)\n备份保存失败：\(error.localizedDescription)") }
        }
        return [final]
    }
}
