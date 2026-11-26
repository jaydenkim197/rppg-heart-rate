# rPPG 개발 및 실험 진행 계획

[통합 설계 명세서](master-design-specification.md)가 기술 범위와 비교 순서의 기준이다. 촬영 전에 사용할 규격은 [촬영·데이터 수집 프로토콜](experiment-protocol.md)에 있다. 11/27 09:00 KST 촬영은 장비·시간축·참조 기록을 먼저 확인하며, 최적화는 촬영 매체를 확보한 뒤에도 개발 데이터로 진행할 수 있다. 기존 제안과 회의 이력은 [기술 결정 검토서](decision-review.md) 및 [팀 회의록](meetings/2026-11-24.md)에 보존한다.

## 단계와 상태

| 단계 | 상태 및 통과 기준 |
|---|---|
| 설계와 촬영 규격 | `IMPLEMENTED` · 데이터/함수 계약과 현장 점검 목록을 작성했다. 장비 실측과 팀 공통 인터페이스 조율은 별도다. |
| 팀원 코드 점검 | `VERIFIED` · 독립 프로토타입의 합성 테스트 범위. 모듈형 팀원 브랜치는 이 로컬 환경에서 필요한 툴박스가 없어 실행이 중단됐다. |
| Method A · 고정 ROI MVP | `PLANNED` · 디코딩 → 프레임별 ROI Green → 실제 시각 처리 → Bandpass → FFT. 합성 75±1 BPM과 실패 경로를 확인한다. |
| 공개 데이터 평가 | `PLANNED` · 공식 자료의 영상·참조를 연결하고 개발/독립 분할을 피험자 기준으로 검증한다. 동일 시도·시각·설정을 기록해 비대화형으로 실행한다. |
| 순차 최적화 및 A~D | `PLANNED` · 공통 ROI와 시간 신호 → B/C → POS/SQI/Fusion 순서. 최소 통과 기준과 정규화는 실험 전에 규정한다. |
| 독립 검증 및 자체 평가 | `PLANNED` · 독립 공개 자료와 예비 장비를 확인한 뒤 커밋·설정을 고정하고 자체 본 실험을 평가한다. |
| 실시간 및 다중 ID | `DEFERRED` · 필수 단일 인원 기능 이후에 미래 데이터 미사용, 유지 표시의 실패 집계 및 ID 혼입을 검증한다. |

## 2026-11-26 팀원 코드 재사용 검토

- `origin/feat/evaluation@6494a96`의 독립 MATLAB `rppg_main('selftest')`를 임시 디렉토리에서 실행했다. A/B/C/D/POS/POS_equal의 합성 75 BPM, 평탄·NaN·대역 밖 처리 및 MAE/RMSE/유효률 검사가 통과했다. 실제 영상, ROI 추적 정확도, 최종 성능은 이 테스트 범위 밖이다. [프로토타입](https://github.com/jaydenkim197/rppg-heart-rate/blob/6494a96d6ba287603a9b082160ad7dfec2121781/docs/sangjun/rppg_main.m)
- `origin/chungwanwoo-netizen-patch-1@c632545`의 모듈형 `selftest_rppg`는 `estimate_hr`에서 `butter`를 찾지 못해 중단됐다. 소스는 KLT/Computer Vision Toolbox 및 `butter/filtfilt`를 사용한다. 시각·피부 픽셀 가중 구조, CSV 평가, 테스트 자산을 참고한다. 16픽셀·90% 등의 수치는 예비 설정이다. [모듈형 코드](https://github.com/jaydenkim197/rppg-heart-rate/tree/c6325457697e0ce2e75144d2a9b5136cff78d31e/matlab)
- MVP는 기존 함수·CSV 계약과 MATLAB `VideoReader`, 배열 연산, `fft/ifft`를 재사용한다. 팀원 독립 코드에서 실제 시각 기록, 픽셀 가중 Green 및 대칭 주파수 영역 Bandpass 설계를 가져온다. 공통 ROI 오류 처리와 확장 방식은 최신 검토서에 맞춘다. 팀원 브랜치의 통합은 별도 PR 및 인터페이스 검토 사항이다.

## 마일스톤 기록

- `408528f` · 현장 장비 점검, Apple Watch·PPG·동기화 이벤트의 수집 항목을 기록했다. 카메라·SSD·기준 장비·LED의 실제 동작은 현장 점검 대기 상태다.
