# RGB 영상 기반 비접촉 심박 추정

스마트폰으로 촬영한 한 사람의 이마와 양쪽 볼에서 RGB 변화를 읽고 심박수(BPM)를 추정한다. 방법 A~D를 같은 피부 영역, 영상 구간, 주파수 대역에서 비교하고 스마트워치와의 오차 및 추정 실패율을 구한다. 조원 발표 PPT와 발표자 노트에서 제안한 처리 흐름을 MATLAB 코드로 구현했다.

## 실행 환경

MATLAB R2022b 이상과 Computer Vision Toolbox, Image Processing Toolbox, Signal Processing Toolbox가 필요하다. MATLAB의 **Current Folder**를 압축을 푼 프로젝트의 `matlab` 폴더로 바꾸고 명령창에서 실행한다.

```matlab
main
selftest_rppg
```

`main`은 필요한 함수가 경로에 있는지 표시하고 `data/videos/`와 실험 기록용 `data/experiments.csv`를 준비한다. `selftest_rppg`는 72 BPM의 합성 입력으로 신호 계산과 누락 처리 규칙을 점검한다.

## 스마트폰 영상 한 편으로 점검

1. 스마트폰 후면 카메라를 삼각대에 고정하고, 1 m 거리에서 정면 얼굴이 보이도록 촬영한다. 권장 설정은 1080p, 30 fps, 60초다. MATLAB에서 열기 쉬운 H.264 MP4를 사용한다.
2. 촬영 파일을 프로젝트의 `data/videos/pilot_1m.mp4`에 넣는다.
3. MATLAB 명령창에서 실행한다.

```matlab
main('pilot_1m.mp4')
```

콘솔에 A~D 및 기본 POS의 추정 BPM과 처리 상태가 나온다. `results/run_…/trial_001/tracked_roi.png`에서 첫·마지막 유효 프레임의 ROI를 확인한다. `signals_and_fft.png`에는 원본 RGB 시계열, 처리 후 파형, FFT 스펙트럼이 있다. 이 실행은 스마트워치 값 없이도 가능하다.

## 거리별 실험

과제 거리 0.5, 1, 2, 3, 4, 5 m에서 촬영하고 스마트워치 심박을 동시에 기록한다. 3명에게 거리별 3회씩 촬영하면 총 54편이다. 조명, 노출, 카메라 각도, 참가자의 자세를 일정하게 유지하고 실제 조건을 메모한다.

`data/experiments.csv`에 **촬영 시도당 한 줄**을 작성한다. `video_id`는 해당 줄을 식별하는 고유 코드, `subject_id`는 참가자 코드다. `start_s` 이상 `end_s` 미만이 공통 분석 구간이다. 스마트워치 평균 BPM을 그 구간에 맞춰 `gt_bpm`에 입력한다. 동기화된 워치 기록 CSV를 사용하는 방법은 [실험 양식 안내](configs/README.md)에 있다.

```matlab
[settings, environment, report] = main('../data/experiments.csv');
```

매번 `results/run_…/`에 새 결과 폴더를 만든다.

| 결과 | 내용 |
|---|---|
| `predictions.csv` | 시도별·방법별 추정 BPM, 기준 BPM, 오차, 추적 성공 비율, 실패 사유 |
| `metrics_by_method.csv`, `method_mae.png` | 방법별 MAE, RMSE, 유효 추정률 |
| `metrics_by_distance.csv`, `distance_mae.png`, `distance_valid_rate.png` | 거리와 방법별 오차 및 성공률 |
| `paired_methods.csv` | A와 B·C·D, 기본 POS와 D를 양쪽 추정에 성공한 공통 영상에서 비교 |
| `failed_trials.csv` | 실패한 시도와 사유 |
| `trial_…/tracked_roi.png`, `signals_and_fft.png` | ROI 확인 이미지와 시계열·FFT 그림 |

오차는 추정에 성공하고 스마트워치 기준값이 있는 시도에서 계산한다. 유효 추정률의 분모는 CSV에 등록한 전체 촬영 시도다. 제출할 때 오차와 함께 비교에 들어간 시도 수 및 추정 실패 건수를 표시한다.

## 비교 방법

| 방법 | 처리 |
|---|---|
| A | 피부 영역 Green 평균, 0.7~3.0 Hz 대역통과, FFT |
| B | 각 프레임의 Green에 3×3 미디언 필터를 적용한 뒤 A와 같은 계산 |
| C | 공통 ROI의 RGB 평균에서 `G/(R+G+B)`를 구한 뒤 같은 대역통과와 FFT 적용 |
| D | 이마와 양쪽 볼에서 POS로 각각의 BPM을 추정한 뒤 FFT 피크 품질로 가중 평균 |
| POS | 세 피부 영역을 합친 기본 POS. D의 자체 개선 효과를 비교하는 기준 |

구현 근거와 주의점은 [개발 계획](docs/development-plan.md), 파일별 역할은 [MATLAB 개발 구조](docs/architecture.md)에 있다.

## 결과 검증과 제출

- `selftest_rppg`의 합성 입력은 심박 계산을 점검한다. 팀은 실제 1 m 영상의 ROI와 시계열, 스마트워치 값을 확인하고 여섯 거리에서 실측한다.
- 최종 PPT와 보고서에는 원본 RGB·필터 후 신호·FFT, 방법별·거리별 오차, 유효 추정률과 실패 사례를 넣는다. 데모는 실제 영상의 MATLAB 입력부터 ROI와 BPM 출력까지 보여준다.
- AI를 구현 초안과 합성 시험에 사용했다. 실제 영상, 실행 환경, 기준값 정렬 및 결과 해석을 팀이 검증한 내역은 보고서에 추가한다.
- 공개 GitHub에 올릴 작업물은 코드, 문서, 빈 양식이다. 동의받아 촬영한 얼굴 영상, 실제 심박 기록, ROI 이미지와 개별 결과는 팀의 접근 제한 공간에서 관리하고 수업에 제출한다.
