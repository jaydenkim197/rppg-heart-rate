function [tracker, shift, observed] = sample_roi_motion_track(tracker, stamp)
%SAMPLE_ROI_MOTION_TRACK Use only translation at the current presentation time.
% One microsecond covers cross-decoder floating point and nine-decimal CSV precision.
tolerance = 1e-6;
row = tracker.row;
while row <= numel(tracker.time_s) && tracker.time_s(row) < stamp-tolerance
    row = row+1;
end
if ~isfinite(stamp) || row > numel(tracker.time_s) || abs(tracker.time_s(row)-stamp) > tolerance
    error('rppg:RoiMotionTimestampMismatch', 'No ROI motion row matches the decoded frame time.');
end
tracker.row = row+1;
observed = tracker.observed(row);
shift = [0, 0];
if observed
    shift = tracker.shift(row,:);
end
end
