<p align="center"><img src="Sources/SubtitleStudio/Resources/AppIcon-1024.png" width="128" alt="绿色字幕转写图标"></p>

# 字幕转写 · Subtitle Studio Local

一个给中文视频创作者用的 macOS 本地字幕工具。拖入音视频，生成可直接导入剪辑软件的单行 SRT。原始音视频不修改。

这个项目源于真实剪辑需求：词库没有生效、字幕挤成两行、翻译后超出字数，以及不清楚该用哪份输出。受益于开源社区，也希望把这个小工具分享给需要的人。

**当前为源码发布版 1.8，不是免安装依赖的通用安装包。** 支持 Apple Silicon Mac；尚未在全新电脑完成完整安装与长音频验收。欢迎反馈兼容性问题。

## 功能

- SwiftUI 原生界面，选择或拖入音视频；默认中文、Whisper large-v3-turbo，可换模型和语言。
- 常用词库自动保存，临时词库本次会话生效；通过 initial prompt 提示识别，完成后归一英文大小写/空格与至少三字的中文同音专名。
- 按 16:9、9:16 等七种画幅限制字幕长度，最多保存三个自定义字数方案。
- 校对、译注、去标点完成后重新拆条：每条单行、独立编号和时间段，括号译文也计入字数。
- 可选本地上下文校对（他她它、的地得、两位年份）、外语括号中文翻译。
- 检测疑似识别循环，尝试分段重试；通过本地 VAD 检查长空档。局部不可靠时保留可用输出并提示复核。
- 默认只生成 `文件名_最终字幕.srt`，碰到同名自动加序号；原始识别与记录可选备份。
- 支持已有 SRT 的词库归一、重新断句、校对，或仅去标点。实时日志、取消、Finder 定位。

## 系统要求

- M 系列 Mac，**完整固定环境要求 macOS 26+**；GUI 的构建目标为 macOS 13，不代表整套 MLX 推理支持旧系统。
- Python **3.12**、FFmpeg、Xcode Command Line Tools（或 Xcode）。开发者先自行安装这些工具。
- 推荐 16GB 或以上统一内存，预留至少 10GB 磁盘；实际需求随所选模型、音频和缓存变化。
- 首次依赖和模型下载需要联网；推理在本地进行。无需安装 Codex，无需云端 API Key。
- 暂不支持 Intel Mac / Windows / Linux。

## 从源码开始

先下载仓库（GitHub 的 Code → Download ZIP 并解压，或 git clone），在项目目录打开终端。已安装 Homebrew 的用户可准备工具：

```bash
brew install python@3.12 ffmpeg
xcode-select --install
```

如果已装 Command Line Tools，第二条无需重复运行。Homebrew 本身不由本项目自动安装。

然后运行（网页上传的脚本可能不带可执行权限，使用 bash 调用即可）：

```bash
bash scripts/setup.sh
```

脚本会检查平台，在 `dist/本地校对环境/venv` 创建独立环境，安装 requirements.txt，下载固定版本 Qwen 校对模型，构建并临时签名 `dist/字幕转写.app`，运行结构自检。Whisper 模型将在第一次转写时单独下载。

Python 命令名不同时可指定 **Python 3.12** 的绝对路径：

```bash
SUBTITLE_PYTHON=/path/to/python3.12 bash scripts/setup.sh
```

双击 `dist/字幕转写.app`，拖入文件即可。常用词库初始为空，请自行填写。字数方案在「管理自定义方案」中保存，范围 4～60；内置 16:9 为 25、9:16 为 16。默认不添加外语翻译，可自行勾选。

**请保持项目路径及 Python 安装位置不变。** venv 仍依赖创建它的 Python；不要把本机的 `dist` 直接发给另一台电脑。移动项目后，重新创建环境并运行 setup.sh。当前 app 与旁边的「本地校对环境」需保持相邻。正式签名、公证、可迁移运行时与 DMG 留待后续版本。

## 测试与自检

不下载模型的结构测试：

```bash
bash scripts/test.sh
```

已安装完整环境时的只读依赖检查：

```bash
dist/本地校对环境/venv/bin/python3 scripts/doctor.py
```

Python 测试涵盖允许/拒绝的校对变更和译注边界；Swift 自检涵盖 SRT 结构、标点、原文件保护、同名防覆盖、词库归一、字数上限、独立拆条、方案编解码和异常检测。测试不代表真实模型识别准确率或完整安装验证。

## 已知限制

- 拆条时间按文字长度在原时间段内估算，**没有逐字声学对齐**；请听校。
- 词库不是任意错字替换器，同音歧义、多音字、漏字、两字中文专名可能不纠正。
- 校对模型仍会误判，年份/代词没有足够上下文时应人工核对。外语必须先识别正确，已有括号注释不自动删除。
- 漏段核查与重试不能保证恢复全部语音；失败片段和异常会列在处理记录中，取消或初次识别失败仍可能不输出文件。
- 公共源码整理版已做本机编译与结构验证，但统一 Python 3.12 安装链还需在干净 Mac 实测；依赖固定的是直接版本，非完整传递依赖锁文件。
- 构建使用 ad-hoc 签名，未公证。macOS 可能提示开发者无法验证；请仅从可信源码构建，不要求关闭系统安全功能。

## 隐私、贡献与致谢

不内置账户、追踪、遥测或上传音视频的功能。模型下载会连接包仓库和 Hugging Face；日志可能包含文件路径、词库、字幕文本，提交 Issue 前请脱敏。详见 [PRIVACY.md](PRIVACY.md)。

欢迎 Issue 和 PR，见 [CONTRIBUTING.md](CONTRIBUTING.md)。请不要提交私人音视频、字幕、密钥、模型或个人词库。感谢 MLX、mlx-whisper、MLX LM、Whisper、Qwen、FFmpeg、WebRTC VAD 等项目。

本项目自己的代码与原创图标采用 [MIT](LICENSE)；第三方库、模型和 FFmpeg 仍遵循各自许可证，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
