# 第三方项目与模型

仓库不包含第三方模型权重、Python 环境、FFmpeg 二进制或第三方源码副本。安装脚本从上游安装依赖，生成的环境不纳入 Git。

| 项目 | 用途 | 上游与许可证 |
| --- | --- | --- |
| MLX / mlx-whisper | Apple Silicon 推理和语音识别 | https://github.com/ml-explore/mlx / https://github.com/ml-explore/mlx-examples （MIT） |
| MLX LM | 本地语言模型推理 | https://github.com/ml-explore/mlx-lm （MIT） |
| OpenAI Whisper / large-v3-turbo | 语音识别模型 | https://github.com/openai/whisper / https://huggingface.co/openai/whisper-large-v3-turbo （按上游 LICENSE 与模型卡） |
| Qwen3-4B-Instruct-2507 | 上下文校对和翻译 | https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507 （Apache-2.0；实际量化模型见下一行） |
| MLX Qwen 4-bit | Qwen 的 MLX 量化版本 | https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit （请查模型卡和随模型下载的许可证） |
| WebRTC VAD / webrtcvad-wheels | 语音活动检测 | https://github.com/wiseman/py-webrtcvad / https://github.com/daanzu/py-webrtcvad-wheels （包装器 MIT；WebRTC 部分保留其 BSD 等通知） |
| FFmpeg | 本地解码和切片，外部命令 | https://ffmpeg.org/legal.html （LGPL/GPL，取决于构建配置；本项目不分发其二进制） |
| Transformers / Hugging Face Hub 等 | 模型加载、下载及传递依赖 | 各已安装软件包的 LICENSE / dist-info；MIT 不覆盖这些独立项目 |

安装和后续再分发时保留各包及模型附带的 LICENSE / NOTICE。若未来将环境或二进制作为 Release 分发，需要对该具体构建单独收集许可证、源代码义务和通知，不能以本表替代。本项目 MIT 仅覆盖自身代码和原创图标，不改变任何上游授权。
