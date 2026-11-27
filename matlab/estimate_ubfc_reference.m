function result = estimate_ubfc_reference(reference, interval_s, settings)
%ESTIMATE_UBFC_REFERENCE Estimate contact pulse rate on the observed UBFC times.
% The sensor's displayed HR is intentionally independent of this calculation.

validateattributes(interval_s, {'numeric'}, {'vector','numel',2,'real','finite'});
if interval_s(1) < 0 || interval_s(2) <= interval_s(1)
    error('rppg:InvalidReferenceInterval', 'Expected a positive-duration video interval.');
end

result = struct('bpm', NaN, 'status', "insufficient_reference", 'n_samples', 0, ...
    'span_s', NaN, 'max_gap_s', NaN, 'band_fraction', NaN, ...
    'peak_fraction', NaN);
time_s = reference.time_s;
ppg = reference.ppg;
if any(~isfinite(time_s)) || any(diff(time_s) <= 0)
    result.status = "invalid_reference_times";
    return
end

inside = time_s >= interval_s(1) & time_s < interval_s(2) & isfinite(ppg);
t = time_s(inside) - interval_s(1);
x = ppg(inside);
result.n_samples = numel(x);
if numel(t) < 2
    return
end
result.span_s = t(end) - t(1);
result.max_gap_s = max(diff([0; t; diff(interval_s)]));
band = settings.heart_band_hz;
if result.span_s < settings.min_duration_s
    return
end
% Windows with an unresolved hole longer than the shortest target period
% are not used in this comparison. No samples are created in shorter gaps.
if result.max_gap_s > 1 / band(2)
    result.status = "reference_gap_too_long";
    return
end
if (numel(t) - 1) / result.span_s <= 2 * band(2)
    result.status = "reference_sample_rate_too_low";
    return
end
design = [ones(size(t)), t - mean(t)];
centered = x - design * (design \ x);
if max(abs(centered)) <= 1e-12 * max(1, max(abs(x)))
    result.status = "flat_reference";
    return
end
[power, frequency_hz] = plomb(centered, t);
indices = find(frequency_hz >= band(1) & frequency_hz <= band(2));
band_power = sum(power(indices));
result.band_fraction = band_power / sum(power);
if isempty(indices) || band_power <= 0 || ~isfinite(result.band_fraction) ...
        || result.band_fraction < settings.min_band_fraction
    result.status = "no_reference_band_energy";
    return
end
[~, peak] = max(power(indices));
peak_hz = frequency_hz(indices(peak));
result.bpm = peak_hz * 60;
near_peak = abs(frequency_hz(indices) - peak_hz) <= settings.peak_half_width_hz;
result.peak_fraction = sum(power(indices(near_peak))) / band_power;
result.status = "ok";
end
