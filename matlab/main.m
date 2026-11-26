function [settings, environment, report] = main(input_file, output_root)
%MAIN 인자 없이 환경을 확인하거나 영상 한 편 또는 실험 CSV를 분석한다.

settings = config();
report = struct();
if ~isfolder(settings.video_dir)
    mkdir(settings.video_dir);
end
if ~isfolder(settings.result_dir)
    mkdir(settings.result_dir);
end
if ~isfile(settings.experiment_file)
    copyfile(settings.experiment_template, settings.experiment_file);
end
function_names = {'VideoReader'; 'vision.CascadeObjectDetector'; ...
    'vision.PointTracker'; 'detectMinEigenFeatures'; 'estgeotform2d'; ...
    'poly2mask'; 'medfilt2'; 'butter'; 'filtfilt'};
available = false(size(function_names));
for index = 1:numel(function_names)
    available(index) = ~isempty(which(function_names{index}));
end
environment = table(function_names, available, 'VariableNames', {'Function', 'FoundOnPath'});
if nargin == 0
    disp(environment);
    fprintf('영상 한 편  main(''pilot_1m.mp4'')\n');
    fprintf('거리 실험  main(''../data/experiments.csv'')\n');
    fprintf('실험 기록 파일  %s\n', settings.experiment_file);
    return
end
if ~all(available)
    error('rppg:MissingToolbox', 'Missing MATLAB functions: %s', ...
        strjoin(function_names(~available), ', '));
end
if nargin == 2
    settings.result_dir = char(output_root);
    if ~isfolder(settings.result_dir)
        mkdir(settings.result_dir);
    end
end

input_file = char(input_file);
[~, name, extension] = fileparts(input_file);
if strcmpi(extension, '.csv')
    trials = read_experiments(input_file, settings.distances_m);
else
    % 단일 영상 점검은 거리 및 스마트워치 값 없이도 실행한다.
    trials = table(string(name), "pilot", NaN, 1, string(input_file), 0, Inf, NaN, "", NaN, ...
        'VariableNames', {'video_id', 'subject_id', 'distance_m', 'trial', 'video_file', ...
        'start_s', 'end_s', 'gt_bpm', 'watch_file', 'watch_offset_s'});
    input_file = '';
end

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
run_dir = fullfile(settings.result_dir, ['run_', stamp]);
if isfolder(run_dir)
    run_dir = tempname(settings.result_dir);
end
mkdir(run_dir);
settings.result_dir = run_dir;
if ~isempty(input_file)
    copyfile(input_file, fullfile(run_dir, 'input_experiments.csv'));
end

num_trials = height(trials);
num_methods = numel(settings.methods);
predictions = prediction_table(num_trials * num_methods);
ground_truth = table(trials.video_id, NaN(num_trials, 1), strings(num_trials, 1), ...
    strings(num_trials, 1), NaN(num_trials, 1), ...
    'VariableNames', {'video_id', 'gt_bpm', 'gt_status', 'gt_reason', 'gt_samples'});

