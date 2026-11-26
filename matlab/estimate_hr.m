function result = estimate_hr(method_signal, settings)
%ESTIMATE_HR Analyze one observed time window with a symmetric FFT bandpass.
% The Butterworth-shaped frequency response follows the team prototype.
% It is an offline response applied to the provided window.

time_s = method_signal.time_s(:);
signal = method_signal.values;
result = struct('method', method_signal.method, 'predicted_bpm', NaN, ...
    'status', 'failed', 'failure_reason', '', 'quality', NaN, 'fs', NaN, ...
    'time_s', time_s, 'filtered', [], 'frequency_hz', [], 'power', [], ...
    'peak_hz', NaN, 'resampled', false);
if numel(time_s) < 2 || any(~isfinite(time_s)) || any(diff(time_s) <= 0)
    result.failure_reason = 'invalid_frame_times';
    return
end
if ~isequal(size(signal), size(time_s)) || any(~isfinite(signal))
    result.failure_reason = 'nonfinite_or_missing_signal';
    return
end

steps = diff(time_s);
step = median(steps);
fs = 1 / step;
result.fs = fs;
band = settings.heart_band_hz;
if fs <= 2 * band(2)
    result.failure_reason = 'sample_rate_too_low';
    return
end
if max(steps) > settings.max_step_ratio * step
    result.failure_reason = 'frame_gap_requires_segment_analysis';
    return
end
if max(abs(steps - step)) > 100 * eps(max(1, max(abs(time_s))))
    uniform_time = time_s(1) + (0:floor((time_s(end) - time_s(1)) / step))' * step;
    uniform_time = uniform_time(uniform_time <= time_s(end));
    signal = interp1(time_s, signal, uniform_time, 'linear');
    result.time_s = uniform_time;
    result.resampled = true;
end
sample_count = numel(signal);
if sample_count * step < settings.min_duration_s
    result.failure_reason = 'analysis_window_too_short';
    return
end

centered = signal - mean(signal);
if max(abs(centered)) <= 1e-12 * max(1, max(abs(signal)))
    result.failure_reason = 'flat_signal';
    return
end

% Reflect within the window before applying the real, two-sided response.
pad = min(sample_count - 1, round(settings.bandpass_reflection_s * fs));
extended = [flipud(centered(2:pad+1)); centered; flipud(centered(end-pad:end-1))];
extended_count = numel(extended);
bins = (0:extended_count-1)';
absolute_hz = min(bins, extended_count - bins) * fs / extended_count;
twice_order = 2 * settings.bandpass_order;
highpass = 1 ./ (1 + (band(1) ./ absolute_hz).^twice_order);
lowpass = 1 ./ (1 + (absolute_hz ./ band(2)).^twice_order);
filtered = real(ifft(fft(extended) .* highpass .* lowpass));
result.filtered = filtered(pad+1:pad+sample_count);

window = 0.5 - 0.5 * cos(2*pi*(0:sample_count-1)' / (sample_count - 1));
one_sided = (1:floor(sample_count/2)+1)';
frequency_hz = (one_sided - 1) * fs / sample_count;
inside = find(frequency_hz >= band(1) & frequency_hz <= band(2));
spectrum = fft(centered .* window);
raw_power = abs(spectrum(one_sided)).^2;
filtered_spectrum = fft((result.filtered - mean(result.filtered)) .* window);
power = abs(filtered_spectrum(one_sided)).^2;
result.frequency_hz = frequency_hz;
result.power = power;

band_energy = sum(power(inside));
if isempty(inside) || band_energy <= 0 ...
        || sum(raw_power(inside)) < settings.min_band_fraction * sum(raw_power)
    result.failure_reason = 'no_pulse_band_energy';
    return
end
[~, relative_index] = max(power(inside));
peak_hz = frequency_hz(inside(relative_index));
near_peak = abs(frequency_hz(inside) - peak_hz) <= settings.peak_half_width_hz;
result.peak_hz = peak_hz;
result.quality = sum(power(inside(near_peak))) / band_energy;
result.predicted_bpm = 60 * peak_hz;
result.status = 'ok';
end
