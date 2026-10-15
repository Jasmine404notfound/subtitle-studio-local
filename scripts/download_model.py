"""Download authorized local model to the app; no audio or subtitles transmitted."""
import argparse
import json
from pathlib import Path
from huggingface_hub import snapshot_download

parser = argparse.ArgumentParser()
parser.add_argument("--destination", required=True)
args = parser.parse_args()
target = Path(args.destination)
repo = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
revision = "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
print(f"下载本地模型 {repo}，固定版本 {revision}。", flush=True)
snapshot_download(repo, revision=revision, local_dir=target / "model",
                  allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "*.jinja", "LICENSE*", "README.md"],
                  max_workers=3)
(target / "model-manifest.json").write_text(json.dumps({"repo": repo, "revision": revision}, indent=2), encoding="utf-8")
print("LOCAL_MODEL_READY", flush=True)
