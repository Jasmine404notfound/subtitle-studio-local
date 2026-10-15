# 参与贡献

欢迎帮助改进字幕质量、安装体验、兼容性和界面，也欢迎报告问题。

Issue 请描述 macOS 版本、芯片、Python 版本、模型、功能开关、期望结果与实际结果；附最短的脱敏复现。请勿上传私人素材、完整字幕、绝对路径、令牌或专有词库。

PR 请说明具体问题和验证结果，运行 `bash scripts/test.sh`。涉及推理/安装时还需运行本地真实短样例，并如实写出未经验证的平台。不要将模型、venv、dist、音视频或生成字幕纳入提交。

源码入口是 Sources/SubtitleStudio/App.swift。Core.swift 调用本地进程；SubtitleProcessing.swift 管理方案和排版；Vocabulary.swift 归一专名；CaptionExport.swift 拆条导出；Resources/proofread.py 进行本地校对/翻译。

贡献按仓库 MIT 许可证提交；不要提交无权再分发的素材或代码。后续优先方向：干净 Mac 安装验收、可迁移 Python 运行时、逐字对齐、签名与公证发布。
