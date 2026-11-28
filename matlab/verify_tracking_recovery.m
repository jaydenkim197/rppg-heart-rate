function report = verify_tracking_recovery()
%VERIFY_TRACKING_RECOVERY Replay fixed artificial translation and loss events.
% Uses the production extractor and records frame-level recovery evidence.

fs = 30;
rectangles = [60,29,16,14; 43,57,17,14; 83,57,17,14];
trackers = ["fixed","ncc","klt","klt_ncc_reacquire"];
modes = ["local_reentry","outside_search"];
report.frames = table();
report.events = table();

for mode = modes
    [video, visible, offsets, reentry] = synthetic_input(mode, fs);
    delete_video = onCleanup(@() delete(video));
    for tracker = trackers
        settings = config();
        settings.roi_tracker = tracker;
        settings.roi_boxes_px = rectangles;
        measured = extract_rgb(video, settings);
        assert(numel(measured.time_s) == numel(visible));
        x = squeeze(measured.roi_positions(:,1,:));
        y = squeeze(measured.roi_positions(:,2,:));
        error_px = max(hypot(x - (rectangles(:,1)' + offsets(:,1)), ...
            y - (rectangles(:,2)' + offsets(:,2))), [], 2);
        localized = visible & all(measured.roi_valid, 2) & error_px <= 1;
        samples = numel(visible);
        rows = table(repmat(mode,samples,1), repmat(tracker,samples,1), (1:samples)', ...
            visible, measured.valid, localized, measured.reacquired, error_px, ...
            'VariableNames', {'case_name','tracker','frame','target_visible','any_roi_observed', ...
            'all_roi_localized','reacquired','max_error_px'});
        report.frames = [report.frames; rows]; %#ok<AGROW>
        for start = reentry
            first_blank = find(~visible(start+1:end),1);
            stop = samples;
            if ~isempty(first_blank)
                stop = start + first_blank - 1;
            end
            first_hit = find(localized(start:stop),1);
            delay_frames = NaN;
            if ~isempty(first_hit)
                delay_frames = first_hit-1;
            end
            event = table(mode,tracker,start,stop,delay_frames,delay_frames/fs, ...
                'VariableNames', {'case_name','tracker','reentry_frame','end_frame', ...
                'recovery_delay_frames','recovery_delay_s'});
            report.events = [report.events; event]; %#ok<AGROW>
        end
    end
    clear delete_video
end

% Baseline preserves the original three coordinates in the first frame.
assert(all(report.frames.all_roi_localized(report.frames.frame == 1)));
assert(height(report.events) == 3*numel(trackers));
end

function [file, visible, offsets, reentry] = synthetic_input(mode, fs)
count = 108;
visible = true(count,1);
offsets = zeros(count,2);
if mode == "local_reentry"
    offsets(21:36,:) = repmat([3,1],16,1);
    offsets(37:71,:) = repmat([6,2],35,1);
    offsets(72:end,:) = repmat([9,3],37,1);
    visible([31:36,60:71,98:108]) = false;
    reentry = [37,72];
else
    visible(35:48) = false;
    offsets(49:end,1) = 135;
    reentry = 49;
end
stream = RandStream('mt19937ar','Seed',117);
texture = uint8(randi(stream,[45,210],62,83));
clutter = uint8(randi(stream,[45,210],62,83));
file = [tempname, '.avi'];
writer = VideoWriter(file,'Uncompressed AVI');
writer.FrameRate = fs;
open(writer);
for frame = 1:count
    gray = repmat(uint8(35),110,260);
    if visible(frame)
        xs = (29:111) + offsets(frame,1);
        ys = (20:81) + offsets(frame,2);
        gray(ys,xs) = texture;
    elseif mode == "local_reentry" && frame >= 60 && frame <= 71
        gray(20:81,29:111) = clutter;
    end
    writeVideo(writer, repmat(gray,1,1,3));
end
close(writer);
end
