function selftest_rppg()
%SELFTEST_RPPG Run reproducible signal and decoded-video checks for Method A.

settings = config();
fs = 30;
t = (0:60*fs-1)' / fs;
signal = signal_data(t, sin(2*pi*1.25*t) + 0.4*sin(2*pi*5*t));
result = estimate_hr(signal, settings);
assert(strcmp(result.status, 'ok') && abs(result.predicted_bpm - 75) < 1);
assert(~result.resampled, 'Uniform timestamps must be retained.');
fprintf('Synthetic signal: %.2f BPM\n', result.predicted_bpm);

signal.time_s = t + 0.0003*sin(2*pi*0.7*t);
result = estimate_hr(signal, settings);
assert(result.resampled && abs(result.predicted_bpm - 75) < 1);
signal.time_s = t;
signal.values(:) = 5;
expect_failure(signal, settings, 'flat_signal');
signal.values(:) = sin(2*pi*5*t);
expect_failure(signal, settings, 'no_pulse_band_energy');
signal.values(11) = NaN;
expect_failure(signal, settings, 'nonfinite_or_missing_signal');
gap = [1:200, 231:numel(t)];
expect_failure(signal_data(t(gap), sin(2*pi*1.25*t(gap))), settings, ...
    'frame_gap_requires_segment_analysis');

video_file = [tempname, '.avi'];
cleanup = onCleanup(@() delete(video_file)); %#ok<NASGU>
writer = VideoWriter(video_file, 'Uncompressed AVI');
writer.FrameRate = fs;
open(writer);
rects = [3, 3, 9, 6; 3, 14, 10, 7; 22, 14, 6, 9];
for index = 1:12*fs
    frame = repmat(reshape(uint8([145, 100, 80]), 1, 1, 3), 32, 36);
    for region = 1:3
        x = rects(region, 1) + (0:rects(region, 3)-1);
        y = rects(region, 2) + (0:rects(region, 4)-1);
        frame(y, x, 2) = uint8(100 + region*2 + 12*sin(2*pi*1.25*t(index)));
    end
    writeVideo(writer, frame);
