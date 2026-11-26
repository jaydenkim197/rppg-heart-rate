function method_signal = apply_method(rgb_data, method, settings)
%APPLY_METHOD Build the pixel-count-weighted Green signal for Method A.

method = char(method);
if ~strcmp(method, 'A')
    error('rppg:NotImplemented', 'Method %s is not implemented in the baseline.', method);
end
sample_count = numel(rgb_data.time_s);
rgb = rgb_data.raw_rgb;
if isfield(rgb_data, 'measurement_rgb')
    rgb = rgb_data.measurement_rgb;
end
green = reshape(rgb(:, 2, :), sample_count, numel(settings.roi_names));
counts = double(rgb_data.pixel_counts);
usable = isfinite(green) & isfinite(counts) & counts > 0;
if isfield(rgb_data, 'roi_valid')
    usable = usable & rgb_data.roi_valid;
end
green(~usable) = 0;
counts(~usable) = 0;
total = sum(counts, 2);
values = NaN(sample_count, 1);
valid = rgb_data.valid(:) & total > 0;
values(valid) = sum(green(valid, :) .* counts(valid, :), 2) ./ total(valid);
method_signal = struct('time_s', rgb_data.time_s(:), 'values', values, ...
    'labels', {{'Green'}}, 'method', method);
end
