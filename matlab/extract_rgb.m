function rgb_data = extract_rgb(video_file, settings, interval_s)
%EXTRACT_RGB 같은 피부 부위를 따라가며 프레임별 색의 평균을 저장한다.

if nargin < 3
    interval_s = [0, Inf];
end
if ~isfile(video_file)
    error('rppg:MissingVideo', 'Video file not found: %s', video_file);
end
try
    video = VideoReader(video_file);
catch cause
    error('rppg:UnreadableVideo', 'Cannot open video: %s', cause.message);
end
if interval_s(2) > video.Duration + settings.max_edge_gap_s && isfinite(interval_s(2))
    error('rppg:InvalidInterval', 'Requested end time exceeds the video duration.');
end
interval_s(2) = min(interval_s(2), video.Duration);
if interval_s(1) < 0 || interval_s(1) >= interval_s(2)
    error('rppg:InvalidInterval', 'Expected a nonempty video time interval.');
end

% estgeotform2d의 표본 추출 순서를 고정하고 호출자의 난수 상태는 복원한다.
previous_rng = rng;
rng_cleanup = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
rng(0, 'twister');

detector = vision.CascadeObjectDetector('FrontalFaceCART');
tracker = vision.PointTracker('MaxBidirectionalError', settings.max_tracking_error_px);
reference_points = zeros(0, 2);
reference_shape = [];
last_face = [];
next_detection = 1;

capacity = max(1, ceil((interval_s(2) - interval_s(1)) * video.FrameRate) + 1);
time_s = NaN(capacity, 1);
raw_rgb = NaN(capacity, 3, 3);
median_green = NaN(capacity, 3);
pixel_counts = zeros(capacity, 3);
roi_positions = NaN(capacity, 4, 2, 3);
valid = false(capacity, 1);
preview(1:2) = struct('frame', [], 'polygons', [], 'time_s', NaN);
frame_index = 0;