for trial_index = 1:num_trials
    trial = trials(trial_index, :);
    rows = (trial_index - 1) * num_methods + (1:num_methods);
    fprintf('[%d/%d] %s\n', trial_index, num_trials, char(trial.video_id));

    requested = [trial.start_s, trial.end_s];
    effective = requested;
    video_file = resolve_file(trial.video_file, settings.video_dir, settings.root_dir);
    frames = 0;
    tracked_fraction = NaN;
    output_folder = "";
    failure_reason = '';
    preview = [];
    raw_time = [];
    raw_rgb = [];
    results = cell(1, num_methods);
    try
        rgb_data = extract_rgb(video_file, settings, requested);
        effective = rgb_data.interval_s;
        frames = numel(rgb_data.time_s);
        if frames > 0
            tracked_fraction = mean(rgb_data.valid);
        end
        [prepared, failure_reason] = prepare_rgb(rgb_data, settings);
        preview = rgb_data.preview;
        if isempty(failure_reason)
            raw_time = prepared.source_time_s;
            raw_rgb = prepared.source_mean_rgb;
            for method_index = 1:num_methods
                method_signal = apply_method(prepared, settings.methods{method_index}, settings);
                results{method_index} = estimate_hr(method_signal, settings);
            end
        end
    catch cause
        % 입력 영상의 문제를 한 시도의 실패로 남긴다. 코드 오류는 호출자에게 전달한다.
        switch cause.identifier
            case 'rppg:MissingVideo'
                failure_reason = 'missing_video';
            case 'rppg:UnreadableVideo'
                failure_reason = 'unreadable_video';
            case 'rppg:InvalidInterval'
                failure_reason = 'invalid_video_interval';
            otherwise
                rethrow(cause)
        end
        fprintf('  %s\n', cause.message);
    end

    if ~isempty(raw_time) || (~isempty(preview) && ~isempty(preview(1).frame))
        output_folder = string(sprintf('trial_%03d', trial_index));
        save_trial_plots(fullfile(run_dir, char(output_folder)), trial.video_id, ...
            preview, raw_time, raw_rgb, results, settings);
    end

    [ground_truth.gt_bpm(trial_index), ground_truth.gt_status(trial_index), ...
        ground_truth.gt_reason(trial_index), ground_truth.gt_samples(trial_index)] = ...
        watch_reference(trial, effective, settings);
    predictions.video_id(rows) = trial.video_id;
    predictions.subject_id(rows) = trial.subject_id;
    predictions.distance_m(rows) = trial.distance_m;
    predictions.trial(rows) = trial.trial;
    predictions.method(rows) = string(settings.methods(:));
    predictions.start_s(rows) = effective(1);
    if isfinite(effective(2))
        predictions.end_s(rows) = effective(2);
    end
    predictions.video_frames(rows) = frames;
    predictions.tracking_percent(rows) = 100 * tracked_fraction;
    predictions.artifact_folder(rows) = output_folder;

    for method_index = 1:num_methods
        row = rows(method_index);
        result = results{method_index};
        if isempty(result)
            predictions.status(row) = "failed";
            predictions.failure_reason(row) = string(failure_reason);
            continue
        end
        predictions.predicted_bpm(row) = result.predicted_bpm;
        predictions.status(row) = string(result.status);
        predictions.failure_reason(row) = string(result.failure_reason);
        predictions.peak_ratio(row) = result.quality;
        if strcmp(result.method, 'D')
            predictions.valid_pos_regions(row) = result.num_valid_regions;
            predictions.forehead_bpm(row) = result.region_bpm(1);
            predictions.left_cheek_bpm(row) = result.region_bpm(2);
            predictions.right_cheek_bpm(row) = result.region_bpm(3);
            predictions.forehead_quality(row) = result.region_quality(1);
            predictions.left_cheek_quality(row) = result.region_quality(2);
            predictions.right_cheek_quality(row) = result.region_quality(3);
        end
    end
end

report = evaluate_results(predictions, ground_truth, settings);
report.output_dir = run_dir;
disp(report.by_method(:, {'method', 'n_trials', 'n_valid', 'n_compared', ...
    'mae_bpm', 'rmse_bpm', 'valid_rate_pct'}));
if num_trials == 1
    disp(report.trials(:, {'method', 'predicted_bpm', 'status', 'failure_reason'}));
end
fprintf('Saved results to %s\n', run_dir);
end

function trials = read_experiments(path, allowed_distances)
if ~isfile(path)
    error('rppg:MissingExperiments', 'Experiment CSV not found: %s', path);
end
options = detectImportOptions(path, 'TextType', 'string', 'VariableNamingRule', 'preserve');
required = {'video_id', 'subject_id', 'distance_m', 'trial', 'video_file', ...
    'start_s', 'end_s', 'gt_bpm'};
if ~all(ismember(required, options.VariableNames))
    error('rppg:InvalidExperiments', 'Follow the column names in configs/experiments_template.csv.');
end
text_names = intersect({'video_id', 'subject_id', 'video_file', 'watch_file'}, ...
    options.VariableNames, 'stable');
