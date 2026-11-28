"""Verify registered development rankings using only saved CSV rows and plan inputs."""

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


NAN = math.nan
STAGES = [
    "tracking", "temporal", "fft_length", "window", "peak", "spatial",
    "color", "pos", "sqi", "fusion", "interactions",
]
METRICS = [
    "MAE", "within_trial_error_sd_bpm", "delta_mae_bpm", "valid_rate_pct", "within_10_pct",
]


WEIGHTS = [
    [25, 15, 20, 30, 10],
    [25, 25, 30, 15, 5],
    [20, 25, 30, 20, 5],
    [25, 25, 30, 15, 5],
    [35, 20, 25, 15, 5],
    [35, 15, 20, 20, 10],
    [35, 20, 20, 15, 10],
    [25, 25, 25, 20, 5],
    [20, 20, 20, 30, 10],
    [25, 20, 25, 25, 5],
    [25, 25, 30, 15, 5],
]


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def number(text):
    return float(text) if text else NAN


def flag(text):
    assert text.lower() in {"true", "false", "1", "0"}, text
    return text.lower() in {"true", "1"}


def mean(values):
    return statistics.fmean(values) if values else NAN


def percentage(count, total):
    return 100 * count / total if total else NAN


def assert_metric(row, key, expected):
    seen = number(row[key])
    if math.isnan(expected):
        assert math.isnan(seen), (row["candidate"], key, expected, seen)
    else:
        assert math.isclose(seen, expected, rel_tol=1e-11, abs_tol=1e-10), (
            row["candidate"], key, expected, seen
        )


def direction(delta, deadband):
    return (1 if delta > 0 else -1) if abs(delta) > deadband else 0


def metrics_for_candidate(whole, first, second, plan):
    assert whole.keys() == first.keys() == second.keys()
    observed_count = sum(row["observed"] for row in whole.values())
    errors = [row["error"] for row in whole.values() if row["paired"]]
    references = sum(row["reference"] for row in whole.values())
    raw_deltas = []
    contact_deltas = []
    trend_refs = 0
    for trial, a in first.items():
        b = second[trial]
        trend_refs += a["reference"] and b["reference"]
        if a["paired"] and b["paired"]:
            raw_deltas.append(b["bpm"] - a["bpm"])
            contact_deltas.append(b["gt"] - a["gt"])
    trend_errors = [a - b for a, b in zip(raw_deltas, contact_deltas)]
    deadband = plan["change_deadband_bpm"]
    match = sum(direction(a, deadband) == direction(b, deadband) for a, b in zip(raw_deltas, contact_deltas))
    return {
        "n_total": len(whole),
        "n_valid": observed_count,
        "n_paired": len(errors),
        "n_reference_missing": len(whole) - references,
        "MAE": mean([abs(value) for value in errors]),
        "RMSE": math.sqrt(mean([value * value for value in errors])),
        "bias": mean(errors),
        "error_sd_bpm": statistics.stdev(errors) if len(errors) >= 2 else NAN,
        "valid_rate_pct": percentage(observed_count, len(whole)),
        "within_5_pct": percentage(sum(abs(value) <= 5 for value in errors), references),
        "within_10_pct": percentage(sum(abs(value) <= 10 for value in errors), references),
        "within_trial_error_sd_bpm": math.sqrt(mean([value * value / 2 for value in trend_errors])),
        "delta_mae_bpm": mean([abs(value) for value in trend_errors]),
        "trend_pair_rate_pct": percentage(len(trend_errors), trend_refs),
        "direction_agreement_pct": percentage(match, len(trend_errors)),
        "n_trend_reference": trend_refs,
        "n_trend_paired": len(trend_errors),
        "n_subjects": len({key[1] for key, row in whole.items() if row["paired"]}),
    }


