# 재현용 로컬 데이터

## 기본 거리별 촬영

`data/field-originals/` 아래에 파일명을 보존해 영상 54개를 압축 해제한다. 원본을 읽기 전용으로 사용하는 것이 좋다. 팀에서 접근을 승인한 별도 위치에 비식별 영상 매핑, 동의 범위 내 동일 구간 기준 BPM과 정렬 품질, 파일별 SHA-256 및 파일 크기 목록을 둔다. 이 파일들의 프로젝트 내 위치는 `results/field-intake/` 또는 평가 실행의 입력 경로로 지정한다. `data/`와 `results/`에는 참가자 원본과 개별 결과를 커밋하지 않도록 기본 제외 규칙을 적용한다.

로컬 `field-originals.zip`은 25,614,738,702바이트이고 MOV 54개와 전체 건강 기록을 포함한 Apple Health 내보내기 ZIP 1개가 있다. Drive의 동명 항목은 바이트 수가 같으며, 원격 체크섬과 팀원만 접근 가능한지는 현재 권한으로 확인되지 않았다. 이 항목을 재현용으로 배포하지 않는다. 영상만 담은 별도 배포본을 만들고 참가자 동의에 맞는 팀 계정 권한과 해시를 확인한 뒤, 승인된 팀 채널의 다운로드 링크를 사용한다. Apple Health 전체 ZIP과 개인 건강 기록을 재현 패키지에 넣지 않는다. 기존 로컬 자료를 사용하므로 원격 25GB 자료를 다시 내려받을 필요가 없다.

배포 파일에는 영상별 실험 ID(`video_id`), 비식별 참가자 ID, 거리, 반복, 기준 창(`[0,60)`), 측정 시각 정렬 상태 및 허용된 기준 BPM이 필요하다. Apple Watch의 개인 시각과 건강 기록은 원본 접근 권한을 가진 사람이 로컬에서만 변환한다. 추정 결과를 보기 전 등록한 표시 방향 기준 ROI와 프레임 PTS 보조 자료를 사용한다. 팀 공유가 승인된 경우에만 이러한 자료를 승인된 위치에서 전달한다.

다운로드가 승인되면 영상만 담은 ZIP의 목차를 확인하고 덮어쓰기 없이 압축을 푼다. PowerShell에서는 승인된 배포 목록의 `relative_path`, `bytes`, `sha256`을 사용해 프로젝트에서 다음을 검사할 수 있다.

```powershell
$root = (Resolve-Path 'data/field-originals').Path
$manifest = Import-Csv 'results/field-intake/team-video-checksums.csv'
if ($manifest.Count -ne 54) { throw 'Expected 54 videos' }
foreach ($row in $manifest) {
    $path = Join-Path $root $row.relative_path
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.sha256) {
        throw "Checksum or size mismatch: $($row.relative_path)"
    }
}
```

[실험 평가 사전 등록](../docs/selection-completion-protocol.md) · [결과 파일 안내](../results/README.md)