number_names = intersect({'distance_m', 'trial', 'start_s', 'end_s', ...
    'gt_bpm', 'watch_offset_s'}, options.VariableNames, 'stable');
options = setvartype(options, text_names, 'string');
options = setvartype(options, number_names, 'double');
trials = readtable(path, options);
if height(trials) == 0
    error('rppg:EmptyExperiments', 'Enter at least one experiment row in the CSV.');
end
if any(ismissing(trials.video_id) | strlength(strtrim(trials.video_id)) == 0) || ...
        numel(unique(trials.video_id)) ~= height(trials)
    error('rppg:InvalidExperiments', 'Each row needs a unique video_id.');
end
if any(~ismember(trials.distance_m, allowed_distances))
    error('rppg:InvalidExperiments', 'Use the six experiment distances in the assignment.');
end
trials.start_s(isnan(trials.start_s)) = 0;
trials.end_s(isnan(trials.end_s)) = Inf;
if ~ismember('watch_file', trials.Properties.VariableNames)
    trials.watch_file = strings(height(trials), 1);
end
if ~ismember('watch_offset_s', trials.Properties.VariableNames)
    trials.watch_offset_s = NaN(height(trials), 1);
end
end

function path = resolve_file(name, default_dir, project_dir)
if ismissing(name) || strlength(strtrim(name)) == 0
    path = '';
    return
end
path = char(strtrim(name));
if isfile(path)
    return
end
if isfile(fullfile(project_dir, path))
    path = fullfile(project_dir, path);
else
    path = fullfile(default_dir, path);
end
end

function [bpm, status, reason, count] = watch_reference(trial, interval, settings)
bpm = NaN;
status = "missing";
reason = "no_watch_reference";
count = NaN;
if isfinite(trial.gt_bpm) && trial.gt_bpm > 0
    bpm = trial.gt_bpm;
    status = "ok";
    reason = "";
    return
end
if ismissing(trial.watch_file) || strlength(trial.watch_file) == 0
    return
end
path = resolve_file(trial.watch_file, fullfile(settings.root_dir, 'data', 'watch'), settings.root_dir);
if ~isfile(path)
    reason = "missing_watch_file";
    return
end
if any(~isfinite(interval)) || interval(2) <= interval(1)
    reason = "unknown_watch_interval";
    return
end
try
    options = detectImportOptions(path, 'VariableNamingRule', 'preserve');
    options = setvartype(options, {'time_s', 'bpm'}, 'double');
    readings = readtable(path, options);
catch
    reason = "invalid_watch_csv";
    return
end
offset = trial.watch_offset_s;
if ~isfinite(offset)
    offset = 0;
end
watch_time = readings.time_s + offset;
inside = isfinite(watch_time) & isfinite(readings.bpm) & readings.bpm > 0 & ...
    watch_time >= interval(1) & watch_time < interval(2);
count = nnz(inside);
if count == 0
    reason = "no_watch_samples_in_window";
    return
end
bpm = mean(readings.bpm(inside));
status = "ok";
reason = "";
end

function predictions = prediction_table(n)
% 열별 단위를 고정해 누락된 값을 빈 필드로 남긴다.
text_names = {'video_id', 'subject_id', 'method', 'status', 'failure_reason', 'artifact_folder'};
number_names = {'distance_m', 'trial', 'start_s', 'end_s', 'video_frames', 'tracking_percent', ...
    'predicted_bpm', 'peak_ratio', 'valid_pos_regions', 'forehead_bpm', 'left_cheek_bpm', ...
    'right_cheek_bpm', 'forehead_quality', 'left_cheek_quality', 'right_cheek_quality'};
predictions = table();
for index = 1:numel(text_names)
    predictions.(text_names{index}) = strings(n, 1);
end
for index = 1:numel(number_names)
    predictions.(number_names{index}) = NaN(n, 1);
end
predictions = movevars(predictions, {'distance_m', 'trial'}, 'After', 'subject_id');
end