end
close(writer);
[~, ~, report] = main(video_file, rects);
assert(strcmp(report.estimate.status, 'ok') && abs(report.estimate.predicted_bpm - 75) < 1);
assert(size(report.rgb_data.raw_rgb, 1) == 12*fs, 'Unexpected decoded frame count.');
assert(all(report.rgb_data.pixel_counts(1, :) == prod(rects(:, 3:4), 2)'));
fprintf('Synthetic video end-to-end: %.2f BPM, %d frames\n', ...
    report.estimate.predicted_bpm, numel(report.rgb_data.time_s));
fprintf('PASS: Method A signal, frame timing, failure paths, and video decode.\n');

trials = table(["S1"; "S2"], ["good"; "missing"], ["development"; "development"], ...
    [string(video_file); string(video_file) + ".missing"], [0; 0], [12; 12], ...
    {rects; rects}, [75; 75], 'VariableNames', {'subject_id', 'video_id', 'split', ...
    'video_file', 'start_s', 'end_s', 'roi_boxes', 'gt_bpm'});
candidates = struct('name', {'butterworth', 'ideal', 'gaussian', 'no_filter', ...
    'rectangular', 'hamming', 'padding', 'parabolic'}, 'overrides', ...
    {struct(), struct('bandpass_variant', 'ideal'), ...
    struct('bandpass_variant', 'gaussian'), struct('bandpass_variant', 'none'), ...
    struct('fft_window', 'rectangular'), struct('fft_window', 'hamming'), ...
    struct('fft_padding_factor', 4), struct('peak_method', 'parabolic')});
bench = run_benchmark(trials, 'development', candidates);
assert(height(bench.predictions) == 2*numel(candidates));
assert(all(bench.metrics.n_total == 2 & bench.metrics.n_paired == 1));
assert(all(bench.metrics.valid_rate_pct == 50 & bench.metrics.within_5_pct == 50));
assert(all(bench.metrics.MAE < 1));
assert(any(bench.predictions.method == "ResearchNoBandpass"));
criteria = table(["MAE"; "valid_rate_pct"], [0.5; 100], [2; 0], [1; 1], [1; 50], ...
    'VariableNames', {'metric', 'target', 'unacceptable', 'weight', 'gate'});
ranking = rank_candidates(bench, criteria, 1, 0.05);
assert(ranking.state == "tie");
assert(any(ranking.ranking.rejection_reason == "research_control"));
unqualified = rank_candidates(bench, criteria, 2, 0.05);
assert(unqualified.state == "no_eligible_candidate");
fprintf('PASS: target-based scoring, control exclusion, tie and subject gates.\n');
trials.split(2) = "independent";
trials.subject_id(2) = trials.subject_id(1);
try
    run_benchmark(trials, 'development', candidates);
    error('rppg:ExpectedSubjectLeakage', 'A split overlap was not rejected.');
catch problem
    assert(strcmp(problem.identifier, 'rppg:SubjectLeakage'));
end

ref_file = [tempname, '.txt'];
ref_cleanup = onCleanup(@() delete(ref_file)); %#ok<NASGU>
writelines(["0  1  0"; "75  75  75"; "0  0.5  1"], ref_file);
reference = read_ubfc_reference(ref_file);
assert(height(reference) == 3 && reference.time_s(end) == 1 && reference.bpm(2) == 75);
writelines(["0  1  1  0"; "75  75  75  75"; "0  0.5  0.5  1"], ref_file);
assert(isequal(read_ubfc_reference(ref_file), reference), 'Identical duplicates count only once.');
writelines(["0  1  2  0"; "75  75  75  75"; "0  0.5  0.5  1"], ref_file);
try
    read_ubfc_reference(ref_file);
    error('rppg:ExpectedInvalidUbfcReference', 'Conflicting duplicate times must fail.');
catch problem
    assert(strcmp(problem.identifier, 'rppg:InvalidUbfcReference'));
end
check_watch_reference();
check_contact_reference(settings);
check_klt_tracking(settings, fs);
fprintf('PASS: eight temporal/FFT candidates, recorded failures, split isolation, UBFC parser.\n');

tracking_file = [tempname, '.avi'];
tracking_cleanup = onCleanup(@() delete(tracking_file)); %#ok<NASGU>
writer = VideoWriter(tracking_file, 'Uncompressed AVI');
writer.FrameRate = fs;
open(writer);
frame(rects(1, 2)+1, rects(1, 1)+1, 1) = uint8(255);
for index = 1:12
    writeVideo(writer, circshift(frame, [0, 3*(index > 4), 0]));
end
close(writer);
settings.roi_boxes_px = rects;
settings.roi_tracker = 'ncc';
tracked = extract_rgb(tracking_file, settings);
assert(all(tracked.valid));
assert(tracked.roi_positions(1, 1, 1) == rects(1, 1));
assert(tracked.roi_positions(end, 1, 1) == rects(1, 1)+3);
settings.saturation_mode = 'hard';
masked = extract_rgb(tracking_file, settings);
assert(all(masked.pixel_counts(:, 1) == tracked.pixel_counts(:, 1)-1));
assert(all(masked.raw_rgb == tracked.raw_rgb, 'all'));
assert(all(masked.measurement_rgb(:, 1, 1) < tracked.measurement_rgb(:, 1, 1)));
fprintf('PASS: NCC translation and hard saturation masking without replacing raw pixels.\n');

method_names = {'B','B','B','B','B','C','C','C','C','C','D','D','D','D','D','POS'};
variants = {struct('spatial_filter', 'median'), struct('spatial_filter', 'mean'), ...
    struct('spatial_filter', 'gaussian'), struct('spatial_filter', 'bilateral'), ...
    struct('spatial_filter', 'wiener'), struct('color_variant', 'rgb_sum'), ...
    struct('color_variant', 'difference'), struct('color_variant', 'temporal'), ...
    struct('color_variant', 'log'), struct('color_variant', 'saturation'), ...
    struct('pos_fusion', 'weighted'), struct('pos_fusion', 'equal'), ...
    struct('pos_fusion', 'best'), struct('pos_fusion', 'consensus'), ...
    struct('pos_fusion', 'spectral'), struct()};
names = {'median','mean','gaussian','bilateral','wiener','rgb_sum','difference', ...
    'temporal','log','saturation','weighted','equal','best','consensus','spectral','pooled_pos'};
candidates = struct('name', names, 'method', method_names, 'overrides', variants);
report = run_benchmark(trial_for_methods(video_file, rects), 'development', candidates);
observable = report.predictions.candidate ~= "saturation";
assert(all(report.predictions.status(observable) == "ok"));
assert(all(abs(report.predictions.predicted_bpm(observable) - 75) < 1));
assert(report.predictions.failure_reason(~observable) == "flat_signal", ...
    'HSV saturation is constant while only the middle RGB channel varies.');
settings.roi_tracker = 'fixed';
settings.saturation_mode = 'raw';
rgb = extract_rgb(video_file, settings);
% With Green as the largest channel, saturation carries the test pulse.
rgb.measurement_rgb(:, 1, :) = 90;
settings.color_variant = 'saturation';
saturation_check = estimate_hr(apply_method(rgb, 'C', settings), settings);
assert(strcmp(saturation_check.status, 'ok') && abs(saturation_check.predicted_bpm-75) < 1);
rgb.roi_valid(:, 2:3) = false;
independent = estimate_hr(apply_method(rgb, 'D', settings), settings);
assert(strcmp(independent.status, 'ok') && isequal(independent.usable_regions, 1));
rgb.roi_valid(:, 1) = false;
invalid = estimate_hr(apply_method(rgb, 'D', settings), settings);
assert(strcmp(invalid.failure_reason, 'no_usable_pos_roi'));
fprintf('PASS: five spatial, five color, five POS fusion candidates and pooled POS.\n');
end

function signal = signal_data(time_s, values)
signal = struct('time_s', time_s, 'values', values, 'method', 'A');
end

function expect_failure(signal, settings, reason)
result = estimate_hr(signal, settings);
assert(strcmp(result.status, 'failed') && strcmp(result.failure_reason, reason), ...
    'Expected %s, got %s.', reason, result.failure_reason);
end

function trial = trial_for_methods(video_file, rects)
trial = table("Synthetic", "methods", "development", string(video_file), 0, 12, ...
    {rects}, 75, 'VariableNames', {'subject_id', 'video_id', 'split', ...
    'video_file', 'start_s', 'end_s', 'roi_boxes', 'gt_bpm'});
end

function check_watch_reference()
keys = {'video_id', 'start_s', 'end_s'};
windows = table(["A"; "A"; "A"; "A"; "B"; "C"; "D"], [0;10;20;30;0;0;0], ...
    [10;20;30;40;10;10;10], 'VariableNames', keys);
captures = table(["A"; "B"; "D"], ["2026-11-27T00:00:00Z"; "2026-11-27T00:00:00"; ...
    "2026-11-27T00:00:00Z"], ["camera_test"; "local"; "camera_test"], [0.5;0.5;0.5], ...
    'VariableNames', {'video_id','video_start_utc','video_start_source','alignment_uncertainty_s'});
start = ["00"; "05"; "05"; "08"; "09"; "10"; "15"; "15"; "17.5"; "20"];
stop = start;
stop(4:5) = ["10"; "11"];
watch = table(repmat("A", 10, 1), "2026-11-27T00:00:"+start+"Z", ...
    "2026-11-27T00:00:"+stop+"Z", [60;70;70;80;90;75;85;86;85;90], ...
    'VariableNames', {'video_id','measurement_start_utc','measurement_end_utc','bpm'});
reference = align_watch_reference(windows, captures, watch);
assert(isequaln(reference.gt_bpm, [70;80;90;NaN;NaN;NaN;NaN]));
assert(isequal(reference.n_watch_samples, [3;2;1;0;0;0;0]));
assert(reference.n_conflicting_times(2) == 1 && abs(reference.max_watch_gap_s(2) - 7.5) < 1e-9);
assert(all(reference.reference_status([4,7]) == "no_valid_watch_samples"));
assert(all(reference.reference_status(5:6) == "capture_timing_unverified"));

captures.alignment_uncertainty_s(1) = NaN;
draft = align_watch_reference(windows, captures, watch, AllowNominalTiming=true);
assert(all(isnan(draft.gt_bpm(1:3))) && isequal(draft.nominal_gt_bpm(1:3), [70;80;90]));
assert(all(draft.reference_status(1:3) == "nominal_timing_only"));
strict = align_watch_reference(windows, captures, watch);
assert(all(strict.reference_status(1:3) == "capture_timing_unverified"));

prediction = windows(1:4,:);
prediction.method = repmat("A", 4, 1);
prediction.predicted_bpm = [72;85;90;NaN];
prediction.status = ["ok"; "ok"; "ok"; "failed"];
prediction.failure_reason = [""; ""; ""; "signal_missing"];
report = evaluate_results(prediction, reference, config());
assert(report.metrics.n_paired == 3 && abs(report.metrics.error_sd_bpm - std([2,5,0])) < 1e-12);
rules = struct('lag_s',10,'deadband_bpm',2,'min_watch_samples',2, ...
    'max_watch_gap_s',10,'max_alignment_uncertainty_s',1);
trends = evaluate_watch_trends(report.predictions, reference, rules);
assert(trends.metrics.n_pairs == 3 && trends.metrics.n_reference == 1 && trends.metrics.n_paired == 1);
assert(trends.metrics.delta_mae_bpm == 3 && trends.metrics.direction_agreement_pct == 100);
fprintf('PASS: Apple Watch UTC, exact windows, duplicates, missing references, Error SD and trend coverage.\n');
end

function check_contact_reference(settings)
% The oximeter's displayed rate must have no influence on the reference.
t = (0:1/30:30)';
t = t + 0.004*sin(2*pi*0.17*t);
t(t >= 12 & t < 12.15) = [];
reference = table(t, sin(2*pi*1.25*t), 115*ones(size(t)), ...
    'VariableNames', {'time_s','ppg','bpm'});
estimate = estimate_ubfc_reference(reference, [0,30], settings);
assert(estimate.status == "ok" && abs(estimate.bpm - 75) < 1);
assert(estimate.max_gap_s > 0.1 && sum(t < 30) == estimate.n_samples);
shorter = reference(reference.time_s < 14 | reference.time_s > 15, :);
estimate = estimate_ubfc_reference(shorter, [0,30], settings);
assert(estimate.status == "reference_gap_too_long" && isnan(estimate.bpm));
reference.ppg(:) = 0.5;
estimate = estimate_ubfc_reference(reference, [0,30], settings);
assert(estimate.status == "flat_reference" && isnan(estimate.bpm));
fprintf('PASS: irregular contact PPG, explicit gaps and independence from sensor HR.\n');
end

function check_klt_tracking(settings, fs)
video_file = [tempname, '.avi'];
cleanup = onCleanup(@() delete(video_file));
stream = RandStream('mt19937ar', 'Seed', 7);
frame = repmat(uint8(randi(stream, [45,210], 96, 120)), 1, 1, 3);
writer = VideoWriter(video_file, 'Uncompressed AVI');
writer.FrameRate = fs;
open(writer);
for index = 1:14
    if index <= 8
        writeVideo(writer, circshift(frame, [0, 3*(index > 4), 0]));
    elseif index <= 11
        writeVideo(writer, zeros(size(frame), 'like', frame));
    else
        writeVideo(writer, circshift(frame, [0, 5, 0]));
    end
end
close(writer);
settings.roi_tracker = 'klt';
settings.roi_boxes_px = [42,20,22,12; 26,50,14,14; 74,50,14,14];
tracked = extract_rgb(video_file, settings);
assert(all(tracked.roi_valid(1:8,:), 'all'));
assert(all(tracked.roi_positions(8,1,:) - tracked.roi_positions(1,1,:) == 3, 'all'));
assert(all(~tracked.roi_valid(9:end,:), 'all') && all(isnan(tracked.raw_rgb(9:end,:,:)), 'all'));
settings.roi_tracker = 'klt_ncc_reacquire';
recovery = extract_rgb(video_file, settings);
assert(isequaln(recovery.raw_rgb(1:11,:,:), tracked.raw_rgb(1:11,:,:)));
assert(all(recovery.roi_valid(12:end,:), 'all') && nnz(recovery.reacquired) == 1 && recovery.reacquired(12));
assert(all(recovery.roi_positions(12:end,1,:) - tracked.roi_positions(1,1,:) == 5, 'all'));
fprintf('PASS: KLT translation, loss and frame-local NCC reacquisition on decoded video.\n');
end
