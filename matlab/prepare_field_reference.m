function reference = prepare_field_reference(input_dir)
%PREPARE_FIELD_REFERENCE Align local intake CSVs without promoting draft HR.
% Run after tools/extract_watch_hr.py. Outputs stay beside the private inputs.

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
experiments.gt_bpm = reference.gt_bpm;
writetable(reference, fullfile(input_dir, 'watch_reference.csv'));
writetable(experiments, fullfile(input_dir, 'experiments_aligned.csv'));
end
