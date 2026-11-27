function plan = selection_plan()
%SELECTION_PLAN Pre-registered development selection policy (revision 1).
plan.revision = 'selection-v1';
plan.windows_s = [0 30; 0 15; 15 30];
plan.min_reference_subjects = 18;
plan.min_reference_trend_pairs = 12;
plan.min_paired_subjects = 16;
plan.min_paired_trend_rate_pct = 70;
plan.tie_margin = 0.02;
plan.change_deadband_bpm = 2;
plan.metrics = ["MAE"; "within_trial_error_sd_bpm"; "delta_mae_bpm"; ...
    "valid_rate_pct"; "within_10_pct"];
plan.target = [5; 4; 3; 100; 90];
plan.unacceptable = [20; 16; 15; 60; 35];
plan.gate = [15; 12; 12; 85; 50];
plan.weights = [25 15 20 30 10; 25 25 30 15 5; 20 25 30 20 5; ...
    25 25 30 15 5; 35 20 25 15 5; 35 15 20 20 10; ...
    35 20 20 15 10; 25 25 25 20 5; 20 20 20 30 10; ...
    25 20 25 25 5; 25 25 30 15 5];
plan.stages = ["tracking"; "temporal"; "fft_length"; "window"; "peak"; ...
    "spatial"; "color"; "pos"; "sqi"; "fusion"; "interactions"];
end
