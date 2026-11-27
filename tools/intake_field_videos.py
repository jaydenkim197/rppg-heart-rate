"""Inspect the 54 planned field MOV files and export a private manifest."""

import argparse
import csv
import hashlib
import io
import itertools
import statistics
import struct
import sys
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path

EPOCH = datetime(1904, 1, 1, tzinfo=UTC)
DATE = b"com.apple.quicktime.creationdate"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(data, offset, format):
    return struct.unpack_from(">" + format, data, offset)


def boxes(stream, begin, end):
    while begin < end:
        if begin + 8 > end:
            raise ValueError("truncated atom")
        stream.seek(begin)
        size, tag = struct.unpack(">I4s", stream.read(8))
        header = 8
        if size == 1:
            size = struct.unpack(">Q", stream.read(8))[0]
            header = 16
        if size == 0:
            size = end - begin
        if not header <= size <= end - begin:
            raise ValueError("invalid atom size")
        yield tag, begin + header, begin + size
        begin += size


def children(data):
    mem = io.BytesIO(data)
    for tag, begin, end in boxes(mem, 0, len(data)):
        yield tag, data[begin:end]


def unique_child(data, target):
    (child,) = [atom for key, atom in children(data) if key == target]
    return child


def header(data):
    return read(data, 4, "QQIQ" if data[0] == 1 else "IIII")


def meta_date(meta):
    cur = io.BytesIO(meta)
    (keys,) = [meta[a:b] for k, a, b in boxes(cur, 0, len(meta)) if k == b"keys"]
    (items,) = [meta[a:b] for k, a, b in boxes(cur, 0, len(meta)) if k == b"ilst"]
    labels = [k[1] for k in children(keys[8:])]
    index = labels.index(DATE) + 1
    entry = unique_child(items, index.to_bytes(4, "big"))
    return unique_child(entry, b"data")[8:].decode()


def table(data, form):
    (n,) = read(data, 4, "I")
    length = struct.calcsize(">" + form)
    require(len(data) == 8 + n * length, "metadata table length mismatch")
    return [read(data, at, form) for at in range(8, len(data), length)]


def check_video_payload_ranges(stbl, segments, n):
    same_size, n_sizes = read(stbl[b"stsz"], 4, "II")
    require(n == n_sizes, "sample count mismatch")
    if same_size:
        sizes = [same_size] * n
    else:
        require(len(stbl[b"stsz"]) == 12 + 4 * n, "invalid sample size table")
        sizes = [
            read(stbl[b"stsz"], at, "I")[0] for at in range(12, len(stbl[b"stsz"]), 4)
        ]
    chunks = table(stbl[b"stco"], "I") if b"stco" in stbl else table(stbl[b"co64"], "Q")
    runs = table(stbl[b"stsc"], "III")
    require(
        runs
        and runs[0][0] == 1
        and all(a[0] < b[0] for a, b in itertools.pairwise(runs)),
        "invalid sample-to-chunk table",
    )
    cursor = 0
    run = 0
    for i, (offset,) in enumerate(chunks, 1):
        if run + 1 < len(runs) and i >= runs[run + 1][0]:
            run += 1
        block = runs[run][1]
        end = offset + sum(sizes[cursor : cursor + block])
        require(
            block > 0
            and cursor + block <= n
            and any(a <= offset < end <= b for a, b in segments),
            "chunk samples outside the media payload",
        )
        cursor += block
    require(
        cursor == n and all(size > 0 for size in sizes),
        "incomplete or empty video samples",
    )


def iso(d):
    return d.astimezone(UTC).isoformat().replace("+00:00", "Z")


