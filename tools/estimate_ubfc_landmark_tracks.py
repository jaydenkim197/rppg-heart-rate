"""Export development-only UBFC frame translations from MediaPipe Face Landmarker."""

import argparse
import csv
from concurrent.futures import ProcessPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import re
from statistics import median

import av
import mediapipe as mp
from mediapipe.tasks import python as tasks
from mediapipe.tasks.python import vision


# Nose bridge and inner/outer eye corners in the fixed MediaPipe face topology.
ANCHORS = (33, 133, 168, 263, 362)
MODEL_SHA256 = '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff'


def current_anchor(faces, width, height):
    if len(faces) != 1:
        return None, "face_missing" if not faces else "face_ambiguous"
    points = [(faces[0][i].x, faces[0][i].y) for i in ANCHORS]
    if not all(0 <= x <= 1 and 0 <= y <= 1 for x, y in points):
        return None, "anchor_outside_image"
    return [(x * width, y * height) for x, y in points], "ok"


def export_track(trial, model, output_dir):
    video = Path(trial["video_file"])
    options = vision.FaceLandmarkerOptions(
        base_options=tasks.BaseOptions(model_asset_path=str(model)),
        running_mode=vision.RunningMode.VIDEO,
        num_faces=2,
    )
    path = output_dir / f'{trial["video_id"]}.csv'
    temp = path.with_suffix(".tmp")
    with av.open(str(video)) as container, \
            vision.FaceLandmarker.create_from_options(options) as tracker, \
            temp.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(("frame_index", "time_s", "dx", "dy", "valid", "reason",
                         "frame_width", "frame_height"))
        first_time = None
        previous_ms = -1
        initial_anchor = None
        total = 0
        valid = 0
        for frame in container.decode(video=0):
            if frame.time is None or not math.isfinite(frame.time) or frame.is_corrupt:
                raise ValueError("Missing presentation timestamp or corrupt decoded frame.")
            if (frame.width, frame.height) != (640, 480):
                raise ValueError("Expected the released UBFC Dataset 2 frame dimensions.")
            if first_time is None:
                first_time = frame.time
            timestamp_s = frame.time - first_time
            if timestamp_s >= 30:
                break
            timestamp_ms = round(timestamp_s * 1000)
            if timestamp_ms <= previous_ms:
                raise ValueError("Presentation timestamps do not increase at the model clock resolution.")
            previous_ms = timestamp_ms
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame.to_ndarray(format="rgb24"))
            result = tracker.detect_for_video(image, timestamp_ms)
            anchor, reason = current_anchor(result.face_landmarks, frame.width, frame.height)
            if total == 0:
                initial_anchor = anchor
            total += 1
            dx, dy = "", ""
            if initial_anchor is None:
                reason = "initial_landmarks_missing"
            elif anchor is not None:
                dx = round(median(a[0] - b[0] for a, b in zip(anchor, initial_anchor)))
                dy = round(median(a[1] - b[1] for a, b in zip(anchor, initial_anchor)))
                valid += 1
            writer.writerow((total, f"{timestamp_s:.9f}", dx, dy, int(reason == "ok"), reason,
                             frame.width, frame.height))
        if total == 0:
            raise ValueError("No decoded frames in the requested window.")
    temp.replace(path)
    return total, valid


def export_or_fail(task):
    trial, model, output_dir = task
    try:
        total, valid = export_track(trial, model, output_dir)
        return trial["video_id"], total, valid, ""
    except (OSError, ValueError, RuntimeError) as issue:
        return trial["video_id"], "", "", type(issue).__name__


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trials", type=Path, help="Local frozen UBFC development trials JSON.")
    parser.add_argument("model", type=Path, help="Pinned official Face Landmarker task model.")
    parser.add_argument("output", type=Path, help="Private ignored development result directory.")
    parser.add_argument("--limit", type=int, help="Only for a small integration diagnostic.")
    parser.add_argument("--workers", type=int, default=1, help="Independent whole-clip processes.")
    args = parser.parse_args()
    if not 1 <= args.workers <= 4:
        parser.error("Use one to four independent clip workers.")
    with args.model.open("rb") as file:
        if hashlib.file_digest(file, "sha256").hexdigest() != MODEL_SHA256:
            parser.error("The model file is not the registered Face Landmarker bundle.")
    trials = json.loads(args.trials.read_text(encoding="utf-8-sig"))
    if len(trials) != 28 or len({row["video_id"] for row in trials}) != 28:
        parser.error("Expected the 28 unique development trials.")
    for row in trials:
        video = Path(row["video_file"])
        subject = row["subject_id"].removeprefix("UBFC-")
        if (row["split"], row["start_s"], row["end_s"]) != ("development", 0, 30) \
                or not re.fullmatch(r"subject\d+", subject) or row["video_id"] != subject \
                or video.parent.name != subject or video.parent.parent.name != "ubfc-dataset2":
            parser.error("Expected only original [0,30) UBFC development trial paths.")
    if args.limit is not None and not 1 <= args.limit <= len(trials):
        parser.error("Invalid diagnostic clip count.")
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        parser.error("Use a fresh output directory to avoid mixing track runs.")
    with (args.output / "coverage.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(("video_id", "n_frames", "n_valid", "failure_reason"))
        tasks = [(trial, args.model, args.output) for trial in trials[:args.limit]]
        if args.workers == 1:
            for row in map(export_or_fail, tasks):
                writer.writerow(row)
                file.flush()
        else:
            with ProcessPoolExecutor(max_workers=args.workers) as workers:
                for row in workers.map(export_or_fail, tasks):
                    writer.writerow(row)
                    file.flush()


if __name__ == "__main__":
    main()
