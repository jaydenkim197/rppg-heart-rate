function save_trial_plots(folder, video_id, preview, raw_time, raw_rgb, results, settings)
%SAVE_TRIAL_PLOTS 피부 영역과 영상 한 편의 처리 결과 그래프를 그린다.

if ~isfolder(folder)
    mkdir(folder);
end
figure_handle = figure('Visible', 'off', 'Color', 'white', 'Position', [50, 50, 1150, 850]);
cleanup = onCleanup(@() close(figure_handle)); %#ok<NASGU>

if ~isempty(preview) && ~isempty(preview(1).frame)
    layout = tiledlayout(figure_handle, 1, 2);
    colors = [1, 0.78, 0.25; 0.30, 0.94, 0.88; 0.98, 0.40, 0.63];
    for frame_index = 1:2
        axes_handle = nexttile(layout);
        imshow(preview(frame_index).frame, 'Parent', axes_handle);
        hold(axes_handle, 'on');
        for region = 1:3
            roi = preview(frame_index).polygons([1:4, 1], :, region);
            plot(axes_handle, roi(:, 1), roi(:, 2), 'Color', colors(region, :), 'LineWidth', 2);
        end
        title(axes_handle, sprintf('Frame at %.2f s', preview(frame_index).time_s));
    end
    title(layout, char(video_id), 'Interpreter', 'none');
    exportgraphics(figure_handle, fullfile(folder, 'tracked_roi.png'), 'Resolution', 140);
    clf(figure_handle);
end

if isempty(raw_time)
    return
end
layout = tiledlayout(figure_handle, 3, 1);
raw_axes = nexttile(layout);
hold(raw_axes, 'on');
set(raw_axes, 'ColorOrder', [0.82, 0.15, 0.20; 0.12, 0.53, 0.28; 0.15, 0.38, 0.77]);
plot(raw_axes, raw_time, raw_rgb, 'LineWidth', 1.0);
title(raw_axes, 'Raw RGB in shared skin regions');
xlabel(raw_axes, 'Time (s)');
ylabel(raw_axes, 'Pixel value');
legend(raw_axes, 'Red', 'Green', 'Blue', 'Location', 'northeast');
grid(raw_axes, 'on');

signal_axes = nexttile(layout);
spectral_axes = nexttile(layout);
hold(signal_axes, 'on');
hold(spectral_axes, 'on');
plotted = false;
for index = 1:numel(results)
    result = results{index};
    if isempty(result) || isempty(result.filtered) || isempty(result.power)
        continue
    end
    scale = std(result.filtered);
    visible = result.frequency_hz >= settings.heart_band_hz(1) & ...
        result.frequency_hz <= settings.heart_band_hz(2);
    peak_power = max(result.power(visible));
    if scale <= 0 || isempty(peak_power) || peak_power <= 0
        continue
    end
    name = result.method;
    if strcmp(result.method, 'D')
        name = sprintf('D (%s)', result.display_name);
    end
    plot(signal_axes, result.time_s, result.filtered / scale, 'DisplayName', name);
    plot(spectral_axes, result.frequency_hz(visible), result.power(visible) / peak_power, ...
        'LineWidth', 1.1, 'DisplayName', name);
    plotted = true;
end

title(signal_axes, 'Bandpass output');
ylabel(signal_axes, 'Signal / standard deviation');
xlabel(signal_axes, 'Time (s)');
grid(signal_axes, 'on');
title(spectral_axes, 'FFT within the heart rate band');
xlabel(spectral_axes, 'Frequency (Hz)');
ylabel(spectral_axes, 'Power / peak power');
xlim(spectral_axes, settings.heart_band_hz);
grid(spectral_axes, 'on');
if plotted
    legend(signal_axes, 'Location', 'northeast', 'Interpreter', 'none');
    legend(spectral_axes, 'Location', 'northeast', 'Interpreter', 'none');
else
    text(signal_axes, 0.5, 0.5, 'No usable waveform', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center');
end
title(layout, char(video_id), 'Interpreter', 'none');
exportgraphics(figure_handle, fullfile(folder, 'signals_and_fft.png'), 'Resolution', 150);
end
