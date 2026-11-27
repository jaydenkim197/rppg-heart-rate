function selftest_field_coordinates(ffmpegPath)
%SELFTEST_FIELD_COORDINATES Verify display-space ROI indexing after MOV rotation.
% FFmpeg is needed only to generate this asymmetric synthetic HEVC clip.
arguments
    ffmpegPath (1,1) string
end
assert(isfile(ffmpegPath), 'field:MissingFixtureEncoder', 'Provide a local FFmpeg executable.');
raw_path = [tempname, '.rgb'];
plain_path = [tempname, '.mov'];
rotated_path = [tempname, '.mov'];
files = {raw_path, plain_path, rotated_path};
cleanup = onCleanup(@() delete_files(files)); %#ok<NASGU>

[y, x] = ndgrid(1:64, 1:96);
input_rgb = uint8(cat(3, 2*x, 3*y, x+2*y));
fid = fopen(raw_path, 'wb');
assert(fid ~= -1, 'field:FixtureWriteError', 'Could not write synthetic RGB frames.');
payload = permute(input_rgb, [3,2,1]);
fwrite(fid, repmat(payload(:), 1, 8), 'uint8');
fclose(fid);

encode = sprintf('"%s" -y -hide_banner -loglevel error -f rawvideo -pix_fmt rgb24 -s 96x64 -r 30 -i "%s" -an -c:v libx265 -threads 1 -x265-params pools=1:log-level=error:bframes=0:keyint=1 -pix_fmt yuv420p -tag:v hvc1 "%s"', ...
    ffmpegPath, raw_path, plain_path);
[status, diagnostic] = system(encode);
assert(status == 0, 'field:FixtureEncodeError', 'Synthetic encode failed: %s', diagnostic);
coded_rgb = first_frame(plain_path);
for angle = [90, -90]
    rotate = sprintf('"%s" -y -hide_banner -loglevel error -display_rotation:v:0 %d -i "%s" -map 0:v:0 -c:v copy "%s"', ...
        ffmpegPath, angle, plain_path, rotated_path);
    [status, diagnostic] = system(rotate);
    assert(status == 0, 'field:FixtureRotationError', 'Synthetic rotation metadata failed: %s', diagnostic);

    display_rgb = first_frame(rotated_path);
    assert(isequal(size(coded_rgb), [64,96,3]) && isequal(size(display_rgb), [96,64,3]));
    assert(isequal(rot90(coded_rgb, angle/90), display_rgb), 'field:FixtureOrientationMismatch', ...
        'The backend did not apply the MOV metadata rotation to the decoded pixels.');

    settings = config();
    settings.analysis_interval_s = [0,0.095];
    settings.roi_boxes_px = [3,68,8,12; 22,5,9,5; 46,38,9,9];
    rgb = extract_rgb(rotated_path, settings);
    assert(numel(rgb.time_s) == 3 && all(abs(rgb.time_s - (0:2)'/30) < 1e-6), 'Observed time vector: %s', sprintf('%.9f ',rgb.time_s));
    assert(all(rgb.roi_valid,'all'));
    for region = 1:3
        rectangle = settings.roi_boxes_px(region,:);
        x_pixels = rectangle(1) + (0:rectangle(3)-1);
        y_pixels = rectangle(2) + (0:rectangle(4)-1);
        expected = mean(reshape(double(display_rgb(y_pixels,x_pixels,:)), [], 3),1);
        assert(isequal(rgb.raw_rgb(1,:,region), expected));
        assert(all(rgb.pixel_counts(:,region) == rectangle(3)*rectangle(4)));
        assert(all(rgb.roi_positions(:,:,region) == rectangle, 'all'));
    end
    settings.roi_boxes_px(1,1) = 80;  % Fits the coded width but exceeds the displayed width.
    try
        extract_rgb(rotated_path, settings);
        error('field:UnrejectedCodedCoordinates', 'A coded-space x coordinate was accepted.');
    catch failure
        assert(strcmp(failure.identifier,'rppg:ROIOutsideVideo'), 'field:WrongCoordinateError', ...
            'Expected the display-space ROI bounds error.');
    end
end
disp('PASS: HEVC MOV metadata rotation, display-space ROI values/bounds, and [0,0.095) frame time.')
end

function rgb = first_frame(path)
reader = VideoReader(path);
rgb = readFrame(reader);
end

function delete_files(paths)
for index = 1:numel(paths)
    if isfile(paths{index})
        delete(paths{index});
    end
end
end
