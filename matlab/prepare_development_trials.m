function trials = prepare_development_trials(seed, reference, plan)
%PREPARE_DEVELOPMENT_TRIALS Expand a registered capture into identical timed comparisons.
if any(string(seed.split) ~= "development") || any(string(reference.split) ~= "development")
    error('rppg:HoldoutSelection', 'This comparison accepts development rows only.');
end
keys = {'video_id','start_s','end_s'};
if height(unique(reference(:,keys))) ~= height(reference)
    error('rppg:DuplicateReference', 'Each reference window must have a unique key.');
end
n = size(plan.windows_s,1);
trials = seed(repelem((1:height(seed))',n),:);
trials.start_s = repmat(plan.windows_s(:,1),height(seed),1);
trials.end_s = repmat(plan.windows_s(:,2),height(seed),1);
trials.tracking_start_s = repmat(min(plan.windows_s(:,1)),height(trials),1);
trials.tracking_end_s = repmat(max(plan.windows_s(:,2)),height(trials),1);
trials.video_id = string(trials.video_id);
reference.video_id = string(reference.video_id);
[found,index] = ismember(trials(:,keys),reference(:,keys));
if ~all(found)
    error('rppg:ReferenceCoverageUnknown', 'Every attempted window must have a reference status row.');
end
trials.gt_bpm = reference.gt_bpm(index);
trials.reference_status = reference.reference_status(index);
end
