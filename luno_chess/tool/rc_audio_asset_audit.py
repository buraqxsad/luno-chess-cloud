import array
import hashlib
import io
import json
import math
from pathlib import Path
import sys
import wave


def inspect_wave(data):
    with wave.open(io.BytesIO(data), "rb") as audio:
        channels = audio.getnchannels()
        sample_width = audio.getsampwidth()
        rate = audio.getframerate()
        frames = audio.getnframes()
        if audio.getcomptype() != "NONE" or sample_width != 2:
            raise ValueError("Audit supports the current uncompressed PCM16 assets only")
        if channels < 1 or rate < 1 or frames < 1:
            raise ValueError("Missing audio frames or invalid stream dimensions")
        decoded = audio.readframes(frames)
        if len(decoded) != frames * channels * sample_width:
            raise ValueError("Truncated PCM data")
    samples = array.array("h", decoded)
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(sample) for sample in samples)
    if peak == 0:
        raise ValueError("Audio asset is entirely silent")
    return {
        "channels": channels,
        "sampleWidth": sample_width,
        "sampleRate": rate,
        "frames": frames,
        "decodedBytes": len(decoded),
        "durationSeconds": frames / rate,
        "peak": peak / 32768,
        "rms": math.sqrt(sum(sample * sample for sample in samples) / len(samples)) / 32768,
    }


def fixture(samples):
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(22050)
        audio.writeframes(array.array("h", samples).tobytes())
    return buffer.getvalue()


def self_test():
    valid = fixture([0, 1800, -1800, 0])
    assert inspect_wave(valid)["frames"] == 4
    for bad in [b"", b"NOPE" + valid[4:], valid[:-2], fixture([0, 0, 0, 0])]:
        try:
            inspect_wave(bad)
        except (ValueError, wave.Error, EOFError):
            continue
        raise AssertionError("Invalid fixture was accepted")
    print(json.dumps({"selfTests": 5, "passed": True}))


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    root = Path(__file__).resolve().parent.parent
    inventory = json.loads((root / "qa/rc/product-inventory.json").read_text(encoding="utf-8"))
    rows = []
    for asset in inventory["assets"]:
        if not asset["file"].endswith(".wav"):
            continue
        data = (root / asset["file"]).read_bytes()
        rows.append({"file": asset["file"], "sha256": hashlib.sha256(data).hexdigest(),
                     "bytes": len(data), **inspect_wave(data)})
    if not rows:
        raise ValueError("No WAV assets were audited")
    print(json.dumps({
        "method": "Python wave parser, complete PCM16 sample decode and frame-length/non-silence validation; not listening quality or native playback proof",
        "assets": len(rows), "decodedFrames": sum(row["frames"] for row in rows),
        "inventory": rows,
    }, indent=2))


if __name__ == "__main__":
    main()
