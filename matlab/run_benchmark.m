function report = run_benchmark(trials, split, candidates, output_dir, options)
%RUN_BENCHMARK Compare pre-registered ROI and signal candidates on the same intervals.
% trials is a table with subject_id, video_id, split, video_file, start_s,
% end_s, roi_boxes (3x4 matrix per cell) and gt_bpm. An absent reference
% is represented by NaN. Use only locally authorized data and output paths.

arguments
    trials table
    split
    candidates struct
    output_dir = ""
    options.ShareSpatialExtraction (1,1) logical = false
    options.TraceFirstA (1,1) logical = false
end

required = {'subject_id', 'video_id', 'split', 'video_file', 'start_s', 'end_s', ...
    'roi_boxes', 'gt_bpm'};
if ~all(ismember(required, trials.Properties.VariableNames))
    error('rppg:InvalidTrialManifest', 'The trial manifest is missing required fields.');
end
trials.subject_id = string(trials.subject_id);
trials.video_id = string(trials.video_id);
trials.split = string(trials.split);
split = string(split);
if ~isscalar(split) || ~ismember(split, ["development", "independent", "final"]) ...
        || any(~ismember(trials.split, ["development", "independent", "final"]))
    error('rppg:InvalidSplit', 'Use development, independent, or final.');
end
if any(ismissing(trials.subject_id) | strlength(strtrim(trials.subject_id)) == 0)
    error('rppg:MissingSubject', 'A subject label is required to validate the split.');
end
subjects = unique(trials.subject_id);
for index = 1:numel(subjects)
    if numel(unique(trials.split(trials.subject_id == subjects(index)))) ~= 1
        error('rppg:SubjectLeakage', 'A participant occurs in multiple splits.');
    end
end
requested = trials(trials.split == split, :);
key = {'video_id', 'start_s', 'end_s'};
if isempty(requested) || height(unique(requested(:, key))) ~= height(requested)
    error('rppg:InvalidTrialKeys', 'The selected split needs nonempty, unique trial keys.');
end
if any(ismissing(requested.video_id) | strlength(strtrim(requested.video_id)) == 0)
    error('rppg:MissingVideoId', 'Each trial must have a video identifier.');
end

if ~iscell(requested.roi_boxes) || any(cellfun(@isempty, requested.roi_boxes))
    error('rppg:MissingRoi', 'A noninteractive benchmark needs pre-registered ROI coordinates.');
end

if isempty(candidates) || numel(unique(string({candidates.name}))) ~= numel(candidates)
    error('rppg:InvalidCandidates', 'Nonempty unique candidate names are required.');
end
base = config();
methods = repmat("A", numel(candidates), 1);
if isfield(candidates, 'method')
    methods = string({candidates.method})';
end
if any(~ismember(methods, ["A", "B", "C", "D", "POS"]))
    error('rppg:UnknownMethod', 'Expected A, B, C, D, or POS.');
end
if split ~= "development" && numel(unique(methods)) ~= numel(methods)
    error('rppg:HoldoutSweep', 'Holdouts accept one frozen candidate per method.');
end
candidate_settings = repmat(base, numel(candidates), 1);
allowed = {'bandpass_variant', 'bandpass_order', 'fft_window', 'fft_padding_factor', 'peak_method', 'fft_chunk_s', ...
    'roi_tracker', 'ncc_min_corr', 'camshift_min_score', 'klt_min_points', 'klt_max_points', 'klt_max_error_px', ...
    'saturation_mode', 'spatial_filter', ...
    'median_filter_size', 'spatial_sigma_px', 'color_variant', 'color_window_s', ...
    'pos_window_s', 'pos_sqi', 'pos_min_sqi', 'pos_fusion', 'consensus_tolerance_bpm'};
for index = 1:numel(candidates)
    overrides = candidates(index).overrides;
    names = fieldnames(overrides);
    if methods(index) == 'B'
        candidate_settings(index).spatial_filter = 'median';
    end
    if any(~ismember(names, allowed))
        error('rppg:InvalidCandidateSetting', 'Unsupported benchmark override.');
    end
    for field = 1:numel(names)
        candidate_settings(index).(names{field}) = overrides.(names{field});
    end
    no_time_filter = strcmp(candidate_settings(index).bandpass_variant, 'none');
    no_spatial_filter = methods(index) == "B" && strcmp(candidate_settings(index).spatial_filter, 'none');
    if split ~= "development" && (no_time_filter || no_spatial_filter ...
            || is_research_control(candidates(index)) || strlength(unavailable_reason(candidates(index))) > 0)
        error('rppg:ResearchControlOnHoldout', 'Unfiltered research controls belong to development.');
    end
