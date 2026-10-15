import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Model: ObservableObject {
    @Published var input: URL?
    @Published var outputDirectory: URL?
    @Published var model: String = "mlx-community/whisper-large-v3-turbo"
    @Published var language = "zh"
    @Published var common: String { didSet { UserDefaults.standard.set(common, forKey: "commonVocabulary") } }
    @Published var temporary = ""
    @Published var executable: String { didSet { UserDefaults.standard.set(executable, forKey: "whisperExecutable") } }
    @Published var running = false
    @Published var logs = ""
    @Published var processingReport = ""
    @Published var showReport = false
    @Published var status = "准备就绪"
    @Published var results: [URL] = []
    @Published var began: Date?
    @Published var alertMessage = ""
    @Published var showAlert = false
    @Published var ratio = UserDefaults.standard.string(forKey: "videoRatio") ?? "16:9" {
        didSet {
            UserDefaults.standard.set(ratio, forKey: "videoRatio")
            maxCharacters = presetLimit(for: ratio)
        }
    }
    @Published var maxCharacters = UserDefaults.standard.object(forKey: "lineLimit") as? Int ?? 25 {
        didSet { UserDefaults.standard.set(maxCharacters, forKey: "lineLimit") }
    }
    @Published var schemes = CaptionScheme.load() {
        didSet { CaptionScheme.save(schemes) }
    }
    @Published var selectedScheme = UserDefaults.standard.string(forKey: "selectedCaptionScheme") ?? "" {
        didSet {
            UserDefaults.standard.set(selectedScheme, forKey: "selectedCaptionScheme")
            maxCharacters = presetLimit(for: ratio)
        }
    }
    func presetLimit(for ratio: String) -> Int {
        schemes.first(where: { $0.id == selectedScheme })?.limit(for: ratio) ?? CaptionScheme.defaults[ratio] ?? 25
    }
    func saveScheme(_ scheme: CaptionScheme) {
        if let index = schemes.firstIndex(where: { $0.id == scheme.id }) { schemes[index] = scheme }
        else if schemes.count < 3 { schemes.append(scheme) }
        else { return }
        selectedScheme = scheme.id
    }
    func deleteScheme(_ id: String) {
        schemes.removeAll { $0.id == id }
        if selectedScheme == id { selectedScheme = "" }
    }
    @Published var expandYears = true
    @Published var contextualCorrection = true
    @Published var translateForeign = UserDefaults.standard.bool(forKey: "translateForeign") {
        didSet { UserDefaults.standard.set(translateForeign, forKey: "translateForeign") }
    }
    @Published var recordingYear = Calendar.current.component(.year, from: Date())
    @Published var keepPunctuation = UserDefaults.standard.bool(forKey: "keepPunctuation") { didSet { UserDefaults.standard.set(keepPunctuation, forKey: "keepPunctuation") } }
    @Published var saveExtras = UserDefaults.standard.bool(forKey: "saveExtras") { didSet { UserDefaults.standard.set(saveExtras, forKey: "saveExtras") } }
    @Published var processExistingSRT = true
    @Published private(set) var srtOnly: Bool
    var worker: Transcriber?
    init(srtOnly: Bool) {
        self.srtOnly = srtOnly
        common = UserDefaults.standard.string(forKey: "commonVocabulary") ?? ""
        let bundledCLI = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("本地校对环境/venv/bin/mlx_whisper").path
        let savedCLI = UserDefaults.standard.string(forKey: "whisperExecutable")
        let candidates = [savedCLI, bundledCLI, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Python/3.9/bin/mlx_whisper").path, "/opt/homebrew/bin/mlx_whisper", "/usr/local/bin/mlx_whisper"].compactMap { $0 }
        executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? bundledCLI
    }
    func switchMode(_ srt: Bool) {
        guard !running, srt != srtOnly else { return }
        srtOnly = srt
        input = nil; results = []; logs = ""; status = "准备就绪"; showAlert = false
    }
    func append(_ text: String) { logs += text; if logs.count > 70000 { logs = String(logs.suffix(60000)) } }
    func accept(_ url: URL) {
        guard !running else { return }
        let allowed = ["srt", "m4a", "mp3", "wav", "mp4", "mov", "aiff", "aif", "aac", "flac", "ogg", "opus", "mkv", "webm", "m4v"]
        guard allowed.contains(url.pathExtension.lowercased()), FileManager.default.isReadableFile(atPath: url.path) else {
            alertMessage = srtOnly ? "请选择可读取的 SRT 文件" : "请选择可读取的音频或视频文件"; showAlert = true; return
        }
        switchMode(url.pathExtension.lowercased() == "srt")
        input = url; results = []; status = "文件已就绪"
    }
    func chooseInput() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = srtOnly ? [UTType(filenameExtension: "srt") ?? .plainText] : [.audio, .movie]
        if panel.runModal() == .OK, let url = panel.url { accept(url) }
    }
    func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }
    func chooseExecutable() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: executable).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { executable = url.path }
    }
    func finish(_ result: Result<[URL], Error>) {
        let report = worker?.lastReport ?? ""
        processingReport = report
        running = false; worker = nil
        switch result {
        case .success(let urls):
            results = urls; status = "已完成"
            append("\n最终字幕（导入视频请使用此文件）：\n" + urls.map(\.path).joined(separator: "\n") + "\n")
            alertMessage = "最终字幕已保存：\(urls.first?.lastPathComponent ?? "")。导入视频请使用这一份文件。"; NSSound.beep()
            if report.contains("校对未完成") || report.contains("翻译未完成") {
                status = "已输出（部分处理未完成）"
                alertMessage += "部分校对或翻译未完成，请查看处理记录。"
            }
            if report.contains("识别待复核") {
                status = "已输出（含待复核片段）"
                alertMessage += "存在待听校片段，请查看处理记录中的时间。"
            }
        case .failure(let error): status = "未完成"; alertMessage = error.localizedDescription; append("\n" + error.localizedDescription + "\n")
        }
        showAlert = true
    }
    func start() {
        guard let input, !running else { return }
        let directory = outputDirectory ?? input.deletingLastPathComponent()
        let prompt = [common, temporary].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "，")
        let options = ProcessingOptions(enabled: true, ratio: ratio, maxCharacters: maxCharacters,
            expandYears: expandYears, contextualCorrection: contextualCorrection, translateForeign: translateForeign, recordingYear: recordingYear, vocabulary: prompt, keepPunctuation: keepPunctuation, saveExtras: saveExtras)
        results = []; logs = ""; processingReport = ""; running = true; began = Date(); status = srtOnly ? (processExistingSRT ? "正在排版与校对" : "正在去标点") : "正在转写"
        if srtOnly {
            if processExistingSRT {
                let worker = Transcriber(); self.worker = worker
                worker.processSRT(input, directory: directory, options: options,
                    log: { text in DispatchQueue.main.async { self.append(text) } },
                    completion: { result in DispatchQueue.main.async { self.finish(result) } })
                return
            }
            DispatchQueue.global().async {
                let result = Result { [try Subtitles.stripFile(input, directory: directory)] }
                DispatchQueue.main.async { self.finish(result) }
            }
        } else {
            let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedModel.isEmpty else { finish(.failure(ToolError(message: "模型不能为空"))); return }
            let request = TranscriptionRequest(input: input, directory: directory, executable: URL(fileURLWithPath: executable), model: selectedModel, language: language, prompt: prompt, processing: options)
            append("输入：\(input.path)\n模型：\(selectedModel)\n语言：\(language.isEmpty ? "自动识别" : language)\n合并词库：\(prompt)\n\n")
            let worker = Transcriber(); self.worker = worker
            worker.run(request, log: { text in DispatchQueue.main.async { self.append(text) } },
                       completion: { result in DispatchQueue.main.async { self.finish(result) } })
        }
    }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting(results) }
}

