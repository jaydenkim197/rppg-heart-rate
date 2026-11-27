function comparison = compare_development_interactions(trials, source_root, output_root)
%COMPARE_DEVELOPMENT_INTERACTIONS Run the registered two-factor checks.
if any(string(trials.split) ~= "development")
    error('rppg:HoldoutSelection','Interaction experiments accept the development split only.');
end
plan = selection_plan();
pairs = ["tracking" "mask"; "temporal" "fft_length"; "sqi" "fusion"];
second_fields = ["saturation_mode","fft_chunk_s","pos_fusion"];
comparison = table();
for index = 1:size(pairs,1)
    first_stage = pairs(index,1);
    second_stage = pairs(index,2);
    first = top_two(first_stage,source_root);
    if second_stage == "mask"
        second = struct('name',{"raw","hard"}, ...
            'overrides',{struct('saturation_mode',"raw"),struct('saturation_mode',"hard")});
    else
        second = top_two(second_stage,source_root);
    end
    name = first_stage + "_x_" + second_stage;
    if isempty(first) || isempty(second)
        row = table(name,"insufficient_candidate_evidence",0, ...
            'VariableNames',{'interaction','status','n_combinations'});
        comparison = [comparison; row]; %#ok<AGROW>
        continue
    end
    candidates = struct('name', {}, 'method', {}, 'overrides', {});
    for a = 1:numel(first)
        for b = 1:numel(second)
            combined = first(a).overrides;
            varied = second_fields(index);
            combined.(varied) = second(b).overrides.(varied);
            item = struct('name',string(first(a).name)+"__"+string(second(b).name), ...
                'method',string(first(a).method),'overrides',combined);
            candidates(end+1) = item; %#ok<AGROW>
        end
    end
    destination = fullfile(output_root,name);
    raw = run_benchmark(trials,"development",candidates,destination);
    scored = score_selection_stage(raw,"interactions",plan);
    writetable(scored.ranking.ranking,fullfile(destination,'ranking.csv'));
    writetable(scored.common_metrics,fullfile(destination,'common_metrics.csv'));
    writetable(scored.change_pairs,fullfile(destination,'change_pairs.csv'));
    row = table(name,"completed_development_diagnostic",numel(candidates), ...
        'VariableNames',{'interaction','status','n_combinations'});
    comparison = [comparison; row]; %#ok<AGROW>
end
if ~isfolder(output_root)
    mkdir(output_root);
end
writetable(comparison,fullfile(output_root,'interaction_status.csv'));
end

function selected = top_two(stage,root)
stage_dir = fullfile(root,stage);
ranking_path = fullfile(stage_dir,'ranking.csv');
settings_path = fullfile(stage_dir,'settings.json');
selected = struct([]);
if ~isfile(ranking_path) || ~isfile(settings_path)
    return
end
ranking = readtable(ranking_path,'TextType','string','Delimiter',',');
ranking = ranking(isfinite(ranking.score) & ranking.n_paired > 0 ...
    & ~startsWith(ranking.method,"Research"),:);
ranking = sortrows(ranking,{'eligible','score','candidate'}, ...
    {'descend','descend','ascend'});
record = jsondecode(fileread(settings_path));
for index = 1:min(2,height(ranking))
    item = record.candidates(string({record.candidates.name}) == string(ranking.candidate(index)));
    selected = [selected, item]; %#ok<AGROW>
end
end
