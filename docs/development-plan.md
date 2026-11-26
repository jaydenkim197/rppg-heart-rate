# rPPG 개발 및 실험 진행 계획

[통합 설계 명세서](master-design-specification.md)가 기술 범위와 비교 순서의 기준이다. 촬영 전에 사용할 규격은 [촬영·데이터 수집 프로토콜](experiment-protocol.md)에 있다. 11/27 09:00 KST 촬영은 장비·시간축·참조 기록을 먼저 확인하며, 최적화는 촬영 매체를 확보한 뒤에도 개발 데이터로 진행할 수 있다. 기존 제안과 회의 이력은 [기술 결정 검토서](decision-review.md) 및 [팀 회의록](meetings/2026-11-24.md)에 보존한다.

## 단계와 상태

| 단계 | 상태 및 통과 기준 |
|---|---|
| 설계와 촬영 규격 | `IMPLEMENTED` · 데이터/함수 계약과 현장 점검 목록을 작성했다. 장비 실측과 팀 공통 인터페이스 조율은 별도다. |
| 팀원 코드 점검 | `VERIFIED` · 독립 프로토타입의 합성 테스트 범위. 모듈형 팀원 브랜치는 이 로컬 환경에서 필요한 툴박스가 없어 실행이 중단됐다. |
| Method A · 고정 ROI MVP | `VERIFIED` · 고정 ROI Method A의 합성 신호 및 영상 테스트. 동일 피부 영역 추적 및 실제 영상 정확도는 검증 대기 상태다. |
| 공개 데이터 평가 | `IMPLEMENTED` · 고정 ROI·시간/FFT 배치 비교와 결과 저장. MPU-rPPG 단일 샘플에서 초기 실행 검증을 했다. UBFC 실자료 및 독립 검증은 남아 있다. |
| 순차 최적화 및 A~D | `PLANNED` · 공통 ROI와 시간 신호 → B/C → POS/SQI/Fusion 순서. 최소 통과 기준과 정규화는 실험 전에 규정한다. |
| 독립 검증 및 자체 평가 | `PLANNED` · 독립 공개 자료와 예비 장비를 확인한 뒤 커밋·설정을 고정하고 자체 본 실험을 평가한다. |
| 실시간 및 다중 ID | `DEFERRED` · 필수 단일 인원 기능 이후에 미래 데이터 미사용, 유지 표시의 실패 집계 및 ID 혼입을 검증한다. |

## 2026-11-26 팀원 코드 재사용 검토