struct ContentView: View {
    @ObservedObject var vm: Model
    @State private var targeted = false
    @State private var advanced = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Picker("功能", selection: Binding(get: { vm.srtOnly }, set: { vm.switchMode($0) })) {
                Text("音视频转写").tag(false)
                Text("已有 SRT").tag(true)
            }.pickerStyle(.segmented).disabled(vm.running)
            HStack {
                Image(systemName: vm.srtOnly ? "text.badge.checkmark" : "waveform.circle.fill").font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.srtOnly ? "已有 SRT" : "字幕转写").font(.title2.bold())
                    Text(vm.srtOnly ? "保留原始字幕，可选排版与上下文校对" : "本地转写 · 语义排版 · 上下文校对").foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.title2)
                Text(vm.input?.lastPathComponent ?? (vm.srtOnly ? "将 SRT 拖到这里" : "将音频或视频拖到这里")).font(.headline).lineLimit(2)
                if let input = vm.input { Text(input.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled) }
                Button("选择文件…") { vm.chooseInput() }.disabled(vm.running)
            }
            .frame(maxWidth: .infinity).padding(14)
            .background(targeted ? Color.blue.opacity(0.14) : Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(targeted ? Color.blue : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard !vm.running, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { vm.accept(url) } }
                }
                return true
            }
            if !vm.srtOnly {
                HStack {
                    Text("模型")
                    TextField("Hugging Face 模型或本地模型目录", text: $vm.model)
                    Menu("常用模型") {
                        ForEach(["mlx-community/whisper-large-v3-turbo", "mlx-community/whisper-large-v3", "mlx-community/whisper-medium", "mlx-community/whisper-small", "mlx-community/whisper-tiny"], id: \.self) { name in
                            Button(name) { vm.model = name }
                        }
                    }
                    Picker("语言", selection: $vm.language) {
                        Text("中文").tag("zh"); Text("自动").tag(""); Text("英语").tag("en"); Text("粤语").tag("yue"); Text("日语").tag("ja"); Text("韩语").tag("ko")
                    }.frame(width: 145)
                }.disabled(vm.running)
                HStack(alignment: .top, spacing: 12) {
                    vocabulary(title: "常用专有名词词库 · 自动保存", text: $vm.common)
                    vocabulary(title: "本次临时词库 · 仅本次会话", text: $vm.temporary)
                }.disabled(vm.running)
                Text("用逗号或换行分隔词语。识别后按词库归一专名；中文三字以上同音词、英文大小写与空格自动纠正。").font(.caption).foregroundStyle(.secondary)
            }
            if vm.srtOnly {
                Toggle("启用词库纠正、独立字幕断句和可选翻译", isOn: $vm.processExistingSRT).disabled(vm.running)
            }
            if !vm.srtOnly || vm.processExistingSRT {
                SubtitlePreferences(vm: vm).disabled(vm.running)
            }
            HStack {
                Text("输出目录")
                Text(vm.outputDirectory?.path ?? "源文件同目录").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button("更改…") { vm.chooseDirectory() }
                if vm.outputDirectory != nil { Button("恢复默认") { vm.outputDirectory = nil } }
            }.disabled(vm.running)
            if !vm.srtOnly {
                DisclosureGroup("高级：mlx-whisper 命令路径", isExpanded: $advanced) {
                    HStack { TextField("命令绝对路径", text: $vm.executable); Button("选择…") { vm.chooseExecutable() } }.padding(.top, 5)
                }.disabled(vm.running)
            }
            HStack {
                Button(vm.srtOnly ? (vm.processExistingSRT ? "生成最终字幕" : "生成无标点字幕") : "开始转写") { vm.start() }.buttonStyle(.borderedProminent).disabled(vm.input == nil || vm.running)
                if vm.running {
                    ProgressView().controlSize(.small)
                    if vm.worker != nil { Button("取消") { vm.worker?.cancel(); vm.status = "正在取消…" } }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("已用时 \(Int(context.date.timeIntervalSince(vm.began ?? context.date))) 秒").foregroundStyle(.secondary)
                    }
                }
                Text(vm.status).foregroundStyle(.secondary)
                Spacer()
                Button("查看处理记录") { vm.showReport = true }.disabled(vm.processingReport.isEmpty)
                Button("在 Finder 中显示") { vm.reveal() }.disabled(vm.results.isEmpty)
            }
            Text("实时日志").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.logs.isEmpty ? "等待开始…" : vm.logs).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(8).background(Color(nsColor: .textBackgroundColor)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                .onChange(of: vm.logs) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }.frame(height: 180)
            Text(vm.srtOnly ? "原始字幕始终保留 · 重名输出自动加序号 · 完全本地处理" : "原始文件始终保留 · 重名输出自动加序号 · 新模型首次下载需要联网").font(.caption).foregroundStyle(.secondary)
        }.padding(22)
        }.frame(minWidth: 760, minHeight: 600)
        .sheet(isPresented: $vm.showReport) {
            VStack(alignment: .leading, spacing: 12) {
                Text("本次处理记录").font(.headline)
                ScrollView { Text(vm.processingReport).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("关闭") { vm.showReport = false }
            }.padding(20).frame(width: 700, height: 520)
        }
        .alert("字幕工具", isPresented: $vm.showAlert) {
            if !vm.results.isEmpty { Button("在 Finder 中显示") { vm.reveal() } }
            Button("好", role: .cancel) {}
        } message: { Text(vm.alertMessage) }
    }
    func vocabulary(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            TextEditor(text: text).font(.body).frame(height: 82).padding(4).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }.frame(maxWidth: .infinity)
    }
}

