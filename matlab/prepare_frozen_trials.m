function trials = prepare_frozen_trials(manifest_path, split, freeze_path, options)
%PREPARE_FROZEN_TRIALS Resolve a private manifest and register initial ROIs.
% Supported tables contain local paths (relative to the manifest by default).
% Optional RoiCsv contains video_id,roi_boxes_json and records manual blind ROIs.
% For independent UBFC, provide one row per held-out video and ReferenceRoot.

arguments
    manifest_path (1,1) string
    split (1,1) string {mustBeMember(split,["final","independent"])}
    freeze_path (1,1) string
    options.VideoRoot (1,1) string = ""
    options.RoiCsv (1,1) string = ""
    options.ReferenceRoot (1,1) string = ""
    options.MetadataCsv (1,1) string = ""
end
freeze = jsondecode(fileread(freeze_path));
if ~isfield(freeze,'roi_seed') || ~isfield(freeze.roi_seed,'mode')
    error('rppg:MissingFrozenRoiPolicy','Freeze a blind ROI initialization policy first.');
end
roi_policy = freeze.roi_seed;
policy = string(roi_policy.mode);
if ~ismember(policy,["registered","cascade"]) ...
        || strlength(options.RoiCsv) == 0 && policy == "registered" ...
        || strlength(options.RoiCsv) > 0 && policy ~= "registered"
    error('rppg:FrozenRoiPolicyMismatch','Use the frozen Cascade policy or its separately registered ROI CSV.');
end

manifest = readtable(manifest_path,'TextType','string','Delimiter',',');
required = {'video_id','subject_id','video_file'};
if ~all(ismember(required,manifest.Properties.VariableNames)) || isempty(manifest)
    error('rppg:InvalidVideoManifest','Expected video_id, subject_id and video_file.');
end
if ismember('split',manifest.Properties.VariableNames) && any(string(manifest.split) ~= split)
    error('rppg:MixedEvaluationPartitions','Supply one manifest for the requested evaluation split.');
end
manifest.split = repmat(split,height(manifest),1);
manifest.video_id = string(manifest.video_id);
manifest.subject_id = string(manifest.subject_id);
root = options.VideoRoot;
if strlength(root) == 0
    root = string(fileparts(manifest_path));
end
root = absolute_root(root);
manifest.video_file = resolve_paths(manifest.video_file,root);
if strlength(options.MetadataCsv) > 0
    manifest = merge_metadata(manifest,options.MetadataCsv);
end
for sidecar = ["frame_pts_csv","roi_motion_file"]
    if ismember(sidecar,manifest.Properties.VariableNames)
        manifest.(sidecar) = resolve_paths(manifest.(sidecar),root);
    end
end

trials = field_or_ubfc(manifest,split,options.ReferenceRoot,root);
videos = unique(trials(:, {'video_id','video_file'}),'stable');
if height(videos) ~= numel(unique(videos.video_id)) ...
        || any(ismissing(videos.video_id) | strlength(videos.video_id) == 0)
    error('rppg:AmbiguousFrozenVideo','A nonempty video identifier must designate exactly one path.');
end

trials.roi_boxes = cell(height(trials),1);
trials.roi_status = repmat("unset",height(trials),1);
if policy == "registered"
    roi_rows = readtable(options.RoiCsv,'TextType','string','Delimiter',',');
    required = {'video_id','roi_boxes_json'};
    if ~all(ismember(required,roi_rows.Properties.VariableNames)) ...
            || height(roi_rows) ~= numel(unique(string(roi_rows.video_id)))
        error('rppg:InvalidRegisteredRois','ROI CSV must contain one coordinate entry per video.');
    end
    [found, path_row] = ismember(trials.video_id,string(roi_rows.video_id));
    for row = 1:height(trials)
        if found(row)
            value = roi_rows.roi_boxes_json(path_row(row));
            if ~ismissing(value) && strlength(value) > 0
                trials.roi_boxes{row} = checked_boxes(jsondecode(value));
                trials.roi_status(row) = "ok";
            else
                trials.roi_status(row) = "missing_registered_roi";
            end
        else
            trials.roi_status(row) = "missing_registered_roi";
        end
    end
else
    [scales, fractions] = validate_policy(roi_policy);
    detector = vision.CascadeObjectDetector();
    for index = 1:height(videos)
        [boxes, status] = detect_rois(videos.video_file(index),detector,scales,fractions);
        rows = trials.video_id == videos.video_id(index);
        trials.roi_boxes(rows) = repmat({boxes},nnz(rows),1);
        trials.roi_status(rows) = status;
    end
end
end

function manifest = merge_metadata(manifest,metadata_path)
metadata = readtable(metadata_path,'TextType','string','Delimiter',',');
fields = {'video_id','frame_pts_csv','display_width','display_height'};
if ~all(ismember(fields,metadata.Properties.VariableNames)) ...
        || height(metadata) ~= numel(unique(string(metadata.video_id)))
    error('rppg:InvalidFrozenMetadata','Expected unique video IDs and their native PTS and display metadata.');
