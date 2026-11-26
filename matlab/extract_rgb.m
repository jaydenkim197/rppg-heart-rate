function rgb_data = extract_rgb(video_file, settings)
%EXTRACT_RGB Read RGB means and timestamps for three fixed skin rectangles.
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
raw_rgb = zeros(capacity, 3, 3);
saturation_fraction = zeros(capacity, 3);
count = 0;
white = double(intmax(class(frame)));
while stamp < interval(2)
    if stamp >= interval(1)
        count = count + 1;
        time_s(count, 1) = stamp;
        for region = 1:3
            patch = frame(rects(region, 2):bottom(region), rects(region, 1):right(region), :);
            pixels = reshape(double(patch), [], 3);
            raw_rgb(count, :, region) = mean(pixels, 1);
            saturation_fraction(count, region) = mean(any(pixels == 0 | pixels == white, 2));
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

rgb_data = struct('time_s', time_s(1:count), 'raw_rgb', raw_rgb(1:count, :, :), ...
    'median_rgb', [], 'pixel_counts', repmat(prod(rects(:, 3:4), 2)', count, 1), ...
    'roi_positions', repmat(reshape(rects', 1, 4, 3), count, 1, 1), ...
    'valid', true(count, 1), 'roi_valid', true(count, 3), ...
    'saturation_fraction', saturation_fraction(1:count, :), 'interval_s', interval);
end