struct SubtitlePreferences: View {
    @ObservedObject var vm: Model
    @State private var editingScheme: CaptionScheme?
    @State private var managingSchemes = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Picker("字数方案", selection: $vm.selectedScheme) {
                    Text("内置预设").tag("")
                    ForEach(vm.schemes) { scheme in Text(scheme.name).tag(scheme.id) }
                }.frame(width: 280)
                Button("管理自定义方案…") { managingSchemes = true }
                Spacer()
            }
            HStack {
                Picker("视频比例", selection: $vm.ratio) {
                    ForEach(CaptionScheme.ratios, id: \.self) { ratio in Text(ratio).tag(ratio) }
                }.frame(width: 200)
                Stepper("每条最多 \(vm.maxCharacters) 字", value: $vm.maxCharacters, in: 4...60).frame(width: 240)
                Button("恢复该方案预设") { vm.maxCharacters = vm.presetLimit(for: vm.ratio) }
                Spacer()
            }
            Text("切换方案或比例自动应用已存字数；本页调整仅用于本次，保存预设请进入管理。最多三个自定义方案。").font(.caption).foregroundStyle(.secondary)
            Text("超长正文拆成独立编号、独立时间段的单行字幕；时间按文字长度估算分配，请听校。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("补全两位年份", isOn: $vm.expandYears)
                Stepper("录制年份 \(String(vm.recordingYear))", value: $vm.recordingYear, in: 1900...2100).frame(width: 235)
                Spacer()
            }
            Toggle("保留标点（默认关闭）", isOn: $vm.keepPunctuation)
            Toggle("额外备份原始识别和处理记录", isOn: $vm.saveExtras)
            Text("默认只输出「文件名_最终字幕.srt」，直接导入视频；备份仅在勾选后存入「字幕备份」子文件夹。").font(.caption).foregroundStyle(.secondary)
            Toggle("本地智能校对：他／她／它、的／地／得", isOn: $vm.contextualCorrection)
            Toggle("外语后添加中文翻译（本地）", isOn: $vm.translateForeign)
            Text("例如 product market fit（产品与市场匹配）；最终字幕也保留中文括号。需要原音中的外语先被正确识别。").font(.caption).foregroundStyle(.secondary)
            Text("依据上下文校对；性别、指代或年份不确定时保留原文，可在 App 内查看处理记录。").font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $managingSchemes) {
            VStack(alignment: .leading, spacing: 16) {
                Text("自定义字数方案（\(vm.schemes.count)/3）").font(.headline)
                Text("每个方案可分别设置所有比例的上限，自动保存在本机。")
                ForEach(vm.schemes) { scheme in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(scheme.name).font(.headline)
                            Text(CaptionScheme.ratios.map { "\($0)：\(scheme.limit(for: $0))" }.joined(separator: "  ")).font(.caption)
                        }
                        Spacer()
                        Button("编辑") { editingScheme = scheme }
                        Button("删除", role: .destructive) { vm.deleteScheme(scheme.id) }
                    }
                }
                HStack {
                    Button("新增方案") {
                        var limits = CaptionScheme.defaults
                        for ratio in CaptionScheme.ratios { limits[ratio] = vm.presetLimit(for: ratio) }
                        limits[vm.ratio] = vm.maxCharacters
                        editingScheme = CaptionScheme(name: "自定义方案\(vm.schemes.count + 1)", limits: limits)
                    }.disabled(vm.schemes.count >= 3)
                    Spacer()
                    Button("完成") { managingSchemes = false }
                }
            }.padding(22).frame(width: 640)
            .sheet(item: $editingScheme) { scheme in
                CaptionSchemeEditor(scheme: scheme) { saved in vm.saveScheme(saved) }
            }
        }
    }
}


