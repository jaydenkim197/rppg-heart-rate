"""Prepare local field manifests and extract the overlapping Apple Watch HR records."""

import argparse
import csv
import math
import re
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.sax import make_parser
from xml.sax.handler import ContentHandler, feature_external_ges
from zipfile import ZipFile

DISTANCES = (0.5, 1, 2, 3, 4, 5)
HR_TYPE = "HKQuantityTypeIdentifierHeartRate"


def timestamp(value):
    parsed = datetime.fromisoformat(value)
    if parsed.utcoffset() is None:
        raise ValueError("A timestamp is missing its time zone.")
    return parsed


def utc_text(value):
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def read_captures(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = [(repeat, f"S{person:02d}", distance)
                for repeat in range(1, 4)
                for person in range(1, 4)
                for distance in DISTANCES]
    observed = [(int(row["trial"]), row["subject_id"], float(row["distance_m"]))
                for row in rows]
    if observed != expected or len({row["video_id"] for row in rows}) != len(expected):
        raise ValueError("The capture map does not match the expected 54 unique ordered trials.")
    previous_end = None
    for row in rows:
        start = timestamp(row["video_start_utc"])
        duration = float(row["duration_s"])
        if not math.isfinite(duration) or duration <= 0 or (previous_end is not None and start < previous_end):
            raise ValueError("The capture map has invalid durations, overlapping videos, or an order error.")
        row["start"] = start
        row["end"] = start + timedelta(seconds=duration)
        previous_end = row["end"]
    return rows


def watch_model(device):
    hardware = re.search(r"\bhardware:\s*(Watch\d+,\d+)", device, re.IGNORECASE)
    if hardware:
        return hardware.group(1)
    if re.search(r"\bmodel:\s*(?:Apple\s+)?Watch\b", device, re.IGNORECASE):
        return "Apple Watch"
    return ""


class DifferentXmlRoot(Exception):
    """An archive XML member other than the HealthData export."""


class HealthRecords(ContentHandler):
    def __init__(self, first, last):
        super().__init__()
        self.first = first
        self.last = last
        self.seen_root = False
        self.records = []
        self.workouts = []
        self.skipped = Counter()

    def startElement(self, name, attrs):
        if not self.seen_root:
            if name != "HealthData":
                raise DifferentXmlRoot()
            self.seen_root = True
        if name != "Workout" and (name != "Record" or attrs.get("type") != HR_TYPE):
            return
        try:
            start, end = timestamp(attrs["startDate"]), timestamp(attrs["endDate"])
        except (KeyError, ValueError):
            self.skipped["invalid_timestamp"] += 1
            return
        if start >= self.last or end < self.first:
            return
        model = watch_model(attrs.get("device", ""))
        if not model or end < start:
            self.skipped["unsupported_source_or_interval"] += 1
            return
        # Keep the source in process memory for disambiguation. Export only hardware model.
        source = (model, attrs.get("sourceName", ""))
        if name == "Workout":
            self.workouts.append((start, end, source, attrs.get("workoutActivityType", "")))
            return
        try:
            bpm = float(attrs.get("value", "nan"))
        except ValueError:
            bpm = math.nan
        if attrs.get("unit") != "count/min" or not math.isfinite(bpm) or bpm <= 0:
            self.skipped["invalid_bpm_or_unit"] += 1
            return
        self.records.append((start, end, source, bpm))


def read_health(archive_path, first, last):
    exports = []
    with ZipFile(archive_path) as archive:
        for member in archive.infolist():
            if not member.filename.lower().endswith(".xml"):
                continue
            records = HealthRecords(first, last)
            parser = make_parser()
            parser.setFeature(feature_external_ges, False)
            parser.setContentHandler(records)
            with archive.open(member) as stream:
                try:
                    parser.parse(stream)
                except DifferentXmlRoot:
                    continue
            exports.append(records)
    if len(exports) != 1:
        raise ValueError("The archive must contain exactly one Apple Health HealthData XML document.")
    return exports[0]


def write_csv(path, fields, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("captures", type=Path, help="Local chronological video map from intake.")
    args.add_argument("archive", type=Path, help="Apple Health export ZIP on the local drive.")
    args.add_argument("output", type=Path, help="Ignored local directory for private CSVs.")
    args = args.parse_args()
    captures = read_captures(args.captures)
    health = read_health(args.archive, captures[0]["start"], captures[-1]["end"])
    args.output.mkdir(parents=True, exist_ok=True)
    experiment_rows, watch_rows, attendance, capture_rows = [], [], [], []
    for camera in captures:
        start, end = camera["start"], camera["end"]
        video_id = camera["video_id"]
        readings = [(a, b, source, bpm) for a, b, source, bpm in health.records
                    if start <= a < end and b <= end]
        sources = {source for _, _, source, _ in readings}
        source_status = "ok" if len(sources) == 1 else (
            "no_watch_samples" if not sources else "ambiguous_watch_source")
        usable = readings if source_status == "ok" else []
        modes = set()
        for a, b, source, bpm in sorted(usable):
            found = {mode for begin, stop, watch_source, mode in health.workouts
                     if watch_source == source and begin <= a < stop and b <= stop}
            mode = "outside_confirmed_workout"
            if len(found) == 1:
                mode = next(iter(found))
            elif found:
                mode = "ambiguous_workout"
            modes.add(mode)
            watch_rows.append(dict(video_id=video_id, measurement_start_utc=utc_text(a),
                                   measurement_end_utc=utc_text(b), bpm=bpm, watch_model=source[0],
                                   recording_mode=mode, source_offset=a.strftime("%z")))
        notes = "nominal_camera_time;wearer_inferred_from_capture_order;" + source_status
        experiment_rows.append(dict(camera, start_s=0, end_s=60, gt_bpm="", notes=notes))
        capture_rows.append(dict(camera, split="final", scenario="rest",
                                 resolution=f'{camera.get("width", "")}x{camera.get("height", "")}',
                                 configured_fps="", notes=notes))
        attendance.append(dict(video_id=video_id, subject_id=camera["subject_id"], trial=camera["trial"],
                               source_status=source_status, recording_modes=";".join(sorted(modes)),
                               n_samples_in_video=len(usable)))
    write_csv(args.output / "experiments.csv",
              ("video_id", "subject_id", "distance_m", "trial", "video_file", "start_s", "end_s", "gt_bpm", "notes"),
              experiment_rows)
    write_csv(args.output / "capture_metadata.csv",
              ("video_id", "split", "scenario", "video_start_utc", "video_start_source",
               "alignment_uncertainty_s", "resolution", "configured_fps", "codec", "shutter_s",
               "iso", "white_balance", "focus", "lens", "lighting", "frame_drops", "notes"), capture_rows)
    write_csv(args.output / "watch_hr.csv",
              ("video_id", "measurement_start_utc", "measurement_end_utc", "bpm", "watch_model",
               "recording_mode", "source_offset", "notes"), watch_rows)
    write_csv(args.output / "watch_coverage.csv",
              ("video_id", "subject_id", "trial", "source_status", "recording_modes", "n_samples_in_video"),
              attendance)
    wearer_rows = []
    for offset in range(0, len(captures), len(DISTANCES)):
        block = captures[offset:offset + len(DISTANCES)]
        start, end = block[0]["start"], block[-1]["end"]
        intersecting = sum(a < end and b > start for a, b, _, _ in health.workouts)
        wearer_rows.append(dict(subject_id=block[0]["subject_id"], trial=block[0]["trial"],
                                first_clip=block[0]["video_id"], last_clip=block[-1]["video_id"],
                                first_video_utc=utc_text(start), last_video_end_utc=utc_text(end),
                                n_overlapping_workouts=intersecting,
                                evidence="ordered_video_block;actual_handoff_time_unknown"))
    write_csv(args.output / "wearer_blocks.csv",
              ("subject_id", "trial", "first_clip", "last_clip", "first_video_utc", "last_video_end_utc",
               "n_overlapping_workouts", "evidence"), wearer_rows)
    print(f"Prepared {len(captures)} trials and {len(watch_rows)} in-video watch readings.")
    print("Watch source status:", dict(Counter(row["source_status"] for row in attendance)))
    print("In-video recording modes:", dict(Counter(row["recording_modes"] for row in attendance)))
    print("Rejected record classes:", dict(health.skipped))


if __name__ == "__main__":
    main()
