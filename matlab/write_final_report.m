function summary = write_final_report(report, output_dir, example)
%WRITE_FINAL_REPORT Export private evaluation tables and charts after the freeze.
% Give the result of run_benchmark(...,"final",frozen_candidates).
% Optional example is an already evaluated report with rgb_data and estimate.

predictions = report.predictions;
keys = {'video_id','start_s','end_s'};
required = [keys, {'method','candidate','split','subject_id','distance_m', ...
    'predicted_bpm','gt_bpm','status','failure_reason'}];
if isempty(predictions) || ~all(ismember(required, predictions.Properties.VariableNames))
    error('rppg:InvalidFinalReport', 'Final predictions need trial, method and reference fields.');
end
methods = ["A","B","C","D"];
predictions.method = string(predictions.method);
predictions.candidate = string(predictions.candidate);
predictions.subject_id = string(predictions.subject_id);
if any(~ismember(string(predictions.split), "final")) ...
        || any(~ismember(predictions.method, methods)) ...
        || any(ismissing(predictions.candidate) | strlength(strtrim(predictions.candidate)) == 0) ...
        || height(unique(predictions(:, {'method','candidate'}))) ~= numel(methods)
    error('rppg:InvalidFinalSelection', 'Expected the final split and one frozen candidate for each of A through D.');
end
if any(ismissing(predictions.subject_id) | strlength(strtrim(predictions.subject_id)) == 0) ...
        || any(~isfinite(predictions.distance_m) | predictions.distance_m <= 0)
    error('rppg:InvalidFinalAssignment', 'Every attempt needs a subject and positive finite distance.');
end

[trials, ~, trial_index] = unique(predictions(:, keys));
counts = accumarray(trial_index, 1);
[~, first_rows] = unique(trial_index, 'first');
trial_reference = predictions.gt_bpm(first_rows(trial_index));
same_reference = predictions.gt_bpm == trial_reference ...
    | (isnan(predictions.gt_bpm) & isnan(trial_reference));
if any(counts ~= numel(methods)) ...
        || height(unique(predictions(:, [keys, {'method'}]))) ~= height(predictions) ...
        || height(unique(predictions(:, [keys, {'subject_id','distance_m'}]))) ~= height(trials) ...
        || ~all(same_reference)
    error('rppg:IncompleteFinalTrials', 'Each trial needs four distinct method attempts with the same assignment and reference.');
end

settings = config();
if nargin < 2
    output_dir = fullfile(settings.result_dir, 'final-report');
end
settings.distances_m = unique(predictions.distance_m);
reference = predictions(first_rows, [keys, {'gt_bpm'}]);
evaluated = evaluate_results(predictions, reference, settings);
predictions = evaluated.predictions;
metrics = evaluated.metrics;

subject_metrics = table();
subjects = unique(predictions.subject_id);
for subject = subjects'
    selected = predictions.subject_id == subject;
    evaluated_subject = evaluate_results(predictions(selected,:), reference, settings);
    rows = addvars(evaluated_subject.metrics, repmat(subject, height(evaluated_subject.metrics), 1), ...
        'Before', 'method', 'NewVariableNames', 'subject_id');
    subject_metrics = [subject_metrics; rows]; %#ok<AGROW>
end

% Use exactly the same successful reference-backed attempts for all methods.
shared = splitapply(@all, predictions.valid_estimate & predictions.has_reference, trial_index);
common_metrics = metrics([],:);
if any(shared)
    common = evaluate_results(predictions(shared(trial_index), :), reference, settings);
    common_metrics = common.metrics;
end

failed = ~predictions.valid_estimate;
reason = string(predictions.failure_reason(failed));
reason(ismissing(reason) | strlength(strtrim(reason)) == 0) = "unspecified_estimation_failure";
failure_keys = predictions(failed, {'subject_id','distance_m','method','candidate'});
failures = count_by_reason(failure_keys, reason, "estimation_failure");

missing = ~predictions.has_reference;
missing_keys = predictions(missing, {'subject_id','distance_m','method','candidate'});
failures = [failures; count_by_reason(missing_keys, repmat("no_usable_reference", nnz(missing), 1), ...
    "reference_missing")];

if ~isfolder(output_dir)
    mkdir(output_dir);
end
writetable(predictions, fullfile(output_dir, 'final_predictions.csv'));
writetable(metrics, fullfile(output_dir, 'metrics_by_distance.csv'));
writetable(subject_metrics, fullfile(output_dir, 'metrics_by_subject_distance.csv'));
writetable(common_metrics, fullfile(output_dir, 'metrics_common_valid.csv'));
writetable(failures, fullfile(output_dir, 'failure_breakdown.csv'));
write_metric_plots(metrics, settings.distances_m, methods, output_dir);
if nargin >= 3
    write_signal_plot(example, output_dir);
