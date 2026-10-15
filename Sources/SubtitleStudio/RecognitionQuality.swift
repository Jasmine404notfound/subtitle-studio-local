import Foundation

enum RecognitionQuality {
    static func badText(_ text: String) -> Bool {
        if text.contains("\u{FFFD}") { return true }
        let compact = text.filter { !$0.isWhitespace && !$0.isPunctuation }
        guard compact.count >= 16 else { return false }
        if compact.range(of: #"(.)\1{7,}"#, options: .regularExpression) != nil { return true }
        if compact.range(of: #"(.{2,12})\1{5,}"#, options: .regularExpression) != nil { return true }
        return false
    }
    static func suspicious(_ cues: [SubtitleCue]) -> Set<Int> {
        var result = Set(cues.indices.filter {
            let cue = cues[$0], (a,b) = range(cues[$0])
            let count = cue.text.filter { $0.isLetter || $0.isNumber }.count
            // A few words stretched across a whole recognition window can
            // conceal skipped speech, so inspect the source audio again.
            return badText(cue.text) || (b-a >= 15 && Double(count) < (b-a)*1.2)
        })
        if cues.count >= 3 {
            for i in 2..<cues.count {
                let t = cues[i].text.filter { !$0.isWhitespace }
                if t.count >= 12 && cues[i-1].text.filter({ !$0.isWhitespace }) == t && cues[i-2].text.filter({ !$0.isWhitespace }) == t {
                    result.formUnion([i-2, i-1, i])
                }
            }
        }
        return result
    }
    static func seconds(_ timestamp: String) -> Double {
        let p = timestamp.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        return p.count == 3 ? p[0]*3600 + p[1]*60 + p[2] : 0
    }
    static func range(_ cue: SubtitleCue) -> (Double, Double) {
        let p = cue.timing.components(separatedBy: " --> ")
        return (seconds(p[0]), seconds(p[1].components(separatedBy: " ")[0]))
    }
    static func stamp(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms/3600000, ms/60000%60, ms/1000%60, ms%1000)
    }
}

struct SpeechInterval: Codable {
    var start: Double
    var end: Double
}
struct SpeechActivity: Codable {
    var duration: Double
    var speech: [SpeechInterval]
}
extension RecognitionQuality {
    /// Leading, internal and trailing gaps, using the furthest coverage end
    /// so overlapping cues cannot create a false gap.
    static func gaps(_ cues: [SubtitleCue], duration: Double, minimum: Double = 3) -> [SpeechInterval] {
        var cursor = 0.0, gaps: [SpeechInterval] = []
        for cue in cues.sorted(by: { range($0).0 < range($1).0 }) {
            let (a,b) = range(cue)
            if a - cursor >= minimum { gaps.append(SpeechInterval(start: cursor, end: min(a, duration))) }
            cursor = max(cursor, b)
        }
        if duration - cursor >= minimum { gaps.append(SpeechInterval(start: cursor, end: duration)) }
        return gaps.filter { $0.end - $0.start >= minimum }
    }
    static func voicedDuration(_ gap: SpeechInterval, speech: [SpeechInterval]) -> Double {
        speech.reduce(0) { $0 + max(0, min(gap.end, $1.end) - max(gap.start, $1.start)) }
    }
    static func uncoveredSpeech(_ cues: [SubtitleCue], within gap: SpeechInterval, speech: [SpeechInterval]) -> Double {
        // Small alignment tolerances prevent ordinary word boundaries from
        // being mistaken for a missing sentence.
        let padded = cues.map { cue -> SubtitleCue in
            var copy = cue; let (a,b) = range(cue)
            copy.timing = "\(stamp(max(0,a-0.35))) --> \(stamp(b+0.35))"
            return copy
        }
        return gaps(padded, duration: gap.end, minimum: 1.2).reduce(0) { total, item in
            total + voicedDuration(SpeechInterval(start: max(item.start, gap.start), end: min(item.end, gap.end)), speech: speech)
        }
    }
}
