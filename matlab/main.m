function [settings, environment, report] = main(video_file, roi_boxes, interval_s)
%MAIN Inspect the environment, or estimate Method A from one RGB video.
% Use [~, ~, report] = main(video_file, roi_boxes, [start_s end_s]).

settings = config();

if ~isfolder(settings.video_dir)
    mkdir(settings.video_dir);
end
if ~isfolder(settings.result_dir)
    mkdir(settings.result_dir);
end
if ~isfile(settings.experiment_file)
    copyfile(settings.experiment_template, settings.experiment_file);
end

function_names = {'VideoReader'; 'fft'; 'bandpass'; 'medfilt2'};
available = false(size(function_names));
for index = 1:numel(function_names)
    available(index) = ~isempty(which(function_names{index}));
end
environment = table(function_names, available, ...
    'VariableNames', {'Function', 'FoundOnPath'});

report = [];
if nargin >= 1
    if nargin >= 2
        settings.roi_boxes_px = roi_boxes;
    end
    if nargin >= 3
        settings.analysis_interval_s = interval_s;
    end
    rgb_data = extract_rgb(video_file, settings);
    method_signal = apply_method(rgb_data, 'A', settings);
    report = struct('rgb_data', rgb_data, 'signal', method_signal, ...
        'estimate', estimate_hr(method_signal, settings));
    return
end

fprintf('rPPG MATLAB 개발 환경 확인\n');
fprintf('심박 탐색 범위  %.1f ~ %.1f Hz\n', settings.heart_band_hz);
fprintf('비교 방법  %s\n', strjoin(settings.methods, ', '));
disp(environment);
fprintf('실험 기록 파일  %s\n', settings.experiment_file);
fprintf('함수 경로와 실제 라이선스 사용 가능 여부를 함께 확인하세요.\n');
fprintf('영상 파일을 입력하면 고정 ROI에서 Method A를 실행합니다.\n');
end
