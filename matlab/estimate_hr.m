function result = estimate_hr(method_signal, settings)
%ESTIMATE_HR 공통 필터와 FFT로 BPM을 추정하고 D의 부위별 결과를 결합한다.

band = settings.heart_band_hz;
fs = method_signal.fs;
% 3차 Butterworth 설계를 대역통과로 변환한 뒤 양방향으로 필터링한다.
[b, a] = butter(3, band / (fs / 2), 'bandpass');
for channel = 1:size(method_signal.values, 2)
    estimate = estimate_channel(method_signal.values(:, channel), fs, b, a, settings);
    if channel == 1
        regions = estimate;
    else
        regions(channel) = estimate; %#ok<AGROW>
    end
end

result = struct('method', method_signal.method, 'predicted_bpm', NaN, ...
    'status', 'failed', 'failure_reason', regions(1).failure_reason, ...
    'quality', NaN, 'num_valid_regions', 0, 'display_name', method_signal.labels{1}, ...
    'time_s', method_signal.time_s, 'frequency_hz', regions(1).frequency_hz, ...
    'power', regions(1).power, 'filtered', regions(1).filtered, ...
    'region_bpm', [regions.bpm], 'region_quality', [regions.quality]);

usable = find(isfinite(result.region_bpm));
if isempty(usable)
    if strcmp(method_signal.method, 'D')
        result.failure_reason = 'no_usable_pos_region';
    end
    return
end

weights = result.region_quality(usable);
result.predicted_bpm = sum(result.region_bpm(usable) .* weights) / sum(weights);
result.quality = sum(weights .^ 2) / sum(weights);
result.status = 'ok';
result.failure_reason = '';
if strcmp(method_signal.method, 'D')
    result.num_valid_regions = numel(usable);
end
[~, relative_index] = max(weights);
best = usable(relative_index);
result.display_name = method_signal.labels{best};
result.frequency_hz = regions(best).frequency_hz;
result.power = regions(best).power;
result.filtered = regions(best).filtered;
end

function channel = estimate_channel(signal, fs, b, a, settings)
channel = struct('bpm', NaN, 'quality', NaN, 'failure_reason', '', ...
    'frequency_hz', [], 'power', [], 'filtered', []);
signal = signal(:);
if any(~isfinite(signal))
    channel.failure_reason = 'nonfinite_signal';
    return
end
count = numel(signal);
if count <= 3 * (max(numel(b), numel(a)) - 1)
    channel.failure_reason = 'analysis_window_too_short';
    return
end

centered = signal - mean(signal);
if max(abs(centered)) <= 1e-12 * max(1, max(abs(signal)))
    channel.failure_reason = 'flat_signal';
    return
end
filtered = filtfilt(b, a, centered);
hann_window = 0.5 - 0.5 * cos(2 * pi * (0:count-1)' / (count - 1));
nfft = 2 ^ nextpow2(4 * count);
spectrum = fft(filtered .* hann_window, nfft);
indices = (1:floor(nfft/2)+1)';
frequency_hz = (indices - 1) * fs / nfft;
power = abs(spectrum(indices)).^2;
channel.frequency_hz = frequency_hz;
channel.power = power;
channel.filtered = filtered;

band = settings.heart_band_hz;
band_indices = find(frequency_hz >= band(1) & frequency_hz <= band(2));
band_energy = sum(power(band_indices));
if isempty(band_indices) || ~isfinite(band_energy) || band_energy <= 0
    channel.failure_reason = 'no_pulse_band_energy';
    return
end

[~, peak_index] = max(power(band_indices));
peak_hz = frequency_hz(band_indices(peak_index));
near_peak = abs(frequency_hz(band_indices) - peak_hz) <= settings.peak_half_width_hz;
channel.quality = sum(power(band_indices(near_peak))) / band_energy;
if channel.quality < settings.min_peak_ratio
    channel.failure_reason = 'weak_spectral_peak';
    return
end
channel.bpm = 60 * peak_hz;
end
