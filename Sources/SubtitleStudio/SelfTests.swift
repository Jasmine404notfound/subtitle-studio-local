import Foundation

enum SelfTests {
    static func run() {
        do {
            let scheme = CaptionScheme(name: "横竖屏方案", limits: ["16:9": 21, "9:16": 13, "3:4": 80, "1:1": 1])
            let restored = try JSONDecoder().decode(CaptionScheme.self, from: JSONEncoder().encode(scheme))
            guard restored == scheme, restored.limit(for: "16:9") == 21, restored.limit(for: "9:16") == 13,
                  restored.limit(for: "3:4") == 60, restored.limit(for: "1:1") == 4, restored.limit(for: "4:5") == 17,
                  CaptionScheme.ratios.count == 7 else { throw ToolError(message: "custom scheme persistence / per-ratio limits regression") }
            let original = "\u{FEFF}1\r\n00:00:00,000 --> 00:00:02,345\r\n你好，世界！Hello, world…“词语”_test—ok。\r\n123,456\r\n\r\n2\r\n00:00:02,345 --> 00:00:04,500\r\n$100 + 20% 😀\r\n\r\n"
            let expected = "\u{FEFF}1\r\n00:00:00,000 --> 00:00:02,345\r\n你好世界Hello world词语testok\r\n123456\r\n\r\n2\r\n00:00:02,345 --> 00:00:04,500\r\n$100 + 20 😀\r\n\r\n"
            guard try Subtitles.clean(original) == expected else { throw ToolError(message: "Unicode / CRLF / BOM regression") }
            for bad in ["random text", "1\nwrong timeline\nhello", "1\n"] {
                do { _ = try Subtitles.clean(bad); throw ToolError(message: "accepted malformed SRT") }
                catch let e as ToolError where e.message == "accepted malformed SRT" { throw e }
                catch {}
            }
            let cr = "1\r00:00:00,000 --> 00:00:01,000\r你好！\r\r"
            guard try Subtitles.clean(cr) == cr.replacingOccurrences(of: "！", with: "") else { throw ToolError(message: "CR newline regression") }
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("SubtitleTests-" + UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? fm.removeItem(at: dir) }
            let input = dir.appendingPathComponent("测试 空格 ' $ name.srt")
            try Data(original.utf8).write(to: input)
            let output = try Subtitles.stripFile(input, directory: dir)
            let output2 = try Subtitles.stripFile(input, directory: dir)
            guard try Data(contentsOf: input) == Data(original.utf8), output != input, output != output2,
                  String(decoding: try Data(contentsOf: output), as: UTF8.self) == expected else { throw ToolError(message: "file preservation / collision regression") }
            do { try Subtitles.writeExclusive(Data("bad".utf8), to: input); throw ToolError(message: "overwrite permitted") }
            catch let e as ToolError where e.message == "overwrite permitted" { throw e }
            catch {}
            let request = TranscriptionRequest(input: input, directory: dir, executable: input, model: "mlx-community/whisper-large-v3-turbo", language: "zh", prompt: "品牌甲，品牌乙")
            let args = request.arguments(staging: dir)
            guard args.first == input.path, let p = args.firstIndex(of: "--initial-prompt"), args[p+1] == "品牌甲，品牌乙", args.contains("zh") else { throw ToolError(message: "CLI argument regression") }
            let paragraph = "我们从2018年开始研究这个品牌，但是消费者的真实需求仍然需要认真分析。Fly By Jing为这个项目提供了重要的参考。"
            for limit in [4, 16, 18, 25, 30, 60] {
                let wrapped = SemanticWrapping.wrap(paragraph, limit: limit, vocabulary: "Fly By Jing，消费者")
                guard wrapped.replacingOccurrences(of: "\n", with: "") == paragraph,
                      wrapped.components(separatedBy: "\n").allSatisfy({ $0.count <= limit && !$0.isEmpty }) else {
                    throw ToolError(message: "semantic wrapping content / hard limit regression")
                }
                if limit >= 16 && (!wrapped.contains("2018年") || !wrapped.contains("Fly By Jing")) {
                    throw ToolError(message: "split protected date or proper noun")
                }
            }
            let cues = try SubtitleDocument.parse(original)
            let options = ProcessingOptions(maxCharacters: 16, expandYears: false, contextualCorrection: false, saveExtras: true)
            let formatted = try ProcessedOutput.save(originalData: Data(original.utf8), cues: cues, report: "测试", options: options, directory: dir, stem: "layout")
            let reparsed = try SubtitleDocument.parse(Subtitles.read(formatted[0]))
            let backup = dir.appendingPathComponent("字幕备份/layout_最终字幕/原始识别.srt")
            guard formatted.count == 1, formatted[0].lastPathComponent == "layout_最终字幕.srt",
                  reparsed.allSatisfy({ !$0.text.contains("\n") && $0.text.count <= 16 }),
                  try Data(contentsOf: backup) == Data(original.utf8) else { throw ToolError(message: "final export / optional backup regression") }
            let noun = Vocabulary.normalize([SubtitleCue(id: 0, number: "1", timing: "00:00:00,000 --> 00:00:05,000", text: "海贵爸爸和海归爸爸购买baby care以及BabyCare，babycareful不应被改")], vocabulary: "刀姐 doris 泡泡玛特 Babycare 海龟爸爸，Fly By Jing")
            guard noun.cues[0].text == "海龟爸爸和海龟爸爸购买Babycare以及Babycare，babycareful不应被改" else { throw ToolError(message: "vocabulary correction regression: " + noun.cues[0].text) }
            guard Vocabulary.terms("海龟爸爸 Babycare\nFly By Jing，ROI").contains("Fly By Jing") else { throw ToolError(message: "vocabulary parsing regression") }
            let sentence = [SubtitleCue(id: 0, number: "2", timing: "00:00:06,560 --> 00:00:11,600", text: "它变成了个十万家文章 为什么呢 它其实当时就是说出了大家一个心声嘛")]
            let split = CaptionExport.prepare(sentence, options: ProcessingOptions(maxCharacters: 25))
            guard split.count >= 2, split.allSatisfy({ $0.text.count <= 25 && !$0.text.contains("\n") }),
                  RecognitionQuality.range(split.first!).0 == 6.56, RecognitionQuality.range(split.last!).1 == 11.6 else { throw ToolError(message: "single-line timed cue splitting regression") }
            for i in 1..<split.count { guard RecognitionQuality.range(split[i-1]).1 == RecognitionQuality.range(split[i]).0 else { throw ToolError(message: "split cue gap or overlap") } }
            guard RecognitionQuality.badText(String(repeating: "卖", count: 100)),
                  RecognitionQuality.badText("异常�"),
                  !RecognitionQuality.badText("这个产品卖得很好，我们需要认真分析消费者需求"),
                  args.contains("--condition-on-previous-text"), args.contains("False") else {
                throw ToolError(message: "recognition repetition protection regression")
            }
            let repeated = (0..<3).map { SubtitleCue(id: $0, number: String($0+1), timing: "00:00:00,000 --> 00:00:01,000", text: "欢迎大家关注点赞评论我们的视频") }
            guard RecognitionQuality.suspicious(repeated).count == 3 else { throw ToolError(message: "cross-window loop detection regression") }
            let translated = [SubtitleCue(id: 0, number: "1", timing: "00:00:00,000 --> 00:00:02,000", text: "我们关注 product market fit（产品与市场匹配），以及增长。")]
            let translatedURLs = try ProcessedOutput.save(originalData: Data("original".utf8), cues: translated, report: "test", options: ProcessingOptions(translateForeign: true), directory: dir, stem: "translation")
            let translatedClean = try String(contentsOf: translatedURLs[0], encoding: .utf8)
            guard translatedClean.contains("（"), translatedClean.contains("）"), !translatedClean.contains("，"), !translatedClean.contains("。") else { throw ToolError(message: "translation parentheses lost") }
            for (limit, phrase) in [(25, "brand positioning（品牌定位）"), (16, "AI（人工智能）"), (18, "ありがとう（谢谢）")] {
                let text = "今天我们重点讨论" + phrase + "然后再分析实际效果"
                let wrapped = SemanticWrapping.wrap(text, limit: limit)
                guard wrapped.contains(phrase), wrapped.replacingOccurrences(of: "\n", with: "") == text,
                      wrapped.components(separatedBy: "\n").allSatisfy({ $0.count <= limit }) else { throw ToolError(message: "bilingual phrase must wrap together") }
            }
            for limit in [16, 18, 25, 30] {
                let text = "重点是 product market fit（产品与市场匹配）以及 sustainable competitive advantage（可持续竞争优势）"
                let wrapped = SemanticWrapping.wrap(text, limit: limit)
                guard wrapped.replacingOccurrences(of: "\n", with: "") == text,
                      wrapped.components(separatedBy: "\n").allSatisfy({ $0.count <= limit }),
                      wrapped.contains("（产品与市场匹配）"), wrapped.contains("（可持续竞争优势）") else { throw ToolError(message: "long translation hard limit regression") }
            }
            guard !RecognitionQuality.suspicious([SubtitleCue(id: 0, number: "1", timing: "00:00:00,000 --> 00:00:29,980", text: "请不吝点赞订阅转发打赏支持明镜与点点栏目")]).isEmpty else { throw ToolError(message: "sparse long cue regression") }
            let gapCues = [SubtitleCue(id: 0, number: "1", timing: "00:00:04,000 --> 00:00:08,000", text: "开头"), SubtitleCue(id: 1, number: "2", timing: "00:00:31,360 --> 00:00:34,000", text: "结尾")]
            let gaps = RecognitionQuality.gaps(gapCues, duration: 40)
            guard gaps.count == 3, abs(gaps[1].end-gaps[1].start-23.36) < 0.001,
                  RecognitionQuality.voicedDuration(gaps[1], speech: [SpeechInterval(start: 12, end: 15)]) == 3,
                  RecognitionQuality.voicedDuration(gaps[0], speech: []) == 0,
                  RecognitionQuality.uncoveredSpeech(gapCues, within: SpeechInterval(start: 4, end: 8), speech: [SpeechInterval(start: 4.2, end: 7.9)]) == 0 else { throw ToolError(message: "speech gap coverage regression") }
            let overlapped = gapCues + [SubtitleCue(id: 2, number: "3", timing: "00:00:05,000 --> 00:00:06,000", text: "重叠")]
            guard RecognitionQuality.gaps(overlapped, duration: 40).count == 3 else { throw ToolError(message: "overlapping cue gap regression") }
            print("SELF_TEST_PASS: Unicode punctuation, numeric dialogue, timestamps, blank lines, BOM, LF/CRLF/CR, malformed SRT, original preservation, collision protection, CLI arguments")
        } catch { print("SELF_TEST_FAIL:", error.localizedDescription); exit(1) }
    }
}
