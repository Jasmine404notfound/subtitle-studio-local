import Foundation
import Darwin

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Subtitles {
    // Parse the SRT structure before filtering: numeric dialogue is still dialogue.
    static func clean(_ text: String) throws -> String {
        let ns = text as NSString
        let re = try NSRegularExpression(pattern: "[^\\r\\n]*(?:\\r\\n|\\r|\\n|$)")
        let lines = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var state = 0, cueCount = 0, result = ""
        for match in lines where match.range.length > 0 {
            let original = ns.substring(with: match.range)
            var body = original, ending = ""
            if body.hasSuffix("\r\n") { ending = "\r\n"; body.removeLast() }
            else if body.hasSuffix("\n") || body.hasSuffix("\r") { ending = String(body.removeLast()) }
            var parsed = body
            if result.isEmpty && parsed.hasPrefix("\u{FEFF}") { parsed.removeFirst() }
            let blank = parsed.trimmingCharacters(in: .whitespaces).isEmpty
            if blank {
                if state == 1 { throw ToolError(message: "字幕编号后缺少时间轴") }
                state = 0; result += original; continue
            }
            if state == 0 {
                guard parsed.range(of: "^[0-9]+$", options: .regularExpression) != nil else {
                    throw ToolError(message: "SRT 格式无效：预期字幕编号，实际为 \(parsed.prefix(60))")
                }
                state = 1; result += original
            } else if state == 1 {
                guard parsed.range(of: "^\\d{2,}:\\d{2}:\\d{2},\\d{3}[ \\t]+-->[ \\t]+\\d{2,}:\\d{2}:\\d{2},\\d{3}(?:[ \\t].*)?$", options: .regularExpression) != nil else {
                    throw ToolError(message: "SRT 时间轴格式无效：\(parsed.prefix(80))")
                }
                state = 2; cueCount += 1; result += original
            } else {
                let kept = body.unicodeScalars.filter { scalar in
                    switch scalar.properties.generalCategory {
                    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                         .initialPunctuation, .finalPunctuation, .otherPunctuation: return false
                    default: return true
                    }
                }
                result += String(String.UnicodeScalarView(kept)) + ending
            }
        }
        guard state != 1, cueCount > 0 else { throw ToolError(message: "文件没有有效 SRT 时间轴") }
        return result
    }
    static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if String(data: data, encoding: .utf8) != nil { return String(decoding: data, as: UTF8.self) }
        if data.starts(with: [0xff, 0xfe]), let text = String(data: data, encoding: .utf16LittleEndian) { return text }
        if data.starts(with: [0xfe, 0xff]), let text = String(data: data, encoding: .utf16BigEndian) { return text }
        throw ToolError(message: "字幕编码不是 UTF-8 或 UTF-16，请先转换编码")
    }
    static func uniquePair(directory: URL, stem: String) -> (URL, URL) {
        var n = 1
        while true {
            let name = n == 1 ? stem : "\(stem)_\(n)"
            let raw = directory.appendingPathComponent(name + ".srt")
            let clean = directory.appendingPathComponent(name + "_无标点.srt")
            if !FileManager.default.fileExists(atPath: raw.path) && !FileManager.default.fileExists(atPath: clean.path) { return (raw, clean) }
            n += 1
        }
    }
    static func stripFile(_ input: URL, directory: URL) throws -> URL {
        let text = try clean(read(input))
        let stem = input.deletingPathExtension().lastPathComponent + "_最终字幕"
        var n = 1, output = directory.appendingPathComponent(stem + ".srt")
        while FileManager.default.fileExists(atPath: output.path) { n += 1; output = directory.appendingPathComponent(stem + "_" + String(n) + ".srt") }
        // Exclusive creation never replaces an existing file, including the input.
        try writeExclusive(Data(text.utf8), to: output)
        return output
    }
    static func writeExclusive(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
    }
}

