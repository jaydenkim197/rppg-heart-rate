function report = run_frozen_evaluation(trials, freeze_path, output_dir)
%RUN_FROZEN_EVALUATION Evaluate a pinned A-D pipeline and its separate pooled POS control.
% The caller must supply a prepared final or independent manifest and prior freeze.

freeze_json = fileread(freeze_path);
freeze = jsondecode(freeze_json);
required = {'revision','code_commit','candidates','field_gates',...
    'independent_min_reference_subjects','independent_min_reference_trend_pairs','independent_min_paired'};
if ~all(isfield(freeze, required)) || isempty(regexp(freeze.code_commit,'^[0-9a-f]{40}$','once'))
    error('rppg:InvalidFreeze', 'Use a preregistered freeze with a full implementation commit.');
end
base = config();
files = {'config','extract_rgb','apply_method','estimate_hr','run_benchmark', ...
    'score_selection_stage','selection_plan','evaluate_results','prepare_frozen_trials', ...
    'run_frozen_evaluation','write_final_report', ...
    'build_ubfc_reference_table','validate_ubfc_reference','estimate_ubfc_reference'};
assert_frozen_sources(base.root_dir, freeze.code_commit, files);
candidates = load_candidates(freeze.candidates, base);
trials.split = string(trials.split);
split = unique(trials.split);
trials.video_id = string(trials.video_id);
trials.subject_id = string(trials.subject_id);
trials.video_file = string(trials.video_file);
keys = {'video_id','start_s','end_s'};
if ~isscalar(split) || ~ismember(split,["final","independent"]) ...
        || height(unique(trials(:, keys))) ~= height(trials)
    error('rppg:InvalidFrozenTrials','Use one complete final or independent split with unique interval keys.');
end
validate_cohort(trials, split, base);
if ~isfolder(output_dir)
    mkdir(output_dir);
end
pin_path = fullfile(output_dir, 'freeze.json');
if isfile(pin_path)
    if ~strcmp(fileread(pin_path), freeze_json)
        error('rppg:FreezeChanged','Existing output is pinned to a different freeze.');
    end
else
    copyfile(freeze_path, pin_path);
end
checkpoint_dir = fullfile(output_dir,'checkpoints');
if ~isfolder(checkpoint_dir)
    mkdir(checkpoint_dir);
end
started = tic;
predictions = table();
example = [];
videos = unique(trials.video_id,'stable');
roi_fail = ismember('roi_status',trials.Properties.VariableNames);
record = struct('freeze',freeze_json,'runtime',version,'share_spatial',true);
for index = 1:numel(videos)
    local_trials = trials(trials.video_id == videos(index),:);
    path = fullfile(checkpoint_dir,sprintf('%03d.mat',index));
    fingerprint = input_fingerprint(local_trials);
    cached = struct();
    if isfile(path)
        try
            cached = load(path);
        catch issue
            warning('rppg:DamagedCheckpoint','Could not read checkpoint %d (%s).',index,issue.identifier);
        end
    end
    if isfield(cached,'key') && isfield(cached,'part') ...
            && isequaln(cached.key,{record,local_trials,fingerprint}) ...
            && height(cached.part.predictions) == height(local_trials)*5
        part = cached.part;
        action = "checkpoint";
    else
        if roi_fail && any(string(local_trials.roi_status) ~= "ok")
            part = failed_roi_predictions(local_trials, candidates, keys, base);
        else
            part = run_benchmark(local_trials,split,candidates, ...
                ShareSpatialExtraction=true,TraceFirstA=split == "final" && index == 1);
        end
        key = {record,local_trials,fingerprint};
        temporary = string(tempname(checkpoint_dir))+".mat";
        save(temporary,'key','part');
        movefile(temporary,path,'f');
        action = "evaluated";
    end
    if index == 1 && isfield(part,'trace')
        example = part.trace;
    end
    predictions = [predictions; part.predictions]; %#ok<AGROW>
    fprintf('%s %d/%d %s, elapsed %.1f s\n',split,index,numel(videos),action,toc(started));
end
trials_output = removevars(trials,'roi_boxes');
writetable(trials_output,fullfile(output_dir,'evaluated_manifest.csv'));
writetable(predictions(string(predictions.method) == "POS",:), ...
    fullfile(output_dir,'pooled_pos_predictions.csv'));
report = struct();
report.d_vs_pos = paired_pos(predictions);
writetable(report.d_vs_pos.pairs,fullfile(output_dir,'d_vs_pos_pairs.csv'));
writetable(report.d_vs_pos.metrics,fullfile(output_dir,'d_vs_pos_metrics.csv'));

