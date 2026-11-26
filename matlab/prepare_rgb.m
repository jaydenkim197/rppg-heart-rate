function [prepared, failure_reason] = prepare_rgb(rgb_data, settings)
%PREPARE_RGB A~D가 동일 구간과 동일 피부 영역을 이용하도록 입력을 맞춘다.

prepared = struct();
failure_reason = '';
time_s = rgb_data.time_s(:);
valid = rgb_data.valid(:);
if ~any(valid)
    failure_reason = 'no_valid_roi';
    return
end
if any(~isfinite(time_s)) || numel(time_s) < 2 || any(diff(time_s) <= 0)
    failure_reason = 'invalid_frame_times';
    return
end
interval = rgb_data.interval_s;
fs = 1 / median(diff(time_s));
if fs <= 2 * settings.heart_band_hz(2)
    failure_reason = 'sample_rate_too_low';
    return
end
if diff(interval) < settings.min_duration_s
    failure_reason = 'analysis_window_too_short';
    return
end
if mean(valid) < settings.min_tracking_fraction || nnz(valid) < 2
    failure_reason = 'too_few_valid_frames';
    return
end

valid_times = time_s(valid);
if any(diff(valid_times) > settings.max_frame_gap_s)
    failure_reason = 'long_tracking_gap';
    return
end
if valid_times(1) - interval(1) > settings.max_edge_gap_s || ...
        interval(2) - valid_times(end) > settings.max_edge_gap_s
    failure_reason = 'untracked_window_edge';
    return
end

% 부위 평균을 조직할 때 피부 픽셀 수를 가중치로 사용한다.
region_rgb = rgb_data.raw_rgb(valid, :, :);
counts = double(rgb_data.pixel_counts(valid, :));
if any(counts(:) <= 0) || any(~isfinite(region_rgb(:)))
    failure_reason = 'invalid_rgb_samples';
    return
end
total_pixels = sum(counts, 2);
mean_rgb = sum(region_rgb .* reshape(counts, [], 1, 3), 3) ./ total_pixels;
median_green = sum(rgb_data.median_green(valid, :) .* counts, 2) ./ total_pixels;

% 짧은 누락은 선형 보간한다. 양 끝은 가까운 유효 표본으로 채운다.
num_samples = ceil(diff(interval) * fs);
sample_times = interval(1) + (0:num_samples-1)' / fs;
sample_times = sample_times(sample_times < interval(2));
query_times = min(max(sample_times, valid_times(1)), valid_times(end));
flat_rgb = reshape(region_rgb, [], 9);
values = interp1(valid_times, [flat_rgb, mean_rgb, median_green], query_times, 'linear');
prepared.time_s = sample_times;
prepared.fs = fs;
prepared.rgb = reshape(values(:, 1:9), [], 3, 3);
prepared.mean_rgb = values(:, 10:12);
prepared.median_green = values(:, 13);
prepared.source_time_s = time_s;
prepared.source_mean_rgb = NaN(numel(time_s), 3);
prepared.source_mean_rgb(valid, :) = mean_rgb;
end