def inspect(path):
    with path.open("rb") as f:
        root = list(boxes(f, 0, path.stat().st_size))
        ((start, end),) = [(a, b) for tag, a, b in root if tag == b"moov"]
        segments = [(a, b) for k, a, b in root if k == b"mdat"]
        f.seek(start)
        moov = f.read(end - start)
    src = meta_date(unique_child(moov, b"meta"))
    original_dt = datetime.fromisoformat(src)
    require(
        original_dt.utcoffset() is not None, "embedded creation date has no UTC offset"
    )
    mv_creation, _, movie_hz, movie_duration = header(unique_child(moov, b"mvhd"))
    (track,) = [
        a
        for t, a in children(moov)
        if t == b"trak"
        and unique_child(unique_child(a, b"mdia"), b"hdlr")[8:12] == b"vide"
    ]
    mdia = dict(children(unique_child(track, b"mdia")))
    md_creation, _, track_hz, track_duration = header(mdia[b"mdhd"])
    stbl = dict(children(unique_child(mdia[b"minf"], b"stbl")))
    stsd = stbl[b"stsd"]
    require(read(stsd, 4, "I")[0] == 1, "expected a single video sample description")
    width, height = read(stsd, 40, "HH")
    track_header = unique_child(track, b"tkhd")
    matrix_offset = 52 if track_header[0] == 1 else 40
    horizontal_x, horizontal_y, _, vertical_x, vertical_y = read(
        track_header, matrix_offset, "5i"
    )
    # Track matrices can present coded 3840x2160 media as a portrait video.
    quarter_turn = (
        horizontal_x == vertical_y == 0
        and abs(horizontal_y) == abs(vertical_x) == 65536
    )
    require(
        quarter_turn
        or (
            horizontal_y == vertical_x == 0
            and abs(horizontal_x) == abs(vertical_y) == 65536
        ),
        "unsupported track display matrix",
    )
    display_width, display_height = (height, width) if quarter_turn else (width, height)
    codec = stsd[12:16].decode()
    steps = [delta for n, delta in table(stbl[b"stts"], "II") for _ in range(n)]
    require(
        len(steps) >= 2
        and all(step > 0 for step in steps)
        and sum(steps) == track_duration,
        "invalid video sample timing table",
    )
    if b"ctts" in stbl:
        ctts = stbl[b"ctts"]
        # The QuickTime files can store negative offsets as signed 32-bit
        # values even in version 0. Enforce a monotone, zero-based edited PTS below.
        offsets = [delta for n, delta in table(ctts, "Ii") for _ in range(n)]
        require(len(offsets) == len(steps), "composition timing sample count mismatch")
    else:
        offsets = [0] * len(steps)
    require(movie_hz > 0 and track_hz > 0, "invalid time scale")
    edits = unique_child(unique_child(track, b"edts"), b"elst")
    ((vd, edit_start, rate, subrate),) = table(
        edits, "Qqhh" if edits[0] == 1 else "Iihh"
    )
    require(
        vd / movie_hz >= 60 and edit_start >= 0 and rate == 1 and subrate == 0,
        "clip does not contain the planned analysis window",
    )
    frame_ticks = []
    dts = 0
    for i, (step, offset) in enumerate(zip(steps, offsets), 1):
        frame_ticks.append((dts + offset - edit_start, dts - edit_start, i))
        dts += step
    pts_sorted = sorted(frame_ticks)
    require(
        pts_sorted[0][0] == 0
        and all(a[0] < b[0] for a, b in itertools.pairwise(pts_sorted)),
        "video presentation timestamps are not unique and zero-based",
    )
    n = len(pts_sorted)
    frame_gaps = [(b[0] - a[0]) / track_hz for a, b in itertools.pairwise(pts_sorted)]
    check_video_payload_ranges(stbl, segments, n)
    result = {
        "video_file": str(path),
        "file_name": path.name,
        "bytes": path.stat().st_size,
        "video_start_utc": iso(original_dt),
        "video_start_source": "quicktime_com.apple.quicktime.creationdate",
        "camera_metadata_original": src,
        "timestamp_resolution_s": 1.0,
        "alignment_uncertainty_s": "",
        "alignment_status": "cross_device_clock_unverified",
        "mapping_status": "user_reported_sequence",
        "qt_movie_header_creation_utc": iso(EPOCH + timedelta(seconds=mv_creation)),
        "qt_track_header_creation_utc": iso(EPOCH + timedelta(seconds=md_creation)),
        "file_modified_utc": iso(datetime.fromtimestamp(path.stat().st_mtime, UTC)),
        "container": "QuickTime MOV",
        "codec": codec,
        "width": width,
        "height": height,
        "display_width": display_width,
        "display_height": display_height,
        "nominal_fps": 1 / statistics.median(frame_gaps),
        "average_fps": n * movie_hz / vd,
        "duration_s": vd / movie_hz,
        "container_duration_s": movie_duration / movie_hz,
        "frames": n,
        "pts_begin_s": 0.0,
        "pts_last_s": pts_sorted[-1][0] / track_hz,
        "pts_step_min_s": min(frame_gaps),
        "pts_step_max_s": max(frame_gaps),
        "frame_time_base_s": 1 / track_hz,
        "container_integrity_status": "validated_video_sample_offsets_and_pts",
        "sha256": "",
        "decode_status": "pending",
    }
    return original_dt, result, pts_sorted, track_hz


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "input_dir", type=Path, help="Directory containing the original files"
    )
    parser.add_argument(
        "output_dir", type=Path, help="Private output directory on another path"
    )
    parser.add_argument(
        "--sha256",
        action="store_true",
        help="Read all file bytes to flag exact duplicates",
    )
    options = parser.parse_args()
    input_dir = options.input_dir.resolve(strict=True)
    output_dir = options.output_dir.resolve()
    if output_dir.is_relative_to(input_dir):
        parser.error("Output must be outside the source directory.")
    if not input_dir.is_dir():
        parser.error("Input must be a directory.")
    output_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = output_dir / "frame_pts"
    frames_dir.mkdir(exist_ok=True)
    files = [
        file
        for file in input_dir.iterdir()
        if file.suffix.lower() == ".mov" and file.is_file()
    ]
    records = []
    for path in files:
        try:
            records.append(inspect(path))
        except (KeyError, OSError, ValueError, struct.error) as problem:
            print(path.name, type(problem).__name__, str(problem), file=sys.stderr)
    if len(files) != 54 or len(records) != 54:
        raise SystemExit(f"{len(records)} parsed of {len(files)}")
    records.sort(key=lambda row: row[0])
    dates = [row[0] for row in records]
    if any(earlier >= later for earlier, later in itertools.pairwise(dates)):
        raise SystemExit(
            "Embedded creation timestamps do not establish a unique order."
        )
    filenames = [record[1]["file_name"] for record in records]
    if filenames != sorted(filenames):
        raise SystemExit("Embedded creation timestamps disagree with filename order.")
    for (start, video, *_), next_start in zip(records, dates[1:]):
        if (next_start - start).total_seconds() <= video["duration_s"]:
            raise SystemExit(
                "Adjacent video intervals may overlap or have uncertain order."
            )
    row_list = []
    digests = Counter()
    for index, (_, result, times, hz) in enumerate(records):
        trial = index // 18 + 1
        subject = f"S{((index // 6) % 3) + 1:02d}"
        distance = [0.5, 1, 2, 3, 4, 5][index % 6]
        video_id = f"{subject}_D{str(distance).replace('.', 'p')}_R{trial}"
        pts_file = frames_dir / (video_id + ".csv")
        with pts_file.open("w", newline="", encoding="utf-8") as target:
            csvwriter = csv.writer(target)
            csvwriter.writerow(
                ["frame_index", "pts_s", "dts_s", "sample_index_decode_order"]
            )
            for frame_number, (pts, dts, sample) in enumerate(times, 1):
                csvwriter.writerow(
                    [frame_number, f"{pts / hz:.9f}", f"{dts / hz:.9f}", sample]
                )
        if options.sha256:
            with Path(result["video_file"]).open("rb") as media:
                digest = hashlib.file_digest(media, "sha256").hexdigest()
            digests[digest] += 1
            result["sha256"] = digest
        row_list.append(
            dict(
                camera_sequence=index + 1,
                video_id=video_id,
                subject_id=subject,
                distance_m=distance,
                trial=trial,
                start_s=0,
                end_s=60,
                frame_pts_csv=str(pts_file.resolve()),
                **result,
            )
        )
    for result in row_list:
        result["hash_status"] = (
            "pending"
            if not options.sha256
            else (
                "exact_duplicate" if digests[result["sha256"]] > 1 else "unique_sha256"
            )
        )
    temp = output_dir / "videos.tmp"
    with temp.open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=list(row_list[0]))
        writer.writeheader()
        writer.writerows(row_list)
    temp.replace(output_dir / "videos.csv")
    for field in [
        "container",
        "codec",
        "width",
        "height",
        "display_width",
        "display_height",
        "nominal_fps",
        "frame_time_base_s",
    ]:
        print(field, Counter(row[field] for row in row_list))
    for field in ["duration_s", "frames", "pts_step_min_s", "pts_step_max_s"]:
        vals = [r[field] for r in row_list]
        print(field, "range", min(vals), max(vals))
    for field in [
        "qt_movie_header_creation_utc",
        "qt_track_header_creation_utc",
        "file_modified_utc",
    ]:
        diffs = [
            (
                datetime.fromisoformat(r[field])
                - datetime.fromisoformat(r["video_start_utc"])
            ).total_seconds()
            for r in row_list
        ]
        print(field, "difference range (seconds)", min(diffs), max(diffs))
    if options.sha256:
        print("Exact duplicate copies:", sum(count - 1 for count in digests.values()))
    print(
        "valid non-overlap, embedded creation/filename ordering agrees, row count",
        len(row_list),
    )


if __name__ == "__main__":
    main()
