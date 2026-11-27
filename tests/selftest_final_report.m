function selftest_final_report()
%SELFTEST_FINAL_REPORT Check missing-reference and shared-success denominators.
methods = ["A";"B";"C";"D"];
predictions = table();
predictions.video_id = repelem(["a";"b";"c"], 4);
predictions.start_s = zeros(12, 1);
predictions.end_s = repmat(60, 12, 1);
predictions.method = repmat(methods, 3, 1);
predictions.candidate = predictions.method + "_frozen";
predictions.split = repmat("final", 12, 1);
predictions.subject_id = repelem(["P1";"P1";"P2"], 4);
predictions.distance_m = repelem([0.5;1;1], 4);
predictions.gt_bpm = repelem([72;NaN;74], 4);
predictions.predicted_bpm = [71;72;73;70;75;NaN;75;75;80;74;NaN;76];
predictions.status = repmat("ok", 12, 1);
predictions.status([6,11]) = "failed";
predictions.failure_reason = repmat("", 12, 1);
predictions.failure_reason([6,11]) = ["decode_failure";"invalid_frame_times"];

time_s = (0:359)' / 30;
pulse = sin(2*pi*1.2*time_s);
example = struct();
example.rgb_data = struct('time_s', time_s, ...
    'raw_rgb', repmat([130 + pulse, 110 + 2*pulse, 90 + pulse], 1, 1, 3));
example.estimate = estimate_hr(struct('time_s',time_s,'values',pulse,'method','A'), config());
root = tempname;
mkdir(root);
cleanup = onCleanup(@() remove_generated_fixture(root)); %#ok<NASGU>
report = struct('predictions', predictions);
summary = write_final_report(report, fullfile(root, 'primary'), example);
overall = summary.metrics(isnan(summary.metrics.distance_m), :);
method_b = overall.method == "B";
assert(all(overall.n_total == 3) && all(overall.n_reference_missing == 1));
assert(overall.n_valid(method_b) == 2 && overall.n_paired(method_b) == 2);
assert(sum(summary.failures.n_attempts(summary.failures.issue == "estimation_failure")) == 2);
assert(sum(summary.failures.n_attempts(summary.failures.issue == "reference_missing")) == 4);
assert(all(summary.common_metrics.n_total == 1));
assert(any(summary.subject_metrics.subject_id == "P2" & summary.subject_metrics.distance_m == 1));
files = ["final_predictions.csv", "metrics_by_distance.csv", "metrics_by_subject_distance.csv", ...
    "metrics_common_valid.csv", "failure_breakdown.csv", "performance_by_method.png", ...
    "performance_by_distance.png", "example_signal.png"];
assert(all(isfile(fullfile(root, 'primary', files))));

report.predictions.gt_bpm(:) = NaN;
summary = write_final_report(report, fullfile(root, 'no_reference'));
assert(isempty(summary.common_metrics) && width(summary.common_metrics) == width(summary.metrics));
assert(all(isnan(summary.metrics.MAE)));

report.predictions(end,:) = [];
try
    write_final_report(report, fullfile(root, 'incomplete'));
    error('rppg:ExpectedIncompleteTrials', 'Incomplete final trial was accepted.');
catch problem
    assert(strcmp(problem.identifier, 'rppg:IncompleteFinalTrials'));
end
fprintf('PASS: final report denominators, failures, cohort comparison, and plots.\n');
end


function remove_generated_fixture(root)
expected_parent = char(java.io.File(tempdir).getCanonicalPath());
resolved_root = char(java.io.File(root).getCanonicalPath());
if strcmp(fileparts(resolved_root), expected_parent)
    rmdir(resolved_root, 's');
end
end
