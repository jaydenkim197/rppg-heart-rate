function reference = read_ubfc_reference(path)
%READ_UBFC_REFERENCE Read original Dataset 2 PPG, sensor HR and seconds.

lines = splitlines(string(fileread(path)));
lines(strlength(strtrim(lines)) == 0) = [];
if numel(lines) ~= 3
    error('rppg:InvalidUbfcReference', 'The Dataset 2 reference requires exactly three rows.');
end
ppg = str2double(split(strtrim(lines(1))));
bpm = str2double(split(strtrim(lines(2))));
time_s = str2double(split(strtrim(lines(3))));
if numel(time_s) < 2 || numel(ppg) ~= numel(time_s) || numel(bpm) ~= numel(time_s) ...
        || any(~isfinite(time_s)) || any(diff(time_s) <= 0)
    error('rppg:InvalidUbfcReference', 'Reference rows and timestamps must align.');
end
reference = table(time_s(:), ppg(:), bpm(:), 'VariableNames', {'time_s', 'ppg', 'bpm'});
end
