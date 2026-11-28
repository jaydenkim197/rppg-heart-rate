function results = compare_supplementary_ties(seed, reference_root, groups, output_root)
%COMPARE_SUPPLEMENTARY_TIES Score vetted primary ties on disjoint development windows.
% Each field of groups names a registered stage and holds its primary passing,
% near-tied candidates with the same frozen settings. Apply the predeclared
% incumbent/priority rule outside this diagnostic when scores remain tied.

plan = selection_plan();
plan.windows_s = [30 60; 30 45; 45 60];
keys = {'video_id','start_s','end_s'};
required = {'video_id','subject_id','split','video_file','roi_boxes','video_duration_s'};
if isempty(seed) || ~all(ismember(required,seed.Properties.VariableNames)) ...
        || any(string(seed.split) ~= "development") ...
        || numel(unique(string(seed.video_id))) ~= height(seed) ...
        || numel(unique(string(seed.subject_id))) ~= height(seed) ...
        || any(~isfinite(seed.video_duration_s) | seed.video_duration_s <= 0)
    error('rppg:InvalidSupplementarySeed','Expected unique development video seeds and durations.');
end
stages = string(fieldnames(groups));
if isempty(stages) || any(~ismember(stages,["peak","color","sqi","fusion"]))
    error('rppg:InvalidSupplementaryStage','Supply at least one registered tie stage.');
end
candidates = struct([]);
for stage = stages'
    group = groups.(stage);
    if numel(group) < 2 || any([group.research_only]) ...
            || any(strlength(string({group.unavailable_reason})) > 0)
        error('rppg:InvalidSupplementaryGroup','Supply at least two eligible primary candidates.');
    end
    for index = 1:numel(group)
        group(index).name = stage + ":" + group(index).name;
    end
    candidates = [candidates,group]; %#ok<AGROW>
end

seed.video_id = string(seed.video_id);
manifest = seed(repelem((1:height(seed))',3),:);
manifest.start_s = repmat(plan.windows_s(:,1),height(seed),1);
manifest.end_s = repmat(plan.windows_s(:,2),height(seed),1);
reference = build_ubfc_reference_table(manifest,reference_root,"development");
short = manifest.video_duration_s + 1e-6 < manifest.end_s;
reference.gt_bpm(short) = NaN;
reference.reference_status(short) = "video_too_short_for_window";
trials = prepare_development_trials(seed,reference,plan);
trials.tracking_start_s(:) = 0;
trials.tracking_end_s = min(60,trials.video_duration_s);
trials.tracking_end_s(abs(trials.tracking_end_s - 60) <= 1e-6) = 60;

checkpoint_dir = fullfile(output_root,"checkpoints");
if ~isfolder(checkpoint_dir)
    mkdir(checkpoint_dir);
end
checkpoint_key = struct('plan',plan,'candidates',candidates,'base',config(),'sources',source_contents());
writetable(reference,fullfile(output_root,"references.csv"));
writelines(string(jsonencode(table2struct(trials),PrettyPrint=true)),fullfile(output_root,"trials.json"));
raw.predictions = table();
for row = 1:height(seed)
    these = trials.video_id == seed.video_id(row);
    video = trials(these,:);
    too_short = short(these);
    path = fullfile(checkpoint_dir,sprintf('%03d.mat',row));
    reuse = false;
    if isfile(path)
        previous = load(path,'checkpoint','video','predictions');
        reuse = isequaln(previous.checkpoint,checkpoint_key) && isequaln(previous.video,video);
    end
    if reuse
        predictions = previous.predictions;
    else
        predictions = table();
        if any(~too_short)
            supported = run_benchmark(video(~too_short,:),"development",candidates);
            predictions = supported.predictions;
        end
        if any(too_short)
            skipped = video(too_short,:);
            skipped.tracking_end_s(:) = 60;
            unavailable = candidates;
            [unavailable.unavailable_reason] = deal("video_too_short_for_window");
            missing_rows = run_benchmark(skipped,"development",unavailable);
            predictions = [predictions;missing_rows.predictions];
        end
        checkpoint = checkpoint_key;
        temporary = string(tempname(checkpoint_dir))+".mat";
        save(temporary,'checkpoint','video','predictions');
        movefile(temporary,path,'f');
    end
    raw.predictions = [raw.predictions;predictions]; %#ok<AGROW>
    fprintf('Supplementary video %d/%d checked.\n',row,height(seed));
end
assert(height(raw.predictions) == height(trials)*numel(candidates));
writetable(raw.predictions,fullfile(output_root,"predictions.csv"));
results = table();
for stage = stages'
    names = string(raw.predictions.candidate);
    part.predictions = raw.predictions(startsWith(names,stage+":"),:);
    part.predictions.candidate = extractAfter(part.predictions.candidate,stage+":");
    scored = score_selection_stage(part,stage,plan);
    folder = fullfile(output_root,stage);
    if ~isfolder(folder)
        mkdir(folder);
    end
    writetable(scored.ranking.ranking,fullfile(folder,"ranking.csv"));
    writetable(scored.common_metrics,fullfile(folder,"common_metrics.csv"));
    writetable(scored.change_pairs,fullfile(folder,"change_pairs.csv"));
    results = [results;table(stage,scored.ranking.state,scored.ranking.selected, ...
        scored.n_reference_subjects,scored.n_reference_trend_pairs, ...
        'VariableNames',{'stage','state','leading','n_reference','n_reference_pairs'})]; %#ok<AGROW>
end
writetable(results,fullfile(output_root,"stage_status.csv"));
writelines(string(jsonencode(rmfield(checkpoint_key,'sources'),PrettyPrint=true)),fullfile(output_root,"settings.json"));
end

function signature = source_contents()
% A worktree timestamp change alone does not change the code signature.
sources = dir(fullfile(fileparts(mfilename('fullpath')),'*.m'));
signature = strings(numel(sources),2);
for index = 1:numel(sources)
    file = fullfile(sources(index).folder,sources(index).name);
    signature(index,:) = string({sources(index).name,fileread(file)});
end
end
