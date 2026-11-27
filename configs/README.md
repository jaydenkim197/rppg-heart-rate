# 공통 설정과 실험 기록

MATLAB의 공통 설정은 `matlab/config.m`에서 관리한다. 실제 영상의 프레임 시각을 분석에 사용하고, 설정의 FPS와 촬영 길이는 권장 촬영 조건으로 사용한다.

`experiments_template.csv`는 빈 기록 양식이다. `main`을 처음 실행하면 `data/experiments.csv`로 복사한다. 이 로컬 파일에 촬영 조건과 같은 시간 구간의 스마트워치 평균 BPM을 기록한다. 기존 파일이 있으면 재사용한다.

| 열 | 의미 |
|---|---|
| video_id | 영상의 고유 번호 |
| subject_id | 이름 대신 사용하는 참가자 코드 |
| distance_m | 촬영 거리 |
| trial | 반복 번호 |
| video_file | 영상 파일 경로 |
| start_s, end_s | 영상에서 평가할 구간 |
| gt_bpm | 그 구간과 정렬된 스마트워치 평균 BPM |
| notes | 촬영 조건과 시간 정렬 관련 메모 |

자체 실험의 기준 심박은 Apple Watch로 기록한다. [촬영 메타데이터 양식](capture_metadata_template.csv)과 [워치 심박 양식](watch_hr_template.csv)을 로컬 `data/`에 복사해 첫 프레임 UTC와 측정의 시작·종료 UTC를 저장한다. `video_id`로 기존 실험 목록과 연결한다. 원본 시간대와 시각의 출처를 남기고 `gt_bpm`에는 같은 구간에서 관측된 유효 표본의 평균을 사용한다. 정렬이 확인되지 않은 경우 기준을 결측으로 기록한다. 평가 구간, 품질 판정 기준, 결측치 처리와 필터 설정은 평가 전에 정하고 모든 방법에 같은 기준을 적용한다. [수집 규격](../docs/experiment-protocol.md#3-보관-규격)

MATLAB에서 `windows`는 `video_id,start_s,end_s` 열이 있는 평가 창 표다. `captures`와 `watch`는 위 로컬 양식으로 준비한 표이며, `watch`에는 시도별로 확인된 워치와 모드에서 나온 행을 담는다. 시각은 UTC 문자열 또는 시간대가 지정된 `datetime`으로 가져온다. 분석 구간의 초는 첫 프레임 기준으로 입력한다.

```matlab
reference = align_watch_reference(windows, captures, watch);
summary = evaluate_results(predictions, reference, config());
trends = evaluate_watch_trends(summary.predictions, reference, rules);
```

외장 원본을 읽어 생성한 영상 매핑 CSV와 Apple Health 내보내기 ZIP을 이용해 로컬 양식을 준비할 수 있다. `tools/extract_watch_hr.py`는 영상 시간에 겹치는 워치 기록만 내보내고, 시도별 착용자를 촬영 순서에서 연결한다. 착용자 교대의 순간은 관측되지 않았으므로 `wearer_blocks.csv`의 시작과 끝은 해당 참가자 영상의 범위다. 원본 HealthData XML은 압축을 푼 파일로 쓰지 않는다.

```powershell
python tools/intake_field_videos.py "<원본 폴더>" "results/field-intake/workspace-media"
python tools/extract_watch_hr.py "results/field-intake/workspace-media/videos.csv" "<Apple Health ZIP>" "results/field-intake"
```

영상 인수는 QuickTime 시각과 프레임별 표시 타임스탬프를 기록한다. 원본 중복 검사가 별도로 필요한 경우 인수 명령에 `--sha256`을 추가한다. MATLAB의 `tools/check_field_video_decode.m`은 분석 창의 시작·중간·끝 부근에서 디코딩을 점검한다.

MATLAB에서 `prepare_field_reference("results/field-intake")`를 실행하면 `watch_reference.csv`와 `experiments_aligned.csv`를 작성한다. 카메라·워치 시계 오차 근거가 비어 있으면 명목 UTC 기준 커버리지와 초안 평균을 `nominal_gt_bpm`으로 표시하고, 실험 평가의 `gt_bpm` 칸은 비워 둔다. 촬영자가 두 시계가 일치했다고 확인한 경우 `ConfirmMatchingClocks=true`로 실행하여 60초 절대 BPM 비교를 사용한다. 이 경우 상태는 `ok_operator_confirmed_clock`이고 수치화하지 못한 시계 오차는 공란으로 남는다.

`reference`에는 관측 심박 평균, 표본 수, 첫·마지막 관측 시각, 중앙 표본 간격, 창 양 끝을 포함한 최대 공백, 정렬 오차와 실패 사유가 남는다. `rules`의 `lag_s`, `deadband_bpm`, `min_watch_samples`, `max_watch_gap_s`, `max_alignment_uncertainty_s`는 예비 기록 확인 후 사전 등록한 값을 전달한다. `trends`는 같은 길이의 창을 비교하고 워치의 새 관측을 확인한 뒤 ΔBPM MAE와 방향 일치율 및 분모를 기록한다.

## Method D 품질 후보와 POS 창

공개 개발 데이터의 `run_benchmark` 후보에서 `pos_window_s`에는 1.0, 1.6, 2.0, 3.0초를 사용한다. 이 값은 RGB 시간 정규화와 overlap-add 구간을 정하며 FFT 분석 구간은 시도 매니페스트의 시작·끝으로 지정한다. ROI별 D와 픽셀 수 가중 RGB의 pooled POS 대조군 모두에 POS 창을 적용한다.

| `pos_sqi` | Method D의 ROI 점수 |
|---|---|
| `energy_ratio` | 기존 기본값. 여과된 심박 탐색 대역의 파워 중 추정 피크의 ±0.10 Hz 안에 있는 비율이다. |
| `relative_peaks` | 가장 큰 여과 스펙트럼 진폭과 가장 큰 별도 국소 피크의 상대 차이다. 같은 주엽을 다시 세는 일을 줄이기 위해 기존 피크 여유 대역과 제로패딩 전 주엽 근사의 큰 값을 사용한다. |
| `cross_correlation` | 여과된 인접 2초 구간의 평균을 각각 제거한다. ±0.5초 내 최대 정규화 상관의 양수 부분을 구간 쌍에 걸쳐 평균한다. 두 개의 완전한 구간이 필요하다. |
| `kurtosis` | 중심화한 여과 전 ROI 신호의 Pearson 첨도 역수다. 1에 가까울수록 극단값이 적다는 작업 가설을 비교한다. |
| `none` | 수학적으로 유효한 ROI에 점수 1을 부여한다. 품질 컷을 건너뛰고 기존 평탄·결측·시간·탐색 대역 검사는 적용한다. |

각 점수의 범위는 0~1이다. 구현은 상대 스펙트럼 피크 및 연속 구간 상관의 정의, Pearson 첨도의 정의를 참고했다. 첨도 역수와 주엽 제외 폭은 프로젝트 후보 정의다. 실제 심박 오차에 대한 식별력을 개발 데이터에서 검증한 후 사용할 품질 기준을 고정한다. [Ernst 등 2020](https://www.cinc.org/archives/2020/pdf/CinC2020-165.pdf) · [Elgendi 등 2024](https://doi.org/10.1038/s44328-024-00002-1)

## STAPLE 실행 의존성 검사

공식 MATLAB 구현 `7b6b5b579a7cd25acae6bcabe93f8dfb78040215`의 Windows x64 바이너리를 MATLAB R2026b에서 확인했다. 합성 96×128 RGB의 FHOG 계산은 성공했다. `mexResize`는 동봉 OpenCV 2.4.2 DLL을 검색 경로에 추가한 뒤에도 `MATLAB:mex:ErrInvalidMEXFile`을 반환했다. 수정 없이 실행한 `trackerMain`도 첫 `getSubwindow` 호출에서 중단됐다. 의존성 검사에서 두 OpenCV DLL은 레거시 `tbb.dll`을 가져온다. 공식 아카이브에는 이 DLL이 없고 MATLAB 설치에는 `tbb12.dll`이 있었다. 현재 MATLAB에서 선택된 C++ MEX 컴파일러는 0개였다. [STAPLE 공식 구현](https://github.com/bertinetto/staple/tree/7b6b5b579a7cd25acae6bcabe93f8dfb78040215) · [Intel TBB 호환성 안내](https://cdrdv2-public.intel.com/772619/onetbb_get-started-guide_2021.6-772619.pdf)

호환되는 Windows x64 TBB 런타임을 확보하거나, 지원되는 C++ MEX 컴파일러로 DSST의 `mexResize` 소스를 호환 OpenCV에 재빌드한 후 추적을 재검증한다. 후보 등록 전 프레임을 디스크에 쓰지 않는 어댑터에서 첫 프레임 ROI 바운딩 박스, MATLAB 행·열 순서 변환 및 원본 프레임 좌표 복귀를 확인한다. 현재 상태는 STAPLE 추적 비교 미실행이다. [업스트림 빌드 안내](https://github.com/bertinetto/staple/blob/7b6b5b579a7cd25acae6bcabe93f8dfb78040215/README.md#faq)
