# RGB Video-based Contactless Heart Rate Estimation

영남대학교 전자공학과 디지털영상처리 2026-2 텀프로젝트. RGB 영상에서 피부 반사광의 미세한 변화를 분석하여 비접촉 심박수(BPM)를 추정한다. 교육용 프로젝트이며 의료기기가 아니다.

## Goals
- [ ] 얼굴/피부 ROI 추적 및 RGB 시계열 추출
- [ ] Bandpass + FFT 기반 단일 인물 BPM 추정
- [ ] 영상처리 개선 방법 A–D 비교
- [ ] 0.5, 1, 2, 3, 4, 5 m 거리별 스마트워치 HR 비교
- [ ] MAE, RMSE, 유효 추정률 및 실패 원인 분석
- [ ] (Bonus) 다중 인물 추정 및 실시간 시각화

## Pipeline
RGB video → face/skin ROI → spatial/color processing → RGB temporal signal → bandpass → FFT → BPM

## Methods
| ID | Method |
|---|---|
| A | Green channel mean + bandpass + FFT |
| B | A + spatial filtering/denoising |
| C | A + illumination/color correction |
| D | POS or CHROM + team-proposed improvement |

모든 방법에서 동일한 ROI, 영상 구간, 심박 탐색 대역을 적용한다. 초기 권장 대역은 0.7–3.0 Hz이며 실험 전 팀에서 확정한다.

## Proposed environment
Python 3.11, OpenCV, NumPy, SciPy, pandas, Matplotlib. 팀 협의에 따라 변경 가능.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

현재는 협업용 초기 구조이며 알고리즘은 아직 구현되지 않았다. 실행 명령은 MVP 구현 후 추가한다.

## Collaboration
`main`에 직접 push하기보다는 기능별 브랜치에서 작업하고 Pull Request로 병합한다. 역할 및 인터페이스는 첫 팀 미팅에서 확정한다. [협업 규칙](CONTRIBUTING.md) / [실험 계획](docs/experiment-protocol.md) / [시스템 구조](docs/architecture.md)

## Schedule
- 11/25: 제안서 제출 (목표, 방법, 역할, 일정, AI 활용 계획)
- 11/30: 제안 발표 및 기본 파이프라인 구현
- 12/07: 영상처리 개선 및 거리별 실험
- 12/12: 최종 분석, 발표, 데모, 보고서

LMS 공지 일정이 우선한다. AI 사용 및 자체 검증 과정은 기록한다.

## Privacy
공개 저장소에는 참가자 얼굴 영상, 개인별 심박 기록, 식별 정보, 원본 강의자료를 올리지 않는다. 데이터는 동의 및 접근 제한을 갖춘 별도 공간에서 관리한다. 공개 결과는 별도 동의를 확보하거나 비식별 집계 자료로 제한한다.
