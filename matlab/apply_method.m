function method_signal = apply_method(prepared, method, settings)
%APPLY_METHOD 각 방법의 RGB 시계열을 분석할 신호로 변환한다.

method_signal.method = char(method);
method_signal.time_s = prepared.time_s;
method_signal.fs = prepared.fs;
method_signal.labels = {method_signal.method};
switch method_signal.method
    case 'A'
        method_signal.values = prepared.mean_rgb(:, 2);
    case 'B'
        method_signal.values = prepared.median_green;
    case 'C'
        intensity = sum(prepared.mean_rgb, 2);
        intensity(intensity <= eps) = NaN;
        method_signal.values = prepared.mean_rgb(:, 2) ./ intensity;
    case 'D'
        method_signal.labels = settings.roi_names;
        method_signal.values = NaN(numel(prepared.time_s), 3);
        for region = 1:3
            method_signal.values(:, region) = pos_signal(prepared.rgb(:, :, region), ...
                prepared.fs, settings.pos_window_s);
        end
    case 'POS'
        % 공통 피부 영역에서 계산한 기본 POS를 D의 비교 기준으로 둔다.
        method_signal.values = pos_signal(prepared.mean_rgb, prepared.fs, settings.pos_window_s);
    otherwise
        error('rppg:UnknownMethod', 'Unknown method: %s', method_signal.method);
end
end

function pulse = pos_signal(rgb, fs, window_s)
% Wang 등의 POS에서 정규화, 투영, 표준편차 보정, 겹쳐 더하기를 수행한다.
window_length = max(2, round(window_s * fs));
num_samples = size(rgb, 1);
pulse = zeros(num_samples, 1);
covered = false(num_samples, 1);
for first = 1:num_samples - window_length + 1
    rows = first:first + window_length - 1;
    segment = rgb(rows, :);
    color_mean = mean(segment, 1);
    if any(~isfinite(color_mean)) || any(color_mean <= eps)
        continue
    end

    normalized = segment ./ color_mean;
    s1 = normalized(:, 2) - normalized(:, 3);
    s2 = -2 * normalized(:, 1) + normalized(:, 2) + normalized(:, 3);
    h = s1;
    if std(s2) > eps
        h = s1 + (std(s1) / std(s2)) * s2;
    end
    pulse(rows) = pulse(rows) + h - mean(h);
    covered(rows) = true;
end
pulse(~covered) = NaN;
end
