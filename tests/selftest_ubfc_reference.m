function selftest_ubfc_reference()
%SELFTEST_UBFC_REFERENCE Verify waveform qualification and source partition guards.
base = (0:899)' / 30;
times = base + 0.005*sin(2*pi*0.20*base);
waveform = 50 + 7*cos(2*pi*1.25*times) + 0.5*cos(2*pi*0.15*times);
device_bpm = repmat(200, size(times));
reference = table(times, waveform, device_bpm, 'VariableNames', {'time_s','ppg','bpm'});
full = validate_ubfc_reference(reference, [0,30]);
first = validate_ubfc_reference(reference, [0,15]);
last = validate_ubfc_reference(reference, [15,30]);
assert(full.reference_status == "ok" && full.device_bpm == 200 && abs(full.gt_bpm-75) < 1);
assert(first.reference_status == "ok" && last.reference_status == "ok");
assert(max(abs([first.gt_bpm,last.gt_bpm]-75)) < 1);
reference.bpm(:) = 15;
assert(validate_ubfc_reference(reference, [0,30]).gt_bpm == full.gt_bpm);
with_gap = reference(~(times >= 8 & times < 8.9), :);
rejected = validate_ubfc_reference(with_gap, [0,30]);
assert(rejected.reference_status == "reference_gap_too_long" && isnan(rejected.gt_bpm));
reference.ppg(:) = 100;
flat = validate_ubfc_reference(reference, [0,30]);
assert(flat.reference_status == "flat_reference" && isnan(flat.gt_bpm));

manifest = table(["UBFC-subject1";"UBFC-subject2"], ["v1";"v2"], ...
    ["development";"independent"], [0;0], [30;30], ...
    'VariableNames', {'subject_id','video_id','split','start_s','end_s'});
missing = build_ubfc_reference_table(manifest, tempname, "development");
assert(height(missing) == 1 && missing.video_id == "v1");
assert(missing.reference_status == "missing_reference_file" && isnan(missing.gt_bpm));
manifest.subject_id(2) = "subject1";
try
    build_ubfc_reference_table(manifest, tempname, "development");
    error('rppg:ExpectedUbfcLeakage', 'Partition leakage should have been rejected.');
catch issue
    assert(strcmp(issue.identifier, 'rppg:UbfcReferenceLeakage'));
end
fprintf('PASS: UBFC contact BPM, 15-second windows, missing and degenerate signals, and split isolation.\n');
end
