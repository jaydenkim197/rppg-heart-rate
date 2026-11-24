function rgb_data = extract_rgb(video_file, settings)
%EXTRACT_RGB 영상의 공통 피부 영역에서 RGB 시간 신호를 추출할 함수 틀.
% 입력은 영상 경로와 config()의 공통 설정이다.
% 출력은 time_s, raw_rgb, median_rgb, pixel_counts, roi_positions, valid다.
% 배열 크기와 부위 순서는 docs/architecture.md에 정의되어 있다.

error('rppg:NotImplemented', ...
    'extract_rgb의 영상 입력, ROI 유지, RGB 평균 추출을 구현해야 합니다.');
end