def rejection_and_score(metrics, method, plan, weights):
    measured = [metrics[key] for key in METRICS]
    reasons = []
    if method.startswith("Research"):
        reasons.append("research_control")
    if metrics["n_subjects"] < plan["min_paired_subjects"]:
        reasons.append("too_few_paired_subjects")
    components = []
    for value, target, zero in zip(measured, plan["target"], plan["unacceptable"]):
        components.append(max(0, min(1, (value - zero) / (target - zero))))
    score = sum(weight * norm for weight, norm in zip(weights, components)) / sum(weights)
    gates = [value <= gate if target < zero else value >= gate for value, target, zero, gate in zip(
        measured, plan["target"], plan["unacceptable"], plan["gate"])]
    paired_rate = metrics["trend_pair_rate_pct"]
    if not all(math.isfinite(x) for x in [*measured, paired_rate]):
        score = NAN
        reasons.append("missing_metric")
    elif not all(gates) or paired_rate < plan["min_paired_trend_rate_pct"]:
        reasons.append("metric_gate_failed")
    return ";".join(reasons), score


def verify(folder, stage, development_subjects):
    metadata = json.loads((folder / "settings.json").read_text(encoding="utf-8-sig"))
    plan = metadata["plan"]
    windows = [tuple(window) for window in plan["windows_s"]]
    assert windows in [[(0, 30), (0, 15), (15, 30)], [(30, 60), (30, 45), (45, 60)]]
    assert plan["target"] == [5, 4, 3, 100, 90] and plan["unacceptable"] == [20, 16, 15, 60, 35]
    assert plan["metrics"] == METRICS and plan["stages"] == STAGES and plan["gate"] == [15, 12, 12, 85, 50]
    assert plan["min_reference_subjects"] == 18 and plan["min_reference_trend_pairs"] == 12
    assert plan["min_paired_subjects"] == 16 and plan["min_paired_trend_rate_pct"] == 70
    assert plan["tie_margin"] == 0.02 and plan["change_deadband_bpm"] == 2
    assert plan["weights"] == WEIGHTS
    weights = WEIGHTS[STAGES.index(stage)]
    rows = read_csv(folder / "predictions.csv")
    by_candidate = defaultdict(lambda: defaultdict(dict))
    reference_rows = {}
    for row in rows:
        assert row["split"] == "development", row["split"]
        window = (number(row["start_s"]), number(row["end_s"]))
        assert window in windows
        trial = (row["video_id"], row["subject_id"])
        if development_subjects is not None:
            assert trial[1].removeprefix("UBFC-") in development_subjects, trial
        group = (row["method"], row["candidate"])
        assert trial not in by_candidate[group][window], (group, trial, window)
        value, reference = number(row["predicted_bpm"]), number(row["gt_bpm"])
        valid = row["status"] == "ok" and math.isfinite(value)
        has_ref = math.isfinite(reference) and reference > 0
        assert valid == flag(row["valid_estimate"]) and has_ref == flag(row["has_reference"])
        paired = valid and has_ref
        assert_metric(row, "error_bpm", value - reference if paired else NAN)
        ref_key = (trial, window)
        ref_value = (has_ref, reference if has_ref else None, row.get("reference_status"))
        assert reference_rows.setdefault(ref_key, ref_value) == ref_value
        by_candidate[group][window][trial] = {
            "bpm": value, "gt": reference, "observed": valid, "reference": has_ref,
            "paired": paired, "error": value - reference if paired else NAN,
        }
    ranked = read_csv(folder / "ranking.csv")
    assert set(by_candidate) == {(row["method"], row["candidate"]) for row in ranked}
    expected_names = {candidate["name"] for candidate in metadata["candidates"]}
    assert expected_names == {row["candidate"] for row in ranked}
    subject_count = len({trial[1] for trial, window in reference_rows if window == windows[0]})
    assert subject_count == 28 and len(rows) == 3 * subject_count * len(ranked)
    eligible = []
    for row in ranked:
        by_window = by_candidate[row["method"], row["candidate"]]
        calculated = metrics_for_candidate(*(by_window[window] for window in windows), plan)
        for key, expected in calculated.items():
            assert_metric(row, key, expected)
        reason, score = rejection_and_score(calculated, row["method"], plan, weights)
        assert row["rejection_reason"] == reason and flag(row["eligible"]) == (not reason), row
        assert_metric(row, "score", score)
        if not reason:
            eligible.append((score, row["candidate"]))
    assert eligible == sorted(eligible, key=lambda pair: -pair[0])
    whole_refs = sum(values[0] for (_, window), values in reference_rows.items() if window == windows[0])
    paired_refs = sum(reference_rows[trial, windows[2]][0] and values[0]
                      for (trial, window), values in reference_rows.items() if window == windows[1])
    if whole_refs < plan["min_reference_subjects"] or paired_refs < plan["min_reference_trend_pairs"]:
        state = "reference_gate_failed"
    elif not eligible:
        state = "no_eligible_candidate"
    elif len(eligible) > 1 and eligible[0][0] - eligible[1][0] <= plan["tie_margin"]:
        state = "tie"
    else:
        state = "selected"
    return len(rows), state, eligible, whole_refs, paired_refs


