# Results

Store private per-trial results locally. Publish only reviewed, appropriately consented or non-identifying aggregate results.

## Final stable-distance evaluation

After the final settings are frozen, run the A–D benchmark with the `final` split, then pass the result to `write_final_report(report, output_dir)`. The exporter expects all four method attempts for each trial and one frozen candidate per method. The default output is the local, ignored `results/final-report` directory.

- `final_predictions.csv` records all method attempts, including missing reference data and estimation failures.
- `metrics_by_distance.csv` records the per-method overall and distance summaries. A blank distance marks an overall row.
- `metrics_by_subject_distance.csv` records per-subject overall and distance summaries. These are private results.
- `metrics_common_valid.csv` reports only trials with a usable reference and valid estimates from all four methods. Compare this with the full-cohort summary.
- `failure_breakdown.csv` counts missing references and estimation failures independently by method, participant and distance. A trial can contribute to both categories.
- `performance_by_method.png` and `performance_by_distance.png` show paired BPM error and valid estimation rates.

To add raw RGB, processed signal and FFT panels for a representative trial, pass its evaluated `rgb_data` and `estimate` as the third argument. Generate that trace using the frozen candidate settings, the same trial interval and its registered ROIs. Select the representative trial by a rule independent of BPM error. The plot uses the estimate's available arrays and labels missing signals or spectra. Keep the representative trace and the resulting figure local.

## 공간 필터 개발 비교 재실행

`results/selection-v1/spatial-diagnostic/`에는 28개 개발 영상의 원본 입력을 읽어 생성한 영상별 체크포인트를 둔다. 세 분석 구간은 `[0,30)`, `[0,15)`, `[15,30)`이다. 추적기는 Fixed, 기타 공통 설정은 당시 등록 기준을 사용한다. 필터 후보는 미적용 대조, Median, Mean, Gaussian, Bilateral, Wiener다.

기준 소스는 `1fa82ac`이다. 먼저 기본 경로에서 완성된 영상은 `checkpoints/`에 저장한다. 이어지는 로컬 재실행은 기준 소스의 분리된 작업 트리에 `execution-variant/matlab/`의 네 파일을 적용하고 `files.sha256.csv`로 파일을 확인한다. 이 실행 변형은 같은 `VideoReader` RGB 프레임과 읽기 전 시각을 영상별로 한 번만 보관한다. Wiener는 기본 uint8 3×3에 한해 0 패딩 박스 필터로 같은 전 프레임 노이즈 추정을 계산하고, 반올림 경계 또는 거의 0인 노이즈에서는 기본 `wiener2`를 호출한다. 27개 합성·개발 프레임의 전체 출력 및 두 개발 영상의 30프레임 구간에서 추정 입력 구조체가 정확히 일치했다. [검증 도구의 범위와 설정](../configs/README.md)

MATLAB에서 위 로컬 출력 폴더를 경로에 추가하고 재실행용 작업 트리에서 아래 함수를 호출한다. `projectRoot`에는 원본 증거와 실험 출력이 들어 있는 프로젝트 경로를 전달한다. 작업 인덱스는 `1..workers`이며 두 묶음의 체크포인트는 별도 파일에 저장한다.

```matlab
assert_spatial_equivalence(projectRoot)
spatial_subset_partition(worker, workers, projectRoot)
spatial_wiener_partition(worker, workers, projectRoot)
score_spatial_checkpoints(projectRoot, true)
```

집계는 영상 28개와 중복 없는 504행을 검증한 뒤 기존 `score_selection_stage`로 계산한다. `false`를 전달한 집계는 Wiener를 제외한 진단용이며 별도의 `spatial_without_wiener/`에 기록한다. 재실행 자료와 영상별 결과의 보관 위치는 로컬이며 검증 분할과 자체 영상에 이 변형을 적용한 이력은 없다.
