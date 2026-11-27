function report = score_selection_stage(raw, stage, plan)
%SCORE_SELECTION_STAGE Score whole-window errors and paired within-video changes.
prediction = raw.predictions;
windows = plan.windows_s;
main = prediction.start_s == windows(1,1) & prediction.end_s == windows(1,2);
left = prediction.start_s == windows(2,1) & prediction.end_s == windows(2,2);
right = prediction.start_s == windows(3,1) & prediction.end_s == windows(3,2);
keys = {'video_id','subject_id','method','candidate'};
first = sortrows(prediction(left,:), keys);
second = sortrows(prediction(right,:), keys);
if isempty(first) || ~isequal(first(:,keys),second(:,keys)) ...
        || height(unique(first(:,keys))) ~= height(first)
    error('rppg:UnmatchedTrendWindows', 'All candidates need the same two windows for each video.');
end

whole = prediction(main,:);
[~,first_key] = unique(whole(:,{'video_id','start_s','end_s'}));
whole_reference = whole(first_key, {'video_id','start_s','end_s','gt_bpm'});
report = evaluate_results(prediction(main,:), whole_reference, config());
roi = report.metrics;
pair_reference = first.has_reference & second.has_reference;
pair_valid = pair_reference & first.valid_estimate & second.valid_estimate;
prediction_change = second.predicted_bpm-first.predicted_bpm;
reference_change = second.gt_bpm-first.gt_bpm;
report.change_pairs = first(:,keys);
report.change_pairs.has_reference = pair_reference;
report.change_pairs.valid_pair = pair_valid;
report.change_pairs.predicted_delta_bpm = prediction_change;
report.change_pairs.reference_delta_bpm = reference_change;
report.change_pairs.delta_error_bpm = prediction_change-reference_change;
report.change_pairs.left_failure = first.failure_reason;
report.change_pairs.right_failure = second.failure_reason;
report.n_reference_subjects = numel(unique(prediction.subject_id(main & prediction.has_reference)));
report.n_reference_trend_pairs = height(unique(first(pair_reference, {'video_id','subject_id'})));
roi.within_trial_error_sd_bpm = NaN(height(roi),1);
roi.delta_mae_bpm = NaN(height(roi),1);
roi.trend_pair_rate_pct = NaN(height(roi),1);
roi.direction_agreement_pct = NaN(height(roi),1);
roi.n_trend_reference = zeros(height(roi),1);
roi.n_trend_paired = zeros(height(roi),1);
for index = 1:height(roi)
    group = first.method == roi.method(index) & first.candidate == roi.candidate(index);
    paired = group & pair_valid;
    delta_error = prediction_change(paired)-reference_change(paired);
    roi.within_trial_error_sd_bpm(index) = sqrt(mean(delta_error.^2)/2);
    roi.delta_mae_bpm(index) = mean(abs(delta_error));
    roi.n_trend_reference(index) = nnz(group & pair_reference);
    roi.n_trend_paired(index) = nnz(paired);
    if roi.n_trend_reference(index) > 0
        roi.trend_pair_rate_pct(index) = 100*nnz(paired)/roi.n_trend_reference(index);
    end
    predicted = prediction_change(paired);
    observed = reference_change(paired);
    roi.direction_agreement_pct(index) = 100*mean( ...
        sign(predicted).*(abs(predicted)>plan.change_deadband_bpm) == ...
        sign(observed).*(abs(observed)>plan.change_deadband_bpm));
end
report.metrics = roi;

stage_index = find(plan.stages == stage,1);
if isempty(stage_index)
    error('rppg:UnknownSelectionStage', 'Use a pre-registered stage.');
end
criteria = table([plan.metrics;"trend_pair_rate_pct"], [plan.target;100], ...
    [plan.unacceptable;0], [plan.weights(stage_index,:)';0], ...
    [plan.gate;plan.min_paired_trend_rate_pct], ...
    'VariableNames', {'metric','target','unacceptable','weight','gate'});
report.ranking = rank_candidates(report, criteria, plan.min_paired_subjects, plan.tie_margin);
if report.n_reference_subjects < plan.min_reference_subjects ...
        || report.n_reference_trend_pairs < plan.min_reference_trend_pairs
    report.ranking.state = "reference_gate_failed";
    report.ranking.selected = "";
end

all_main = report.predictions;
usable = roi.candidate(roi.n_paired > 0);
matched = all_main(ismember(all_main.candidate,usable),:);
pairs = matched.valid_estimate & matched.has_reference;
[~,~,trial_groups] = unique(matched(:, {'video_id','start_s','end_s'}));
common = false(height(matched),1);
if ~isempty(trial_groups)
    complete = splitapply(@all,pairs,trial_groups);
    common = complete(trial_groups);
end
report.common_metrics = roi([],:);
if any(common)
    paired = evaluate_results(matched(common,:), whole_reference, config());
    report.common_metrics = paired.metrics;
end
end