struct TranscriptionRequest {
    var input: URL
    var directory: URL
    var executable: URL
    var model: String
    var language: String
    var prompt: String
    var processing: ProcessingOptions? = nil
    func arguments(staging: URL) -> [String] {
        var args = [input.path, "--model", model, "--output-dir", staging.path,
                    "--output-name", "transcript", "--output-format", "srt", "--verbose", "True", "--condition-on-previous-text", "False"]
        if !language.isEmpty { args += ["--language", language] }
        if !prompt.isEmpty { args += ["--initial-prompt", prompt] }
        return args
    }
}

final class Transcriber {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var recognitionNotes: [String] = []
    private(set) var lastReport = ""
    private func checkCancelled() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw ToolError(message: "已取消，未写入字幕") }
    }
    private func execute(_ executable: URL, arguments: [String], environment: [String: String],
                         log: @escaping (String) -> Void) throws {
        let p = Process(), pipe = Pipe()
        p.executableURL = executable; p.arguments = arguments
        var childEnvironment = environment
        if executable.lastPathComponent.hasPrefix("python") {
            for key in ["__PYVENV_LAUNCHER__", "PYTHONHOME", "PYTHONPATH"] { childEnvironment.removeValue(forKey: key) }
        }
        p.environment = childEnvironment
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw ToolError(message: "已取消") }
        process = p
        do { try p.run(); lock.unlock() } catch { process = nil; lock.unlock(); throw error }
        var pending = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            if let text = String(data: pending, encoding: .utf8) { log(text); pending.removeAll(keepingCapacity: true) }
            else if pending.count > 8192 { log(String(decoding: pending, as: UTF8.self)); pending.removeAll() }
        }
        if !pending.isEmpty { log(String(decoding: pending, as: UTF8.self)) }
        p.waitUntilExit()
        lock.lock(); process = nil; lock.unlock()
        try checkCancelled()
        guard p.terminationStatus == 0 else { throw ToolError(message: "处理进程失败（退出码 \(p.terminationStatus)），请查看日志") }
    }
    private func enhance(_ source: String, options: ProcessingOptions, staging: URL,
                         log: @escaping (String) -> Void) throws -> ProofreadingResult {
        let normalized = Vocabulary.normalize(try SubtitleDocument.parse(source), vocabulary: options.vocabulary)
        let cues = normalized.cues
        log(normalized.report + "\n")
        guard options.expandYears || options.contextualCorrection || options.translateForeign else {
            return ProofreadingResult(cues: cues, report: normalized.report + "\n未启用上下文校对。\n")
        }
        guard let resources = Bundle.main.resourceURL else { throw ToolError(message: "找不到应用资源目录") }
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("本地校对环境")
        let runtime = sibling
        let python = runtime.appendingPathComponent("venv/bin/python3")
        let script = resources.appendingPathComponent("proofread.py")
        let model = runtime.appendingPathComponent("model")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: model.appendingPathComponent("config.json").path) else {
            throw ToolError(message: "本地校对环境未就绪，请运行 scripts/setup.sh；也可关闭年份、同音字校对和翻译，仅做词库归一与排版")
        }
        let input = staging.appendingPathComponent("proofread-input.json"), output = staging.appendingPathComponent("proofread-output.json")
        let payload = ProofreadingPayload(cues: cues, reference_year: options.recordingYear,
            expand_years: options.expandYears, correct_homophones: options.contextualCorrection, vocabulary: Vocabulary.terms(options.vocabulary).joined(separator: "，"), translate_foreign: options.translateForeign)
        try JSONEncoder().encode(payload).write(to: input)
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"; env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        log("\n正在进行本地上下文校对…\n")
        try execute(python, arguments: [script.path, "--input", input.path, "--output", output.path, "--model", model.path], environment: env, log: log)
        let result = try JSONDecoder().decode(ProofreadingResult.self, from: Data(contentsOf: output))
        guard result.cues.count == cues.count, zip(cues, result.cues).allSatisfy({ a, b in a.id == b.id && a.number == b.number && a.timing == b.timing }) else {
            throw ToolError(message: "校对结果结构不一致，已拒绝采用")
        }
        return ProofreadingResult(cues: result.cues, report: normalized.report + "\n" + result.report)
    }
    private func saveEnhanced(_ original: Data, source: String, options: ProcessingOptions, staging: URL,
                              directory: URL, stem: String, log: @escaping (String) -> Void) throws -> [URL] {
        let result: ProofreadingResult
        do { result = try enhance(source, options: options, staging: staging, log: log) }
        catch {
            try checkCancelled()
            let message = "校对未完成，保留原文进行排版：\(error.localizedDescription)"
            log("\n注意：\(message)\n")
            let normalized = Vocabulary.normalize(try SubtitleDocument.parse(source), vocabulary: options.vocabulary)
            result = ProofreadingResult(cues: normalized.cues, report: normalized.report + "\n" + message + "\n年份和同音字未自动校对。\n")
        }
        try checkCancelled()
        log("正在按 \(options.ratio) 拆成独立单行字幕，每条最多 \(options.maxCharacters) 字…\n")
        let report = (self.recognitionNotes.isEmpty ? "" : "识别待复核\n" + self.recognitionNotes.joined(separator: "\n") + "\n\n") + result.report
        lastReport = CaptionExport.report(report, options: options)
        log("\n处理记录（不另存文件，勾选备份时才保存）：\n" + lastReport + "\n")
        return try ProcessedOutput.save(originalData: original, cues: result.cues, report: report,
            options: options, directory: directory, stem: stem)
    }

    func processSRT(_ input: URL, directory: URL, options: ProcessingOptions,
                    log: @escaping (String) -> Void, completion: @escaping (Result<[URL], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("SubtitleStudio-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let source = try Subtitles.read(input), data = try Data(contentsOf: input)
                guard RecognitionQuality.suspicious(try SubtitleDocument.parse(source)).isEmpty else { throw ToolError(message: "这份 SRT 含连续重复、乱码或异常长字幕。请重新选择原音视频转写，无法仅靠文字校对恢复。") }
                let urls = try self.saveEnhanced(data, source: source, options: options, staging: staging,
                    directory: directory, stem: input.deletingPathExtension().lastPathComponent, log: log)
                completion(.success(urls))
            } catch { completion(.failure(error)) }
        }
    }
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
    func run(_ request: TranscriptionRequest, log: @escaping (String) -> Void,
             completion: @escaping (Result<[URL], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let staging = fm.temporaryDirectory.appendingPathComponent("SubtitleStudio-" + UUID().uuidString)
            defer { try? fm.removeItem(at: staging) }
            do {
                guard fm.isExecutableFile(atPath: request.executable.path) else {
                    throw ToolError(message: "找不到可执行 mlx_whisper：\(request.executable.path)\n请在界面选择已安装的命令文件")
                }
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                var env = ProcessInfo.processInfo.environment
                let home = fm.homeDirectoryForCurrentUser.path
                env["PATH"] = [request.executable.deletingLastPathComponent().path, "\(home)/Library/Python/3.9/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", env["PATH"] ?? ""].joined(separator: ":")
                env["PYTHONUNBUFFERED"] = "1"; env["PYTHONIOENCODING"] = "utf-8"
                log("已启动 mlx-whisper，首次使用新模型可能需要下载。\n")
                try self.execute(request.executable, arguments: request.arguments(staging: staging), environment: env, log: log)
                let rawTemp = staging.appendingPathComponent("transcript.srt")
                let firstPass = try Data(contentsOf: rawTemp)
                try self.repairRecognition(request, raw: rawTemp, staging: staging, environment: env, log: log)
                try self.repairSpeechGaps(request, raw: rawTemp, staging: staging, environment: env, log: log)
                let rawData = try Data(contentsOf: rawTemp)
                if let options = request.processing, options.enabled {
                    let urls = try self.saveEnhanced(firstPass, source: Subtitles.read(rawTemp), options: options,
                        staging: staging, directory: request.directory, stem: request.input.deletingPathExtension().lastPathComponent, log: log)
                    completion(.success(urls)); return
                }
                let cleanText = try Subtitles.clean(Subtitles.read(rawTemp))
                let (raw, clean) = Subtitles.uniquePair(directory: request.directory, stem: request.input.deletingPathExtension().lastPathComponent)
                try Subtitles.writeExclusive(rawData, to: raw)
                do { try Subtitles.writeExclusive(Data(cleanText.utf8), to: clean) }
                catch { throw ToolError(message: "原始字幕已保存到 \(raw.path)，但无标点版本保存失败：\(error.localizedDescription)") }
                var saved = [raw, clean]
                if !self.recognitionNotes.isEmpty {
                    let report = raw.deletingPathExtension().appendingPathExtension("txt")
                    try Subtitles.writeExclusive(Data(("识别待复核\n" + self.recognitionNotes.joined(separator: "\n")).utf8), to: report)
                    saved.append(report)
                }
                completion(.success(saved))
            } catch { completion(.failure(error)) }
        }
    }
}

