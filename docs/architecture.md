# MATLAB 개발 구조

| 파일 | 처리 |
|---|---|
| `main.m` | 환경을 확인하고 영상 한 편 또는 실험 CSV로 전체 분석을 실행 |
| `config.m` | 공통 경로, 거리, ROI 비율, 신호와 품질 기준 |
| `extract_rgb.m` | 얼굴 검출·KLT 추적, 피부 영역별 RGB 및 공간 필터를 적용한 Green 평균 |
| `prepare_rgb.m` | 공통 분석 구간 검증, 피부 픽셀 수 가중 평균, 일정한 시간 간격으로 보간 |
| `apply_method.m` | Green, 미디언 처리 Green, RGB 비율, POS 신호 생성 |
| `estimate_hr.m` | 대역통과, FFT, 피크 품질 확인, BPM 및 D의 신호 품질 가중 평균 |
| `evaluate_results.m` | GT 비교, MAE·RMSE·유효 추정률 계산, 실패와 결과 파일 저장 |
| `save_trial_plots.m` | ROI 확인 이미지, 원본 RGB, 처리 후 신호와 FFT 그림 |
| `selftest_rppg.m` | 합성 RGB 신호와 결측·평탄 신호 점검 |

## 함수가 주고받는 값

- `extract_rgb`는 영상 구간에 해당하는 프레임의 시각과 색을 반환한다. `raw_rgb`는 N×3×3이며 각 축은 프레임, R·G·B, 이마·영상 왼쪽 볼·영상 오른쪽 볼이다. `median_green`과 `pixel_counts`는 N×3, `roi_positions`는 N×4×2×3, `valid`는 N×1이다.
- `prepare_rgb`는 같은 구간의 균일 시각 `time_s`와 초당 표본 수 `fs`를 정한다. `mean_rgb`는 각 프레임에서 피부 픽셀 수로 가중한 전체 ROI 평균, `median_green`은 동일한 ROI의 필터링 후 Green 평균이다.
- `apply_method`는 A·B·C·POS의 시간 신호를 한 열, D의 부위별 POS 신호를 세 열로 반환한다.
- `estimate_hr`는 추정값, 피크 품질, 처리 상태와 실패 사유, 표시용 파형과 FFT를 반환한다. D의 그림에는 신호 품질이 가장 좋은 ROI의 파형과 스펙트럼을 표시하고, CSV에는 부위별 BPM과 가중 평균한 최종 BPM을 남긴다.
- `evaluate_results`는 영상 고유 코드로 예측 표와 스마트워치 표를 연결한다. `status`는 추정 성공 여부, `gt_status`는 비교 기준의 확보 여부다.

시간은 초, 주파수는 Hz, 심박수는 BPM, 거리는 m를 사용한다. `main`은 영상별로 ROI와 RGB를 한 번 계산해 모든 방법에 전달한다.
