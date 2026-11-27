# MediaPipe ROI 개발 후보

공식 Face Landmarker를 VIDEO 모드의 CPU 추론으로 실행하는 개발용 변환 도구다. UBFC Dataset 2 개발 28명용 `[0,30)`초 매니페스트만 읽는다. 지원 범위는 UBFC의 640×480 원본과 첫 프레임에 등록한 ROI의 정수 평행이동이다. 회전·확대 변환과 피부 영역 유지의 직접 검증은 별도 항목이다. [Google AI Edge Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker?tab=Python)

- 실행 환경은 Python 3.11, `mediapipe==0.10.32`, `av==16.1.0`이다. 설치와 모델 파일, 출력은 Git이 제외하는 로컬 결과 폴더에 둔다. Face Landmarker 코드와 등록 모델의 라이선스는 Apache-2.0이다. 버전 1 FP16 번들의 SHA-256은 `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`다. [MediaPipe 코드 라이선스](https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE) · [동일 해시의 공식 연결 모델 카드](https://huggingface.co/litert-community/MediaPipe-FaceLandmarker) · [등록 모델 다운로드](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task)
- 코와 양쪽 눈 가장자리 다섯 점의 축별 이동 중앙값을 첫 프레임 기준으로 계산한다. 첫 프레임 기준점이 없으면 그 시도에서 관측을 생성할 수 없다. 매 프레임 검출이 하나이고 기준점이 영상 안에 있을 때만 유효 이동을 기록한다. 복수 검출, 누락, 영상 바깥 좌표는 사유를 붙여 유지한다. 얼굴 식별이나 다중 인원 대응으로 해석할 수 없다.
- PyAV 디코딩의 표시 시각을 첫 프레임 기준으로 보관한다. 모델의 정수 ms API에는 같은 시각을 반올림해 전달한다. 원본 시각을 별도 열로 사용하고 프레임 번호 임의 보간을 적용하지 않는다. MATLAB 소비자는 원본 차원과 1 μs 이내 프레임 시각이 일치할 때만 해당 현재 프레임의 이동을 적용한다. [PyAV 프레임 시각 문서](https://pyav.org/docs/stable/api/frame.html)
- `tools/estimate_ubfc_landmark_tracks.py <공식 개발 trials.json> <등록 모델> <로컬 새 폴더> --workers 4`로 개발 후보를 계산한다. 파일에는 프레임 번호·표시 초·이동량·유효 여부·사유·크기를 기록한다. 실패한 영상도 요약에 남긴다. 모델, 영상, 윤곽점 원본이나 개인별 결과는 공개 저장소에 올리지 않는다.
- 개발 초반 두 영상에서 1,765/1,765개 프레임에 이동량을 생성했다. MATLAB과 PyAV에 각각 878개와 887개 프레임이 있었고, 같은 프레임 시각의 최대 차이는 0.5 ns 미만이었다. 이 확인은 두 디코더의 연동과 관측 가용성 범위다. 피부 ROI 위치 정확도와 BPM 정확도는 공통 후보 실험에서 평가한다.
- 네 개의 독립 프로세스로 고정된 개발 28개를 처리했다. 24,561/24,561개 프레임에서 정수 평행이동을 기록했고, 개발 초반 두 영상의 단일 프로세스 결과와 병렬 결과의 파일 바이트가 같았다. 개발 집계와 프레임별 이동은 로컬 결과 폴더에 저장했다. 독립 UBFC와 자체 촬영 영상은 실행에 포함되지 않았다.
