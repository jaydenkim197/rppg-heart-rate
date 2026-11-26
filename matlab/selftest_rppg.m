function selftest_rppg()
%SELFTEST_RPPG 합성 RGB에서 계산값과 결측 처리 규칙을 점검한다.

settings = config();
fps = 30;
expected_bpm = 72;
time_s = (0:fps*30-1)' / fps;
pulse = sin(2*pi*(expected_bpm/60)*time_s);
light = 1 + 0.025 * sin(2*pi*0.2*time_s);

% 프레임 시각에 작은 오차를 줘 보간 경로도 실행한다.
rgb_data.time_s = time_s + 0.0004 * sin(2*pi*0.79*time_s);
rgb_data.interval_s = [0, 30];
rgb_data.valid = true(numel(time_s), 1);
rgb_data.valid(180:182) = false;
rgb_data.pixel_counts = repmat([120, 80, 90], numel(time_s), 1);
rgb_data.raw_rgb = zeros(numel(time_s), 3, 3);
for region = 1:3
    color = [179, 126, 103] + [2, 1, 2] * (region - 1);
    rgb_data.raw_rgb(:, :, region) = (1 + pulse * [0.001, 0.006, 0.002]) .* color .* light;
end
rgb_data.median_green = reshape(rgb_data.raw_rgb(:, 2, :), [], 3);

[prepared, reason] = prepare_rgb(rgb_data, settings);
assert(isempty(reason), 'Expected short tracking gap to pass: %s', reason);
assert(isnan(prepared.source_mean_rgb(180, 2)), 'The raw graph must preserve the tracking gap.');
for index = 1:numel(settings.methods)
    method = settings.methods{index};
    signal = apply_method(prepared, method, settings);
    result = estimate_hr(signal, settings);
    assert(strcmp(result.status, 'ok'), 'Method %s rejected the synthetic pulse.', method);
    assert(abs(result.predicted_bpm - expected_bpm) < 1, ...
        'Method %s returned %.2f BPM, expected %d BPM.', method, result.predicted_bpm, expected_bpm);
    fprintf('%s: %.2f BPM (expected %d BPM)\n', method, result.predicted_bpm, expected_bpm);
end

rgb_data.valid(200:230) = false;
[~, reason] = prepare_rgb(rgb_data, settings);
assert(strcmp(reason, 'long_tracking_gap'), 'Expected the long tracking gap to fail.');

% D의 영역 중 하나가 평탄하면 그 부위를 버리고 남은 부위의 결과를 결합한다.
signal = apply_method(prepared, 'D', settings);
signal.values(:, 3) = 0;
result = estimate_hr(signal, settings);
assert(result.num_valid_regions == 2 && isfinite(result.predicted_bpm));
assert(isnan(result.region_bpm(3)));

signal = apply_method(prepared, 'A', settings);
signal.values(:) = 100;
result = estimate_hr(signal, settings);
assert(strcmp(result.status, 'failed') && strcmp(result.failure_reason, 'flat_signal'));

fprintf('Synthetic checks passed (short gap, long gap, flat signal, POS contribution).\n');
end
