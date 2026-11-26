function summary = evaluate_results(predictions, ground_truth, settings)
%EVALUATE_RESULTS Evaluate all attempts and distinguish missing reference data.

required = {'video_id', 'method', 'predicted_bpm', 'status', 'failure_reason'};
if ~all(ismember(required, predictions.Properties.VariableNames)) ...
        || ~all(ismember({'video_id', 'gt_bpm'}, ground_truth.Properties.VariableNames))
    error('rppg:InvalidEvaluationTables', 'Prediction or reference fields are missing.');
end
predictions.video_id = string(predictions.video_id);
ground_truth.video_id = string(ground_truth.video_id);
predictions.method = string(predictions.method);
interval_names = {'start_s', 'end_s'};
has_prediction_window = any(ismember(interval_names, predictions.Properties.VariableNames));
has_reference_window = any(ismember(interval_names, ground_truth.Properties.VariableNames));
key = {'video_id'};
if has_prediction_window || has_reference_window
    if ~all(ismember(interval_names, predictions.Properties.VariableNames)) ...
            || ~all(ismember(interval_names, ground_truth.Properties.VariableNames))
        error('rppg:ReferenceIntervalMissing', 'Both tables must use the same interval fields.');
    end
    key = [key, interval_names];
end
[distinct, ~] = unique(ground_truth(:, key));
if height(distinct) ~= height(ground_truth)
    error('rppg:DuplicateReference', 'Reference keys must be unique.');
end
[found, rows] = ismember(predictions(:, key), ground_truth(:, key));
predictions.gt_bpm = NaN(height(predictions), 1);
predictions.gt_bpm(found) = ground_truth.gt_bpm(rows(found));
valid = string(predictions.status) == "ok" & isfinite(predictions.predicted_bpm);
has_reference = isfinite(predictions.gt_bpm) & predictions.gt_bpm > 0;
paired = valid & has_reference;
errors = NaN(height(predictions), 1);
errors(paired) = predictions.predicted_bpm(paired) - predictions.gt_bpm(paired);
predictions.error_bpm = errors;
predictions.valid_estimate = valid;
predictions.has_reference = has_reference;
if ~ismember('candidate', predictions.Properties.VariableNames)
    predictions.candidate = repmat("baseline", height(predictions), 1);
end
predictions.candidate = string(predictions.candidate);
groups = unique(predictions(:, {'method', 'candidate'}));
metrics = table();
distances = NaN;
if ismember('distance_m', predictions.Properties.VariableNames)
    distances = [NaN; settings.distances_m(:)];
end
for index = 1:height(groups)
    group_rows = predictions.method == groups.method(index) ...
        & predictions.candidate == groups.candidate(index);
    for d = distances'
        chosen = group_rows;
        if isfinite(d)
            chosen = chosen & predictions.distance_m == d;
        end
        if ~any(chosen)
            continue
        end
        combined = chosen & paired;
        e = errors(combined);
        error_sd = NaN;
        if numel(e) >= 2
            error_sd = std(e);
        end
        ref_count = nnz(chosen & has_reference);
        within5 = NaN;
        within10 = NaN;
        if ref_count > 0
            within5 = 100 * nnz(abs(e) <= 5) / ref_count;
            within10 = 100 * nnz(abs(e) <= 10) / ref_count;
        end
        row = table(groups.method(index), groups.candidate(index), d, nnz(chosen), ...
            nnz(chosen & valid), nnz(combined), nnz(chosen & ~has_reference), ...
            mean(abs(e)), sqrt(mean(e.^2)), mean(e), error_sd, ...
            100 * nnz(chosen & valid) / nnz(chosen), within5, within10, ...
            'VariableNames', {'method', 'candidate', 'distance_m', 'n_total', ...
            'n_valid', 'n_paired', 'n_reference_missing', 'MAE', 'RMSE', 'bias', 'error_sd_bpm', ...
            'valid_rate_pct', 'within_5_pct', 'within_10_pct'});
        metrics = [metrics; row]; %#ok<AGROW>
    end
end
summary = struct('predictions', predictions, 'metrics', metrics);
end
