# Experimental protocol

## Capture
- 스마트폰 후면 RGB 카메라, 삼각대 고정.
- 거리: 0.5, 1, 2, 3, 4, 5 m.
- 권장: 1080p, 30 fps, 60초, 3명 이상, 거리별 3회 이상 반복.
- 조명, 노출, 시점, 움직임을 통제하고 실제 촬영 조건을 기록한다.
- 스마트워치 HR을 동시에 기록하고 영상과 시간 정렬한다. 평균/갱신 지연을 고려한다. 이는 HR 비교이며 GT 파형 검증이 아니다.

## Evaluation
- 방법 A–D에서 동일 ROI, 분석 구간 및 주파수 탐색 대역 적용.
- MAE와 RMSE(BPM), 유효 추정률(%), 실패 수 및 원인 기록.
- 실패 영상은 제외하지 않고 별도 집계한다. 유효 추정률의 분모는 전체 시도 수로 한다.
- 원본 RGB 시계열, 처리 후 시계열, FFT 스펙트럼, 방법별 MAE와 거리별 MAE 그래프 작성.
- 개선 기법과 판정 조건은 평가 전에 확정하고 변경 이력을 기록한다.

## Proposed record fields (private)
trial_id, subject_id, distance_m, repeat, fps, start_time, end_time, method, gt_bpm, estimated_bpm, valid, failure_reason

참가자 동의 및 접근 제한 필수. 공개 저장소에는 원본 데이터와 개인별 결과를 저장하지 않는다.
