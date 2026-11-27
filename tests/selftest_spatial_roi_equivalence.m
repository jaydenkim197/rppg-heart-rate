function selftest_spatial_roi_equivalence()
%SELFTEST_SPATIAL_ROI_EQUIVALENCE Match ROI measurements against full-frame filtering.
rng(42);
frame = uint8(randi([0,255],63,77,3));
path = string(tempname)+".avi";
writer = VideoWriter(path,'Uncompressed AVI');
open(writer);
writeVideo(writer,frame);
close(writer);
cleanup = onCleanup(@() delete(path)); %#ok<NASGU>
settings = config();
settings.roi_boxes_px = [1 1 4 5; 28 22 9 8; 74 61 4 3];
for width = [3,5]
    settings.median_filter_size = [width,width];
    for variant = ["median","mean","gaussian","bilateral","wiener"]
        settings.spatial_filter = variant;
        observed = extract_rgb(path,settings);
        for channel = 1:3
            raw = frame(:,:,channel);
            switch variant
                case "median"
                    filtered = medfilt2(raw,[width,width],'symmetric');
                case "mean"
                    filtered = imfilter(raw,ones(width)/width^2,'symmetric');
                case "gaussian"
                    filtered = imgaussfilt(raw,settings.spatial_sigma_px, ...
                        FilterSize=[width,width],Padding='symmetric');
                case "bilateral"
                    filtered = imbilatfilt(raw);
                otherwise
                    filtered = wiener2(raw,[width,width]);
            end
            for region = 1:3
                box = settings.roi_boxes_px(region,:);
                roi = filtered(box(2)+(0:box(4)-1),box(1)+(0:box(3)-1));
                assert(abs(mean(double(roi),'all')-observed.filtered_rgb(1,channel,region)) < 1e-10,variant);
            end
        end
    end
end
disp('PASS: ROI-edge and interior spatial filter equivalence.');
end