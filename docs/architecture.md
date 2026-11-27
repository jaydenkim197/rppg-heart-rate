# MATLAB 개발 구조

[통합 설계 명세서](master-design-specification.md)는 확정 방향과 실험 후보를 정의한다. [개발 계획](development-plan.md)에서 실행 근거 및 단계별 상태를 확인한다. 수식과 후보 비교에는 [문헌·강의 검토](literature-review.md)를 사용한다.

## 현재 코드와 구현 대상

| 경로 | 개발 단계 |
|---|---|
| `matlab/main.m`, `config.m` | 환경 점검과 경로·설정, RGB 영상 한 편에서 A~D 및 기본 POS 실행. 기본값은 A다. |
| `extract_rgb.m` | Fixed·NCC·KLT 후보로 프레임 시각·RGB·좌표를 기록하고 실제 영상 범위에 있는 ROI 영역을 사용한다. KLT는 평행이동 후보이며 추적 신뢰도는 현 추적 초기화 시점의 특징점 대비 유효 일치점 비율이다. 선택 후보 `klt_ncc_reacquire`는 상실 시 현재 프레임에서 초기 NCC 패치와 일치하는 위치를 찾고 KLT를 재초기화한다. 재검출 프레임은 `reacquired`로 기록한다. Raw/Hard Masking을 비교하며 피부색 마스크와 추가 추적기는 개발 대상이다. |
| `apply_method.m`, `estimate_hr.m` | 픽셀 수 가중 Green, 필요한 경우 선형 재표본화, 대칭 Butterworth형 FFT Bandpass와 Hann·최대 bin. B의 공간 필터와 C의 색상 정규화 후보, D의 ROI별 POS와 품질 기반 후보를 같은 신호 분석기로 호출한다. |
| `evaluate_results.m`, `configs/experiments_template.csv` | 스칼라 BPM 참조와 방법별 결과를 동일 구간으로 연결한다. `run_benchmark`와 `rank_candidates`에서 후보 비교 결과와 채택 기준을 처리한다. 자체 실험의 Apple Watch 시각과 영상의 첫 프레임 UTC는 시도별 [보관 규격](experiment-protocol.md#3-보관-규격)에 따른다. |
| `align_watch_reference.m`, `evaluate_watch_trends.m` | 정규화된 UTC 측정으로 평가 창의 BPM 평균과 관측 범위를 계산한다. 동일 영상·후보에서 정해 둔 시간 간격만큼 떨어진 창을 짝지어 ΔBPM 오차와 방향 일치를 계산한다. |
| `origin/feat/evaluation` 및 `origin/chungwanwoo-netizen-patch-1` | 팀원 구현 후보를 보존한다. 현재 브랜치의 기본 함수 계약에 필요한 부분을 선택적으로 재사용한다. |

## 공통 인터페이스

- `extract_rgb(video_file,settings)`의 `time_s`는 프레임별 영상 초, `raw_rgb`와 B의 후보 응답인 `filtered_rgb`와 호환 필드 `median_rgb`는 N×3×3(프레임·RGB·ROI), `pixel_counts`는 N×3이다. ROI 순서는 이마·왼쪽 볼·오른쪽 볼이다. `valid`는 프레임의 공통 관측 검사, `roi_valid`는 ROI별 N×3의 독립 관측 상태다. `roi_positions`는 ROI 좌표이며, 고정 사각형은 N×4×3 `[x,y,width,height]`를 사용한다. `raw_rgb`는 관측 ROI의 원본 평균이며 `measurement_rgb`는 Raw 또는 Hard Masking의 측정값이다. `saturation_fraction`과 `tracking_confidence`는 별도로 기록한다.
- `apply_method(rgb_data,method,settings)`는 `time_s,values,labels,method`를 반환한다. `values`의 각 열은 하나의 신호이며 기준 A~C는 단일 열, D는 ROI별 신호다. pooled POS는 D와 구분한다.
- `estimate_hr(method_signal,settings)`는 `predicted_bpm,status,failure_reason,quality`와 `time_s,filtered,frequency_hz,power`를 반환한다. 시각 유효성, 공백, 평탄, 대역 에너지, 품질 실패를 구분한다. 비교 시 동일한 관측 구간과 심박 대역을 사용한다.
- `evaluate_results(predictions,ground_truth,settings)`는 `video_id`와 동일 구간 기준 결과를 연결한다. 실패 시도, 기술별 유효율, 참조 누락, 참조가 있는 유효 예측의 MAE/RMSE 및 Error SD를 구분한다. `evaluate_watch_trends`는 `align_watch_reference`의 표본 수, 구간 양 끝을 포함한 최대 공백, 정렬 불확실성과 신규 워치 관측 여부를 검사한다. 기준 부족과 rPPG 추정 실패는 별도 상태다.
- 실시간·다중 인원은 추정 시각과 정보 나이, ROI·ID의 개별 유효성을 추가한다. 기존 분석과 분리해 미래 입력 독립성과 ID 혼입을 검증한다.

### 자체 촬영의 프레임 시각과 ROI 좌표계

판독과 ROI 지정은 같은 `VideoReader` 표시 프레임을 사용한다. `x`는 열, `y`는 행이며 좌표와 크기는 1부터 시작하는 픽셀 단위다. 자체 MOV는 인코딩 크기가 3840×2160이며 재생 행렬을 적용한 표시 프레임은 2160×3840이다. 입력 ROI는 표시 크기의 프레임에서 지정하고 유효 범위를 검사한다. [MATLAB VideoReader](https://www.mathworks.com/help/matlab/ref/videoreader.html)

자체 평가의 `[0,60)`초는 순차 `readFrame` 직전의 `CurrentTime`으로 판정한다. 명목 FPS는 타임스탬프 대체에 쓰지 않는다. `check_field_frame_timing`은 각 파일의 표시 프레임 크기를 검사하고 실제 순차 판독 시각을 입수 시 저장한 MOV PTS와 비교한다. `FullWindowIds`를 명시한 영상은 분석 창 전체와 다음 프레임의 경계를 검사한다. 확인 결과 CSV는 개인별 파일 경로를 가진 입력 매니페스트와 함께 로컬에 저장한다. [MATLAB readFrame](https://www.mathworks.com/help/matlab/ref/videoreader.readframe.html)

`selftest_field_coordinates(ffmpegPath)`는 재생 행렬이 붙은 비대칭 합성 HEVC MOV로 회전 방향, 표시 프레임의 ROI 추출 평균과 경계 오류를 확인한다. FFmpeg는 합성 표본 생성에 사용한다.
