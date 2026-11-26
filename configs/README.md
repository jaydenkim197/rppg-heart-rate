# 공통 설정과 실험 기록

MATLAB의 공통 설정은 `matlab/config.m`에서 관리한다. 실제 영상의 프레임 시각을 분석에 사용하고, 설정의 FPS와 촬영 길이는 권장 촬영 조건으로 사용한다.

`experiments_template.csv`는 빈 기록 양식이다. `main`을 처음 실행하면 `data/experiments.csv`로 복사한다. 이 로컬 파일에 촬영 조건과 같은 시간 구간의 스마트워치 평균 BPM을 기록한다. 기존 파일이 있으면 재사용한다.

| 열 | 의미 |
|---|---|
| video_id | 영상의 고유 번호 |
| subject_id | 이름 대신 사용하는 참가자 코드 |
| distance_m | 촬영 거리 |
| trial | 반복 번호 |
| video_file | 영상 파일 경로 |
| start_s, end_s | 영상에서 평가할 구간 |
| gt_bpm | 그 구간과 정렬된 스마트워치 평균 BPM |
| notes | 촬영 조건과 시간 정렬 관련 메모 |

자체 실험의 기준 심박은 Apple Watch로 기록한다. [촬영 메타데이터 양식](capture_metadata_template.csv)과 [워치 심박 양식](watch_hr_template.csv)을 로컬 `data/`에 복사해 첫 프레임 UTC와 측정의 시작·종료 UTC를 저장한다. `video_id`로 기존 실험 목록과 연결한다. 원본 시간대와 시각의 출처를 남기고 `gt_bpm`에는 같은 구간에서 관측된 유효 표본의 평균을 사용한다. 정렬이 확인되지 않은 경우 기준을 결측으로 기록한다. 평가 구간, 품질 판정 기준, 결측치 처리와 필터 설정은 평가 전에 정하고 모든 방법에 같은 기준을 적용한다. [수집 규격](../docs/experiment-protocol.md#3-보관-규격)
