function selftest_frozen_evaluation(output_root)
%SELFTEST_FROZEN_EVALUATION Exercise freeze pinning and checkpoint coverage synthetically.
if nargin < 1
    settings = config();
    output_root = string(tempname(settings.result_dir));
end
mkdir(output_root);
settings = config();
[status, revision] = system(sprintf('git -C "%s" rev-parse HEAD',settings.root_dir));
assert(status == 0, 'A committed worktree is required for this freeze self-test.');
candidates = struct('name', {'a','b','c','d','pooled_pos'}, ...
    'method', {'A','B','C','D','POS'},'overrides', {struct()});
freeze = struct('revision',"synthetic-fixture",'code_commit',strtrim(revision), ...
    'candidates',candidates, ...
    'field_gates',struct('expected_trials',9,'min_valid',8,'min_paired',8, ...
    'max_mae_bpm',15,'min_within_10_pct',50), ...
    'independent_min_reference_subjects',9,'independent_min_reference_trend_pairs',7, ...
    'independent_min_paired',8, ...
    'roi_seed',struct('mode',"registered"));
freeze_path = fullfile(output_root,'synthetic_freeze.json');
writelines(jsonencode(freeze,PrettyPrint=true),freeze_path);
video = fullfile(output_root,'fixture.avi');
writer = VideoWriter(video,'Uncompressed AVI');
writer.FrameRate = 15;
open(writer);
[x,y] = meshgrid(1:48,1:40);
for index = 1:915
    stamp = (index-1)/writer.FrameRate;
    pulse = sin(2*pi*1.25*stamp);
    frame = uint8(cat(3,110+mod(x,5)+pulse,130+mod(y,4)+8*pulse, ...
        120+mod(x+y,6)+2*pulse));
    writeVideo(writer,frame);
end
close(writer);
boxes = [8 6 12 8; 8 21 10 8; 26 21 10 8];
number = (1:54)';
manifest = table("T"+number,"S"+repelem(repmat((1:3)',3,1),6), ...
    fullfile(output_root,"missing_"+number+".avi"), ...
    repmat(settings.distances_m(:),9,1),repelem((1:3)',18),zeros(54,1), ...
    repmat(60,54,1),NaN(54,1), ...
    'VariableNames',{'video_id','subject_id','video_file','distance_m','trial','start_s','end_s','gt_bpm'});
manifest.video_file(1) = "fixture.avi";
manifest.gt_bpm(1) = 75;
manifest.frame_pts_csv = repmat("synthetic_frame_pts.csv",54,1);
frame_index = (1:915)';
pts_s = (frame_index-1)/writer.FrameRate;
writetable(table(frame_index,pts_s),fullfile(output_root,'synthetic_frame_pts.csv'));
writetable(manifest,fullfile(output_root,'synthetic_manifest.csv'));
manual = table("T1",string(jsonencode(boxes)),'VariableNames',{'video_id','roi_boxes_json'});
writetable(manual,fullfile(output_root,'synthetic_rois.csv'));
trials = prepare_frozen_trials(fullfile(output_root,'synthetic_manifest.csv'),"final", ...
    freeze_path,RoiCsv=fullfile(output_root,'synthetic_rois.csv'));
assert(trials.video_file(1) == video && nnz(trials.roi_status == "ok") == 1);

original = run_benchmark(trials(1,:),"final",candidates);
shared = run_benchmark(trials(1,:),"final",candidates,ShareSpatialExtraction=true,TraceFirstA=true);
assert(isequaln(original.predictions,shared.predictions));
assert(~isempty(shared.trace.rgb_data.raw_rgb) && ~isempty(shared.trace.estimate.power));
broken = candidates;
broken(2).overrides.spatial_filter = 'invalid_synthetic_filter';
result = run_benchmark(trials(1,:),"final",broken,ShareSpatialExtraction=true);
assert(result.predictions.valid_estimate(result.predictions.method == "A"));
assert(~result.predictions.valid_estimate(result.predictions.method == "B"));

destination = fullfile(output_root,'synthetic_report');
result = run_frozen_evaluation(trials,freeze_path,destination);
assert(sum(result.primary.metrics.n_total(isnan(result.primary.metrics.distance_m))) == 216);
assert(height(readtable(fullfile(destination,'pooled_pos_predictions.csv'))) == 54);
assert(height(result.d_vs_pos.pairs) == 54 && sum(result.d_vs_pos.pairs.paired) == 1);
assert(height(result.distance_gates) == 24 && ~any(result.distance_gates.absolute_pass));
assert(height(result.within_subject_repeats) == 72 && height(result.repeats) == 84);
assert(length(dir(fullfile(destination,'checkpoints','*.mat'))) == 54);
assert(isfile(fullfile(destination,'example_signal.png')));

previous = dir(fullfile(destination,'checkpoints','*.mat'));
again = run_frozen_evaluation(trials,freeze_path,destination);
assert(isequaln(result.distance_gates,again.distance_gates));
assert(isequal([previous.datenum],[dir(fullfile(destination,'checkpoints','*.mat')).datenum]));
fprintf('PASS: frozen manifest, spatial sharing equivalence, B fallback, 216+54 rows, reports and resume.\n');
end
