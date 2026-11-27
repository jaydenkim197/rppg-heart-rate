function rgb_data = extract_rgb(video_file, settings)
%EXTRACT_RGB Read RGB means and timestamps for three skin rectangles.
% Coordinates are one-based integer [x, y, width, height] in video pixels.

video = VideoReader(video_file);
interval = settings.analysis_interval_s;
if isempty(interval)
    interval = [0, min(video.Duration, settings.recommended_duration_s)];
end
validateattributes(interval, {'numeric'}, {'real', 'finite', 'vector', 'numel', 2});
if interval(1) < 0 || interval(2) <= interval(1) || interval(2) > video.Duration + 1e-6
    error('rppg:InvalidInterval', 'Analysis interval must be inside the video.');
end
video.CurrentTime = interval(1);
if ~hasFrame(video) || video.CurrentTime >= interval(2)
    error('rppg:NoVideoFrames', 'No frames in the analysis interval.');
end
stamp = video.CurrentTime;
frame = readFrame(video);
if size(frame, 3) ~= 3
    error('rppg:InvalidVideo', 'An RGB video is required.');
end

rects = settings.roi_boxes_px;
if isempty(rects)
    fig = figure('Name', 'Select forehead, left cheek, right cheek');
    close_on_exit = onCleanup(@() close(fig)); %#ok<NASGU>
    image(frame);
    axis image;
    rects = zeros(3, 4);
    for region = 1:3
        title(strrep(settings.roi_names{region}, '_', ' '));
        drawn = drawrectangle();
        if isempty(drawn) || ~isvalid(drawn) || isempty(drawn.Position)
            error('rppg:ROISelectionCancelled', 'ROI selection was cancelled.');
        end
        rects(region, :) = round(drawn.Position);
    end
end
validateattributes(rects, {'numeric'}, {'real', 'integer', 'finite', 'positive', 'size', [3, 4]});
right = rects(:, 1) + rects(:, 3) - 1;
bottom = rects(:, 2) + rects(:, 4) - 1;
if any(right > size(frame, 2) | bottom > size(frame, 1))
    error('rppg:ROIOutsideVideo', 'Each fixed ROI must be inside the video frame.');
end
for left = 1:2
    for other = left+1:3
        overlaps = min(right(left), right(other)) >= max(rects(left, 1), rects(other, 1)) ...
            && min(bottom(left), bottom(other)) >= max(rects(left, 2), rects(other, 2));
        if overlaps
            error('rppg:OverlappingROI', 'Fixed skin ROIs must not overlap.');
        end
    end
end

capacity = max(1, ceil(diff(interval) * video.FrameRate));
time_s = zeros(capacity, 1);
raw_rgb = NaN(capacity, 3, 3);
measurement_rgb = raw_rgb;
use_filtered = ~strcmp(settings.spatial_filter, 'none');
filtered_rgb = [];
if use_filtered
    filtered_rgb = raw_rgb;
end
pixel_counts = zeros(capacity, 3);
roi_positions = NaN(capacity, 4, 3);
roi_valid = false(capacity, 3);
saturation_fraction = NaN(capacity, 3);
tracking_confidence = NaN(capacity, 1);
reacquired = false(capacity, 1);
count = 0;
white = double(intmax(class(frame)));
tracking_mode = char(settings.roi_tracker);
switch tracking_mode
    case 'ncc'
        tracker = start_ncc(frame, rects);
    case {'klt', 'klt_ncc_reacquire'}
        validateattributes(settings.klt_min_points, {'numeric'}, {'scalar','integer','>=',2});
        validateattributes(settings.klt_max_points, {'numeric'}, ...
            {'scalar','integer','>=',settings.klt_min_points});
        validateattributes(settings.klt_max_error_px, {'numeric'}, {'scalar','real','finite','positive'});
        tracker = start_klt(frame, rects, settings, [0, 0]);
        if isempty(tracker)
            error('rppg:KltFeaturesUnavailable', 'Too few trackable points in the initial ROI hull.');
        end
        if strcmp(tracking_mode, 'klt_ncc_reacquire')
            anchor = start_ncc(frame, rects);
        end
    case 'fixed'
        % Keep initial coordinates.
    otherwise
        error('rppg:UnknownTracker', 'Unsupported ROI tracking mode.');
end
saturation_mode = char(settings.saturation_mode);
if ~ismember(saturation_mode, {'raw', 'hard'})
    error('rppg:UnknownSaturationMode', 'Use raw or hard saturation handling.');
