function results = compare_development_stages(seed, reference, stages, output_root)
%COMPARE_DEVELOPMENT_STAGES Run selected development stages and preserve gated progression.
% seed is one row per UBFC development video with pre-registered initial ROI.
if any(string(seed.split) ~= "development") || any(string(reference.split) ~= "development")
    error('rppg:HoldoutSelection', 'This comparison accepts development rows only.');
end
plan = selection_plan();
stages = string(stages(:)');
if isempty(stages) || ~all(ismember(stages,plan.stages(1:end-1))) ...
        || numel(unique(stages)) ~= numel(stages)
    error('rppg:InvalidSelectionStages', 'Choose distinct registered individual stages.');
end
keys = {'video_id','start_s','end_s'};
if height(unique(reference(:,keys))) ~= height(reference)
    error('rppg:DuplicateReference', 'Each reference window must have a unique key.');
end
n = size(plan.windows_s,1);
trials = seed(repelem((1:height(seed))',n),:);
trials.start_s = repmat(plan.windows_s(:,1),height(seed),1);
trials.end_s = repmat(plan.windows_s(:,2),height(seed),1);
trials.tracking_start_s = repmat(min(plan.windows_s(:,1)),height(trials),1);
trials.tracking_end_s = repmat(max(plan.windows_s(:,2)),height(trials),1);
trials.video_id = string(trials.video_id);
reference.video_id = string(reference.video_id);
[found,index] = ismember(trials(:,keys),reference(:,keys));
if ~all(found)
    error('rppg:ReferenceCoverageUnknown', 'Every attempted window must have a reference status row.');
end
trials.gt_bpm = reference.gt_bpm(index);
trials.reference_status = reference.reference_status(index);
if ~isfolder(output_root)
    mkdir(output_root);
end
inherited = struct();
results = table();
can_promote = true;
for count = 1:numel(stages)
    stage = stages(count);
    planned_index = find(plan.stages == stage);
    can_promote = can_promote && planned_index == count;
    candidates = development_candidates(stage,inherited);
    dir_path = fullfile(output_root,stage);
    fprintf('Starting %s (%d candidates)\n',stage,numel(candidates));
    raw = run_benchmark(trials,"development",candidates,dir_path);
    score = score_selection_stage(raw,stage,plan);
    writetable(score.ranking.ranking, fullfile(dir_path,'ranking.csv'));
    writetable(score.common_metrics, fullfile(dir_path,'common_metrics.csv'));
    writetable(score.change_pairs, fullfile(dir_path,'change_pairs.csv'));
    % A stage may show an eligible result while required comparisons remain unavailable.
    incomplete = any(strlength(string({candidates.unavailable_reason})) > 0);
    state = score.ranking.state;
    if state == "tie"
        ties = score.ranking.ranking;
        near = ties.eligible & ties.score >= ties.score(1)-plan.tie_margin;
        baseline = find_baseline(candidates,inherited);
        if strlength(baseline) > 0 && any(ties.candidate(near) == baseline)
            score.ranking.selected = baseline;
            state = "retained_baseline";
        end
    end
    selected = score.ranking.selected;
    adopted = "";
    if can_promote && ~incomplete && strlength(selected) > 0
        winner = candidates(string({candidates.name}) == selected);
        adopted = selected;
        % Common stages supply shared ROI/time settings. B, C and D are independent paths.
        if planned_index <= 5 || planned_index >= 8
            inherited = winner.overrides;
        end
    elseif incomplete
        state = "incomplete_candidate_set";
    elseif ~can_promote
        state = "exploratory_" + state;
    end
    results = [results; table(stage,state,selected,adopted,score.n_reference_subjects, ...
        score.n_reference_trend_pairs, 'VariableNames', ...
        {'stage','state','leading_eligible','adopted','n_reference_subjects','n_reference_changes'})]; %#ok<AGROW>
    can_promote = can_promote && strlength(adopted) > 0;
    writetable(results,fullfile(output_root,'stage_status.csv'));
    fprintf('%s: %s, adopted "%s"\n',stage,state,adopted);
end
end

function name = find_baseline(candidates,inherited)
name = "";
for index = 1:numel(candidates)
    if isequal(candidates(index).overrides, inherited)
        name = string(candidates(index).name);
        return
    end
end
end
