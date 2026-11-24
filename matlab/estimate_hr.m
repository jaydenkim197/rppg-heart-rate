function result = estimate_hr(method_signal, settings)
%ESTIMATE_HR 시간 신호로 심박수와 처리 상태를 계산할 함수 틀.
% 실제 시각 확인, 재표본화, 필터링, FFT, 피크 탐색 순서로 구현한다.
% D는 부위별 BPM과 신호 품질을 구하고 기본 POS와 함께 비교한다.
% 출력에는 predicted_bpm, status, failure_reason 및 분석 그래프용 값을 담는다.

error('rppg:NotImplemented', ...
    'estimate_hr의 필터링, FFT, BPM 및 유효성 판정을 구현해야 합니다.');
end