end

% An extraction with B's filter already retains the original measurements.
% A, C, D and POS consume those measurements independently of filtered RGB.
share_candidate = find(methods == "B", 1);
if ~options.ShareSpatialExtraction || split == "development" || isempty(share_candidate) ...
        || ~can_share_spatial(candidate_settings, share_candidate)
    share_candidate = [];
end
trace = [];
predictions = table();
has_tracking_interval = all(ismember({'tracking_start_s','tracking_end_s'}, requested.Properties.VariableNames));
cache = containers.Map('KeyType','char','ValueType','any');
previous_video = "";
for trial_index = 1:height(requested)
    trial = requested(trial_index, :);
    interval = [trial.start_s, trial.end_s];
    tracking_interval = interval;
    if has_tracking_interval
        tracking_interval = [trial.tracking_start_s, trial.tracking_end_s];
        if tracking_interval(1) > interval(1) || tracking_interval(2) < interval(2)
            error('rppg:InvalidTrackingWindow', 'The tracking window must contain the analysis interval.');
        end
    end
    video_file = string(trial.video_file(1));
    if video_file ~= previous_video
        cache = containers.Map('KeyType','char','ValueType','any');
        previous_video = video_file;
    end
    for index = 1:numel(candidates)
        method = methods(index);
        settings = candidate_settings(index);
        if strcmp(settings.roi_tracker, 'mediapipe') ...
                && ismember('roi_motion_file', trial.Properties.VariableNames)
            settings.roi_motion_file = string(trial.roi_motion_file(1));
        end
        failure = unavailable_reason(candidates(index));
        roi_coverage = NaN;
        if strlength(failure) == 0
            extraction_settings = settings;
            if ~isempty(share_candidate)
                extraction_settings.spatial_filter = candidate_settings(share_candidate).spatial_filter;
                extraction_settings.median_filter_size = candidate_settings(share_candidate).median_filter_size;
                extraction_settings.spatial_sigma_px = candidate_settings(share_candidate).spatial_sigma_px;
            end
            cached = run_extraction(cache, video_file, trial.roi_boxes{1}, tracking_interval, extraction_settings);
            if strlength(cached.failure) > 0 && ~isempty(share_candidate) && method ~= "B"
                cached = run_extraction(cache, video_file, trial.roi_boxes{1}, tracking_interval, settings);
            end
            failure = cached.failure;
            if strlength(failure) == 0
                rgb = crop_rgb(cached.rgb, interval);
                roi_coverage = 100 * mean(rgb.roi_valid, 'all');
            end
        end
        if is_research_control(candidates(index))
            method = "Research" + method;
        elseif strcmp(settings.bandpass_variant, 'none')
            method = "ResearchNoBandpass";
        elseif method == "B" && strcmp(settings.spatial_filter, 'none')
            method = "ResearchNoSpatial";
        end
        if strlength(failure) == 0
            signal = apply_method(rgb, methods(index), settings);
            if options.TraceFirstA && trial_index == 1 && methods(index) == "A"
                [estimate, example] = estimate_interval(signal, settings, interval);
                trace = struct('rgb_data', rgb, 'estimate', example, ...
                    'fft_chunk_s', settings.fft_chunk_s);
            else
                estimate = estimate_interval(signal, settings, interval);
            end
        else
            estimate = failed_estimate(failure);
        end
        row = table(trial.video_id, trial.subject_id, split, trial.start_s, trial.end_s, ...
            method, string(candidates(index).name), estimate.predicted_bpm, ...
            string(estimate.status), string(estimate.failure_reason), estimate.quality, roi_coverage, ...
            'VariableNames', {'video_id', 'subject_id', 'split', 'start_s', 'end_s', ...
            'method', 'candidate', 'predicted_bpm', 'status', 'failure_reason', 'quality', 'roi_coverage_pct'});
        if ismember('reference_status', trial.Properties.VariableNames)
            row.reference_status = string(trial.reference_status);
        end
        if ismember('distance_m', trial.Properties.VariableNames)
            row.distance_m = trial.distance_m;
        end
        predictions = [predictions; row]; %#ok<AGROW>
    end
end
report = evaluate_results(predictions, requested(:, [key, {'gt_bpm'}]), base);
if options.TraceFirstA
    report.trace = trace;
