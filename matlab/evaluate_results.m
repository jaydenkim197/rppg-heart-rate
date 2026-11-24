function summary = evaluate_results(predictions, ground_truth, settings)
%EVALUATE_RESULTS 모든 시도의 예측값과 같은 시간대 GT를 비교할 함수 틀.
% 입력 표의 video_id와 평가 구간을 맞춰 비교한다.
% 성공 시도의 MAE/RMSE, 전체 시도의 성공 비율, 실패 원인을 함께 저장한다.

error('rppg:NotImplemented', ...
    'evaluate_results의 시간 구간 대조, 오차 집계와 결과 저장을 구현해야 합니다.');
end