end
summary = struct('metrics', metrics, 'subject_metrics', subject_metrics, ...
    'common_metrics', common_metrics, 'failures', failures);
end

function counts = count_by_reason(keys, reasons, issue)
keys.reason = reasons;
[counts, ~, group] = unique(keys);
counts.issue = repmat(issue, height(counts), 1);
counts.n_attempts = accumarray(group, 1, [height(counts), 1]);
end

function write_metric_plots(metrics, distances, methods, output_dir)
overall = metrics(isnan(metrics.distance_m), :);
[~, indices] = ismember(methods, overall.method);
overall = overall(indices, :);
fig = figure('Visible', 'off', 'Color', 'w');
close_figure = onCleanup(@() close(fig)); %#ok<NASGU>
layout = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact');
ax = nexttile(layout);
bar(ax, [overall.MAE, overall.RMSE]);
set(ax, 'XTick', 1:numel(methods), 'XTickLabel', methods);
ylabel(ax, 'Error (BPM)');
title(ax, 'Heart rate error on paired estimates');
legend(ax, {'MAE','RMSE'}, 'Location', 'best');
grid(ax, 'on');
ax = nexttile(layout);
bar(ax, overall.valid_rate_pct);
set(ax, 'XTick', 1:numel(methods), 'XTickLabel', methods);
ylim(ax, [0 105]);
xlabel(ax, 'Method');
ylabel(ax, 'Valid estimates (%)');
title(ax, 'Valid estimates out of all attempts');
grid(ax, 'on');
exportgraphics(fig, fullfile(output_dir, 'performance_by_method.png'), 'Resolution', 160);

fig_distance = figure('Visible', 'off', 'Color', 'w');
close_distance = onCleanup(@() close(fig_distance)); %#ok<NASGU>
layout = tiledlayout(fig_distance, 2, 1, 'TileSpacing', 'compact');
error_axis = nexttile(layout);
coverage_axis = nexttile(layout);
hold(error_axis, 'on');
hold(coverage_axis, 'on');
for method = methods
    rows = metrics(metrics.method == method & isfinite(metrics.distance_m), :);
    rows = sortrows(rows, 'distance_m');
    plot(error_axis, rows.distance_m, rows.MAE, 'o-', 'LineWidth', 1.4, 'DisplayName', method);
    plot(coverage_axis, rows.distance_m, rows.valid_rate_pct, 'o-', ...
        'LineWidth', 1.4, 'DisplayName', method);
end
xticks(error_axis, distances');
xticks(coverage_axis, distances');
ylabel(error_axis, 'MAE (BPM)');
title(error_axis, 'Paired error by distance');
legend(error_axis, 'Location', 'best');
grid(error_axis, 'on');
ylim(coverage_axis, [0 105]);
xlabel(coverage_axis, 'Distance (m)');
ylabel(coverage_axis, 'Valid estimates (%)');
title(coverage_axis, 'Valid estimates by distance');
grid(coverage_axis, 'on');
exportgraphics(fig_distance, fullfile(output_dir, 'performance_by_distance.png'), 'Resolution', 160);
end

function write_signal_plot(example, output_dir)
rgb = example.rgb_data;
est = example.estimate;
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 780 900]);
close_figure = onCleanup(@() close(fig)); %#ok<NASGU>
layout = tiledlayout(fig, size(rgb.raw_rgb, 3) + 2, 1, 'TileSpacing', 'compact');
colors = [0.79 0.15 0.20; 0.08 0.53 0.27; 0.13 0.37 0.75];
for roi = 1:size(rgb.raw_rgb, 3)
    ax = nexttile(layout);
    colororder(ax, colors);
    plot(ax, rgb.time_s, rgb.raw_rgb(:,:,roi));
    title(ax, sprintf('ROI %d raw RGB', roi));
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Intensity');
    if roi == 1
        legend(ax, {'R','G','B'}, 'Location', 'best');
    end
    grid(ax, 'on');
end
ax = nexttile(layout);
if ~isempty(est.filtered)
    plot(ax, est.time_s, est.filtered, 'LineWidth', 1);
else
    text(ax, 0.5, 0.5, 'Processed signal unavailable', 'HorizontalAlignment', 'center');
end
title(ax, 'Processed signal');
xlabel(ax, 'Time (s)');
grid(ax, 'on');
ax = nexttile(layout);
if ~isempty(est.power)
    plot(ax, est.frequency_hz, est.power, 'LineWidth', 1);
else
    text(ax, 0.5, 0.5, 'Spectrum unavailable', 'HorizontalAlignment', 'center');
end
title(ax, 'FFT spectrum');
xlabel(ax, 'Frequency (Hz)');
ylabel(ax, 'Power');
grid(ax, 'on');
exportgraphics(fig, fullfile(output_dir, 'example_signal.png'), 'Resolution', 160);
end
