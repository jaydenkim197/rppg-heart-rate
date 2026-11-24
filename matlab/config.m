function settings = config()
%CONFIG 팀 전체가 사용할 경로와 초기 실험 설정을 반환한다.

matlab_dir = fileparts(mfilename('fullpath'));
settings.root_dir = fileparts(matlab_dir);
settings.video_dir = fullfile(settings.root_dir, 'data', 'videos');
settings.result_dir = fullfile(settings.root_dir, 'results');
settings.experiment_file = fullfile(settings.root_dir, 'data', 'experiments.csv');
settings.experiment_template = fullfile(settings.root_dir, ...
    'configs', 'experiments_template.csv');

settings.heart_band_hz = [0.7, 3.0];
settings.distances_m = [0.5, 1, 2, 3, 4, 5];
settings.methods = {'A', 'B', 'C', 'D'};
settings.roi_names = {'forehead', 'left_cheek', 'right_cheek'};
settings.median_filter_size = [3, 3];

% 권장 촬영 조건이다. 심박 계산에는 실제 영상의 시간 정보를 사용한다.
settings.recommended_fps = 30;
settings.recommended_duration_s = 60;
end
