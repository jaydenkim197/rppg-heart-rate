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

## 추적 설정을 적용한 공간 필터 재실행

`results/selection-v1/spatial-tracked/`의 주 비교는 개발 영상 28개를 같은 세 창으로 분석한다. 영상 원본에서 KLT+NCC로 추적하고 Raw 포화 정책을 쓰며, Butterworth 2차와 전체 분석 창, Hamming 및 4배 Zero Padding을 적용한다. 필터별 후보는 미적용 대조, Median, Mean, Gaussian, Bilateral, Wiener다.

분리 작업 트리의 기준은 `2300d76`이다. `execution-variant/matlab/`의 파일은 필터링 전 추적 결과와 원본 `VideoReader` 프레임을 재사용해 필터별 RGB를 만든다. 체크포인트 `checkpoints/NN/필터명.mat`은 원본 영상 1개의 0~30초 추적 시각, ROI 및 필터별 색상 평균 또는 실패 원인을 저장한다. 이미 완성된 후보는 재실행 시 건너뛴다. 같은 필터에서 피크 설정만 다시 계산할 때는 색상 평균을 재사용할 수 있다.

실제 개발 영상 2개의 2초 구간에서 여섯 후보의 전체 RGB 관측 구조체가 기준 소스와 정확히 일치했다. 그중 한 영상의 6초 구간에서는 여섯 후보의 BPM, 품질, ROI 유효 비율을 포함한 전체 채점 결과가 기준 실행과 일치했다. 이 재실행 변형의 검증 범위는 공개 개발 자료다.

```matlab
verify_tracked_spatial(projectRoot)
verify_tracked_spatial_score(projectRoot)
tracked_spatial_partition(worker, workers, projectRoot)
score_tracked_spatial(projectRoot, "zero_padding_4")
```

MATLAB 경로 및 `projectRoot`는 위 Fixed 진단과 같은 방식으로 설정한다. `tracked_spatial_partition`은 지정된 작업자의 영상을 분할 처리한다. 집계는 개발 영상 28개에서 중복 없는 504행을 확인하고 `spatial-zero_padding_4/`에 원본 예측과 순위, 공통 사례 지표, 변화량 짝을 저장한다.

메모리가 부족하면 원본 프레임을 한 번에 한 장씩 읽는 경로를 사용한다. 두 개발 영상에서 전체 구간과 후반부만 필터링한 결과가 기준 경로의 같은 시각 RGB와 일치했다. 아래 검사 후 남은 영상 인덱스를 벡터로 전달한다.

```matlab
verify_spatial_streaming(projectRoot)
tracked_spatial_stream_queue(projectRoot, unfinishedIndices)
```
