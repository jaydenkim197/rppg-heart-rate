# MATLAB 개발 구조

현재 `main.m`과 `config.m`은 초기 환경 확인과 공통 설정을 담당한다. 나머지 `.m` 파일에는 함수 입력·출력의 약속과 구현 예정 상태를 표시했다. 예정 함수는 호출하면 `rppg:NotImplemented` 오류를 내도록 구성했다.

## 파일과 입출력

| 파일 | 입력 | 출력 및 역할 |
|---|---|---|
| `matlab/main.m` | 없음 | 공통 설정, 함수 경로 확인표. 로컬 폴더와 빈 기록 양식 준비 |
| `matlab/config.m` | 없음 | 경로, 주파수 범위, 거리, 필터 크기 등 설정 구조체 |
| `matlab/extract_rgb.m` | 영상 경로, 공통 설정 | 프레임 시각, 공통 ROI, 원본 및 미디언 처리 RGB 평균 |
| `matlab/apply_method.m` | RGB 데이터, 방법 A~D, 공통 설정 | 분석할 시간 신호와 부위 정보 |
| `matlab/estimate_hr.m` | 시간 신호와 부위 정보, 공통 설정 | BPM, 파형, FFT, 처리 상태, 부위별 결과 |
| `matlab/evaluate_results.m` | 모든 시도의 예측 결과, GT 표, 공통 설정 | 방법별·거리별 MAE/RMSE, 유효 추정률, 그래프와 결과 CSV |

## 데이터 약속

- 시간은 초, 주파수는 Hz, 심박수는 BPM, 거리는 m로 저장한다.
- `rgb_data.time_s`는 N×1 프레임 시각이다.
- `rgb_data.raw_rgb`와 `rgb_data.median_rgb`는 N×3×3 배열이다. 첫 축은 프레임, 두 번째는 R·G·B, 세 번째는 이마·왼쪽 볼·오른쪽 볼이다.
- `rgb_data.pixel_counts`는 N×3 부위별 피부 픽셀 수다. A~C와 기본 POS에서 동일한 ROI 집합의 평균을 구할 때 픽셀 수를 반영한다.
- `rgb_data.roi_positions`와 `rgb_data.valid`에는 프레임별 ROI 위치와 추적 상태를 저장한다. 모든 방법에서 재사용한다.
- `method_signal.time_s`는 공통 시각, `method_signal.values`는 N×K 시간 신호다. A~C는 한 열, D는 세 부위 신호와 기본 POS 비교 신호를 사용한다.
- `method_signal.labels`로 각 열의 의미를 기록하고 `method_signal.method`에 A~D를 저장한다.
- `estimate_hr`는 실제 시간 간격을 확인해 필요한 경우 일정 간격으로 재표본화한 뒤 필터링과 FFT를 수행한다.
- 결과에는 `video_id`, `method`, `predicted_bpm`, `status`, `failure_reason`을 기록한다. `status`는 `ok` 또는 `failed`다. 구현 예정 상태는 실행 오류로 알리고 실험 결과를 만들지 않는다.

## 구현 단계의 실행 순서

`main`에서 설정을 읽고 `extract_rgb`를 한 번 실행한다. 추출 결과를 공통으로 사용해 각 방법의 `apply_method`와 `estimate_hr`를 실행한다. 모든 시도의 결과를 모아 `evaluate_results`로 전달한다.

공간 필터는 `extract_rgb`에서 프레임별 R·G·B에 적용한다. `apply_method`의 B는 그 처리 결과를 선택한다. D의 기본 POS는 공통 ROI 집합의 RGB 평균을 사용하며, 개선안은 같은 영역을 세 부위로 나누어 신호 품질을 반영한다.

현재 `main`은 환경 확인까지만 수행한다. 위 연결은 기본 방법 A 구현부터 추가한다.
