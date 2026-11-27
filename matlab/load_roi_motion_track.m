function tracker = load_roi_motion_track(path, frame)
%LOAD_ROI_MOTION_TRACK Validate an offline MediaPipe translation sidecar.
% The original decoded RGB frame establishes the expected coordinate system.

track = readtable(path, 'Delimiter', ',', 'TextType', 'string', ...
    'Format', '%f%f%f%f%f%s%f%f');
fields = {'frame_index','time_s','dx','dy','valid','reason','frame_width','frame_height'};
if isempty(track) || ~isequal(track.Properties.VariableNames, fields) ...
        || any(track.frame_index ~= (1:height(track))') || track.time_s(1) ~= 0 ...
        || any(~isfinite(track.time_s)) || any(diff(track.time_s) <= 0) ...
        || any(~ismember(track.valid, [0,1]))
    error('rppg:InvalidRoiMotionFile', 'The ROI motion sidecar has invalid rows or presentation times.');
end
if any(track.frame_width ~= size(frame,2) | track.frame_height ~= size(frame,1))
    error('rppg:RoiMotionOrientationMismatch', 'The ROI motion and decoded RGB coordinate systems differ.');
end
observed = track.valid == 1;
shift = [track.dx, track.dy];
if any(~isfinite(shift(observed,:)) | shift(observed,:) ~= round(shift(observed,:)), 'all')
    error('rppg:InvalidRoiMotionFile', 'Observed motions require finite integer translation in pixels.');
end
tracker = struct('time_s',track.time_s, 'shift',shift, 'observed',observed, 'row',1);
end
