#!/usr/bin/env python3
"""Local WebRTC speech activity check over a 16kHz mono PCM WAV."""
import argparse
import json
import wave
from pathlib import Path
import webrtcvad


def detect(path):
    vad = webrtcvad.Vad(2)
    spans = []
    with wave.open(str(path), 'rb') as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
            raise ValueError('语音检测需要 16kHz 单声道 PCM16 音频')
        duration = audio.getnframes() / 16000
        frame, start, last = 0, None, None
        while True:
            data = audio.readframes(480)
            if len(data) != 960:
                break
            t = frame * 0.03
            if vad.is_speech(data, 16000):
                if start is None:
                    start = t
                last = t + 0.03
            elif start is not None and t - last > 0.24:
                if last - start >= 0.18:
                    spans.append(dict(start=round(start, 3), end=round(last, 3)))
                start, last = None, None
            frame += 1
        if start is not None and last - start >= 0.18:
            spans.append(dict(start=round(start, 3), end=round(last, 3)))
    return dict(duration=duration, speech=spans)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    Path(args.output).write_text(json.dumps(detect(args.input)), encoding='utf-8')
    print('本地语音活动检测完成。', flush=True)
