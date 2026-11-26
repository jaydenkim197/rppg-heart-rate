# MATLAB 개발 구조

[통합 설계 명세서](master-design-specification.md)는 확정 방향과 실험 후보를 정의한다. [개발 계획](development-plan.md)에서 실행 근거 및 단계별 상태를 확인한다. 수식과 후보 비교에는 [문헌·강의 검토](literature-review.md)를 사용한다.

## 현재 코드와 구현 대상

| 경로 | 개발 단계 |
|---|---|
| `matlab/main.m`, `config.m` | 환경 점검과 경로·설정, RGB 영상 한 편에서 A~D 및 기본 POS 실행. 기본값은 A다. |
| `extract_rgb.m` | Fixed 또는 NCC 후보로 프레임 시각·RGB·좌표를 기록하고 실제 영상 범위에 있는 ROI 영역을 사용한다. Raw/Hard Masking을 비교하며 피부색 마스크와 추가 추적기는 개발 대상이다. |
| `apply_method.m`, `estimate_hr.m` | 픽셀 수 가중 Green, 필요한 경우 선형 재표본화, 대칭 Butterworth형 FFT Bandpass와 Hann·최대 bin. B의 공간 필터와 C의 색상 정규화 후보, D의 ROI별 POS와 품질 기반 후보를 같은 신호 분석기로 호출한다. |
| `evaluate_results.m`, `configs/experiments_template.csv` | 스칼라 BPM 참조와 방법별 결과를 동일 구간으로 연결한다. `run_benchmark`와 `rank_candidates`에서 후보 비교 결과와 채택 기준을 처리한다. 연속 참조는 시도별 [보관 규격](experiment-protocol.md#3-보관-규격)에 따른다. |
| `origin/feat/evaluation` 및 `origin/chungwanwoo-netizen-patch-1` | 팀원 구현 후보를 보존한다. 현재 브랜치의 기본 함수 계약에 필요한 부분을 선택적으로 재사용한다. |

## 공통 인터페이스

- `extract_rgb(video_file,settings)`의 `time_s`는 프레임별 영상 초, `raw_rgb`와 B의 후보 응답인 `filtered_rgb`와 호환 필드 `median_rgb`는 N×3×3(프레임·RGB·ROI), `pixel_counts`는 N×3이다. ROI 순서는 이마·왼쪽 볼·오른쪽 볼이다. `valid`는 프레임의 공통 관측 검사, `roi_valid`는 ROI별 N×3의 독립 관측 상태다. `roi_positions`는 ROI 좌표이며, 고정 사각형은 N×4×3 `[x,y,width,height]`를 사용한다. `raw_rgb`는 관측 ROI의 원본 평균이며 `measurement_rgb`는 Raw 또는 Hard Masking의 측정값이다. `saturation_fraction`과 `tracking_confidence`는 별도로 기록한다.
- `apply_method(rgb_data,method,settings)`는 `time_s,values,labels,method`를 반환한다. `values`의 각 열은 하나의 신호이며 기준 A~C는 단일 열, D는 ROI별 신호다. pooled POS는 D와 구분한다.
- `estimate_hr(method_signal,settings)`는 `predicted_bpm,status,failure_reason,quality`와 `time_s,filtered,frequency_hz,power`를 반환한다. 시각 유효성, 공백, 평탄, 대역 에너지, 품질 실패를 구분한다. 비교 시 동일한 관측 구간과 심박 대역을 사용한다.
- `evaluate_results(predictions,ground_truth,settings)`는 `video_id`와 동일 구간 기준 결과를 연결한다. 실패 시도, 기술별 유효율, 참조 누락, 참조가 있는 유효 예측의 MAE/RMSE를 구분한다.
- 실시간·다중 인원은 추정 시각과 정보 나이, ROI·ID의 개별 유효성을 추가한다. 기존 분석과 분리해 미래 입력 독립성과 ID 혼입을 검증한다.
