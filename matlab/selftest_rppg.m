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
end

function signal = signal_data(time_s, values)
signal = struct('time_s', time_s, 'values', values, 'method', 'A');
end

function expect_failure(signal, settings, reason)
result = estimate_hr(signal, settings);
assert(strcmp(result.status, 'failed') && strcmp(result.failure_reason, reason), ...
    'Expected %s, got %s.', reason, result.failure_reason);
end