struct CaptionSchemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var scheme: CaptionScheme
    var onSave: (CaptionScheme) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑字数方案").font(.headline)
            TextField("方案名称", text: $scheme.name)
            ForEach(CaptionScheme.ratios, id: \.self) { ratio in
                Stepper("\(ratio)    每条最多 \(scheme.limit(for: ratio)) 字", value: Binding(
                    get: { scheme.limit(for: ratio) }, set: { scheme.limits[ratio] = $0 }), in: 4...60)
            }
            HStack {
                Button("恢复全部内置值") { scheme.limits = CaptionScheme.defaults }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存并应用") {
                    scheme.name = scheme.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(scheme); dismiss()
                }.buttonStyle(.borderedProminent)
                .disabled(scheme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 440)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let vm = Model(srtOnly: false)
    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 850, height: min(950, (NSScreen.main?.visibleFrame.height ?? 1000) - 80))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "字幕转写"
        window.contentView = NSHostingView(rootView: ContentView(vm: vm))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "关于字幕工具", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item)
        let edit = NSMenuItem(), editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; menu.addItem(edit); NSApplication.shared.mainMenu = menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if vm.running == true {
            let alert = NSAlert(); alert.messageText = "仍在处理字幕"; alert.informativeText = "退出将取消当前任务。"; alert.addButton(withTitle: "继续等待"); alert.addButton(withTitle: "取消并退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            vm.worker?.cancel()
        }
        return .terminateNow
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { vm.accept(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }
}

@main enum Entry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); return }
        if let i = CommandLine.arguments.firstIndex(of: "--transcribe-test"), CommandLine.arguments.count > i + 2 {
            let request = TranscriptionRequest(input: URL(fileURLWithPath: CommandLine.arguments[i + 1]), directory: URL(fileURLWithPath: CommandLine.arguments[i + 2]), executable: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Python/3.9/bin/mlx_whisper"), model: "mlx-community/whisper-large-v3-turbo", language: "zh", prompt: "珀莱雅，欧莱雅，字幕识别")
            let worker = Transcriber()
            worker.run(request, log: { print($0, terminator: "") }, completion: { result in
                switch result { case .success(let urls): print("TRANSCRIBE_PASS", urls.map(\.path)); exit(0)
                case .failure(let error): print("TRANSCRIBE_FAIL", error.localizedDescription); exit(1) }
            })
            RunLoop.current.run(); return
        }
        let app = NSApplication.shared; let delegate = AppDelegate()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
