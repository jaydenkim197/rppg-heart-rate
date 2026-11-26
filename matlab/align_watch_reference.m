function reference = align_watch_reference(windows, captures, watch)
%ALIGN_WATCH_REFERENCE Aggregate observed Apple Watch BPM for video intervals.
% Date columns use ISO 8601 UTC strings ending in Z, or zoned datetimes.
% The watch table must already be filtered to the agreed device and mode.

keys = {'video_id', 'start_s', 'end_s'};
capture_columns = {'video_id', 'video_start_utc', 'video_start_source', 'alignment_uncertainty_s'};
watch_columns = {'video_id', 'measurement_start_utc', 'measurement_end_utc', 'bpm'};
if ~all(ismember(keys, windows.Properties.VariableNames)) ...
        || ~all(ismember(capture_columns, captures.Properties.VariableNames)) ...
        || ~all(ismember(watch_columns, watch.Properties.VariableNames))
    error('rppg:InvalidWatchTables', 'Missing video window, capture timing, or watch columns.');
end

reference = windows(:, keys);
reference.video_id = string(reference.video_id);
capture_ids = string(captures.video_id);
if numel(unique(capture_ids)) ~= height(captures) || height(unique(reference)) ~= height(reference)
    error('rppg:DuplicateWatchKeys', 'Capture IDs and video window keys must be unique.');
end
if any(~isfinite(reference.start_s) | reference.start_s < 0 ...
        | ~isfinite(reference.end_s) | reference.end_s <= reference.start_s)
    error('rppg:InvalidWatchWindow', 'Video windows must have finite positive durations.');
end

video_start = parse_utc(captures.video_start_utc);
watch_start = parse_utc(watch.measurement_start_utc);
watch_end = parse_utc(watch.measurement_end_utc);
watch_ids = string(watch.video_id);
source = string(captures.video_start_source);
timing = captures.alignment_uncertainty_s;
valid_watch = ~isnat(watch_start) & ~isnat(watch_end) & watch_end >= watch_start ...
    & isfinite(watch.bpm) & watch.bpm > 0;

count = height(windows);
reference.gt_bpm = NaN(count, 1);
reference.n_watch_samples = zeros(count, 1);
reference.first_watch_s = NaN(count, 1);
reference.last_watch_s = NaN(count, 1);
reference.median_watch_interval_s = NaN(count, 1);
reference.max_watch_gap_s = NaN(count, 1);
reference.alignment_uncertainty_s = NaN(count, 1);
reference.n_conflicting_times = zeros(count, 1);
reference.reference_status = repmat("capture_timing_unverified", count, 1);
[found, capture_rows] = ismember(reference.video_id, capture_ids);

for capture = unique(capture_rows(found))'
    if isnat(video_start(capture)) || ismissing(source(capture)) ...
            || strlength(strtrim(source(capture))) == 0 || ~isfinite(timing(capture)) || timing(capture) < 0
        continue
    end
    rows = find(capture_rows == capture);
    source_rows = valid_watch & watch_ids == capture_ids(capture);
    watch_times = [seconds(watch_start(source_rows) - video_start(capture)), ...
        seconds(watch_end(source_rows) - video_start(capture))];
    watch_times = round(watch_times, 6);
    [times, ~, group] = unique(watch_times, 'rows');
    values = watch.bpm(source_rows);
    low = accumarray(group, values, [size(times, 1), 1], @min);
    high = accumarray(group, values, [size(times, 1), 1], @max);
    conflict = low ~= high;
    reference.alignment_uncertainty_s(rows) = timing(capture);

    for row = rows'
        start_s = round(reference.start_s(row), 6);
        end_s = round(reference.end_s(row), 6);
        inside = times(:, 1) >= start_s & times(:, 1) < end_s & times(:, 2) <= end_s;
        reference.n_conflicting_times(row) = nnz(inside & conflict);
        kept = inside & ~conflict;
        reference.reference_status(row) = "no_valid_watch_samples";
        if ~any(kept)
            continue
        end
        sample_times = unique(times(kept, 2));  % Observable by the measurement end time.
        reference.gt_bpm(row) = mean(low(kept));
        reference.n_watch_samples(row) = nnz(kept);
        reference.first_watch_s(row) = sample_times(1);
        reference.last_watch_s(row) = sample_times(end);
        reference.median_watch_interval_s(row) = median(diff(sample_times));
        reference.max_watch_gap_s(row) = max(diff([start_s; sample_times; end_s]));
        reference.reference_status(row) = "ok";
    end
end
end

function dates = parse_utc(values)
if isdatetime(values)
    dates = values;
    if isempty(dates.TimeZone)
        error('rppg:WatchTimeZoneRequired', 'Datetime values must have a time zone.');
    end
    dates.TimeZone = 'UTC';
    return
end
values = string(values);
dates = NaT(size(values), 'TimeZone', 'UTC');
for index = 1:numel(values)
    if ismissing(values(index))
        continue
    end
    iso = char(values(index));
    if isempty(regexp(iso, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$', 'once'))
        continue
    end
    try
        stamp = datetime(iso(1:19), 'InputFormat', "yyyy-MM-dd'T'HH:mm:ss", 'TimeZone', 'UTC');
        if numel(iso) > 20
            stamp = stamp + seconds(str2double(['0', iso(20:end-1)]));
        end
        dates(index) = stamp;
    catch
        % Out-of-range dates are treated as unavailable timing.
    end
end
end
