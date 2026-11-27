# rPPG 개발 및 실험 진행 계획

[통합 설계 명세서](master-design-specification.md)가 기술 범위와 비교 순서의 기준이다. 촬영 전에 사용할 규격은 [촬영·데이터 수집 프로토콜](experiment-protocol.md)에 있다. 11/27 09:00 KST 촬영은 장비·시간축·참조 기록을 먼저 확인하며, 최적화는 촬영 매체를 확보한 뒤에도 개발 데이터로 진행할 수 있다. 기존 제안과 회의 이력은 [기술 결정 검토서](decision-review.md) 및 [팀 회의록](meetings/2026-11-24.md)에 보존한다.

## 단계와 상태

| 단계 | 상태 및 통과 기준 |
|---|---|
| 설계와 촬영 규격 | `IMPLEMENTED` · 데이터/함수 계약과 현장 점검 목록을 작성했다. 장비 실측과 팀 공통 인터페이스 조율은 별도다. |
| 팀원 코드 점검 | `VERIFIED` · 독립·모듈형 프로토타입 모두 합성 테스트를 실행했다. 툴박스 확보 이후의 모듈형 재검증은 아래에 기록했다. |
| Method A · 고정 ROI MVP | `VERIFIED` · 고정 ROI Method A의 합성 신호 및 영상 테스트. 동일 피부 영역 추적 및 실제 영상 정확도는 검증 대기 상태다. |
| 자체 기준 심박 및 시각 정렬 | `DECISION` · Apple Watch를 유일 기준으로 사용한다. UTC 구간 집계와 ΔBPM·방향 일치 검사는 구현했다. 영상 첫 프레임 UTC 확인, 워치 내보내기, 실제 기록 해상도와 지연은 현장 점검 대상이다. |
| 공개 데이터 평가 | `IMPLEMENTED` · Fixed/NCC·시간/FFT 배치 비교와 결과 저장. UBFC 42쌍 및 MPU 4쌍의 파일 점검을 완료했다. UBFC 개발 분할로 초기 비교를 실행했으며 독립 성능 평가가 남아 있다. |
| 순차 최적화 및 A~D | `IMPLEMENTED` · 비교 실행기와 A~D/POS 후보의 초기 구현. 최종 후보 선정, 기준 확정 및 주요 조합 재검증은 남아 있다. |
| 독립 검증 및 자체 평가 | `PLANNED` · 독립 공개 자료와 예비 장비를 확인한 뒤 커밋·설정을 고정하고 자체 본 실험을 평가한다. |
| 실시간 및 다중 ID | `DEFERRED` · 필수 단일 인원 기능 이후에 미래 데이터 미사용, 유지 표시의 실패 집계 및 ID 혼입을 검증한다. |

## 2026-11-26 자체 기준 심박 변경

