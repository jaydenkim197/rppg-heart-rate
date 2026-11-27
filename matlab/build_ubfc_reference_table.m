function references = build_ubfc_reference_table(trials, reference_root, split)
%BUILD_UBFC_REFERENCE_TABLE Reference for only the explicitly requested UBFC partition.
% Keys match evaluate_results. Invalid or missing contact windows remain as rows.

keys = {'video_id','start_s','end_s'};
required = [keys, {'subject_id','split'}];
if ~all(ismember(required, trials.Properties.VariableNames))
    error('rppg:InvalidReferenceManifest', 'Trial manifest is missing UBFC reference keys.');
end
split = string(split);
splits = string(trials.split);
allowed = ["development", "independent"];
if ~isscalar(split) || ~ismember(split, allowed) || any(~ismember(splits, allowed))
    error('rppg:InvalidReferenceSplit', 'Explicitly choose development or independent UBFC.');
end
folders = regexprep(string(trials.subject_id), '^UBFC-', '', 'ignorecase');
if ismember('ubfc_subject', trials.Properties.VariableNames)
    folders = string(trials.ubfc_subject);
end
clean_names = regexp(cellstr(folders), '^subject[0-9]+$', 'once');
if any(ismissing(folders)) || any(cellfun(@isempty, clean_names))
    error('rppg:InvalidUbfcSubject', 'Expected a UBFC subject directory name.');
end
[subjects, ~, group] = unique(folders);
if any(accumarray(group, splits == "development") > 0 ...
        & accumarray(group, splits == "independent") > 0)
    error('rppg:UbfcReferenceLeakage', 'A UBFC subject is assigned to both partitions.');
end

selected = splits == split;
requested = trials(selected, :);
requested.video_id = string(requested.video_id);
if isempty(requested) || any(ismissing(requested.video_id) | requested.video_id == "") ...
        || height(unique(requested(:, keys))) ~= height(requested)
    error('rppg:InvalidReferenceKeys', 'Requested UBFC reference keys must be nonempty and unique.');
end
requested_folders = folders(selected);
empty_record = table(zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'time_s','ppg','bpm'});
empty_result = validate_ubfc_reference(empty_record, [0,30]);
results = repmat(empty_result, height(requested), 1);
for folder = subjects'
    rows = find(requested_folders == folder);
    if isempty(rows)
        continue
    end
    path = fullfile(reference_root, folder, 'ground_truth.txt');
    if ~isfile(path)
        for row = rows'
            results(row).reference_status = "missing_reference_file";
        end
        continue
    end
    try
        reference = read_ubfc_reference(path);
    catch issue
        if ~strcmp(issue.identifier, 'rppg:InvalidUbfcReference')
            rethrow(issue);
        end
        for row = rows'
            results(row).reference_status = "invalid_reference_file";
        end
        continue
    end
    for row = rows'
        results(row) = validate_ubfc_reference(reference, [requested.start_s(row), requested.end_s(row)]);
    end
end
references = [requested(:, required), struct2table(results)];
end
