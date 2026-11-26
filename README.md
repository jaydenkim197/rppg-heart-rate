# RGB Video-based Contactless Heart Rate Estimation

디지털영상처리 텀프로젝트. RGB 영상에서 피부 반사광의 변화를 분석하고 비접촉 심박수를 추정한다. MATLAB으로 개발한다.

## 실행

MATLAB의 Current Folder를 저장소의 `matlab` 폴더로 지정한다. `main`은 함수 환경과 실험 CSV를 준비하고, 영상 경로를 인자로 주면 Method A를 실행한다.

```matlab
main
[~, ~, trial] = main("video.mp4");
bpm = trial.estimate.predicted_bpm;
selftest_rppg
```

대화형 실행은 첫 프레임에서 이마, 왼쪽 볼, 오른쪽 볼의 고정 ROI 세 곳을 선택한다. 좌표를 직접 넘기려면 `main(videoFile, roiBoxes, [startSeconds, endSeconds])`를 사용한다. `roiBoxes`는 영상의 1기반 정수 좌표 3행 `[x, y, 너비, 높이]`다. 분석 구간 생략 시 처음 최대 60초를 사용한다. 실패 원인은 `trial.estimate.failure_reason`에 기록된다. 주파수 응답, ROI별 원시 RGB 및 시각은 결과 구조체에서 확인한다.

현재 합성 신호와 합성 AVI로 Method A를 검증했다. 고정 ROI는 안정 영상의 기준이며 최종 과제는 동일 피부 영역 추적과 방법별 비교를 요구한다. 진행 단계와 확인된 한계는 [개발 계획](docs/development-plan.md)에 기록한다.

## 설계와 실험

- [통합 설계 명세서](docs/master-design-specification.md)
- [MATLAB 구조 및 데이터 계약](docs/architecture.md)
- [촬영·데이터 수집 규격](docs/experiment-protocol.md)
- [선행연구 및 강의자료](docs/literature-review.md)
- [협업 및 PR 규칙](CONTRIBUTING.md)

얼굴 영상, 원시 생체신호, 개인별 결과는 접근이 제한된 로컬 데이터로 관리한다. 실험실 연구 및 과제 평가용 코드다.
