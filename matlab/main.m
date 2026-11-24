function [settings, environment] = main()
%MAIN 초기 프로젝트 폴더와 MATLAB 함수 사용 환경을 확인한다.
% 심박 추정 연결은 기본 방법 A를 구현하면서 추가한다.

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

fprintf('rPPG MATLAB 개발 환경 확인\n');
fprintf('심박 탐색 범위  %.1f ~ %.1f Hz\n', settings.heart_band_hz);
fprintf('비교 방법  %s\n', strjoin(settings.methods, ', '));
disp(environment);
fprintf('실험 기록 파일  %s\n', settings.experiment_file);
fprintf('함수 경로와 실제 라이선스 사용 가능 여부를 함께 확인하세요.\n');
fprintf('현재 단계는 개발 틀 준비입니다. 다음 단계에서 방법 A를 연결합니다.\n');
end
