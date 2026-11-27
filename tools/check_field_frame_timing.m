function timing = check_field_frame_timing(manifestPath, outputPath, options)
%CHECK_FIELD_FRAME_TIMING Compare sequential MATLAB decoding with native MOV PTS.
% Each sidecar contains the edited video track in presentation order. Reads
% start at zero like the field evaluation. Only timing/shape data are saved.
arguments
    manifestPath (1,1) string
    outputPath (1,1) string
    options.LeadingFrames (1,1) double {mustBeInteger,mustBePositive} = 12
    options.FullWindowIds (:,1) string = strings(0,1)
end

manifest = readtable(manifestPath, 'TextType', 'string', 'Delimiter', ',');
if any(manifest.start_s ~= 0) || any(~ismember(options.FullWindowIds, manifest.video_id))
    error('field:InvalidTimingCheckWindow', 'Expected zero-based windows and known full-window video IDs.');
end
timing = table(manifest.video_id, ismember(manifest.video_id, options.FullWindowIds), ...
    zeros(height(manifest),1), zeros(height(manifest),1), NaN(height(manifest),1), ...
    repmat("unchecked",height(manifest),1), strings(height(manifest),1), ...
    'VariableNames', {'video_id','full_window','n_expected','n_checked','max_pts_difference_s','status','error_id'});
tolerance_s = 1e-6;
started = tic;
for index = 1:height(manifest)
    try
        sidecar = readtable(manifest.frame_pts_csv(index), 'Delimiter', ',');
        expected = sidecar.pts_s;
        assert(height(sidecar) == manifest.frames(index) && all(isfinite(expected)) ...
            && expected(1) == 0 && all(diff(expected) > 0) ...
            && isequal(sidecar.frame_index, (1:height(sidecar))'), ...
            'field:InvalidTimingSidecar', 'The native presentation timestamps must form one ordered track.');
        finish = manifest.end_s(index);
        assert(expected(end) >= finish, 'field:ShortTimingSidecar', ...
            'The native presentation timeline ends before the analysis window.');
        expected = expected(expected < finish);
        if ~timing.full_window(index)
            expected = expected(1:min(options.LeadingFrames, numel(expected)));
        end
        timing.n_expected(index) = numel(expected);
        reader = VideoReader(manifest.video_file(index));
        reader.CurrentTime = 0;
        error_s = 0;
        for frame_index = 1:numel(expected)
            assert(hasFrame(reader), 'field:PrematureDecodeEnd', ...
                'MATLAB stopped before reaching the expected native presentation timestamp.');
            stamp = reader.CurrentTime;
            frame = readFrame(reader);
            assert(isequal(size(frame), [manifest.display_height(index), manifest.display_width(index), 3]), ...
                'field:UnexpectedDisplaySize', 'Decoded RGB frame does not match the display matrix.');
            timing.n_checked(index) = frame_index;
            error_s = max(error_s, abs(stamp - expected(frame_index)));
            timing.max_pts_difference_s(index) = error_s;
            assert(error_s <= tolerance_s, 'field:PresentationTimeMismatch', ...
                'MATLAB sequential frame time differs from the native presentation timestamp.');
        end
        if timing.full_window(index)
            assert(reader.CurrentTime >= finish && hasFrame(reader), ...
                'field:AnalysisBoundaryMismatch', 'The next decoded frame must be at or beyond the interval end.');
        end
        timing.status(index) = "ok";
    catch failure
        timing.status(index) = "failed";
        timing.error_id(index) = string(failure.identifier);
    end
    clear reader frame
    if mod(index,6) == 0
        fprintf('MATLAB sequential timing %d/%d in %.0fs\n', index, height(manifest), toc(started));
    end
end
writetable(timing, outputPath);
disp(groupsummary(timing, ["status","error_id"]));
end