if split == "final"
    primary.predictions = predictions(string(predictions.method) ~= "POS",:);
    [seen, which] = ismember(primary.predictions(:,keys),trials(:,keys));
    assert(all(seen),'rppg:UnexpectedPrediction','Each prediction must match its manifest interval.');
    primary.predictions.trial = trials.trial(which);
    if isempty(example)
        report.primary = write_final_report(primary,output_dir);
    else
        report.primary = write_final_report(primary,output_dir,example);
    end
    reference = trials(:,[keys, {'gt_bpm'}]);
    [report.repeats,report.within_subject_repeats] = repeat_metrics(primary.predictions,reference,base);
    writetable(report.repeats,fullfile(output_dir,'metrics_by_repeat.csv'));
    writetable(report.within_subject_repeats,fullfile(output_dir,'within_subject_repeats.csv'));
    [report.distance_gates,report.distance_range] = distance_metrics(report.primary.metrics,freeze.field_gates,base);
    writetable(report.distance_gates,fullfile(output_dir,'distance_gates.csv'));
    writetable(report.distance_range,fullfile(output_dir,'distance_range.csv'));
else
    plan = selection_plan();
    raw.predictions = predictions;
    score = score_selection_stage(raw,"tracking",plan);
    report.independent = independent_checks(score,freeze,plan);
    writetable(predictions(string(predictions.method) ~= "POS",:),fullfile(output_dir,'predictions.csv'));
    writetable(report.independent,fullfile(output_dir,'independent_gates.csv'));
    writetable(score.change_pairs,fullfile(output_dir,'change_pairs.csv'));
end
end

function assert_frozen_sources(root, commit, files)
paths = join("matlab/"+string(files)+".m"," ");
[status,~] = system(sprintf('git -C "%s" diff --quiet %s -- %s',root,commit,paths));
if status ~= 0
    error('rppg:UnpinnedSources', 'Algorithm and evaluation sources must match the frozen commit.');
end
end

function items = load_candidates(encoded, base)
if ~iscell(encoded)
    encoded = num2cell(encoded);
end
items = struct('name',{},'method',{},'overrides',{});
for index = 1:numel(encoded)
    item = encoded{index};
    items(index) = struct('name',string(item.name),'method',string(item.method),'overrides',item.overrides);
end
expected = ["A","B","C","D","POS"];
[seen,positions] = ismember(expected,string({items.method}));
if numel(items) ~= numel(expected) || ~all(seen) || numel(unique(string({items.name}))) ~= numel(items)
    error('rppg:InvalidFrozenCandidates','Lock exactly one named candidate for A, B, C, D and pooled POS.');
end
items = items(positions);
settings = repmat(base,numel(items),1);
settings(2).spatial_filter = 'median';
for index = 1:numel(items)
    names = fieldnames(items(index).overrides);
    for field = 1:numel(names)
        settings(index).(names{field}) = items(index).overrides.(names{field});
    end
end
shared = ["roi_tracker","ncc_min_corr","camshift_min_score","klt_min_points","klt_max_points", ...
    "klt_max_error_px","saturation_mode","bandpass_variant","bandpass_order","fft_chunk_s", ...
    "fft_window","fft_padding_factor","peak_method"];
for field = shared
    if ~all(arrayfun(@(s) isequaln(s.(field),settings(1).(field)),settings))
        error('rppg:ChangedCommonSetting','All methods need identical ROI and temporal settings.');
    end
end
if settings(4).pos_window_s ~= settings(5).pos_window_s
    error('rppg:InconsistentPosControl','D and pooled POS must share their POS window.');
end
end

function validate_cohort(trials, split, base)
subjects = unique(trials.subject_id);
if split == "final"
    mapping = trials(:,{'subject_id','distance_m','trial'});
    n_distances = numel(base.distances_m);
    if height(trials) ~= 54 || numel(subjects) ~= 3 ...
            || ~all(ismember(trials.distance_m,base.distances_m)) ...
            || ~all(ismember(trials.trial,1:3)) || height(unique(mapping)) ~= n_distances*9 ...
            || numel(unique(trials.video_id)) ~= 54 || numel(unique(trials.video_file)) ~= 54 ...
            || any(trials.start_s ~= 0 | trials.end_s ~= 60)
        error('rppg:IncompleteFieldCohort','Expected 54 original videos with all subject, repeat and distance combinations.');
    end