end

while stamp < interval(2)
    if stamp >= interval(1)
        count = count + 1;
        time_s(count, 1) = stamp;
        raw_rgb(count, :, :) = NaN;
        measurement_rgb(count, :, :) = NaN;
        pixel_counts(count, :) = 0;
        roi_positions(count, :, :) = NaN;
        roi_valid(count, :) = false;
        saturation_fraction(count, :) = NaN;
        tracking_confidence(count, 1) = NaN;
        shift = [0, 0];
        observed = true;
        if strcmp(tracking_mode, 'ncc')
            [tracker, shift, confidence] = update_ncc(tracker, frame);
            observed = isfinite(confidence) && confidence >= settings.ncc_min_corr;
            tracking_confidence(count) = confidence;
            if observed
                tracker.last = tracker.origin + shift;
                tracker.misses = 0;
            else
                tracker.misses = tracker.misses + 1;
            end
        elseif ismember(tracking_mode, {'klt', 'klt_ncc_reacquire'})
            [tracker, shift, observed, confidence] = update_klt(tracker, frame, settings);
            tracking_confidence(count) = confidence;
            if strcmp(tracking_mode, 'klt_ncc_reacquire')
                if ~observed
                    [tracker, anchor, shift, observed] = reacquire_klt(tracker, anchor, frame, rects, settings);
                    reacquired(count) = observed;
                end
                if observed
                    anchor.last = anchor.origin + shift;
                    anchor.misses = 0;
                end
            end
        end
        if use_filtered
            filtered_rgb(count, :, :) = NaN;
        end
        if observed
            if use_filtered
                filtered_frame = filter_frame(frame, settings);
            end
            for region = 1:3
                left = max(1, rects(region, 1) + shift(1));
                top = max(1, rects(region, 2) + shift(2));
                x_end = min(size(frame, 2), right(region) + shift(1));
                y_end = min(size(frame, 1), bottom(region) + shift(2));
                if left > x_end || top > y_end
                    continue
                end
                patch = frame(top:y_end, left:x_end, :);
                pixels = reshape(double(patch), [], 3);
                clipped = any(pixels == 0 | pixels == white, 2);
                raw_rgb(count, :, region) = mean(pixels, 1);
                saturation_fraction(count, region) = mean(clipped);
                accepted = true(size(clipped));
                if strcmp(saturation_mode, 'hard')
                    accepted = ~clipped;
                end
                pixels = pixels(accepted, :);
                if use_filtered
                    patch = filtered_frame(top:y_end, left:x_end, :);
                    filtered_pixels = reshape(double(patch), [], 3);
                    filtered_rgb(count, :, region) = mean(filtered_pixels(accepted, :), 1);
                end
                measurement_rgb(count, :, region) = mean(pixels, 1);
                pixel_counts(count, region) = size(pixels, 1);
                roi_valid(count, region) = ~isempty(pixels);
                roi_positions(count, :, region) = [left, top, x_end-left+1, y_end-top+1];
            end
        end
    end
    if ~hasFrame(video)
        break
    end
    stamp = video.CurrentTime;
    if stamp >= interval(2)
        break
    end
    frame = readFrame(video);
end
if count == 0
    error('rppg:NoVideoFrames', 'No frames in the analysis interval.');
end

rows = 1:count;
if use_filtered
    filtered_rgb = filtered_rgb(rows, :, :);
end
median_rgb = [];
if strcmp(settings.spatial_filter, 'median')
    median_rgb = filtered_rgb;
end
rgb_data = struct('time_s', time_s(rows), 'raw_rgb', raw_rgb(rows, :, :), ...
    'measurement_rgb', measurement_rgb(rows, :, :), 'median_rgb', median_rgb, 'filtered_rgb', filtered_rgb, ...
    'pixel_counts', pixel_counts(rows, :), 'roi_positions', roi_positions(rows, :, :), ...
    'valid', any(roi_valid(rows, :), 2), 'roi_valid', roi_valid(rows, :), ...
    'saturation_fraction', saturation_fraction(rows, :), ...
    'tracking_confidence', tracking_confidence(rows), 'reacquired', reacquired(rows), ...
    'interval_s', interval);
end