end
if strlength(string(output_dir)) > 0
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end
    writetable(report.predictions, fullfile(output_dir, 'predictions.csv'));
    writetable(report.metrics, fullfile(output_dir, 'metrics.csv'));
    writelines(string(jsonencode(table2struct(requested), 'PrettyPrint', true)), ...
        fullfile(output_dir, 'trials.json'));
    record = struct('split', split, 'candidates', candidates, 'effective_settings', candidate_settings);
    writelines(string(jsonencode(record, 'PrettyPrint', true)), fullfile(output_dir, 'settings.json'));
end
end

function can_share = can_share_spatial(settings, spatial)
extraction_fields = {'roi_tracker','ncc_min_corr','camshift_min_score','klt_min_points', ...
    'klt_max_points','klt_max_error_px','saturation_mode','roi_motion_file'};
can_share = ~strcmp(settings(spatial).spatial_filter, 'none');
other = setdiff(1:numel(settings),spatial);
for index = other
    if ~strcmp(settings(index).spatial_filter, 'none') ...
            || ~all(cellfun(@(field) isequaln(settings(index).(field), settings(spatial).(field)), extraction_fields))
        can_share = false;
        return
    end
end
end

function cached = run_extraction(cache, video_file, boxes, interval, settings)
key = jsonencode({settings.roi_tracker, settings.ncc_min_corr, settings.camshift_min_score, ...
    settings.klt_min_points, settings.klt_max_points, settings.klt_max_error_px, ...
    settings.saturation_mode, settings.spatial_filter, settings.median_filter_size, ...
    settings.spatial_sigma_px, interval, boxes, settings.roi_motion_file});
if ~isKey(cache, key)
    settings.roi_boxes_px = boxes;
    settings.analysis_interval_s = interval;
    cached = struct('rgb', [], 'failure', "");
    try
        cached.rgb = extract_rgb(video_file, settings);
    catch problem
        cached.failure = string(problem.identifier);
        if strlength(cached.failure) == 0
            cached.failure = "video_or_roi_error";
        end
    end
    cache(key) = cached;
else
    cached = cache(key);
end
end

function yes = is_research_control(candidate)
yes = isfield(candidate, 'research_only') && candidate.research_only;
end

function reason = unavailable_reason(candidate)
reason = "";
if isfield(candidate, 'unavailable_reason')
    reason = string(candidate.unavailable_reason);
end
end

function rgb = crop_rgb(rgb, interval)
inside = rgb.time_s >= interval(1) & rgb.time_s < interval(2);
fields = {'time_s','raw_rgb','measurement_rgb','median_rgb','filtered_rgb','pixel_counts', ...
    'roi_positions','valid','roi_valid','saturation_fraction','tracking_confidence','reacquired'};
for index = 1:numel(fields)
    field = fields{index};
    if ~isempty(rgb.(field))
        rgb.(field) = rgb.(field)(inside,:,:);
    end
end
rgb.interval_s = interval;
end

function [result, example] = estimate_interval(signal, settings, interval)
example = struct('filtered', [], 'power', []);
width = settings.fft_chunk_s;
if width == 0
    result = estimate_hr(signal, settings);
    example = result;
    return
end
if width <= 0 || width > diff(interval)
    result = failed_estimate("fft_window_exceeds_observed_interval");
    return
end
starts = unique([interval(1):width/2:interval(2)-width, interval(2)-width]);
values = NaN(numel(starts), 1);
quality = values;
% The last sample precedes a half-open window's end by one frame.
if numel(signal.time_s) > 1
    settings.min_duration_s = min(settings.min_duration_s, ...
        width - 1.5 * median(diff(signal.time_s)));
end
for index = 1:numel(starts)
    local = signal;
    inside = signal.time_s >= starts(index) & signal.time_s < starts(index)+width;
    local.time_s = signal.time_s(inside);
    local.values = signal.values(inside,:);
    result = estimate_hr(local, settings);
    if index == 1
        example = result;
    end
    if strcmp(result.status, 'ok')
        values(index) = result.predicted_bpm;
        quality(index) = result.quality;
    end
end
if nnz(isfinite(values)) < ceil(0.70*numel(starts))
    result = failed_estimate("insufficient_valid_fft_chunks");
else
    result = struct('predicted_bpm', median(values,'omitnan'), 'status', 'ok', ...
        'failure_reason', '', 'quality', median(quality,'omitnan'));
end
end

function estimate = failed_estimate(reason)
estimate = struct('predicted_bpm', NaN, 'status', 'failed', ...
    'failure_reason', char(reason), 'quality', NaN);
end
