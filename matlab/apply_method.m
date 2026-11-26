function method_signal = apply_method(rgb_data, method, settings)
%APPLY_METHOD Build one method's signal without applying other enhancements.

method = char(method);
time_s = rgb_data.time_s(:);
rgb = rgb_data.raw_rgb;
if isfield(rgb_data, 'measurement_rgb')
    rgb = rgb_data.measurement_rgb;
end
if strcmp(method, 'B')
    % An unfiltered input is allowed as a spatial-filter research comparison.
    if isfield(rgb_data, 'filtered_rgb') && ~isempty(rgb_data.filtered_rgb)
        rgb = rgb_data.filtered_rgb;
    elseif ~isempty(rgb_data.median_rgb)
        rgb = rgb_data.median_rgb;
    end
end
[combined, rgb] = combine_regions(rgb, rgb_data);
labels = {method};
switch method
    case {'A', 'B'}
        values = combined(:, 2);
    case 'C'
        values = apply_color(combined, time_s, settings);
    case 'D'
        labels = settings.roi_names;
        [time_s, samples, fs] = pos_inputs(time_s, rgb, settings);
        values = NaN(numel(time_s), size(samples, 3));
        for region = 1:size(samples, 3)
            values(:, region) = pos_signal(samples(:, :, region), fs, settings.pos_window_s);
        end
    case 'POS'
        [time_s, samples, fs] = pos_inputs(time_s, combined, settings);
        values = pos_signal(samples, fs, settings.pos_window_s);
    otherwise
        error('rppg:UnknownMethod', 'Unsupported method: %s', method);
end
method_signal = struct('time_s', time_s, 'values', values, ...
    'labels', {labels}, 'method', method);
end

function [pooled, regions] = combine_regions(rgb, data)
counts = double(data.pixel_counts);
observed = reshape(all(isfinite(rgb), 2), size(counts)) & isfinite(counts) & counts > 0;
if isfield(data, 'roi_valid')
    observed = observed & data.roi_valid;
end
observed = observed & data.valid(:);
counts(~observed) = 0;
regions = rgb;
pooled = zeros(size(rgb, 1), 3);
for index = 1:size(rgb, 3)
    plane = rgb(:, :, index);
    plane(~observed(:, index), :) = 0;
    pooled = pooled + plane .* counts(:, index);
    plane(~observed(:, index), :) = NaN;
    regions(:, :, index) = plane;
end
total = sum(counts, 2);
total(total <= 0) = NaN;
pooled = pooled ./ total;
end

function values = apply_color(rgb, time_s, settings)
red = rgb(:, 1);
green = rgb(:, 2);
blue = rgb(:, 3);
switch char(settings.color_variant)
    case 'rgb_sum'
        denominator = red + green + blue;
    case 'difference'
        denominator = green + red;
        green = green - red;
    case 'temporal'
        n = max(1, round(settings.color_window_s / median(diff(time_s))));
        denominator = movmean(green, [n-1, 0]);
    case 'log'
        rgb(rgb <= 0) = NaN;
        values = log(rgb(:, 2)) - 0.5*(log(rgb(:, 1)) + log(rgb(:, 3)));
        return
    case 'saturation'
        denominator = max(rgb, [], 2);
        green = denominator - min(rgb, [], 2);
    otherwise
        error('rppg:UnknownColorMethod', 'Unsupported color-normalization method.');
end
denominator(denominator <= 0) = NaN;
values = green ./ denominator;
if strcmp(settings.color_variant, 'temporal')
    values = values - 1;
end
end

function [time_s, values, fs] = pos_inputs(time_s, values, settings)
steps = diff(time_s);
fs = NaN;
if isempty(steps) || any(~isfinite(steps)) || any(steps <= 0)
    return
end
step = median(steps);
if max(steps) > settings.max_step_ratio * step
    return
end
fs = 1 / step;
if max(abs(steps - step)) <= 100 * eps(max(1, max(abs(time_s))))
    return
end
uniform_time = time_s(1) + (0:floor((time_s(end)-time_s(1))/step))' * step;
uniform_time = uniform_time(uniform_time <= time_s(end));
interpolated = interp1(time_s, reshape(values, numel(time_s), []), uniform_time, 'linear');
values = reshape(interpolated, numel(uniform_time), 3, []);
time_s = uniform_time;
end

function pulse = pos_signal(rgb, fs, seconds)
% Wang et al. POS through the time-normalization, projection and OLA steps.
count = size(rgb, 1);
pulse = NaN(count, 1);
if ~isfinite(fs)
    return
end
length_samples = max(3, round(seconds*fs));
overlap = zeros(count, 1);
covered = false(count, 1);
for first = 1:count-length_samples+1
    rows = first:first+length_samples-1;
    segment = rgb(rows, :);
    color = mean(segment, 1);
    if any(~isfinite(color)) || any(color <= 0)
        continue
    end
    normalized = segment ./ color;
    first_axis = normalized(:, 2) - normalized(:, 3);
    second_axis = normalized(:, 2) + normalized(:, 3) - 2*normalized(:, 1);
    scale = std(second_axis);
    if scale <= eps
        continue
    end
    h = first_axis + std(first_axis)/scale*second_axis;
    overlap(rows) = overlap(rows) + h - mean(h);
    covered(rows) = true;
end
pulse(covered) = overlap(covered);
end
