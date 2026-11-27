function result = diagnose_development_stages(trials, stages, output_root, fixed_settings)
%DIAGNOSE_DEVELOPMENT_STAGES Reuse common decoded observations on a fixed seed.
if nargin < 4
    fixed_settings = struct();
end
plan = selection_plan();
stages = string(stages(:)');
if isempty(stages) || ~all(ismember(stages,plan.stages(1:end-1))) ...
        || numel(unique(stages)) ~= numel(stages)
    error('rppg:InvalidSelectionStages','Expected distinct registered stages.');
end
if any(string(trials.split) ~= "development")
    error('rppg:HoldoutSelection','Development diagnostics cannot access holdouts.');
end

flattened = struct([]);
by_stage = cell(1,numel(stages));
for k = 1:numel(stages)
    candidates = development_candidates(stages(k),fixed_settings);
    by_stage{k} = candidates;
    for index = 1:numel(candidates)
        candidates(index).name = stages(k) + ":" + candidates(index).name;
    end
    flattened = [flattened,candidates]; %#ok<AGROW>
end
execution = fullfile(output_root,"execution");
checkpoint_dir = fullfile(execution,"checkpoints");
if ~isfolder(checkpoint_dir)
    mkdir(checkpoint_dir);
end
checkpoint_key = struct('plan',plan,'candidates',flattened,'base',config());
record = dir(fullfile(fileparts(mfilename('fullpath')),'*.m'));
checkpoint_key.sources = [{record.name}; num2cell([record.bytes]); num2cell([record.datenum])];
raw.predictions = table();
videos = unique(trials.video_id,'stable');
for index = 1:numel(videos)
    video = trials(trials.video_id == videos(index),:);
    path = fullfile(checkpoint_dir,sprintf('%03d.mat',index));
    reuse = false;
    if isfile(path)
        previous = load(path,'checkpoint','video','predictions');
        reuse = isequaln(previous.checkpoint,checkpoint_key) && isequaln(previous.video,video);
    end
    if reuse
        predictions = previous.predictions;
    else
        part = run_benchmark(video,"development",flattened);
        predictions = part.predictions;
        checkpoint = checkpoint_key;
        temporary = string(tempname(checkpoint_dir))+".mat";
        save(temporary,'checkpoint','video','predictions');
        movefile(temporary,path,'f');
    end
    raw.predictions = [raw.predictions; predictions]; %#ok<AGROW>
    fprintf('Development video %d/%d complete.\n',index,numel(videos));
end
writetable(raw.predictions,fullfile(execution,'predictions.csv'));
writelines(string(jsonencode(table2struct(trials),PrettyPrint=true)),fullfile(execution,'trials.json'));
result = table();
for k = 1:numel(stages)
    stage = stages(k);
    raw_stage = raw;
    names = string(raw.predictions.candidate);
    raw_stage.predictions = raw.predictions(startsWith(names,stage+":"),:);
    raw_stage.predictions.candidate = extractAfter(raw_stage.predictions.candidate,stage+":");
    scored = score_selection_stage(raw_stage,stage,plan);
    folder = fullfile(output_root,stage);
    if ~isfolder(folder)
        mkdir(folder);
    end
    writetable(raw_stage.predictions,fullfile(folder,'predictions.csv'));
    writetable(scored.ranking.ranking,fullfile(folder,'ranking.csv'));
    writetable(scored.change_pairs,fullfile(folder,'change_pairs.csv'));
    writetable(scored.common_metrics,fullfile(folder,'common_metrics.csv'));
    metadata = struct('candidates',by_stage{k}, ...
        'comparison_mode',"diagnostic", 'fixed_settings',fixed_settings, 'policy',plan.revision);
    writelines(string(jsonencode(metadata,PrettyPrint=true)),fullfile(folder,'settings.json'));
    result = [result; table(stage,"exploratory_"+scored.ranking.state, ...
        scored.ranking.selected, ...
        'VariableNames',{'stage','state','leading_eligible'})]; %#ok<AGROW>
    fprintf('%s: %s\n',stage,scored.ranking.state);
end
writetable(result,fullfile(output_root,'stage_status.csv'));
end