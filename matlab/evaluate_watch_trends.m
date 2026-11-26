function report = evaluate_watch_trends(predictions, reference, rules)
%EVALUATE_WATCH_TRENDS Compare BPM changes on matched windows with new watch observations.
% rules requires lag_s, deadband_bpm, min_watch_samples, max_watch_gap_s,
% and max_alignment_uncertainty_s. Choose these before evaluating holdouts.
% predictions is the windowed output of evaluate_results; reference is from
% align_watch_reference. This evaluates change magnitude and direction.

validateattributes(rules.lag_s, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(rules.deadband_bpm, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(rules.min_watch_samples, {'numeric'}, {'scalar','finite','integer','positive'});
validateattributes(rules.max_watch_gap_s, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(rules.max_alignment_uncertainty_s, {'numeric'}, {'scalar','real','finite','nonnegative'});

keys = {'video_id','start_s','end_s'};
groups = {'method','candidate'};
windows = predictions(:, [keys, groups]);
windows.video_id = string(windows.video_id);
windows.method = string(windows.method);
windows.candidate = string(windows.candidate);
windows.start_s = round(windows.start_s, 6);
windows.end_s = round(windows.end_s, 6);
reference.video_id = string(reference.video_id);
reference.start_s = round(reference.start_s, 6);
reference.end_s = round(reference.end_s, 6);
if height(unique(windows)) ~= height(windows) || height(unique(reference(:,keys))) ~= height(reference)
    error('rppg:DuplicateTrendKeys', 'Trend window keys must be unique to a microsecond.');
end
if round(rules.lag_s, 6) == 0
    error('rppg:InvalidTrendLag', 'The lag must be at least one microsecond.');
end
earlier = windows;
earlier.start_s = round(windows.start_s - rules.lag_s, 6);
earlier.end_s = round(windows.end_s - rules.lag_s, 6);
[has_earlier, earlier_rows] = ismember(earlier, windows);
[has_ref, ref_rows] = ismember(windows(:, keys), reference(:, keys));
eligible = false(height(windows), 1);
in_ref = ref_rows(has_ref);
eligible(has_ref) = reference.reference_status(in_ref) == "ok" ...
    & reference.n_watch_samples(in_ref) >= rules.min_watch_samples ...
    & reference.max_watch_gap_s(in_ref) <= min(rules.lag_s, rules.max_watch_gap_s) ...
    & reference.alignment_uncertainty_s(in_ref) <= min(rules.lag_s, rules.max_alignment_uncertainty_s);

current = find(has_earlier);
prior = earlier_rows(current);
details = windows(current, :);
details.previous_start_s = windows.start_s(prior);
details.previous_end_s = windows.end_s(prior);
details.has_reference = eligible(current) & eligible(prior);
rows = find(details.has_reference);
current_refs = ref_rows(current(rows));
prior_refs = ref_rows(prior(rows));
% Moving windows may carry the same last watch reading. Such a pair has
% no new reference observation, even if both window means are finite.
details.reference_status = repmat("insufficient_watch_coverage", height(details), 1);
details.reference_status(rows) = "no_new_watch_observation";
details.has_reference(rows) = reference.last_watch_s(current_refs) > reference.last_watch_s(prior_refs);
details.reference_status(details.has_reference) = "ok";
details.valid_estimate = predictions.valid_estimate(current) & predictions.valid_estimate(prior);
details.reference_delta_bpm = NaN(height(details), 1);
details.predicted_delta_bpm = NaN(height(details), 1);
rows = find(details.has_reference);
details.reference_delta_bpm(rows) = reference.gt_bpm(ref_rows(current(rows))) ...
    - reference.gt_bpm(ref_rows(prior(rows)));
rows = find(details.valid_estimate);
details.predicted_delta_bpm(rows) = predictions.predicted_bpm(current(rows)) ...
    - predictions.predicted_bpm(prior(rows));
details.delta_error_bpm = details.predicted_delta_bpm - details.reference_delta_bpm;

metrics = unique(windows(:,groups));
metrics.n_pairs = zeros(height(metrics), 1);
metrics.n_reference = zeros(height(metrics), 1);
metrics.n_paired = zeros(height(metrics), 1);
metrics.delta_mae_bpm = NaN(height(metrics), 1);
metrics.direction_agreement_pct = NaN(height(metrics), 1);
for index = 1:height(metrics)
    candidate = details.method == metrics.method(index) & details.candidate == metrics.candidate(index);
    paired = candidate & details.valid_estimate & details.has_reference;
    metrics.n_pairs(index) = nnz(candidate);
    metrics.n_reference(index) = nnz(candidate & details.has_reference);
    metrics.n_paired(index) = nnz(paired);
    metrics.delta_mae_bpm(index) = mean(abs(details.delta_error_bpm(paired)));
    predicted = details.predicted_delta_bpm(paired);
    observed = details.reference_delta_bpm(paired);
    predicted_direction = sign(predicted) .* (abs(predicted) > rules.deadband_bpm);
    observed_direction = sign(observed) .* (abs(observed) > rules.deadband_bpm);
    metrics.direction_agreement_pct(index) = 100 * mean(predicted_direction == observed_direction);
end
report = struct('pairs', details, 'metrics', metrics, 'rules', rules);
end
