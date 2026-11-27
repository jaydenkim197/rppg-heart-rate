function result = diagnose_development_stages(trials, stages, output_root)
%DIAGNOSE_DEVELOPMENT_STAGES Reuse common decoded observations on a fixed seed.
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
    candidates = development_candidates(stages(k));
    by_stage{k} = candidates;
    for index = 1:numel(candidates)
        candidates(index).name = stages(k) + ":" + candidates(index).name;
    end
    flattened = [flattened,candidates]; %#ok<AGROW>
end
raw = run_benchmark(trials,"development",flattened,fullfile(output_root,"execution"));
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
        'comparison_mode',"diagnostic_fixed_default", 'policy',plan.revision);
    writelines(string(jsonencode(metadata,PrettyPrint=true)),fullfile(folder,'settings.json'));
    result = [result; table(stage,"exploratory_"+scored.ranking.state, ...
        scored.ranking.selected, ...
        'VariableNames',{'stage','state','leading_eligible'})]; %#ok<AGROW>
    fprintf('%s: %s\n',stage,scored.ranking.state);
end
writetable(result,fullfile(output_root,'stage_status.csv'));
end