def verify_selection(manifest_path, records):
    # First element is the qualified incumbent where applicable.
    priority = {
        "peak": ["max_bin", "parabolic", "zero_padding_4"],
        "color": ["rgb_sum", "log", "temporal", "difference", "saturation"],
        "pos": ["1.6", "1", "2", "3"],
        "sqi": ["energy_ratio", "kurtosis", "cross_correlation", "relative_peaks"],
        "fusion": ["weighted", "equal", "consensus", "best", "spectral"],
    }
    stages = manifest_path.parent
    chosen = json.loads(manifest_path.read_text(encoding="utf-8-sig"))["selected"]
    for stage, selection in chosen.items():
        folder = stages / stage
        _, main_state, main_eligible, _, _ = records[folder]
        assert main_state in {"selected", "tie"}
        allowed = [name for score, name in main_eligible if main_eligible[0][0] - score <= 0.02]
        if main_state == "selected":
            expected_name, expected_basis = allowed[0], "primary"
        else:
            supplementary = folder / "supplementary"
            _, extra_state, extra_eligible, _, _ = records[supplementary]
            candidates = read_csv(supplementary / "ranking.csv")
            assert set(allowed) == {row["candidate"] for row in candidates}
            if extra_state == "selected" and len(extra_eligible) >= 2:
                expected_name, expected_basis = extra_eligible[0][1], "supplementary"
            else:
                expected_name = next(name for name in priority[stage] if name in allowed)
                expected_basis = "predeclared_tie_rule"
        assert (selection["name"], selection["basis"]) == (expected_name, expected_basis), selection
        metadata = json.loads((folder / "settings.json").read_text(encoding="utf-8-sig"))
        matching = [row for row in metadata["candidates"] if row["name"] == expected_name]
        assert len(matching) == 1 and selection["settings"] == matching[0]["overrides"]
    print(f"{len(chosen)} saved selection decisions verified")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results_root", type=Path)
    parser.add_argument("--split-manifest", type=Path)
    args = parser.parse_args()
    development_subjects = None
    if args.split_manifest is not None:
        development_subjects = {r["subjects"] for r in read_csv(args.split_manifest) if r["split"] == "development"}
        assert len(development_subjects) == 28
    counts = []
    records = {}
    for file in sorted(args.results_root.rglob("ranking.csv")):
        folder = file.parent
        if not (folder / "settings.json").is_file() or not (folder / "predictions.csv").is_file():
            continue
        stage = folder.parent.name if folder.name == "supplementary" else folder.name
        if stage.endswith("_x_fusion") or stage.endswith("_x_fft"):
            stage = "interactions"
        records[folder] = verify(folder, stage, development_subjects)
        count, state, eligible, whole_refs, paired_refs = records[folder]
        leader = eligible[0][1] if eligible else ""
        counts.append(count)
        print(f"{folder.relative_to(args.results_root)} {count} rows {state} {leader} refs {whole_refs}/{paired_refs}")
    assert counts, "No complete development ranking groups found"
    print(f"{len(counts)} rankings and {sum(counts)} predictions verified")
    for selection in sorted(args.results_root.rglob("selected.json")):
        verify_selection(selection, records)


if __name__ == "__main__":
    main()
