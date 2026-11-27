function decode = check_field_video_decode(manifestPath, outputPath)
%CHECK_FIELD_VIDEO_DECODE Spot-check RGB decoding across planned analysis windows.
% Read private input from intake_field_videos.py. No frames are written.

manifest = readtable(manifestPath, 'TextType', 'string');
count = height(manifest);
status = repmat("unchecked", count, 1);
errorId = strings(count, 1);
reportedDuration = NaN(count, 1);
reportedFps = NaN(count, 1);
readerTime = NaN(count, 3);
tic
for index = 1:count
    try
        reader = VideoReader(manifest.video_file(index));
        reportedDuration(index) = reader.Duration;
        reportedFps(index) = reader.FrameRate;
        begin = manifest.start_s(index);
        finish = manifest.end_s(index);
        assert(finish <= reader.Duration, 'field:ShortVideo', ...
            'Decoder duration is shorter than the required analysis window.');
        sampleTimes = [begin, (begin + finish) / 2, max(begin, finish - 1)];
        for position = 1:numel(sampleTimes)
            reader.CurrentTime = sampleTimes(position);
            assert(hasFrame(reader), 'field:MissingDecodeSample', ...
                'A seek within the analysis window did not produce a frame.');
            frame = readFrame(reader);
            assert(size(frame, 1) == manifest.display_height(index) && ...
                size(frame, 2) == manifest.display_width(index) && size(frame, 3) == 3, ...
                'field:UnexpectedDisplaySize', ...
                'Decoded RGB dimensions did not match the track display matrix.');
            readerTime(index, position) = reader.CurrentTime;
        end
        status(index) = "decoded_analysis_start_middle_end";
    catch failure
        status(index) = "failed";
        errorId(index) = string(failure.identifier);
    end
    clear reader frame
    if mod(index, 6) == 0
        fprintf('MATLAB spot decode %d/%d in %.0fs\n', index, count, toc);
    end
end

decode = table(manifest.video_id, status, errorId, reportedDuration, reportedFps, ...
    readerTime(:, 1), readerTime(:, 2), readerTime(:, 3), ...
    'VariableNames', {'video_id', 'decode_status', 'error_id', 'matlab_duration_s', ...
    'matlab_fps', 'reader_time_after_begin_s', 'reader_time_after_mid_s', ...
    'reader_time_after_end_s'});
writetable(decode, outputPath);
disp(groupsummary(decode, "decode_status"));
end