function tracker = start_ncc(frame, rects)
% Use the original hull as a translation template. No face pixels are added.
lower = min(rects(:, 1:2), [], 1);
upper = max(rects(:, 1:2) + rects(:, 3:4) - 1, [], 1);
margin = max(4, round(0.12*max(upper-lower+1)));
lower = max([1, 1], lower-margin);
upper = min([size(frame, 2), size(frame, 1)], upper+margin);
gray = rgb2gray(frame(lower(2):upper(2), lower(1):upper(1), :));
template = double(gray);
if std(template(:)) == 0
    error('rppg:FlatTrackingTemplate', 'The initial ROI tracking template is flat.');
end
tracker = struct('template', template, 'origin', lower, 'last', lower, 'misses', 0);
end

function [tracker, shift, confidence] = update_ncc(tracker, frame)
[h, w] = size(tracker.template);
radius = max(5, round(0.20*max(h, w))) * min(4, tracker.misses+1);
lower = max([1, 1], tracker.last-radius);
upper = min([size(frame, 2), size(frame, 1)], tracker.last+[w-1, h-1]+radius);
search = rgb2gray(frame(lower(2):upper(2), lower(1):upper(1), :));
confidence = NaN;
shift = [0, 0];
if size(search, 1) < h || size(search, 2) < w || std(double(search(:))) == 0
    return
end
correlation = normxcorr2(tracker.template, double(search));
correlation = correlation(h:size(search, 1), w:size(search, 2));
correlation(~isfinite(correlation)) = -Inf;
[confidence, index] = max(correlation(:));
[y, x] = ind2sub(size(correlation), index);
shift = lower + [x-1, y-1] - tracker.origin;
end

function tracker = start_klt(frame, rects, settings, offset)
tracker = [];
lower = max([1, 1], min(rects(:, 1:2), [], 1) + offset);
upper = min([size(frame, 2), size(frame, 1)], max(rects(:, 1:2) + rects(:, 3:4) - 1, [], 1) + offset);
extent = upper - lower + 1;
if any(extent < 3)
    return
end
gray = rgb2gray(frame);
features = detectMinEigenFeatures(gray, 'ROI', [lower, extent]);
if features.Count < settings.klt_min_points
    return
end
features = selectStrongest(features, settings.klt_max_points);
tracker = struct('tracker', vision.PointTracker('MaxBidirectionalError', settings.klt_max_error_px), ...
    'origin', features.Location, 'active', true(features.Count, 1), 'offset', offset);
initialize(tracker.tracker, tracker.origin, gray);
end

function [tracker, anchor, shift, observed] = reacquire_klt(tracker, anchor, frame, rects, settings)
[~, shift, score] = update_ncc(anchor, frame);
observed = false;
if isfinite(score) && score >= settings.ncc_min_corr
    fresh = start_klt(frame, rects, settings, shift);
    if ~isempty(fresh)
        release(tracker.tracker);
        tracker = fresh;
        observed = true;
        return
    end
end
anchor.misses = anchor.misses + 1;
end

function [tracker, shift, observed, confidence] = update_klt(tracker, frame, settings)
shift = [0, 0];
observed = false;
confidence = 0;
if nnz(tracker.active) < settings.klt_min_points
    return
end
[points, found] = tracker.tracker(rgb2gray(frame));
tracker.active = tracker.active & found & all(isfinite(points), 2);
if nnz(tracker.active) < settings.klt_min_points
    return
end
displacement = points(tracker.active, :) - tracker.origin(tracker.active, :);
center = median(displacement, 1);
inliers = vecnorm(displacement-center, 2, 2) <= settings.klt_max_error_px;
confidence = nnz(inliers) / size(tracker.origin, 1);
observed = nnz(inliers) >= settings.klt_min_points;
if observed
    shift = tracker.offset + round(median(displacement(inliers, :), 1));
end
end

function filtered = filter_frame(frame, settings)
filtered = zeros(size(frame), 'like', frame);
kernel = settings.median_filter_size;
for channel = 1:3
    plane = frame(:, :, channel);
    switch char(settings.spatial_filter)
        case 'median'
            filtered(:, :, channel) = medfilt2(plane, kernel, 'symmetric');
        case 'mean'
            filtered(:, :, channel) = imfilter(plane, ones(kernel)/prod(kernel), 'symmetric');
        case 'gaussian'
            filtered(:, :, channel) = imgaussfilt(plane, settings.spatial_sigma_px, ...
                'FilterSize', kernel, 'Padding', 'symmetric');
        case 'bilateral'
            filtered(:, :, channel) = imbilatfilt(plane);
        case 'wiener'
            filtered(:, :, channel) = wiener2(plane, kernel);
        otherwise
            error('rppg:UnknownSpatialFilter', 'Unsupported spatial filter.');
    end
end
end