end
[found,index] = ismember(manifest.video_id,string(metadata.video_id));
if ~all(found)
    error('rppg:MissingFrozenMetadata','Every attempted video needs its original intake metadata.');
end
for field = fields(2:end)
    manifest.(field{1}) = metadata.(field{1})(index);
end
if ismember('sha256',metadata.Properties.VariableNames)
    manifest.sha256 = metadata.sha256(index);
end
end

function trials = field_or_ubfc(manifest, split, reference_root, root)
trials = manifest;
if split == "final"
    columns = {'start_s','end_s','gt_bpm','distance_m','trial'};
    if ~all(ismember(columns,trials.Properties.VariableNames)) ...
            || any(trials.start_s ~= 0 | trials.end_s ~= 60)
        error('rppg:InvalidFieldManifest','Use the finalized 60-second field-reference manifest.');
    end
    return
end
if strlength(reference_root) == 0
    error('rppg:IndependentReferenceRequired','Set ReferenceRoot to the UBFC Dataset 2 directory.');
end
if numel(unique(trials.subject_id)) ~= 14 || height(trials) ~= 14
    error('rppg:IncompleteIndependentCohort','Use one row per registered holdout video.');
end
plan = selection_plan();
n = size(plan.windows_s,1);
trials = trials(repelem((1:height(trials))',n),:);
trials.start_s = repmat(plan.windows_s(:,1),height(manifest),1);
trials.end_s = repmat(plan.windows_s(:,2),height(manifest),1);
trials.tracking_start_s = repmat(min(plan.windows_s(:,1)),height(trials),1);
trials.tracking_end_s = repmat(max(plan.windows_s(:,2)),height(trials),1);
reference = build_ubfc_reference_table(trials,resolve_paths(reference_root,root),"independent");
trials.gt_bpm = reference.gt_bpm;
trials.reference_status = reference.reference_status;
end

function root = absolute_root(root)
if strlength(root) == 0
    root = string(pwd);
elseif ~is_absolute(root)
    root = fullfile(pwd,root);
end
end

function paths = resolve_paths(values,root)
paths = string(values);
for index = 1:numel(paths)
    if ~ismissing(paths(index)) && strlength(paths(index)) > 0 && ~is_absolute(paths(index))
        paths(index) = fullfile(root,paths(index));
    end
end
end

function yes = is_absolute(path)
yes = ~isempty(regexp(path,'^(?:[A-Za-z]:[\\/]|[\\/])','once'));
end

function [scales,fractions] = validate_policy(policy)
scales = policy.scales(:)';
fractions = policy.fractions;
validateattributes(scales,{'numeric'},{'integer','nonnegative','nonempty'});
validateattributes(fractions,{'numeric'},{'real','finite','size',[3 4],'>=',0,'<=',1});
if any(fractions(:,3:4) <= 0,'all') || any(fractions(:,1:2)+fractions(:,3:4)>1,'all')
    error('rppg:InvalidRoiFraction','All three positive-sized regions need to fit within the face box.');
end
end

function [boxes,status] = detect_rois(file, detector, scales, fractions)
boxes = [];
status = "initial_face_not_detected";
try
    reader = VideoReader(file);
    if ~hasFrame(reader)
        status = "initial_frame_unavailable";
        return
    end
    frame = readFrame(reader);
    [h,w,~] = size(frame);
    for target = scales
        if target > 0 && target < max(h,w)
            probe = imresize(frame,target/max(h,w),'bilinear');
        else
            probe = frame;
        end
        face_options = detector(probe);
        if isempty(face_options)
            continue
        end
        faces = sortrows(face_options,[2 1 3 4]);
        [~,index] = max(faces(:,3).*faces(:,4));
        chosen = double(faces(index,:));
        factor = [w/size(probe,2), h/size(probe,1)];
        origin = 1 + (chosen(1:2)-1).*factor;
        dims = chosen(3:4).*factor;
        relative_origin = origin + fractions(:,1:2).*dims;
        relative_extent = fractions(:,3:4).*dims;
        boxes = round([relative_origin,relative_extent]);
        if any(boxes(:,1:2) < 1,'all') || any(boxes(:,1:2)+boxes(:,3:4)-1 > [w,h],'all')
            error('rppg:InitialRoiOutsideFrame','The initial face-based ROIs do not fit the decoded display frame.');
        end
        boxes = checked_boxes(boxes);
        status = "ok";
        return
    end
catch issue
    boxes = [];
    if isempty(issue.identifier)
        status = "roi_initialization_failed";
    else
        status = string(issue.identifier);
    end
end
end

function boxes = checked_boxes(boxes)
validateattributes(boxes,{'numeric'},{'integer','finite','positive','size',[3 4]});
for left = 1:2
    for right = left+1:3
        a = boxes(left,:);
        b = boxes(right,:);
        intersection = min(a(1:2)+a(3:4), b(1:2)+b(3:4)) > max(a(1:2),b(1:2));
        if all(intersection)
            error('rppg:OverlappingRegisteredRoi','Initial skin ROIs must be disjoint.');
        end
    end
end
end