extension Transcriber {
    private func note(_ message: String, log: @escaping (String) -> Void) {
        recognitionNotes.append(message)
        log("\n待复核：" + message + "\n")
    }
    private func retainForReview(_ cue: SubtitleCue) -> SubtitleCue {
        var result = cue
        if RecognitionQuality.badText(cue.text) {
            result.text = "[此段识别异常 请对照原音复核]"
        }
        return result
    }
    private func repairRecognition(_ request: TranscriptionRequest, raw: URL, staging: URL,
                                   environment: [String: String], log: @escaping (String) -> Void) throws {
        let text = try Subtitles.read(raw)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let cues = try SubtitleDocument.parse(text)
        let suspects = RecognitionQuality.suspicious(cues)
        guard !suspects.isEmpty else { log("识别质量检查通过：未发现连续重复、乱码或异常长字幕。\n"); return }
        log("检测到 \(suspects.count) 段可疑字幕，将独立重试；局部失败会保留标记并继续。\n")
        var fixed: [SubtitleCue] = []
        let ffmpeg = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/ffmpeg" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        for (index, cue) in cues.enumerated() {
            try checkCancelled()
            guard suspects.contains(index) else { fixed.append(cue); continue }
            do {
                guard let ffmpeg else { throw ToolError(message: "找不到 ffmpeg，无法重试") }
                let (start, end) = RecognitionQuality.range(cue)
                guard end > start else { throw ToolError(message: "时间轴无效") }
                var recovered: [SubtitleCue] = [], cursor = start
                while cursor < end - 0.001 {
                    let duration = min(15, end-cursor)
                    let clip = staging.appendingPathComponent("retry.wav")
                    try execute(URL(fileURLWithPath: ffmpeg), arguments: ["-nostdin", "-v", "error", "-y", "-ss", String(cursor), "-t", String(duration), "-i", request.input.path, "-ar", "16000", "-ac", "1", clip.path], environment: environment, log: log)
                    var accepted: [SubtitleCue]?
                    for temperature in [0.0, 0.4] {
                        try checkCancelled()
                        do {
                            var retry = request; retry.input = clip
                            // The fallback clears vocabulary as well as preceding
                            // text so a bad prompt cannot perpetuate a loop.
                            if temperature > 0 { retry.prompt = "" }
                            var args = retry.arguments(staging: staging)
                            args[args.firstIndex(of: "--output-name")!+1] = "retry"
                            args += ["--temperature", String(temperature)]
                            let file = staging.appendingPathComponent("retry.srt")
                            try? FileManager.default.removeItem(at: file)
                            log("重试 \(RecognitionQuality.stamp(cursor)) → \(RecognitionQuality.stamp(cursor+duration))，采样温度 \(temperature)\n")
                            try execute(request.executable, arguments: args, environment: environment, log: log)
                            let result = try Subtitles.read(file)
                            let segments = result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try SubtitleDocument.parse(result)
                            if !segments.isEmpty && RecognitionQuality.suspicious(segments).isEmpty { accepted = segments; break }
                        } catch { try checkCancelled(); log("本次重试失败：\(error.localizedDescription)\n") }
                    }
                    if let accepted {
                        for var item in accepted {
                            let (a,b) = RecognitionQuality.range(item)
                            let lo = max(cursor, min(cursor+a, cursor+duration)), hi = max(cursor, min(cursor+b, cursor+duration))
                            if hi > lo {
                                item.timing = "\(RecognitionQuality.stamp(lo)) --> \(RecognitionQuality.stamp(hi))"
                                recovered.append(item)
                            }
                        }
                    } else {
                        var unresolved = cue
                        unresolved.timing = "\(RecognitionQuality.stamp(cursor)) --> \(RecognitionQuality.stamp(cursor+duration))"
                        // Preserve the original only once when a long cue is
                        // split; don't duplicate its words in every failed chunk.
                        if cursor > start { unresolved.text = "[此段识别未恢复 请对照原音复核]" }
                        recovered.append(retainForReview(unresolved))
                        note("[\(unresolved.timing)] 重试后仍无法确认。原音可能是讲话、咳嗽、笑声或背景声；原始识别保存在原始 SRT。", log: log)
                    }
                    cursor += duration
                }
                fixed.append(contentsOf: recovered)
            } catch {
                try checkCancelled()
                fixed.append(retainForReview(cue))
                note("[\(cue.timing)] 局部修复失败，继续输出其他字幕：\(error.localizedDescription)", log: log)
            }
        }
        for index in RecognitionQuality.suspicious(fixed) {
            note("[\(fixed[index].timing)] 此段仍可疑，请听校。", log: log)
            fixed[index] = retainForReview(fixed[index])
        }
        for i in fixed.indices { fixed[i].id = i; fixed[i].number = String(i+1) }
        try Data(SubtitleDocument.serialize(fixed).utf8).write(to: raw)
        log("局部异常处理结束，继续漏段核查与字幕输出。\n")
    }
}

