function result = validate_ubfc_reference(reference, interval_s)
%VALIDATE_UBFC_REFERENCE Qualify a UBFC contact PPG window independently of rPPG.
% Acceptance thresholds are fixed across algorithms and data partitions.

settings = struct('heart_band_hz', [0.7, 3.0], 'min_duration_s', 5, ...
    'min_band_fraction', 0.001, 'peak_half_width_hz', 0.10);
spectrum = estimate_ubfc_reference(reference, interval_s, settings);
result = struct('gt_bpm', NaN, 'reference_status', spectrum.status, ...
    'spectral_bpm', spectrum.bpm, 'beat_bpm', NaN, 'device_bpm', NaN, ...
    'agreement_bpm', NaN, 'n_samples', spectrum.n_samples, 'span_s', spectrum.span_s, ...
    'max_gap_s', spectrum.max_gap_s, 'band_fraction', spectrum.band_fraction, ...
    'peak_fraction', spectrum.peak_fraction, 'n_valid_intervals', 0, ...
    'n_rejected_intervals', 0, 'valid_interval_coverage', 0, 'interval_mad_s', NaN);

inside = reference.time_s >= interval_s(1) & reference.time_s < interval_s(2);
device_values = reference.bpm(inside);
result.device_bpm = mean(device_values(isfinite(device_values) & device_values > 0));
if spectrum.status ~= "ok"
    return
end

usable = inside & isfinite(reference.ppg);
time_s = reference.time_s(usable) - interval_s(1);
waveform = reference.ppg(usable);
centered = waveform - movmedian(waveform, 2, 'SamplePoints', time_s);
amplitude_limits = quantile(centered, [0.10, 0.90]);
amplitude = diff(amplitude_limits);
interval_limits = 1 ./ fliplr(settings.heart_band_hz);
if amplitude > 0
    [~, beats] = findpeaks(centered, time_s, ...
        'MinPeakDistance', interval_limits(1), 'MinPeakProminence', 0.30*amplitude);
    intervals = diff(beats);
    accepted = intervals >= interval_limits(1) & intervals <= interval_limits(2);
    valid = intervals(accepted);
    result.n_valid_intervals = numel(valid);
    result.n_rejected_intervals = nnz(~accepted);
    result.valid_interval_coverage = sum(valid) / diff(interval_s);
    if ~isempty(valid)
        center = median(valid);
        result.beat_bpm = 60 / center;
        result.interval_mad_s = median(abs(valid - center));
        result.agreement_bpm = abs(spectrum.bpm - result.beat_bpm);
    end
end

if spectrum.peak_fraction < 0.25
    result.reference_status = "weak_reference_peak";
elseif result.n_valid_intervals < 4 || result.valid_interval_coverage < 0.70
    result.reference_status = "insufficient_beat_coverage";
elseif result.agreement_bpm > 5
    result.reference_status = "reference_estimators_disagree";
else
    result.gt_bpm = spectrum.bpm;
end
end