while hasFrame(video)
    frame_time = video.CurrentTime;
    if frame_time >= interval_s(2)
        break
    end
    try
        frame = readFrame(video);
    catch cause
        error('rppg:UnreadableVideo', 'Cannot decode video frame: %s', cause.message);
    end
    if frame_time < interval_s(1)
        continue
    end

    frame_index = frame_index + 1;
    time_s(frame_index, 1) = frame_time;
    raw_rgb(frame_index, :, :) = NaN;
    median_green(frame_index, :) = NaN;
    pixel_counts(frame_index, :) = 0;
    roi_positions(frame_index, :, :, :) = NaN;
    valid(frame_index, 1) = false;
    gray_frame = im2gray(frame);

    if isempty(reference_points)
        if frame_index < next_detection
            continue
        end
        next_detection = frame_index + settings.redetect_every_frames;
        face = choose_face(detector(gray_frame), last_face, settings.reacquire_overlap);
        if isempty(face)
            continue
        end
        current_shape = make_regions(face, settings.roi_boxes);
        points = find_points(gray_frame, current_shape(:, :, 1), settings);
        if size(points, 1) < settings.min_tracking_points
            continue
        end
        initialize(tracker, points, gray_frame);
        reference_points = points;
        reference_shape = current_shape;
    else
        [points, found] = tracker(gray_frame);
        if nnz(found) < settings.min_tracking_points
            release(tracker);
            reference_points = zeros(0, 2);
            next_detection = frame_index + 1;
            continue
        end

        % 특징점 쌍에서 이동, 회전, 크기 변화를 구해 기준 도형을 옮긴다.
        [transform, inliers, status] = estgeotform2d(reference_points(found, :), ...
            points(found, :), 'similarity', 'MaxDistance', settings.max_tracking_error_px);
        if status ~= 0 || nnz(inliers) < settings.min_tracking_points
            release(tracker);
            reference_points = zeros(0, 2);
            next_detection = frame_index + 1;
            continue
        end
        corners = reshape(permute(reference_shape, [1, 3, 2]), [], 2);
        moved = transformPointsForward(transform, corners);
        current_shape = permute(reshape(moved, 4, 4, 2), [1, 3, 2]);
        current_points = points(found, :);
        original_points = reference_points(found, :);
        setPoints(tracker, current_points(inliers, :));
        reference_points = original_points(inliers, :);
    end

    rois = current_shape(:, :, 2:4);
    [rgb, green, counts] = sample_regions(frame, rois, settings);
    if any(counts < settings.min_roi_pixels)
        release(tracker);
        reference_points = zeros(0, 2);
        next_detection = frame_index + 1;
        continue
    end
    raw_rgb(frame_index, :, :) = reshape(rgb.', 1, 3, 3);
    median_green(frame_index, :) = green;
    pixel_counts(frame_index, :) = counts;
    roi_positions(frame_index, :, :, :) = reshape(rois, 1, 4, 2, 3);
    valid(frame_index) = true;

    % 점이 줄면 현재 얼굴에서 특징점을 보충한다. 이미 구한 ROI를 기준으로 이어간다.
    face_corners = current_shape(:, :, 1);
    last_face = enclosing_box(face_corners);
    if size(reference_points, 1) < 3 * settings.min_tracking_points
        fresh_points = find_points(gray_frame, face_corners, settings);
        if size(fresh_points, 1) > size(reference_points, 1)
            setPoints(tracker, fresh_points);
            reference_points = fresh_points;
            reference_shape = current_shape;
        end
    end

    snapshot = struct('frame', frame, 'polygons', rois, 'time_s', frame_time);
    if isempty(preview(1).frame)
        preview(1) = snapshot;
    end
    preview(2) = snapshot;
end

rows = 1:frame_index;
rgb_data.time_s = time_s(rows);
rgb_data.raw_rgb = raw_rgb(rows, :, :);
rgb_data.median_green = median_green(rows, :);
rgb_data.pixel_counts = pixel_counts(rows, :);
rgb_data.roi_positions = roi_positions(rows, :, :, :);
rgb_data.valid = valid(rows);
rgb_data.interval_s = interval_s;
rgb_data.preview = preview;
end

function face = choose_face(boxes, last_face, min_overlap)
face = [];
if isempty(last_face)
    if size(boxes, 1) == 1
        face = boxes(1, :);
    end
    return
end
if isempty(boxes)
    return
end

% 재검출할 때 이전 얼굴 박스와 충분히 겹치는 후보만 사용한다.
top_left = max(boxes(:, 1:2), last_face(1:2));
bottom_right = min(boxes(:, 1:2) + boxes(:, 3:4), last_face(1:2) + last_face(3:4));
intersection = prod(max(0, bottom_right - top_left), 2);
combined_area = prod(boxes(:, 3:4), 2) + prod(last_face(3:4)) - intersection;
[overlap, index] = max(intersection ./ combined_area);
if overlap >= min_overlap
    face = boxes(index, :);
end
end

function shapes = make_regions(face, roi_boxes)
width_height = max(face(3:4) - 1, 1);
shapes = zeros(4, 2, 4);
shapes(:, :, 1) = rectangle_points(face(1:2), width_height);
for region = 1:3
    box = roi_boxes(region, :);
    shapes(:, :, region + 1) = rectangle_points( ...
        face(1:2) + box(1:2) .* width_height, box(3:4) .* width_height);
end
end

function corners = rectangle_points(origin, extent)
corners = origin + [0, 0; extent(1), 0; extent; 0, extent(2)];
end

function box = enclosing_box(corners)
lower = min(corners, [], 1);
upper = max(corners, [], 1);
box = [lower, upper - lower];
end

function points = find_points(gray_frame, face, settings)
lower = max(ceil(min(face, [], 1)), [1, 1]);
upper = min(floor(max(face, [], 1)), [size(gray_frame, 2), size(gray_frame, 1)]);
extent = upper - lower;
points = zeros(0, 2);
if any(extent < 6)
    return
end
features = detectMinEigenFeatures(gray_frame, 'ROI', [lower, extent], 'MinQuality', 0.01);
if features.Count > settings.max_tracking_points
    features = selectStrongest(features, settings.max_tracking_points);
end
points = features.Location;
end

function [rgb, green, counts] = sample_regions(frame, rois, settings)
rgb = NaN(3, 3);
green = NaN(1, 3);
counts = zeros(1, 3);
if any(~isfinite(rois(:)))
    return
end

frame_size = [size(frame, 2), size(frame, 1)];
half_filter = floor(fliplr(settings.median_filter_size) / 2);
for region = 1:3
    corners = rois(:, :, region);
    lower = min(corners, [], 1);
    upper = max(corners, [], 1);
    if any(lower < 1) || any(upper > frame_size)
        continue
    end
    % 필터의 이웃 픽셀도 읽게 ROI 주변을 한 픽셀 더 자른다.
    crop_min = max(floor(lower) - half_filter, [1, 1]);
    crop_max = min(ceil(upper) + half_filter, frame_size);
    crop = frame(crop_min(2):crop_max(2), crop_min(1):crop_max(1), :);
    local_corners = double(corners - crop_min + 1);
    mask = poly2mask(local_corners(:, 1), local_corners(:, 2), size(crop, 1), size(crop, 2));
    counts(region) = nnz(mask);
    if counts(region) < settings.min_roi_pixels
        continue
    end
    for channel = 1:3
        plane = crop(:, :, channel);
        rgb(region, channel) = mean(double(plane(mask)));
    end
    filtered_green = medfilt2(crop(:, :, 2), settings.median_filter_size, 'symmetric');
    green(region) = mean(double(filtered_green(mask)));
end
end
