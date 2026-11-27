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
settings.recommended_fps = 60;
settings.recommended_duration_s = 60;

% Initial development settings. Selection experiments can replace them.
settings.analysis_interval_s = [];
settings.roi_boxes_px = [];
settings.roi_tracker = 'fixed';
settings.ncc_min_corr = 0.65;
settings.camshift_min_score = 0.5;
settings.fft_chunk_s = 0;
settings.klt_min_points = 4;
settings.klt_max_points = 80;
settings.klt_max_error_px = 2;
settings.saturation_mode = 'raw';
settings.spatial_filter = 'none';
settings.spatial_sigma_px = 1;
settings.color_variant = 'rgb_sum';
settings.color_window_s = 2;
settings.pos_window_s = 1.6;
settings.pos_sqi = 'energy_ratio';
settings.pos_min_sqi = 0.15;
settings.pos_fusion = 'weighted';
settings.consensus_tolerance_bpm = 5;
settings.min_duration_s = 5;
settings.max_step_ratio = 1.5;
settings.bandpass_variant = 'butterworth';
settings.fft_window = 'hann';
settings.fft_padding_factor = 1;
settings.peak_method = 'max';
settings.bandpass_order = 2;
settings.bandpass_reflection_s = 3;
settings.min_band_fraction = 0.001;
settings.peak_half_width_hz = 0.10;
end
