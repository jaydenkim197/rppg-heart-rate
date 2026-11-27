function selftest_roi_motion_track()
%SELFTEST_ROI_MOTION_TRACK Check exact mapping, missing frames and orientation.
path = string(tempname) + ".csv";
cleanup = onCleanup(@() delete(path)); %#ok<NASGU>
rows = ["frame_index,time_s,dx,dy,valid,reason,frame_width,frame_height";...
    "1,0.000000000,0,0,1,ok,16,12";...
    "2,0.033333333,,,0,face_missing,16,12";...
    "3,0.066666667,3,-2,1,ok,16,12"];
writelines(rows,path);
frame = zeros(12,16,3,'uint8');
tracker = load_roi_motion_track(path, frame);
[tracker, shift, valid] = sample_roi_motion_track(tracker, 0);
assert(valid && isequal(shift, [0,0]));
[tracker, shift, valid] = sample_roi_motion_track(tracker, 1/30);
assert(~valid && isequal(shift, [0,0]));
[~, shift, valid] = sample_roi_motion_track(tracker, 2/30);
assert(valid && isequal(shift, [3,-2]));
try
    sample_roi_motion_track(tracker, 0.065);
    error('rppg:ExpectedMotionTimeError', 'An adjacent timestamp should not be used.');
catch issue
    assert(strcmp(issue.identifier, 'rppg:RoiMotionTimestampMismatch'));
end
try
    load_roi_motion_track(path, permute(frame,[2,1,3]));
    error('rppg:ExpectedMotionOrientationError', 'Swapped coordinates must fail.');
catch issue
    assert(strcmp(issue.identifier, 'rppg:RoiMotionOrientationMismatch'));
end
fprintf('PASS: frame-time match, missing observation and orientation guard.\n');
end