MAX30102·ESP32와 LED 광학 트리거 계획을 철회했다. 현장 예비 영상의 첫 프레임 UTC와 Apple Watch 측정 시작·종료 시각으로 공통 시간축을 만든다. 60초 평균 BPM 비교를 유지하고, 예비 기록의 관측 간격·공백·시각 불확실성을 확인한 뒤 ΔBPM 및 방향 일치의 시간 간격과 최소 관측 조건을 정한다. 변화 감지 지연은 시간 정렬과 워치 관측이 충분한 구간에서 워치 기준으로 기록한다. 촬영/워치 내보내기 실측과 지연 검증은 별도다. [결정 변경 이력](decision-review.md#2026-11-26-기준-심박-변경) · [수집 규격](experiment-protocol.md#3-보관-규격)

## 2026-11-26 팀원 코드 재사용 검토

- `origin/feat/evaluation@6494a96`의 독립 MATLAB `rppg_main('selftest')`를 임시 디렉토리에서 실행했다. A/B/C/D/POS/POS_equal의 합성 75 BPM, 평탄·NaN·대역 밖 처리 및 MAE/RMSE/유효률 검사가 통과했다. 실제 영상, ROI 추적 정확도, 최종 성능은 이 테스트 범위 밖이다. [프로토타입](https://github.com/jaydenkim197/rppg-heart-rate/blob/6494a96d6ba287603a9b082160ad7dfec2121781/docs/sangjun/rppg_main.m)
- `origin/chungwanwoo-netizen-patch-1@c632545`의 모듈형 `selftest_rppg`는 `estimate_hr`에서 `butter`를 찾지 못해 중단됐다. 소스는 KLT/Computer Vision Toolbox 및 `butter/filtfilt`를 사용한다. 시각·피부 픽셀 가중 구조, CSV 평가, 테스트 자산을 참고한다. 16픽셀·90% 등의 수치는 예비 설정이다. [모듈형 코드](https://github.com/jaydenkim197/rppg-heart-rate/tree/c6325457697e0ce2e75144d2a9b5136cff78d31e/matlab)
- MVP는 기존 함수·CSV 계약과 MATLAB `VideoReader`, 배열 연산, `fft/ifft`를 재사용한다. 팀원 독립 코드에서 실제 시각 기록, 픽셀 가중 Green 및 대칭 주파수 영역 Bandpass 설계를 가져온다. 공통 ROI 오류 처리와 확장 방식은 최신 검토서에 맞춘다. 팀원 브랜치의 통합은 별도 PR 및 인터페이스 검토 사항이다.

## 마일스톤 기록

- `408528f` · 현장 장비 점검, Apple Watch·PPG·동기화 이벤트의 수집 항목을 기록했다. 당시의 연속 PPG와 LED 계획은 위 설계 변경으로 대체됐다.

- Method A · MATLAB R2026b에서 `selftest_rppg` 통과. 합성 1.25 Hz 신호와 360프레임 AVI를 모두 75.00 BPM으로 추정했다. 균일 시각 보존, 불규칙 시각 재표본화, 평탄·NaN·대역 밖·긴 공백 실패를 점검했다. Bandpass 응답/창/피크/검사 수치는 비교 전 시제품 설정이다. 긴 관측 공백은 코드로 반환하며 구간 분리 분석은 남아 있다.

## 공개 데이터 평가 초기 점검

`run_benchmark(trials, split, candidates, outputDir)`는 비대화형 Fixed/NCC ROI 시험을 실행한다. `trials`의 열은 `subject_id,video_id,split,video_file,start_s,end_s,roi_boxes,gt_bpm`이다. `roi_boxes`는 3×4 좌표 행렬을 담은 셀 열이다. `distance_m`은 선택 항목이다. 같은 피험자가 여러 분할에 있으면 실행을 중단한다. 독립 검증·본 실험에서는 방법별 단일 고정 후보만 실행한다.

`candidates`는 `name`과 `overrides`를 갖는 구조체 배열이다. 현재 배치 비교는 Butterworth형·Ideal·Gaussian Bandpass, 미적용 연구 대조군, Rectangular/Hann/Hamming, FFT 격자 세분화와 포물선 피크를 지원한다. 같은 영상의 RGB 관측 결과를 재사용하고 실패·참조 누락을 보존한다. 출력 위치를 지정하면 `predictions.csv`, `metrics.csv`, `trials.json`, `settings.json`에 유효 여부, MAE·RMSE·Bias·허용 오차 비율과 실제 설정을 기록한다.

- UBFC Dataset 2 공식 자료의 `PPG/HR/time_s` 3행 형식은 `read_ubfc_reference`로 읽는다. 초기 개발에서는 공개 Drive의 목록과 공급자 안내·예제를 확인했다. 당시 다운로드 제한으로 실자료를 확보하지 못했으며, 후속 확보·검증은 아래 기록에 있다. [UBFC-rPPG 공식 데이터](https://sites.google.com/view/ybenezeth/ubfcrppg)
- MPU-rPPG 공개 샘플 파일 ID `55553417`(MP4), `55553414`(CSV)를 로컬에 확보하고 크기 및 게시된 MD5를 확인했다. 영상은 640×480, 약 60 fps, 약 742.467초다. CSV는 시각 열 없이 0부터 연속하는 `Count`이며 44,548행이 명목 영상 프레임 수와 일치했다. `Count/FrameRate`를 참조 시각으로 사용한 결과는 동기화가 실측된 결과와 구분한다. [MPU-rPPG 공개 샘플](https://figshare.com/articles/dataset/MPU-rPPG_Sample_Dataset/29377835)
- 첫 15초의 개발용 고정 ROI로 8개 후보를 실행했다. 후보별 유효 결과 1건에서 절대 오차는 약 27.1–31.1 BPM이었다. 움직임이 있는 단일 샘플이며 피험자 단위 독립 검증·추적·동기화 게이트를 통과한 설계가 아니다. 후보 채택은 보류한다. 결과 CSV와 원본은 로컬에 보관했다.
- `selftest_rppg`에서 8개 후보, 실패 시도의 분모 유지, 피험자 분할 위반 거부, UBFC 참조 파서의 합성 입력을 검증했다.

- Raw/Hard Masking 및 Fixed/NCC · `selftest_rppg`에서 3픽셀 평행이동 추적, 포화 픽셀 1개 제거, 원시 RGB 보존을 확인했다. NCC는 초기 템플릿의 평행이동만 추적한다. 0.65 상관 컷과 재탐색 증가는 예비값이며 피부색 마스크, 회전·크기 변화 및 장기 가림 복구는 미검증이다.
- 동일한 MPU 공개 샘플 개발 구간에서 Fixed Raw/Hard는 각 31.106 BPM, NCC Raw/Hard는 각 15.106 BPM의 절대 오차를 냈다. 네 경우 모두 ROI 관측률 100%였으며 추적 성공률이 심박 정확도를 보장하지 않았다. 샘플 1개, 추정된 참조 시각의 초기 결과이므로 추적기·포화 처리 선택 근거로 확정하지 않았다.

## A–D 초기 비교와 채택 조건

A, B의 공간 필터, C의 색상 보정, D의 부위별 POS와 pooled POS 기준 대조를 각각 실행할 수 있다. B의 다섯 필터, C의 다섯 정규화, D의 다섯 ROI 결합은 비교 후보다. POS 창·SQI 경계의 현재 설정은 예비값이다. D는 유효 ROI만 결합하고 한 영역만 유효해도 후보를 계산한다. SQI의 최종 지표와 수용 기준은 독립 검증 대상이다.

`run_benchmark`의 후보 구조체에는 `name`, `overrides`와 선택적인 `method`(A/B/C/D/POS)를 둔다. 생략한 방법은 A다. 비교 시 같은 영상·구간·초기 ROI를 고정한다. 독립 검증과 본 실험에서는 방법별 고정 후보 하나를 평가할 수 있다. C의 미적용 대조는 같은 조건의 A다. FFT만 사용한 연구 대조군은 필수 A와 별도로 기록한다.

`rank_candidates`는 개발 데이터의 지표를 사전 등록한 목표·불가 기준으로 0~1에 매핑한다. `criteria` 표의 열은 `metric,target,unacceptable,weight,gate`이며, 최소 짝지어진 피험자 수와 동점 허용폭을 별도로 입력한다. 게이트 미달, 참조 부족, 연구 대조군, 동점 또는 탈락 이유를 기록한다. 이 기능으로 추후 선정하며 단일 개발 샘플로는 조합을 고정하지 않는다.

같은 MPU-rPPG 15초 개발 구간에서 Fixed/NCC, Raw/Hard를 실험한 뒤, 비교 실행 확인을 위해 NCC를 공통 후보로 고정하고 아래 다섯 경로를 실행했다. 참조 시각은 CSV의 Count를 영상 명목 FPS로 나눴다. 원본 영상, 개인별 결과, 중간 시계열 및 설정 로그는 로컬에 보존했다. [MPU-rPPG 공개 샘플](https://figshare.com/articles/dataset/MPU-rPPG_Sample_Dataset/29377835)

| 경로 | 이 한 구간의 절대 오차 (BPM) |
|---|---:|
| A Green | 15.11 |
| B Median | 15.11 |
| C RGB Sum | 7.11 |
| 기본 pooled POS | 7.11 |
| D SQI 가중 POS | 2.36 |

파일별 참조 시간 정렬의 정확도, KLT·CAMShift·STAPLE·MediaPipe 비교, SQI 후보 검증, 최종 통과 기준, 조합 재검증 및 현장 성능은 계속 확인해야 한다. 필수 단일 인원 검증 후 실시간·다중 인원으로 전환한다.


## 2026-11-26 공개 데이터 인수 및 Apple Watch 평가 코드

- UBFC Dataset 2의 영상 42개에서 MATLAB으로 시작과 끝 부근을 읽었고 기준 파일 42개를 파싱했다. 원본 9개에 시각·PPG·HR이 모두 같은 중복 표본 11개가 있었다. 동일 표본만 파싱 시 중복을 제거한다. 서로 다른 값의 동일 시각과 역행 시각은 오류다. 원본은 그대로 보관한다. 공급자의 시간축과 영상 길이의 끝 차이는 절댓값 최대 0.172초였다. 이 값은 프레임 단위 정렬 정확도 검증을 대신하지 않는다. [공급자 데이터 및 이용 안내](https://sites.google.com/view/ybenezeth/ubfcrppg)
- MPU의 로컬 MP4·CSV 8개는 Figshare의 바이트 수와 MD5가 일치했다. MATLAB의 시작·끝 부근 디코딩과 각 CSV의 연속 `Count` 행 수가 해당 영상 프레임 수와 일치하는 것을 확인했다. `Count / FrameRate`는 근사 시간축으로 취급한다. 표본 시각과 하드웨어 지연의 독립 검증은 남아 있다. [MPU-rPPG 공개 샘플](https://figshare.com/articles/dataset/MPU-rPPG_Sample_Dataset/29377835)
- UBFC 피험자는 숫자 순서로 정렬하고 세 번째마다 독립 검증에 배정해 개발 28명·독립 14명으로 나눴다. 이 분할의 독립 자료는 디코딩과 형식 점검만 했다. 최적화 및 후보 선정에는 개발 자료만 사용한다. 식별 가능한 자료와 개인별 결과 및 실험 매니페스트는 로컬에 둔다.
- 초기 비교는 `[0,30)`초, Method A, 첫 프레임 Cascade 얼굴 상자의 상대 위치로 정한 이마·양 볼 ROI에서 수행했다. 동일 좌표로 Fixed/NCC와 Raw/Hard를 비교하고 공급자 HR 행 평균을 초기 실행의 참조로 사용했다. 공급자 논문 재현 및 본 선택 실험에서는 접촉 PPG로부터 산출한 참조와 시간축을 별도로 확인한다. 첫 4명의 초기 실행에서 네 조합 모두 4/4 유효했다. 평균 절대 오차는 Fixed 5.01 BPM, NCC 12.97 BPM이며 각 추적기 내부의 Raw/Hard 결과는 같았다. 초기 실행은 후보 채택 근거로 사용하지 않는다. 같은 구간의 접촉 PPG에 현재 Method A 시간 처리를 그대로 적용한 진단에서 16/28개가 유효했고 12개는 프레임용 공백 기준에 걸렸다. 유효 16개의 접촉 PPG 추정과 센서 HR 평균 사이 평균 절대 차이는 9.54 BPM이었다. 접촉 PPG의 공백 처리와 참조 산출 방식을 별도로 검증한다.
- `align_watch_reference`는 이미 대상 워치와 기록 모드로 정규화한 표에서 구간 평균과 표본 수·간격·공백·정렬 오차를 계산한다. `evaluate_results`는 표본 Error SD를 두 쌍 이상에서 산출한다. `evaluate_watch_trends`는 사전 등록한 관측 조건 및 새로운 워치 측정이 충족된 창에 ΔBPM·방향 일치율을 산출한다. 워치의 실제 기록 주기와 측정 지연, ISO 시각 산출 장치의 오차, 워치 대비 변화 감지 지연의 자동화는 검증 또는 구현 대기 상태다. [로컬 수집 및 사용 규격](../configs/README.md)
- MATLAB R2026b에서 `selftest_rppg`를 통과했다. 타임스탬프 정규화, 경계의 점·구간 표본, 워치 중복·충돌·누락, ΔBPM 분모와 UBFC 중복 처리를 합성 입력으로 확인했다. `butter/filtfilt` 호출과 `vision.PointTracker`의 인공 프레임 2픽셀 이동도 통과했다. 별도 복사본에서 모듈형 팀원 브랜치의 `selftest_rppg`를 재실행해 A–D/POS 약 72.07 BPM과 짧은·긴 공백 등 합성 검사를 확인했다. 이 작업 브랜치의 KLT 연결은 개발 대상이다.

### UBFC 개발 28명 초기 비교

| 추적기 | 포화 처리 | 유효/전체 | MAE (BPM) | RMSE (BPM) |
|---|---|---:|---:|---:|
| Fixed | Raw 및 Hard | 28/28 | 14.685 | 23.976 |
| NCC | Raw 및 Hard | 26/28 | 11.375 | 19.466 |

같은 26개 유효 쌍에서 MAE는 Fixed 13.065 BPM, NCC 11.375 BPM이었다. NCC의 두 실패는 `nonfinite_or_missing_signal`로 남겼다. 공급자의 센서 HR 행을 사용한 개발용 초기 비교다. 접촉 PPG로 산출한 기준의 유효성과 KLT 등 다른 추적기를 확인한 뒤 사전 등록한 기준으로 후보를 비교한다. 개인별 결과와 ROI 매니페스트는 로컬 `results/public-intake/ubfc-development-smoke/`에 보관했다.

### UBFC 접촉 PPG 참조 후보 및 KLT 구현

- `estimate_ubfc_reference`는 시각이 불균일한 접촉 PPG 표본을 그대로 사용한다. 실제 시각에서 선형 추세를 제거하고 MATLAB Signal Processing Toolbox의 Lomb–Scargle 스펙트럼으로 0.7–3.0 Hz의 최대 피크를 구한다. 3 Hz의 한 주기인 1/3초보다 큰 관측 공백은 양쪽 창 경계를 포함해 결측으로 처리한다. 긴 공백, 표본 부족, 평탄 신호, 심박 대역 에너지 부족의 원인을 구분한다. 센서가 표시한 BPM은 참조 산출에서 독립적인 비교 기록이다. [UBFC 제공자 안내](https://sites.google.com/view/ybenezeth/ubfcrppg) · [MATLAB Lomb–Scargle 스펙트럼](https://www.mathworks.com/help/signal/ref/plomb.html)
- MATLAB에서 공개 개발 28명의 첫 30초 접촉 PPG 참조를 모두 산출했다. 센서 표시 HR 평균과의 절대 차이 중앙값은 2.841 BPM이다. 참조 결과에는 표본 수, 관측 범위, 최대 공백과 대역 에너지 비율을 저장했다. 참조 산출에는 접촉 PPG와 표본 시각만 사용했다.
- 팀원 후보의 Shi–Tomasi 특징점, `vision.PointTracker`와 역방향 오차 검사를 재사용했다. 현 단계 KLT는 초기 세 ROI를 감싸는 영역에서 최대 80점을 감지하고, 2픽셀 허용 오차 내의 평행이동 추정에 최소 4점을 사용한다. 기존 직사각형 ROI와 픽셀 관측 계약을 유지하며, 점이 부족하면 관측을 실패로 표시한다. 회전·스케일 보정 및 점 재검출은 후속 비교 대상이다. [MATLAB KLT 추적기](https://www.mathworks.com/help/vision/ref/vision.pointtracker-system-object.html)
- MATLAB `selftest_rppg`에서 불규칙한 합성 PPG의 75 BPM, 긴 공백·평탄 실패, 합성 영상의 KLT 3픽셀 이동과 추적 상실을 확인했다.

### 2026-11-27 공개 개발 추적 비교

공개 개발 28명의 동일한 `[0,30)`초 구간과 초기 ROI에서 Method A 및 Raw를 비교했다. Fixed/NCC의 기존 예측을 위 접촉 PPG 참조로 다시 채점했고 같은 창에 KLT를 새로 실행했다. 최대 공백 1/3초 이하 기준을 모든 참조 창에 적용했다. 검증 설정과 결과는 로컬 `results/public-intake/contact-klt-development/`에 보관했다.

| ROI 추적 | 유효/전체 | MAE | RMSE | 동일 21개에서 MAE |
|---|---:|---:|---:|---:|
| Fixed | 28/28 | 17.320 | 29.301 | 7.763 |
| NCC | 26/28 | 14.020 | 24.348 | 9.857 |
| KLT | 22/28 | 10.681 | 19.396 | 10.428 |

오차 단위는 BPM이다. 추적 실패 후 관측이 부족해 NCC 2개, KLT 6개에서 `nonfinite_or_missing_signal`로 기록됐다. 방법별 유효 건의 단순 평균과 공통 유효 창의 순위가 달랐다. KLT 종합 선정은 유효률과 가림·재검출을 추가 검증한 뒤 판단한다.

접촉 참조는 이동 중앙값으로 기준선을 제거하고 실제 peak 간격을 사용한 보조 계산과도 비교했다. 28개에서 절대 차이 중앙값은 1.455 BPM이며, 4개는 5 BPM보다 크게 달랐다. 시간에 따라 변하는 심박의 단일 창 대표값에 관한 불확실성으로 기록했다. 독립 검증 14명은 참조 산출과 추적 비교에서 보존했다.

#### KLT 결측 진단과 관측 구간 재분석

개발 자료의 KLT 실패 6개만 다시 디코딩해 실제 프레임 시각에 따른 결측을 측정했다. 영상별 최장 연속 결측은 0.134~23.400초였으며, 4개는 분석 창 끝에서 관측이 끊겼다. 기존 추정기와 접촉 참조에 같은 최장 연속 관측 구간을 전달했다. 데이터 보간 없이 구간 길이 6.633~19.206초에서 6개 모두 추정과 참조가 산출됐지만 MAE는 37.674 BPM이었다. 이 값은 단축 구간의 진단 결과다. 기존 30초 분석의 실패 6개는 전체 유효률에 그대로 집계했다.

전체 28개에서 절대 오차 5 BPM 이내의 시도 수는 Fixed 16개, NCC 15개, KLT 13개다. Fixed와 KLT가 함께 유효한 22개에서 MAE는 각각 8.864와 10.681 BPM이었다. KLT가 실패한 6개에서 Fixed의 MAE는 48.324 BPM이었다. 유효률과 짝지어진 오차를 함께 기록하고, KLT의 다음 비교는 실제 관측을 다시 확보하는 재검출 후보를 대상으로 한다. 로컬 결측 진단은 `results/public-intake/contact-klt-development/klt_failed_gap_diagnostics.csv`에 기록했다.

## 2026-11-27 자체 실험 인수

- 기본 거리별 영상 54개를 카메라 내장 시각으로 정렬해 3회 × 3명 × 6거리에 배정했다. 파일명 번호 하나가 연속하지 않았으나 영상 수, 고유 촬영 시각, 시도 조합이 모두 일치했다. 실제 영상은 H.265(hvc1), 인코딩 해상도 3840×2160, 명목 60 fps, 약 69.8~76.4초다. 분석 창은 첫 60초를 공통으로 사용한다.
- Apple Health ZIP에서 촬영 영상 안에 있는 워치 심박 기록만 정규화했다. 첫 60초마다 8~13개 표본이 있었고, 창별 중앙 간격의 중앙값은 5초, 창 경계를 포함한 가장 긴 공백은 24초였다. 대부분 Workout 시각과 겹쳤고 2개 표본은 확인된 Workout 구간 밖이었다. 착용자는 촬영 순서의 9개 블록으로 배정했고 영상 사이의 실제 교대 순간은 관측되지 않았다.
- 촬영자가 두 기기의 시계가 일치했다고 확인했다. 이 확인은 같은 60초의 절대 BPM 비교에 사용하며, 정렬 오차 범위는 실측 근거가 없어 공란으로 남긴다. 초 단위 변화 검증과 변화 감지 지연은 기준 장치의 실제 표본 간격 및 시계 불확실성에 맞는 조건에서만 평가한다.
- `selftest_rppg`와 `selftest_final_report`를 통과했고, 54개 시도의 워치 기준 행을 생성했다. 자체 영상은 최종 평가 분할이며 개발용 후보 최적화에 넣지 않았다. 최종 A–D 실행은 공개 데이터에서 후보와 판정 기준을 고정한 뒤 시작한다. 움직임·회복 촬영은 후속 일정으로 이월했고 다중 인원은 이번 수집에서 제외했다.