extension Transcriber {
    private func repairSpeechGaps(_ request: TranscriptionRequest, raw: URL, staging: URL,
                                  environment: [String: String], log: @escaping (String) -> Void) throws {
        let text = try Subtitles.read(raw)
        var cues = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try SubtitleDocument.parse(text)
        guard let resources = Bundle.main.resourceURL else { note("漏段核查资源缺失，已保留转写结果。", log: log); return }
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("本地校对环境")
        let runtime = sibling
        let python = runtime.appendingPathComponent("venv/bin/python3")
        let script = resources.appendingPathComponent("detect_speech.py")
        let ffmpeg = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/ffmpeg" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let ffmpeg else { note("找不到 ffmpeg，漏段核查未完成，已保留转写结果。", log: log); return }
        let pcm = staging.appendingPathComponent("speech-check.wav")
        let json = staging.appendingPathComponent("speech-check.json")
        do {
            log("开始漏段核查：本地检测原音频中的语音活动…\n")
            try execute(URL(fileURLWithPath: ffmpeg), arguments: ["-nostdin", "-v", "error", "-y", "-i", request.input.path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", pcm.path], environment: environment, log: log)
            var vadEnv = environment; vadEnv["PYTHONDONTWRITEBYTECODE"] = "1"
            try execute(python, arguments: [script.path, "--input", pcm.path, "--output", json.path], environment: vadEnv, log: log)
            let activity = try JSONDecoder().decode(SpeechActivity.self, from: Data(contentsOf: json))
            let gaps = RecognitionQuality.gaps(cues, duration: activity.duration)
            let suspects = gaps.filter { RecognitionQuality.voicedDuration($0, speech: activity.speech) >= 0.6 }
            log("发现 \(gaps.count) 处至少 3 秒的空档，其中 \(suspects.count) 处检测到疑似讲话，逐段核查。\n")
            var restored = 0
            for (index, gap) in suspects.enumerated() {
                try checkCancelled()
                log("漏段核查 \(index+1)/\(suspects.count)：\(RecognitionQuality.stamp(gap.start)) → \(RecognitionQuality.stamp(gap.end))\n")
                var cursor = gap.start
                while cursor < gap.end - 0.001 {
                    let end = min(cursor+20, gap.end)
                    let part = SpeechInterval(start: cursor, end: end)
                    if RecognitionQuality.voicedDuration(part, speech: activity.speech) < 0.3 { cursor = end; continue }
                    do {
                    let clip = staging.appendingPathComponent("gap.wav")
                    try execute(URL(fileURLWithPath: ffmpeg), arguments: ["-nostdin", "-v", "error", "-y", "-ss", String(cursor), "-t", String(end-cursor), "-i", pcm.path, "-c:a", "pcm_s16le", clip.path], environment: environment, log: log)
                    var accepted: [SubtitleCue]?
                    for temperature in [0.0, 0.4] {
                        try checkCancelled()
                        var retry = request; retry.input = clip
                        var args = retry.arguments(staging: staging)
                        args[args.firstIndex(of: "--output-name")!+1] = "gap"
                        // Missing speech must not be skipped again by the
                        // model's no-speech heuristic during this targeted retry.
                        args += ["--temperature", String(temperature), "--no-speech-threshold", "None"]
                        let result = staging.appendingPathComponent("gap.srt")
                        try? FileManager.default.removeItem(at: result)
                        try execute(request.executable, arguments: args, environment: environment, log: log)
                        let retryText = try Subtitles.read(result)
                        let segments = retryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try SubtitleDocument.parse(retryText)
                        var placed: [SubtitleCue] = []
                        for var item in segments {
                            let (a,b) = RecognitionQuality.range(item)
                            let lo = max(cursor, min(cursor+a, end)), hi = max(cursor, min(cursor+b, end))
                            if hi > lo && item.text.contains(where: { $0.isLetter || $0.isNumber }) {
                                item.timing = "\(RecognitionQuality.stamp(lo)) --> \(RecognitionQuality.stamp(hi))"
                                placed.append(item)
                            }
                        }
                        let missing = RecognitionQuality.uncoveredSpeech(placed, within: part, speech: activity.speech)
                        if !placed.isEmpty && RecognitionQuality.suspicious(placed).isEmpty && missing < 1.2 {
                            accepted = placed; break
                        }
                        log("此段仍存在疑似漏字或异常，尝试下一组识别参数。\n")
                    }
                    if let accepted {
                        cues.append(contentsOf: accepted); restored += accepted.count
                    } else {
                        note("[\(RecognitionQuality.stamp(cursor)) --> \(RecognitionQuality.stamp(end))] 疑似有讲话，但两次重识别仍不可靠。此处保持原空档，请对照原音复核；其他字幕继续输出。", log: log)
                    }
                    } catch {
                        try checkCancelled()
                        note("[\(RecognitionQuality.stamp(cursor)) --> \(RecognitionQuality.stamp(end))] 漏段重试失败，保留空档并继续：\(error.localizedDescription)", log: log)
                    }
                    cursor = end
                }
            }
            cues.sort { RecognitionQuality.range($0).0 < RecognitionQuality.range($1).0 }
            for i in cues.indices { cues[i].id = i; cues[i].number = String(i+1) }
            for index in RecognitionQuality.suspicious(cues) {
                note("[\(cues[index].timing)] 此段仍可疑，请听校。", log: log)
                cues[index] = retainForReview(cues[index])
            }
            try checkCancelled()
            if restored > 0 { try Data(SubtitleDocument.serialize(cues).utf8).write(to: raw) }
            log("漏段核查完成，补回 \(restored) 条字幕；没有检测到讲话的空档保持空白。语音活动判断不等于逐字校验，仍建议复核。\n")
        } catch {
            try checkCancelled()
            note("漏段核查未完成，已保留可用识别结果并继续输出：\(error.localizedDescription)", log: log)
            cues.sort { RecognitionQuality.range($0).0 < RecognitionQuality.range($1).0 }
            for i in cues.indices { cues[i].id = i; cues[i].number = String(i+1) }
            if !cues.isEmpty { try Data(SubtitleDocument.serialize(cues).utf8).write(to: raw) }
        }
    }
}