- `origin/feat/evaluation@6494a96`의 독립 MATLAB `rppg_main('selftest')`를 임시 디렉토리에서 실행했다. A/B/C/D/POS/POS_equal의 합성 75 BPM, 평탄·NaN·대역 밖 처리 및 MAE/RMSE/유효률 검사가 통과했다. 실제 영상, ROI 추적 정확도, 최종 성능은 이 테스트 범위 밖이다. [프로토타입](https://github.com/jaydenkim197/rppg-heart-rate/blob/6494a96d6ba287603a9b082160ad7dfec2121781/docs/sangjun/rppg_main.m)
- `origin/chungwanwoo-netizen-patch-1@c632545`의 모듈형 `selftest_rppg`는 `estimate_hr`에서 `butter`를 찾지 못해 중단됐다. 소스는 KLT/Computer Vision Toolbox 및 `butter/filtfilt`를 사용한다. 시각·피부 픽셀 가중 구조, CSV 평가, 테스트 자산을 참고한다. 16픽셀·90% 등의 수치는 예비 설정이다. [모듈형 코드](https://github.com/jaydenkim197/rppg-heart-rate/tree/c6325457697e0ce2e75144d2a9b5136cff78d31e/matlab)
- MVP는 기존 함수·CSV 계약과 MATLAB `VideoReader`, 배열 연산, `fft/ifft`를 재사용한다. 팀원 독립 코드에서 실제 시각 기록, 픽셀 가중 Green 및 대칭 주파수 영역 Bandpass 설계를 가져온다. 공통 ROI 오류 처리와 확장 방식은 최신 검토서에 맞춘다. 팀원 브랜치의 통합은 별도 PR 및 인터페이스 검토 사항이다.

## 마일스톤 기록

- `408528f` · 현장 장비 점검, Apple Watch·PPG·동기화 이벤트의 수집 항목을 기록했다. 카메라·SSD·기준 장비·LED의 실제 동작은 현장 점검 대기 상태다.

- Method A · MATLAB R2026b에서 `selftest_rppg` 통과. 합성 1.25 Hz 신호와 360프레임 AVI를 모두 75.00 BPM으로 추정했다. 균일 시각 보존, 불규칙 시각 재표본화, 평탄·NaN·대역 밖·긴 공백 실패를 점검했다. Bandpass 응답/창/피크/검사 수치는 비교 전 시제품 설정이다. 긴 관측 공백은 코드로 반환하며 구간 분리 분석은 남아 있다.

## 공개 데이터 평가 초기 점검

`run_benchmark(trials, split, candidates, outputDir)`는 비대화형 고정 ROI 시험을 실행한다. `trials`의 열은 `subject_id,video_id,split,video_file,start_s,end_s,roi_boxes,gt_bpm`이다. `roi_boxes`는 3×4 좌표 행렬을 담은 셀 열이다. `distance_m`은 선택 항목이다. 같은 피험자가 여러 분할에 있으면 실행을 중단한다. 독립 검증·본 실험에서는 단일 고정 후보만 실행한다.

`candidates`는 `name`과 `overrides`를 갖는 구조체 배열이다. 현재 배치 비교는 Butterworth형·Ideal·Gaussian Bandpass, 미적용 연구 대조군, Rectangular/Hann/Hamming, FFT 격자 세분화와 포물선 피크를 지원한다. 같은 영상의 RGB 관측 결과를 재사용하고 실패·참조 누락을 보존한다. 출력 위치를 지정하면 `predictions.csv`, `metrics.csv`, `settings.json`에 유효 여부, MAE·RMSE·Bias·허용 오차 비율과 실제 설정을 기록한다.

- UBFC Dataset 2 공식 자료의 `PPG/HR/time_s` 3행 형식은 `read_ubfc_reference`로 읽는다. 공개 Drive에서 목록과 공급자 안내·예제는 확인했다. 일부 다운로드에서 할당량 안내 또는 HTML 응답이 돌아와 이번에 실제 영상·참조 쌍을 확보하지 못했다. [UBFC-rPPG 공식 데이터](https://sites.google.com/view/ybenezeth/ubfcrppg)
- MPU-rPPG 공개 샘플 파일 ID `55553417`(MP4), `55553414`(CSV)를 로컬에 확보하고 크기 및 게시된 MD5를 확인했다. 영상은 640×480, 약 60 fps, 약 742.467초다. CSV는 시각 열 없이 0부터 연속하는 `Count`이며 44,548행이 명목 영상 프레임 수와 일치했다. `Count/FrameRate`를 참조 시각으로 사용한 결과는 동기화가 실측된 결과와 구분한다. [MPU-rPPG 공개 샘플](https://figshare.com/articles/dataset/MPU-rPPG_Sample_Dataset/29377835)
- 첫 15초의 개발용 고정 ROI로 8개 후보를 실행했다. 후보별 유효 결과 1건에서 절대 오차는 약 27.1–31.1 BPM이었다. 움직임이 있는 단일 샘플이며 피험자 단위 독립 검증·추적·동기화 게이트를 통과한 설계가 아니다. 후보 채택은 보류한다. 결과 CSV와 원본은 로컬에 보관했다.
- `selftest_rppg`에서 8개 후보, 실패 시도의 분모 유지, 피험자 분할 위반 거부, UBFC 참조 파서의 합성 입력을 검증했다.

- Raw/Hard Masking 및 Fixed/NCC · `selftest_rppg`에서 3픽셀 평행이동 추적, 포화 픽셀 1개 제거, 원시 RGB 보존을 확인했다. NCC는 초기 템플릿의 평행이동만 추적한다. 0.65 상관 컷과 재탐색 증가는 예비값이며 피부색 마스크, 회전·크기 변화 및 장기 가림 복구는 미검증이다.
- 동일한 MPU 공개 샘플 개발 구간에서 Fixed Raw/Hard는 각 31.106 BPM, NCC Raw/Hard는 각 15.106 BPM의 절대 오차를 냈다. 네 경우 모두 ROI 관측률 100%였으며 추적 성공률이 심박 정확도를 보장하지 않았다. 샘플 1개, 추정된 참조 시각의 초기 결과이므로 추적기·포화 처리 선택 근거로 확정하지 않았다.
