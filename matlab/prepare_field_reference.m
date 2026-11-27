function reference = prepare_field_reference(input_dir, options)
%PREPARE_FIELD_REFERENCE Align local intake CSVs without promoting draft HR.
% Run after tools/extract_watch_hr.py. Outputs stay beside the private inputs.
% ConfirmMatchingClocks is an operator attestation for 60-second absolute
% BPM only. It does not certify a numerical alignment uncertainty.
arguments
    input_dir (1,1) string
    options.ConfirmMatchingClocks (1,1) logical = false
end

capture_path = fullfile(input_dir, 'capture_metadata.csv');
capture_options = detectImportOptions(capture_path, 'TextType', 'string', 'Delimiter', ',');
capture_options = setvartype(capture_options, 'video_start_utc', 'string');
capture_options = setvartype(capture_options, 'alignment_uncertainty_s', 'double');
captures = readtable(capture_path, capture_options);
watch_path = fullfile(input_dir, 'watch_hr.csv');
watch_options = detectImportOptions(watch_path, 'TextType', 'string', 'Delimiter', ',');
watch_options = setvartype(watch_options, ...
    {'measurement_start_utc', 'measurement_end_utc'}, 'string');
watch_options = setvartype(watch_options, 'bpm', 'double');
watch = readtable(watch_path, watch_options);
experiments = readtable(fullfile(input_dir, 'experiments.csv'), 'TextType', 'string', 'Delimiter', ',');

reference = align_watch_reference(experiments, captures, watch, AllowNominalTiming=true);
if options.ConfirmMatchingClocks
    usable = reference.reference_status == "nominal_timing_only" ...
        & reference.start_s == 0 & reference.end_s == 60;
    reference.gt_bpm(usable) = reference.nominal_gt_bpm(usable);
    reference.reference_status(usable) = "ok_operator_confirmed_clock";
    experiments.notes(usable) = experiments.notes(usable) + ";matching_clocks_operator_confirmed";
end
experiments.gt_bpm = reference.gt_bpm;
writetable(reference, fullfile(input_dir, 'watch_reference.csv'));
writetable(experiments, fullfile(input_dir, 'experiments_aligned.csv'));
end
