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
| B | RGB 채널별 3×3 미디언 필터 + A |
| C | ROI 평균의 G/(R+G+B) 정규화 + bandpass + FFT |
| D | 부위별 POS + 신호 품질을 반영한 BPM 결합 |

모든 방법에서 동일한 ROI 집합, 영상 구간, 심박 탐색 대역을 적용한다. 초기 대역은 0.7–3.0 Hz다. D는 공통 ROI를 이마·양쪽 볼로 나누어 처리한다. 기본 POS도 추가로 비교해 자체 개선 효과를 확인한다. B~D의 효과는 실험으로 검증한다.

## MATLAB development framework

MATLAB 기준 개발 설계와 초기 파일을 `matlab/`에 준비했다. 개발 계획은 [개발 방향 및 방법](docs/development-plan.md), 함수별 입출력은 [시스템 구조](docs/architecture.md)에 정리했다.

MATLAB에서 저장소의 `matlab` 폴더를 Current Folder로 지정하고 실행한다.

```matlab
main
```

`main`은 로컬 데이터·결과 폴더를 준비하고, 빈 실험 기록 양식과 필요한 함수의 경로를 확인한다. 기존 측정 기록이 있으면 재사용한다.

| 구분 | 현재 상태 |
|---|---|
| 개발 계획, 공통 설정, 환경 확인 | 작성됨 |
| RGB 추출, 방법 A~D, BPM 계산, 평가 | 함수 틀과 입출력 정의까지 작성됨 |
| MATLAB 실제 실행 | 이 작업 환경에 MATLAB이 없어 확인 전 |
| 실제 영상 및 스마트워치 비교 | 구현 후 검증 예정 |

초기 환경 확인은 MATLAB 기본 기능으로 실행한다. 이후 구현에서 `bandpass`는 Signal Processing Toolbox, `medfilt2`와 수동 ROI 선택은 Image Processing Toolbox를 사용한다. 최종 ROI 추적 방법은 팀 환경을 확인해 구체화한다. 함수 경로 확인 후 실제 실행과 라이선스도 각 개발 환경에서 점검한다.

`src/`와 `requirements.txt`에는 앞서 준비한 Python 초기 구조가 있다. 이번 개발 계획의 실행 진입점은 `matlab/main.m`이다.

## Collaboration
`main`에 직접 push하기보다는 기능별 브랜치에서 작업하고 Pull Request로 병합한다. 역할 및 인터페이스는 첫 팀 미팅에서 확정한다. [협업 규칙](CONTRIBUTING.md) / [실험 계획](docs/experiment-protocol.md) / [시스템 구조](docs/architecture.md)

## Schedule
- 11/25 10:30 제안 발표와 개발 방향 공유
- 11/27 09:00 전 기능 통합 목표, 09:00부터 평가 실험 시작
- 12/07 영상처리 비교 및 거리별 실험 결과 정리
- 12/12 최종 분석, 발표, 데모, 보고서

[팀 회의록](docs/meetings/2026-11-24.md)의 내부 목표를 반영했다. LMS 공지 일정이 우선한다. AI 사용 및 자체 검증 과정은 기록한다.

## Privacy
공개 저장소에는 참가자 얼굴 영상, 개인별 심박 기록, 식별 정보, 원본 강의자료를 올리지 않는다. 데이터는 동의 및 접근 제한을 갖춘 별도 공간에서 관리한다. 공개 결과는 별도 동의를 확보하거나 비식별 집계 자료로 제한한다.