else
    plan = selection_plan();
    [~,~,group] = unique(trials.subject_id);
    counts = accumarray(group,1);
    if numel(subjects) ~= 14 || any(counts ~= size(plan.windows_s,1)) ...
            || height(unique(trials(:,{'subject_id','video_id','video_file'}))) ~= 14 ...
            || numel(unique(trials.video_id)) ~= 14 || numel(unique(trials.video_file)) ~= 14 ...
            || ~all(ismember([trials.start_s trials.end_s],plan.windows_s,'rows'))
        error('rppg:IncompleteIndependentCohort','Expected 14 held-out UBFC videos and all registered interval keys.');
    end
end
end

function signature = input_fingerprint(trials)
files = unique(trials.video_file);
if ismember('roi_motion_file',trials.Properties.VariableNames)
    files = [files; unique(string(trials.roi_motion_file))];
end
if ismember('frame_pts_csv',trials.Properties.VariableNames)
    files = [files; unique(string(trials.frame_pts_csv))];
end
files = files(~ismissing(files) & strlength(files) > 0);
signature = cell(numel(files),1);
for index = 1:numel(files)
    match = dir(files(index));
    signature{index} = {files(index),[match.bytes],[match.datenum]};
end
end

function report = failed_roi_predictions(trials,candidates,keys,base)
n = numel(candidates);
predictions = trials(repelem((1:height(trials))',n),:);
predictions.method = repmat(string({candidates.method})',height(trials),1);
predictions.candidate = repmat(string({candidates.name})',height(trials),1);
predictions.predicted_bpm = NaN(height(predictions),1);
predictions.status = repmat("failed",height(predictions),1);
predictions.failure_reason = string(predictions.roi_status);
predictions.quality = NaN(height(predictions),1);
predictions.roi_coverage_pct = NaN(height(predictions),1);
fields = {'video_id','subject_id','split','start_s','end_s','method','candidate', ...
    'predicted_bpm','status','failure_reason','quality','roi_coverage_pct'};
if ismember('reference_status',trials.Properties.VariableNames)
    fields = [fields,{'reference_status'}];
end
if ismember('distance_m',trials.Properties.VariableNames)
    fields = [fields,{'distance_m'}];
end
report = evaluate_results(predictions(:,fields),trials(:,[keys, {'gt_bpm'}]),base);
end

function result = paired_pos(predictions)
keys = {'video_id','subject_id','start_s','end_s'};
left = sortrows(predictions(predictions.method == "D",:),keys);
right = sortrows(predictions(predictions.method == "POS",:),keys);
assert(isequal(left(:,keys), right(:,keys)), 'rppg:UnpairedPosTrials', 'D and POS must use the same trials.');
pairs = left(:,keys);
if ismember('distance_m',left.Properties.VariableNames)
    pairs.distance_m = left.distance_m;
end
pairs.has_reference = left.has_reference;
pairs.d_valid = left.valid_estimate;
pairs.pos_valid = right.valid_estimate;
pairs.paired = pairs.has_reference & pairs.d_valid & pairs.pos_valid;
pairs.d_error_bpm = left.error_bpm;
pairs.pos_error_bpm = right.error_bpm;
pairs.d_abs_error_minus_pos_bpm = NaN(height(pairs),1);
common = pairs.paired;
pairs.d_abs_error_minus_pos_bpm(common) = abs(left.error_bpm(common)) - abs(right.error_bpm(common));
metrics = table();
distances = NaN;
if ismember('distance_m',pairs.Properties.VariableNames)
    distances = [NaN; unique(pairs.distance_m)];
end
windows = unique(pairs(:,{'start_s','end_s'}));
for window = 1:height(windows)
    for distance = distances'
        rows = pairs.start_s == windows.start_s(window) & pairs.end_s == windows.end_s(window);
        if isfinite(distance)
            rows = rows & pairs.distance_m == distance;
        end
        shared = rows & pairs.paired;
        row = table(windows.start_s(window),windows.end_s(window),distance,nnz(rows), ...
            nnz(rows & pairs.has_reference),nnz(rows & pairs.has_reference & pairs.d_valid), ...
            nnz(rows & pairs.has_reference & pairs.pos_valid),nnz(shared), ...
            mean(abs(pairs.d_error_bpm(shared))),mean(abs(pairs.pos_error_bpm(shared))), ...
            mean(pairs.d_abs_error_minus_pos_bpm(shared)), ...
            'VariableNames',{'start_s','end_s','distance_m','n_total','n_reference','n_d_usable', ...
            'n_pos_usable','n_paired','d_mae_bpm','pos_mae_bpm','paired_delta_mae_bpm'});
        metrics = [metrics; row]; %#ok<AGROW>
    end
end
result = struct('pairs',pairs,'metrics',metrics);
end

function [repeat, within] = repeat_metrics(predictions, reference, base)
repeat = table();
for pass = unique(predictions.trial)'
    evaluated = evaluate_results(predictions(predictions.trial == pass,:),reference,base);
    rows = addvars(evaluated.metrics,repmat(pass,height(evaluated.metrics),1), ...
        'Before','method','NewVariableNames','trial');
    repeat = [repeat; rows]; %#ok<AGROW>
end
keys = {'subject_id','distance_m','method','candidate'};
[within,~,group] = unique(predictions(:,keys));
within.n_total = accumarray(group,1);
within.n_paired = accumarray(group,predictions.valid_estimate & predictions.has_reference);
within.estimated_bpm_sd = NaN(height(within),1);
within.reference_bpm_sd = NaN(height(within),1);
within.error_bpm_sd = NaN(height(within),1);
for index = 1:height(within)
    paired = group == index & predictions.valid_estimate & predictions.has_reference;
    if nnz(paired) >= 2
        within.estimated_bpm_sd(index) = std(predictions.predicted_bpm(paired));
        within.reference_bpm_sd(index) = std(predictions.gt_bpm(paired));
        within.error_bpm_sd(index) = std(predictions.error_bpm(paired));
    end
end
end

function [checks, range] = distance_metrics(metrics,gate,base)
checks = sortrows(metrics(isfinite(metrics.distance_m),:),{'method','distance_m'});
checks.complete_trials = checks.n_total == gate.expected_trials;
checks.valid_pass = checks.n_valid >= gate.min_valid;
checks.paired_pass = checks.n_paired >= gate.min_paired;
checks.mae_pass = checks.MAE <= gate.max_mae_bpm;
checks.within_10_pass = checks.within_10_pct >= gate.min_within_10_pct;
checks.detection_pass = checks.complete_trials & checks.valid_pass;
checks.absolute_pass = checks.detection_pass & checks.paired_pass & checks.mae_pass & checks.within_10_pass;
checks.trend_status = repmat("not_assessed_on_stable_field_trials",height(checks),1);
range = unique(checks(:,{'method','candidate'}));
range.max_contiguous_absolute_m = NaN(height(range),1);
range.max_contiguous_detection_m = NaN(height(range),1);
range.isolated_absolute_passes_m = strings(height(range),1);
range.isolated_detection_passes_m = strings(height(range),1);
for index = 1:height(range)
    chosen = checks(checks.method == range.method(index),:);
    assert(isequal(chosen.distance_m,base.distances_m(:)), 'rppg:MissingDistance', 'All configured distances must be represented.');
    [range.max_contiguous_absolute_m(index),range.isolated_absolute_passes_m(index)] = ...
        contiguous_range(chosen.distance_m,chosen.absolute_pass);
    [range.max_contiguous_detection_m(index),range.isolated_detection_passes_m(index)] = ...
        contiguous_range(chosen.distance_m,chosen.detection_pass);
end
range.trend_status = repmat("not_assessed_on_stable_field_trials",height(range),1);
end

function [max_contiguous, isolated] = contiguous_range(distances, passes)
adjacent = cumprod(passes) == 1;
max_contiguous = NaN;
if any(adjacent)
    max_contiguous = max(distances(adjacent));
end
isolated = "";
isolated_values = distances(passes & ~adjacent);
if ~isempty(isolated_values)
    isolated = join(string(isolated_values), ";");
end
end

function checks = independent_checks(scored, freeze, plan)
checks = scored.metrics;
checks.n_reference_subjects = repmat(scored.n_reference_subjects,height(checks),1);
checks.n_reference_trend_pairs = repmat(scored.n_reference_trend_pairs,height(checks),1);
checks.reference_cohort_pass = repmat(scored.n_reference_subjects >= freeze.independent_min_reference_subjects ...
    & scored.n_reference_trend_pairs >= freeze.independent_min_reference_trend_pairs,height(checks),1);
checks.paired_pass = checks.n_paired >= freeze.independent_min_paired;
checks.mae_pass = checks.MAE <= plan.gate(1);
checks.error_sd_pass = checks.within_trial_error_sd_bpm <= plan.gate(2);
checks.delta_mae_pass = checks.delta_mae_bpm <= plan.gate(3);
checks.valid_rate_pass = checks.valid_rate_pct >= plan.gate(4);
checks.within_10_pass = checks.within_10_pct >= plan.gate(5);
checks.trend_coverage_pass = checks.trend_pair_rate_pct >= plan.min_paired_trend_rate_pct;
checks.passed = checks.reference_cohort_pass & checks.paired_pass & checks.mae_pass ...
    & checks.error_sd_pass & checks.delta_mae_pass & checks.valid_rate_pass ...
    & checks.within_10_pass & checks.trend_coverage_pass;
end
