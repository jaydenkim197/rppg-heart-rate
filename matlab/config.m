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
settings.methods = {'A', 'B', 'C', 'D', 'POS'};
settings.roi_names = {'forehead', 'left_cheek', 'right_cheek'};
settings.median_filter_size = [3, 3];

% 얼굴 박스 안의 [x, y, 너비, 높이] 비율. 좌우는 영상 화면 기준이다.
settings.roi_boxes = [0.25, 0.15, 0.50, 0.16; ...
                      0.13, 0.55, 0.24, 0.18; ...
                      0.63, 0.55, 0.24, 0.18];
settings.min_roi_pixels = 16;
settings.min_tracking_points = 4;
settings.max_tracking_points = 80;
settings.max_tracking_error_px = 2;
settings.reacquire_overlap = 0.2;
settings.redetect_every_frames = 5;

% 예비 촬영에서 확인하고 본 실험 전에 고정할 품질 기준이다.
settings.min_duration_s = 10;
settings.min_tracking_fraction = 0.90;
settings.max_frame_gap_s = 0.5;
settings.max_edge_gap_s = 0.25;
settings.pos_window_s = 1.6;
settings.peak_half_width_hz = 0.15;
settings.min_peak_ratio = 0.25;

% 권장 촬영 조건이다. 심박 계산에는 실제 영상의 시간 정보를 사용한다.
settings.recommended_fps = 30;
settings.recommended_duration_s = 60;
end
