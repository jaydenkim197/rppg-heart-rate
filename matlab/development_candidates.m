function candidates = development_candidates(stage, inherited)
%DEVELOPMENT_CANDIDATES Change only the registered stage variable.
% Inherited carries only settings from common decisions, never B/C/D choices as cumulative edits.
if nargin < 2
    inherited = struct();
end
switch string(stage)
    case "tracking"
        names = ["fixed","ncc","klt","klt_ncc_reacquire","camshift","staple","mediapipe"];
        candidates = variants("A", "roi_tracker", names, inherited);
        candidates(1).research_only = true;
        candidates(6).unavailable_reason = "staple_adapter_unverified";
        candidates(7).unavailable_reason = "mediapipe_model_adapter_unverified";
    case "temporal"
        candidates = variants("A","bandpass_variant",["none","ideal","butterworth","gaussian"],inherited);
        candidates(1).research_only = true;
    case "fft_length"
        candidates = variants("A","fft_chunk_s",[0 3 5 10 20 30 60],inherited);
        candidates(1).name = "full";
    case "window"
        candidates = variants("A","fft_window",["rectangular","hann","hamming"],inherited);
    case "peak"
        candidates = variants("A","peak_method",["max","max","parabolic"],inherited);
        [candidates.name] = deal("max_bin","zero_padding_4","parabolic");
        candidates(2).overrides.fft_padding_factor = 4;
    case "spatial"
        candidates = variants("B","spatial_filter",["none","median","mean","gaussian","bilateral","wiener"],inherited);
        candidates(1).research_only = true;
    case "color"
        candidates = variants("C","color_variant",["rgb_sum","temporal","difference","log","saturation"],inherited);
        control = defaults("A","green_control",inherited);
        control.research_only = true;
        candidates = [control,candidates];
    case "pos"
        candidates = variants("D","pos_window_s",[1.0 1.6 2.0 3.0],inherited);
    case "sqi"
        candidates = variants("D","pos_sqi",["energy_ratio","relative_peaks","cross_correlation","kurtosis","none"],inherited);
        candidates(end).research_only = true;
    case "fusion"
        candidates = variants("D","pos_fusion",["equal","weighted","best","consensus","spectral"],inherited);
        control = defaults("POS","pooled_pos",inherited);
        control.research_only = true;
        candidates = [control,candidates];
    otherwise
        error('rppg:UnknownSelectionStage','Use an individual pre-registered stage.');
end
end

function result = variants(method, field, values, inherited)
for index = 1:numel(values)
    name = string(values(index));
    item = defaults(method,name,inherited);
    item.overrides.(field) = values(index);
    result(index) = item; %#ok<AGROW>
end
end

function item = defaults(method,name,overrides)
item = struct('name',name,'method',method,'overrides',overrides, ...
    'research_only',false,'unavailable_reason',"");
end
