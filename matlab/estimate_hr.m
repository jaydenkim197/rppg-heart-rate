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

result.filtered = apply_bandpass(centered, fs, settings);
angle = 2*pi*(0:sample_count-1)' / (sample_count - 1);
switch char(settings.fft_window)
    case 'rectangular'
        window = ones(sample_count, 1);
    case 'hann'
        window = 0.5 - 0.5*cos(angle);
    case 'hamming'
        window = 0.54 - 0.46*cos(angle);
    otherwise
        error('rppg:UnknownFftWindow', 'Unsupported FFT window.');
end
validateattributes(settings.fft_padding_factor, {'numeric'}, ...
    {'scalar', 'integer', 'positive', 'finite'});
nfft = sample_count * settings.fft_padding_factor;
one_sided = (1:floor(nfft/2)+1)';
frequency_hz = (one_sided - 1) * fs / nfft;
inside = find(frequency_hz >= band(1) & frequency_hz <= band(2));
spectrum = fft(centered .* window, nfft);
raw_power = abs(spectrum(one_sided)).^2;
filtered_spectrum = fft((result.filtered - mean(result.filtered)) .* window, nfft);
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
peak = inside(relative_index);
peak_hz = frequency_hz(peak);
if strcmp(settings.peak_method, 'parabolic') && peak > inside(1) && peak < inside(end)
    levels = log(max(power(peak-1:peak+1), realmin));
    curvature = levels(1) - 2*levels(2) + levels(3);
    if curvature < -eps
        offset = max(-0.5, min(0.5, 0.5*(levels(1)-levels(3))/curvature));
        peak_hz = peak_hz + offset * fs / nfft;
    end
elseif ~ismember(string(settings.peak_method), ["max", "parabolic"])
    error('rppg:UnknownPeakMethod', 'Unsupported peak estimation method.');
end
near_peak = abs(frequency_hz(inside) - peak_hz) <= settings.peak_half_width_hz;
result.peak_hz = peak_hz;
result.quality = sum(power(inside(near_peak))) / band_energy;
result.predicted_bpm = 60 * peak_hz;
result.status = 'ok';
end

function filtered = apply_bandpass(centered, fs, settings)
% Reflect the observed window to reduce circular boundary discontinuities.
if strcmp(settings.bandpass_variant, 'none')
    filtered = centered;
    return
end
band = settings.heart_band_hz;
count = numel(centered);
pad = min(count - 1, round(settings.bandpass_reflection_s * fs));
extended = [flipud(centered(2:pad+1)); centered; flipud(centered(end-pad:end-1))];
extended_count = numel(extended);
bins = (0:extended_count-1)';
absolute_hz = min(bins, extended_count - bins) * fs / extended_count;
switch char(settings.bandpass_variant)
    case 'butterworth'
        validateattributes(settings.bandpass_order, {'numeric'}, {'scalar', 'positive', 'finite'});
        twice_order = 2 * settings.bandpass_order;
        highpass = 1 ./ (1 + (band(1) ./ absolute_hz).^twice_order);
        lowpass = 1 ./ (1 + (absolute_hz ./ band(2)).^twice_order);
        response = highpass .* lowpass;
    case 'ideal'
        response = absolute_hz >= band(1) & absolute_hz <= band(2);
    case 'gaussian'
        highpass = 1 - exp(-log(2) * (absolute_hz ./ band(1)).^2);
        lowpass = exp(-log(2) * (absolute_hz ./ band(2)).^2);
        response = highpass .* lowpass;
    otherwise
        error('rppg:UnknownBandpass', 'Unsupported time filter.');
end
restored = real(ifft(fft(extended) .* response));
filtered = restored(pad+1:pad+count);
end
