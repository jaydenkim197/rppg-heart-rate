# 고정 평가 실행

고정 파일은 공통 추적·시간 처리와 방법별 A~D, pooled POS 설정을 명시하는 JSON이다. 독립 또는 자체 평가의 성능을 보기 전에 고정 파일과 구현 Git 커밋을 정한다. 동일 영상과 구간을 각 방법으로 한 번씩 평가한다. `code_commit`은 평가 함수가 포함된 40자리 Git 커밋이며 실행 전 소스가 이 커밋과 일치해야 한다. 독립 평가 결과로 고정 파일을 갱신해 같은 데이터를 다시 선발하지 않는다.

- `revision`, `code_commit`, `candidates`를 입력한다. `candidates`는 고유한 `name`, `method`와 `overrides` 객체를 가진 다섯 항목으로 A, B, C, D, POS를 한 번씩 포함한다. 모든 방법은 추적·마스크·시간 조건을 공유한다. POS와 D의 POS 창도 같다.
- `roi_seed`의 `mode`는 `cascade` 또는 `registered`다. 자동 초기화는 첫 표시 프레임에서 기본 `vision.CascadeObjectDetector`로 면적이 가장 큰 검출을 선택한다. `scales`는 검사 순서대로 긴 변의 픽셀 수를 지정하며 0은 원본 표시 크기다. `fractions`는 얼굴 검출 상자 기준 `[x,y,width,height]` 비율의 세 행이다. 등록 방식은 검출 결과와 BPM 비교를 분리하고 첫 프레임에서 미리 정한 `video_id,roi_boxes_json` CSV를 사용한다. 모든 방법이 같은 초기 ROI를 사용한다.
- `field_gates`의 `expected_trials`는 거리별 전체 9회다. `min_valid`와 `min_paired`는 각 8회이고, `max_mae_bpm`은 15, `min_within_10_pct`는 50이다. 유효 추정률은 전체 시도에서 산출하며 10 BPM 이내 비율의 분모는 기준값이 있는 전체 시도다.
- `independent_min_reference_subjects`, `independent_min_reference_trend_pairs`, `independent_min_paired`는 독립 배치용 최소 수다. 연속 15초 창의 동일 방법 추정과 [등록 지표](selection-preregistration.md)를 적용한다. 통과 여부를 방법별로 보고한다.

## 현장 자료

```matlab
addpath('matlab');
t = prepare_frozen_trials(aligned_path, "final", freeze_path, ...
    MetadataCsv=intake_manifest_path);
result = run_frozen_evaluation(t, freeze_path, output_path);
```

`aligned_path`는 `prepare_field_reference`로 작성한 `experiments_aligned.csv`다. 원본의 내장 PTS와 표시 크기는 `MetadataCsv`로 연결한다. 상대 영상 경로의 기준 디렉터리는 각 매니페스트 위치이고, 공통 루트의 상대 경로를 쓴 경우 `VideoRoot`를 전달한다. 수동 초기화 동결에는 `RoiCsv`를 추가한다. 자체 54편은 각 60초 창의 프레임 시각을 원본 PTS와 1 μs 이내에서 비교하며, 프레임 수 또는 시각 불일치는 실패로 남긴다.

여러 MATLAB 세션에서 영상 단위로 같은 매니페스트와 출력 위치를 사용해 실행할 수 있다. 각 세션은 `Worker=1,Workers=n`처럼 서로 다른 작업 번호를 전달한다. `Worker=i,Workers=n`은 전체 영상 순서의 `i:n:end`만 계산하고 결과 파일을 합치지 않는다. 모든 작업이 끝나면 `AggregateOnly=true`로 병합한다. 누락 체크포인트가 있으면 이 호출에서 새로 평가하지 않고 중단한다. 인수 없이 다시 실행하면 일치하는 체크포인트를 재사용하고 남은 영상을 처리한다.

## 공개 독립 자료

```matlab
t = prepare_frozen_trials(independent_manifest_path, "independent", ...
    freeze_path, ReferenceRoot=ubfc_dataset2_path);
result = run_frozen_evaluation(t, freeze_path, output_path);
```

등록된 14인의 CSV는 영상당 한 행을 담는다. 함수는 처음 [0,30), [0,15), [15,30)초를 생성하고 제공 데이터의 접촉 PPG를 같은 [기준 규격](ubfc-reference.md)으로 산출한다.

## 결과

A~D 216행은 별도로 보존한다. pooled POS 대조군 54행, D와 POS의 공통 유효 기준 쌍, 반복별·피험자 내 반복 지표, 신호 그래프를 로컬 폴더에 저장한다. 대표 신호는 사전 정한 첫 영상의 A가 처리한 RGB와 FFT 출력이다. 이동 FFT 길이가 고정된 경우 첫 하위 창의 처리 파형과 FFT를 표시한다. 출력할 처리 파형이 없는 경우 그 사실을 표시한다.

거리별 검출은 예상 개수와 유효 조건을 검사하고, 절대 측정에는 기준 쌍·MAE·10 BPM 조건도 적용한다. 0.5m부터 연속으로 통과한 마지막 거리와 더 먼 곳에서 단독으로 통과한 거리를 각각 기록한다. 안정 촬영만으로 추세 추적 가능 거리를 확정하기는 어렵다.
