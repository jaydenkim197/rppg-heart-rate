function report = evaluate_results(predictions, ground_truth, settings)
%EVALUATE_RESULTS GT를 연결하고 성공률, 오차, 두 방법 간 대응 비교를 저장한다.

[has_row, index] = ismember(predictions.video_id, ground_truth.video_id);
rows = find(has_row);
predictions.gt_bpm = NaN(height(predictions), 1);
predictions.gt_status = repmat("missing", height(predictions), 1);
predictions.gt_reason = repmat("no_watch_reference", height(predictions), 1);
predictions.gt_samples = NaN(height(predictions), 1);
predictions.gt_bpm(rows) = ground_truth.gt_bpm(index(rows));
predictions.gt_status(rows) = ground_truth.gt_status(index(rows));
predictions.gt_reason(rows) = ground_truth.gt_reason(index(rows));
predictions.gt_samples(rows) = ground_truth.gt_samples(index(rows));

valid = predictions.status == "ok" & isfinite(predictions.predicted_bpm);
comparable = valid & predictions.gt_status == "ok" & isfinite(predictions.gt_bpm);
predictions.absolute_error_bpm = NaN(height(predictions), 1);
predictions.absolute_error_bpm(comparable) = abs( ...
    predictions.predicted_bpm(comparable) - predictions.gt_bpm(comparable));

methods = string(settings.methods(:));
distances = settings.distances_m(:);
num_methods = numel(methods);
totals = NaN(num_methods, 7);
by_distance = NaN(numel(distances) * num_methods, 7);
for method_index = 1:num_methods
    method_rows = predictions.method == methods(method_index);
    totals(method_index, :) = metrics(method_rows, valid, predictions.absolute_error_bpm);
    for distance_index = 1:numel(distances)
        selection = method_rows & predictions.distance_m == distances(distance_index);
        row = (method_index - 1) * numel(distances) + distance_index;
        by_distance(row, :) = metrics(selection, valid, predictions.absolute_error_bpm);
    end
end

columns = {'n_trials', 'n_valid', 'n_failed', 'n_compared', ...
    'mae_bpm', 'rmse_bpm', 'valid_rate_pct'};
overall = [table(methods, 'VariableNames', {'method'}), array2table(totals, 'VariableNames', columns)];
distance_table = table(repelem(methods, numel(distances)), repmat(distances, num_methods, 1), ...
    'VariableNames', {'method', 'distance_m'});
distance_table = [distance_table, array2table(by_distance, 'VariableNames', columns)];

report.trials = predictions;
report.by_method = overall;
report.by_distance = distance_table;
report.paired = pair_methods(predictions, comparable);
report.failures = predictions(~valid, :);

writetable(report.trials, fullfile(settings.result_dir, 'predictions.csv'));
writetable(report.by_method, fullfile(settings.result_dir, 'metrics_by_method.csv'));
writetable(report.by_distance, fullfile(settings.result_dir, 'metrics_by_distance.csv'));
writetable(report.paired, fullfile(settings.result_dir, 'paired_methods.csv'));
writetable(report.failures, fullfile(settings.result_dir, 'failed_trials.csv'));
save_summary_plots(report, settings);
end

function row = metrics(selection, valid, absolute_errors)
num_trials = nnz(selection);
num_valid = nnz(selection & valid);
errors = absolute_errors(selection & isfinite(absolute_errors));
mae = NaN;
rmse = NaN;
rate = NaN;
if ~isempty(errors)
    mae = mean(errors);
    rmse = sqrt(mean(errors .^ 2));
end
if num_trials > 0
    rate = 100 * num_valid / num_trials;
end
row = [num_trials, num_valid, num_trials - num_valid, numel(errors), mae, rmse, rate];
end

function paired = pair_methods(predictions, comparable)
reference_methods = ["A"; "A"; "A"; "POS"];
tested_methods = ["B"; "C"; "D"; "D"];
n_shared = zeros(numel(tested_methods), 1);
reference_mae = NaN(size(n_shared));
tested_mae = NaN(size(n_shared));
for index = 1:numel(tested_methods)
    reference = predictions(comparable & predictions.method == reference_methods(index), :);
    tested = predictions(comparable & predictions.method == tested_methods(index), :);
    [common, ref_rows, test_rows] = intersect(reference.video_id, tested.video_id);
    n_shared(index) = numel(common);
    if ~isempty(common)
        reference_mae(index) = mean(reference.absolute_error_bpm(ref_rows));
        tested_mae(index) = mean(tested.absolute_error_bpm(test_rows));
    end
end
delta_mae = tested_mae - reference_mae;
paired = table(reference_methods, tested_methods, n_shared, reference_mae, tested_mae, delta_mae, ...
    'VariableNames', {'reference_method', 'tested_method', 'n_shared', ...
    'reference_mae_bpm', 'tested_mae_bpm', 'delta_mae_bpm'});
end

function save_summary_plots(report, settings)
figure_handle = figure('Visible', 'off', 'Color', 'white', 'Position', [50, 50, 960, 460]);
cleanup = onCleanup(@() close(figure_handle)); %#ok<NASGU>
axes_handle = axes(figure_handle);
overall = report.by_method;
bar(axes_handle, 1:height(overall), overall.mae_bpm);
set(axes_handle, 'XTick', 1:height(overall), 'XTickLabel', cellstr(overall.method));
ylabel(axes_handle, 'MAE (BPM)');
title(axes_handle, 'Mean absolute error by method');
grid(axes_handle, 'on');
if ~any(isfinite(overall.mae_bpm))
    text(axes_handle, 0.5, 0.5, 'No paired smartwatch results', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center');
end
exportgraphics(figure_handle, fullfile(settings.result_dir, 'method_mae.png'), 'Resolution', 150);

columns = {'mae_bpm', 'valid_rate_pct'};
titles = {'Mean absolute error by distance', 'Valid estimates by distance'};
labels = {'MAE (BPM)', 'Valid estimation rate (%)'};
names = {'distance_mae.png', 'distance_valid_rate.png'};
limits = {[0, Inf], [0, 105]};
for plot_index = 1:numel(columns)
    cla(axes_handle, 'reset');
    hold(axes_handle, 'on');
    found_data = false;
    for method_index = 1:numel(settings.methods)
        name = settings.methods{method_index};
        row = report.by_distance.method == string(name);
        values = report.by_distance.(columns{plot_index});
        plot(axes_handle, report.by_distance.distance_m(row), values(row), '-o', ...
            'LineWidth', 1.4, 'DisplayName', name);
        found_data = found_data || any(isfinite(values(row)));
    end
    set(axes_handle, 'XTick', settings.distances_m);
    xlim(axes_handle, [min(settings.distances_m) - 0.2, max(settings.distances_m) + 0.2]);
    ylim(axes_handle, limits{plot_index});
    xlabel(axes_handle, 'Camera distance (m)');
    ylabel(axes_handle, labels{plot_index});
    title(axes_handle, titles{plot_index});
    grid(axes_handle, 'on');
    legend(axes_handle, 'Location', 'best');
    if ~found_data
        text(axes_handle, 0.5, 0.5, 'No results with distance and required data', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    exportgraphics(figure_handle, fullfile(settings.result_dir, names{plot_index}), 'Resolution', 150);
end
end
