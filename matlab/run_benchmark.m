function report = run_benchmark(trials, split, candidates, output_dir)
%RUN_BENCHMARK Compare pre-registered ROI and signal candidates on the same intervals.
% trials is a table with subject_id, video_id, split, video_file, start_s,
% end_s, roi_boxes (3x4 matrix per cell) and gt_bpm. An absent reference
% is represented by NaN. Use only locally authorized data and output paths.

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
if split ~= "development" && numel(candidates) ~= 1
    error('rppg:HoldoutSweep', 'Only one frozen candidate can be evaluated on holdouts.');
end

base = config();
candidate_settings = repmat(base, numel(candidates), 1);
allowed = {'bandpass_variant', 'bandpass_order', 'fft_window', 'fft_padding_factor', 'peak_method', ...
    'roi_tracker', 'ncc_min_corr', 'saturation_mode'};
for index = 1:numel(candidates)
    overrides = candidates(index).overrides;
    names = fieldnames(overrides);
    if any(~ismember(names, allowed))
        error('rppg:InvalidCandidateSetting', 'Unsupported benchmark override.');
    end
    for field = 1:numel(names)
        candidate_settings(index).(names{field}) = overrides.(names{field});
    end
    if split ~= "development" && strcmp(candidate_settings(index).bandpass_variant, 'none')
        error('rppg:ResearchControlOnHoldout', 'The no-filter research control belongs to development.');
    end
end

predictions = table();
for trial_index = 1:height(requested)
    trial = requested(trial_index, :);
    interval = [trial.start_s, trial.end_s];
    previous_extraction = "";
    for index = 1:numel(candidates)
        method = "A";
        settings = candidate_settings(index);
        extraction = string(jsonencode({settings.roi_tracker, settings.ncc_min_corr, ...
            settings.saturation_mode}));
        if extraction ~= previous_extraction
            settings.roi_boxes_px = trial.roi_boxes{1};
            settings.analysis_interval_s = interval;
            failure = "";
            roi_coverage = NaN;
            try
                rgb = extract_rgb(string(trial.video_file(1)), settings);
                signal = apply_method(rgb, 'A', settings);
                roi_coverage = 100 * mean(rgb.roi_valid, 'all');
            catch problem
                failure = string(problem.identifier);
                if strlength(failure) == 0
                    failure = "video_or_roi_error";
                end
            end
            previous_extraction = extraction;
        end
        if strcmp(settings.bandpass_variant, 'none')
            method = "ResearchNoBandpass";
        end
        if strlength(failure) == 0
            estimate = estimate_hr(signal, settings);
        else
            estimate = struct('predicted_bpm', NaN, 'status', 'failed', ...
                'failure_reason', char(failure), 'quality', NaN);
        end
        row = table(trial.video_id, trial.subject_id, split, trial.start_s, trial.end_s, ...
            method, string(candidates(index).name), estimate.predicted_bpm, ...
            string(estimate.status), string(estimate.failure_reason), estimate.quality, roi_coverage, ...
            'VariableNames', {'video_id', 'subject_id', 'split', 'start_s', 'end_s', ...
            'method', 'candidate', 'predicted_bpm', 'status', 'failure_reason', 'quality', 'roi_coverage_pct'});
        if ismember('distance_m', trial.Properties.VariableNames)
            row.distance_m = trial.distance_m;
        end
        predictions = [predictions; row]; %#ok<AGROW>
    end
end
report = evaluate_results(predictions, requested(:, [key, {'gt_bpm'}]), base);
if nargin >= 4 && strlength(string(output_dir)) > 0
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end
    writetable(report.predictions, fullfile(output_dir, 'predictions.csv'));
    writetable(report.metrics, fullfile(output_dir, 'metrics.csv'));
    record = struct('split', split, 'candidates', candidates, 'effective_settings', candidate_settings);
    writelines(string(jsonencode(record, 'PrettyPrint', true)), fullfile(output_dir, 'settings.json'));
end
end
