# rPPG 개발 및 실험 진행 계획

[통합 설계 명세서](master-design-specification.md)가 기술 범위와 비교 순서의 기준이다. 촬영 전에 사용할 규격은 [촬영·데이터 수집 프로토콜](experiment-protocol.md)에 있다. 11/27 09:00 KST 촬영은 장비·시간축·참조 기록을 먼저 확인하며, 최적화는 촬영 매체를 확보한 뒤에도 개발 데이터로 진행할 수 있다. 기존 제안과 회의 이력은 [기술 결정 검토서](decision-review.md) 및 [팀 회의록](meetings/2026-11-24.md)에 보존한다.

## 단계와 상태

| 단계 | 상태 및 통과 기준 |
|---|---|
| 설계와 촬영 규격 | `IMPLEMENTED` · 데이터/함수 계약과 현장 점검 목록을 작성했다. 장비 실측과 팀 공통 인터페이스 조율은 별도다. |
| 팀원 코드 점검 | `VERIFIED` · 독립 프로토타입의 합성 테스트 범위. 모듈형 팀원 브랜치는 이 로컬 환경에서 필요한 툴박스가 없어 실행이 중단됐다. |
| Method A · 고정 ROI MVP | `VERIFIED` · 고정 ROI Method A의 합성 신호 및 영상 테스트. 동일 피부 영역 추적 및 실제 영상 정확도는 검증 대기 상태다. |
| 자체 기준 심박 및 시각 정렬 | `DECISION` · Apple Watch를 유일 기준으로 사용한다. 영상 첫 프레임 UTC 확인, 워치 내보내기, 구간 집계 및 실제 기록 해상도 점검이 다음 단계다. |
| 공개 데이터 평가 | `IMPLEMENTED` · 고정 ROI·시간/FFT 배치 비교와 결과 저장. MPU-rPPG 단일 샘플에서 초기 실행 검증을 했다. UBFC 실자료 및 독립 검증은 남아 있다. |
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

- UBFC Dataset 2 공식 자료의 `PPG/HR/time_s` 3행 형식은 `read_ubfc_reference`로 읽는다. 공개 Drive에서 목록과 공급자 안내·예제는 확인했다. 일부 다운로드에서 할당량 안내 또는 HTML 응답이 돌아와 이번에 실제 영상·참조 쌍을 확보하지 못했다. [UBFC-rPPG 공식 데이터](https://sites.google.com/view/ybenezeth/ubfcrppg)
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

공개 개발 피험자와 독립 피험자의 분할, 파일별 참조 시간 정렬, KLT·CAMShift·STAPLE·MediaPipe 비교, SQI 후보 검증, 최종 통과 기준, 조합 재검증 및 현장 성능은 계속 확인해야 한다. 필수 단일 인원 검증 후 실시간·다중 인원으로 전환한다.
