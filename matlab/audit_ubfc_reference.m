function audit = audit_ubfc_reference(trials, reference_root, output_dir)
%AUDIT_UBFC_REFERENCE Run preregistered contact quality audit on UBFC development.
% trials is the frozen one-row-per-video [0,30) development manifest.

if height(trials) ~= 28 || numel(unique(string(trials.subject_id))) ~= 28 ...
        || any(string(trials.split) ~= "development") ...
        || any(trials.start_s ~= 0 | trials.end_s ~= 30)
    error('rppg:InvalidUbfcAuditCohort', 'Use the 28 full-window development trials only.');
end
first = trials;
first.end_s(:) = 15;
second = trials;
second.start_s(:) = 15;
nominal = build_ubfc_reference_table([trials; first; second], reference_root, "development");
width_s = nominal.end_s - nominal.start_s;
full = width_s == 30;
left = nominal.start_s == 0 & width_s == 15;
right = nominal.start_s == 15 & width_s == 15;
earlier = nominal(left, :);
later = nominal(right, :);
[paired_video, paired_index] = ismember(earlier.video_id, later.video_id);
assert(all(paired_video), 'Every planned video has two reference windows.');
later = later(paired_index, :);
delta = table(earlier.subject_id, earlier.video_id, earlier.gt_bpm, later.gt_bpm, ...
    later.gt_bpm - earlier.gt_bpm, earlier.reference_status, later.reference_status, ...
    'VariableNames', {'subject_id','video_id','first_bpm','second_bpm','delta_bpm', ...
    'first_reference_status','second_reference_status'});

agreement_threshold = [3; 5; 8];
valid_full = zeros(size(agreement_threshold));
valid_half = valid_full;
valid_pairs = valid_full;
comparable = ismember(nominal.reference_status, ["ok", "reference_estimators_disagree"]);
for row = 1:numel(agreement_threshold)
    accepted = comparable & nominal.agreement_bpm <= agreement_threshold(row);
    valid_full(row) = nnz(accepted & full);
    valid_half(row) = nnz(accepted & width_s == 15);
    accepted_first = accepted(left);
    accepted_second = accepted(right);
    valid_pairs(row) = nnz(accepted_first & accepted_second(paired_index));
end
sensitivity = table(agreement_threshold, valid_full, valid_half, valid_pairs, ...
    'VariableNames', {'agreement_limit_bpm','valid_full','valid_halves','valid_delta_pairs'});

center = trials;
center.start_s(:) = 0.1;
center.end_s(:) = 29.9;
early = center;
early.start_s(:) = 0;
early.end_s(:) = 29.8;
late = center;
late.start_s(:) = 0.2;
late.end_s(:) = 30;
middle_reference = build_ubfc_reference_table(center, reference_root, "development");
early_reference = build_ubfc_reference_table(early, reference_root, "development");
late_reference = build_ubfc_reference_table(late, reference_root, "development");
relative_start_shift_s = [-0.1; 0.1];
valid_shifted = zeros(2, 1);
pairs_with_center = zeros(2, 1);
median_abs_shift_bpm = NaN(2,1);
max_abs_shift_bpm = NaN(2,1);
shifted = {early_reference, late_reference};
for row = 1:2
    comparisons = abs(shifted{row}.gt_bpm - middle_reference.gt_bpm);
    valid_shifted(row) = nnz(isfinite(shifted{row}.gt_bpm));
    paired = comparisons(isfinite(comparisons));
    pairs_with_center(row) = numel(paired);
    median_abs_shift_bpm(row) = median(paired);
    if ~isempty(paired)
        max_abs_shift_bpm(row) = max(paired);
    end
end
timing = table(relative_start_shift_s, valid_shifted, pairs_with_center, ...
    median_abs_shift_bpm, max_abs_shift_bpm);
pass = nnz(isfinite(nominal.gt_bpm(full))) >= 18 && nnz(isfinite(delta.delta_bpm)) >= 12;
audit = struct('windows',nominal, 'delta',delta, 'agreement_sensitivity',sensitivity, ...
    'timing_sensitivity',timing, 'passed_reference_cohort',pass);
if nargin == 3
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end
    writetable(nominal, fullfile(output_dir, 'reference_windows.csv'));
    writetable(delta, fullfile(output_dir, 'reference_delta.csv'));
    writetable(sensitivity, fullfile(output_dir, 'agreement_sensitivity.csv'));
    writetable(timing, fullfile(output_dir, 'timing_sensitivity.csv'));
end
end
