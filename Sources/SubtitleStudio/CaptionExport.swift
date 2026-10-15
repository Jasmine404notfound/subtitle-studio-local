import Foundation

enum CaptionExport {
    static func prepare(_ cues: [SubtitleCue], options: ProcessingOptions) -> [SubtitleCue] {
        var output: [SubtitleCue] = []
        for cue in cues {
            var text = cue.text
            if !options.keepPunctuation {
                text = String(String.UnicodeScalarView(text.unicodeScalars.filter {
                    (options.translateForeign && ($0 == "（" || $0 == "）")) || !CharacterSet.punctuationCharacters.contains($0)
                }))
            }
            let parts = SemanticWrapping.wrap(text, limit: options.maxCharacters, vocabulary: options.vocabulary)
                .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }
            let (start,end) = RecognitionQuality.range(cue)
            let first = Int((start*1000).rounded()), last = Int((end*1000).rounded())
            let weights = parts.map { max(1,$0.count) }, total = weights.reduce(0,+)
            var cumulative = 0
            for (index, part) in parts.enumerated() {
                let lo = first + (last-first)*cumulative/total
                cumulative += weights[index]
                let hi = index == parts.count-1 ? last : first + (last-first)*cumulative/total
                output.append(SubtitleCue(id: output.count, number: String(output.count+1), timing: "\(RecognitionQuality.stamp(Double(lo)/1000)) --> \(RecognitionQuality.stamp(Double(max(lo+1,hi))/1000))", text: part))
            }
        }
        return output
    }
    static func report(_ report: String, options: ProcessingOptions) -> String {
        "画幅：\(options.ratio)；每条单行字幕最多 \(options.maxCharacters) 字（含字母、空格、翻译、括号）\n长字幕拆为独立编号和时间段；在原时间范围内按文字长度估算分配，未做逐字声学对齐，请听校。\n\n" + report
    }
}
