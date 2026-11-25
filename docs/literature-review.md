# rPPG 선행연구 및 구현 참고 자료

- 작성: 2026-11-25
- 상태: PROPOSAL / 1차 문헌 조사. 이전 대화에서 선정한 25개 항목의 번호를 유지한다.
- 목적: Method A–D, 공통 ROI/시간축 처리, 거리별 평가의 기술 결정과 MATLAB 자체 구현에 활용.
- 검증 범위: 이전 조사 내용을 정리하고 주요 코드 링크를 추가 확인했다. 모든 논문의 원문·정확한 서지·실험 수치를 재검증한 것은 아니다. '이전 조사 표기' 항목은 DOI/PMID 착지 페이지의 제목·연도·내용을 확인한 뒤 최종 인용할 것. 아래 활용 방향은 팀 적용 제안이며 논문 결과나 확정 파라미터가 아니다.
- 코드 상태: 외부 코드의 실행, 라이선스 전체 조항 검토 및 재현 검증은 미수행. 원저자 코드 미확인은 코드가 존재하지 않는다는 뜻이 아니다.

## 1. 문헌별 연구 및 활용 계획

| ID | 분야 | 논문 링크 | 연구 내용 / 조사 주제 | 구현 활용 및 검증 | 코드 연결 |
|---|---|---|---|---|---|
| 1 | 생체광학 | [Remote plethysmographic imaging using ambient light (2008)](https://doi.org/10.1364/OE.16.021434) | 환경광에서 피부 반사광의 주기 변화 및 RGB 채널 특성 | A: Green 평균의 물리적 근거; R/G/B 스펙트럼 비교 | iPhys 재구현 |
| 2 | 생체광학 | [Non-contact, automated cardiac pulse measurements using video imaging and blind source separation (2010)](https://pubmed.ncbi.nlm.nih.gov/20588929/) | ICA 기반 RGB 혼합 신호 분리 | D 대안; ICA의 성분 선택 문제와 비교 | iPhys 재구현 |
| 3 | 생체광학 | [Algorithmic principles of remote PPG (2017)](https://doi.org/10.1109/TBME.2016.2609282) | 피부 반사 모델 및 POS | D: 구간별 RGB 평균 정규화, 투영, 표준편차 비율, overlap-add; 원 논문 Algorithm 확인 | iPhys / rPPG-Toolbox 재구현; 원 논문 저자 저장소 미확인 |
| 4 | 생체광학 | [Robust pulse rate from chrominance-based rPPG (2013)](https://pubmed.ncbi.nlm.nih.gov/23744659/) | 색차 성분 결합과 움직임 잡음 억제 | C/D: CHROM 대조군; 채널 정규화와 결합 방식 비교 | iPhys 재구현 |
| 5 | 신호처리 | [On the use of windows for harmonic analysis with the discrete Fourier transform (1978)](https://doi.org/10.1109/PROC.1978.10837) | 윈도우와 spectral leakage, 주엽 폭의 관계 | estimate_hr.m: Hann/rectangular 비교; coherent gain 및 FFT 축 검증 | 원저자 코드 미확인 |
| 6 | 신호처리 | [The use of fast Fourier transform for the estimation of power spectra (1967)](https://doi.org/10.1109/TAU.1967.1161901) | Welch 분할 평균 PSD | FFT 대비 PSD 분산 감소와 분해능 손실 비교; 필수 FFT는 유지 | 원저자 코드 미확인 |
| 7 | 신호처리 | [Advanced signal-processing framework for rPPG-based heart rate measurement (2026; 이전 조사 표기)](https://doi.org/10.1371/journal.pone.0340097) | 필터 및 신호 개선 후보 | Butterworth, wavelet, Kalman 등 실제 사용 여부와 조건을 원문에서 확인 후 적용 | 미확인 |
| 8 | 영상처리 | [Eulerian video magnification for revealing subtle changes in the world (2012)](https://doi.org/10.1145/2185520.2185561) | 공간 분해 및 시간 필터로 미세 색상/움직임 증폭 | B: 공간·시간 필터 효과 검토; 증폭이 SNR 향상을 보장하지 않음 | MIT 저자 공식 MATLAB 코드 |
| 9 | 영상처리 | [An iterative image registration technique with an application to stereo vision (1981)](https://idl.uw.edu/living-papers-paper/lucas-kanade/) | 영상 정합 및 Lucas–Kanade 원리 | extract_rgb.m: 특징점 이동 및 ROI 위치 보정; 추적 실패 로그 | MathWorks 공식 예제 및 제3자 KLT |
| 10 | 영상처리 | [Detecting pulse from head motions in video (2013)](https://doi.org/10.1109/CVPR.2013.440) | 박동에 의한 미세 머리 움직임 분석 | ROI 추적 좌표의 주기성으로 움직임 오염 진단; 별도 BCG 방식은 선택사항 | Pwan101 C/C++ 재구현 |
| 11 | 영상처리 | [Evaluation of video-based rPPG in challenging environments (2024; 이전 조사 표기)](https://pubmed.ncbi.nlm.nih.gov/39053334/) | 어려운 촬영 조건 및 영상 잡음 후보 | B 및 실패 원인 분석; 정확한 제목·실험 변수 원문 재확인 | 미확인 |
| 12 | 조명·색상 | [Heart rate estimation from facial photoplethysmography during dynamic illuminance changes (2015; 이전 조사 표기)](https://pubmed.ncbi.nlm.nih.gov/26736863/) | 동적 조명 보정 후보 | C: 공통 밝기 변화에 대한 RGB 비율 정규화 검증; 원문 방식과 구분 | 미확인 |
| 13 | 조명·색상 | [Illumination-invariant normalization for robust rPPG extraction (2026; 이전 조사 표기)](https://www.mdpi.com/2079-9292/15/8/1683) | 조명 정규화 후보 | C: RGB 합 정규화와 다른 정규화 방식 비교 검토; 수식·서지 원문 재확인 | 미확인 |
| 14 | 조명·색상 | [The reliability of remote photoplethysmography under low illumination and elevated heart rates (2025; 이전 조사 표기)](https://doi.org/10.1038/s41746-025-02192-y) | 저조도 및 높은 심박 환경의 신뢰성 | 촬영 조도·노출 통제와 실패 분석; 실제 조건 원문 확인 | 미확인 |
| 15 | ROI | [DistancePPG: robust non-contact vital signs monitoring using a camera (2015)](https://doi.org/10.1364/BOE.6.001565) | ROI 추적 및 영역별 품질 기반 맥파 결합 | D: 품질 가중 신호 결합을 참고; 팀의 BPM 결합과 구분 | Rice 저자 연구실 프로젝트 페이지; 코드 미확인 |
| 16 | ROI | [ROI analysis for remote photoplethysmography on facial video (2015; 이전 조사 표기)](https://pubmed.ncbi.nlm.nih.gov/26737399/) | 얼굴 영역별 신호 비교 | 이마·양쪽 볼 선정 근거 및 ROI별 BPM/픽셀 수 기록; 서지 확인 | 미확인 |
| 17 | ROI | [Dynamic region of interest selection in remote photoplethysmography: proof-of-concept study (2023)](https://doi.org/10.2196/44575) | 동적 ROI 선정 | D: 영역별 품질 평가 및 선택; 원문 기준과 팀 임계값 구분 | 원저자 저장소 미확인 |
| 18 | ROI | [Lighting effects on optimal facial regions for remote heart rate measurement (2026; 이전 조사 표기)](https://pubmed.ncbi.nlm.nih.gov/42332009/) | 조명에 따른 얼굴 영역 차이 후보 | ROI별 밝기/품질 비교; 논문 제목·조건 재확인 | 미확인 |
| 19 | 장거리·영상품질 | [Measurement of heart rate from long-distance videos via projection of rotated orthogonal bases in POS (2025)](https://doi.org/10.1016/j.medengphy.2025.104326) | 3–30 m LD-rPPG 데이터 및 ProPOS | 거리별 성능, 카메라 의존성; POS 투영 기저 탐색은 확장 후보 | 원저자 저장소 미확인 |
| 20 | 장거리·영상품질 | [New insights on super-high resolution for video-based heart rate estimation (2019; 이전 조사 표기)](https://pubmed.ncbi.nlm.nih.gov/31760272/) | 영상 해상도와 심박 추정 관계 | 거리별 유효 픽셀 수를 별도 기록; 해상도 변경 실험은 예비 검토 | 미확인 |
| 21 | 장거리·영상품질 | [Effects of video encoding on camera-based heart rate estimation (2019)](https://pubmed.ncbi.nlm.nih.gov/30872217/) | H.264/H.265, 색상 서브샘플링 및 압축 영향 | 원본 영상 보존, 재인코딩 금지, 코덱/해상도 기록 | 원저자 저장소 미확인 |
| 22 | 품질·검증 | [Optimal signal quality index for remote photoplethysmogram sensing (2024)](https://doi.org/10.1038/s44328-024-00002-1) | 8개 SQI 비교 및 품질 분류 | D/평가: 주파수 품질 지표 후보; 논문 임계값을 우리 지표에 그대로 적용하지 않음 | 논문에서 pyVHR 사용 명시; 별도 SQI 코드 미확인 |
| 23 | 품질·검증 | [The accuracy of Apple Watch measurements: a living systematic review and meta-analysis (2026; 이전 조사 표기)](https://doi.org/10.1038/s41746-025-02238-1) | 웨어러블 측정 신뢰도 검토 | 평가: 워치를 절대 참값으로 취급하지 않고 동기화 및 갱신 지연 기록 | 미확인 |
| 24 | 프레임워크 | [iPhys: an open non-contact imaging-based physiological measurement toolbox (2019)](https://pubmed.ncbi.nlm.nih.gov/31947335/) | MATLAB 생체신호 추정 구현 모음 | A/D: Green, ICA, CHROM, POS 출력 대조; 수식 기반 자체 구현 우선 | iPhys 저자 공식 GitHub |
| 25 | 프레임워크 | [Roadmap of remote photoplethysmography from heart rate measurement toward clinical translation (2026; 이전 조사 표기)](https://doi.org/10.1038/s41746-026-02715-1) | rPPG 기술 및 임상 적용 동향 후보 | 보고서 한계·향후 연구; 정확한 서지와 논문 내용 재확인 | 미확인 |

## 2. 코드 및 원저자 공개 자료

| 연결 문헌 | 링크 | 출처 유형 | 언어 및 활용 |
|---|---|---|---|
| 24; 1–4 | [danmcduff/iphys-toolbox](https://github.com/danmcduff/iphys-toolbox) | iPhys 논문의 저자 공식 저장소; Green/ICA/CHROM/POS는 각 원 논문의 재구현 | MATLAB; 가장 먼저 참고. README와 라이선스(README에 MIT/RAIL 관련 안내), 입력 단위·필터·GT 의존성 확인 |
| 3 | [iPhys POS_WANG.m](https://github.com/danmcduff/iphys-toolbox/blob/master/POS_WANG.m) | Wang 논문의 제3자 재구현 | MATLAB; 투영 및 윈도우 처리 비교. 함수 전체를 복사하지 말고 기존 N×3 입력에 맞춰 구현 |
| 3 | [rPPG-Toolbox POS_WANG.py](https://github.com/ubicomplab/rPPG-Toolbox/blob/main/unsupervised_methods/methods/POS_WANG.py) | 별도 연구용 툴박스의 재구현 | Python; 1.6초 창, 채널 평균 정규화 등 교차 확인 |
| 3 | [pavisj/rppg-pos](https://github.com/pavisj/rppg-pos) | 제3자 재구현 | POS 구현 비교용; 원 논문 우선 |
| 8 | [MIT Eulerian Video Magnification](https://people.csail.mit.edu/mrub/vidmag/) | 논문 저자 공식 프로젝트 사이트 (GitHub 아님) | MATLAB 소스 및 논문 재현 예제; 공간·시간 분해와 필터링 참고 |
| 9 | [MathWorks KLT 얼굴 추적](https://www.mathworks.com/help/vision/ug/face-detection-and-tracking-using-the-klt-algorithm.html) | MATLAB 공식 예제, 원 논문 저자 코드는 아님 | ROI 추적, 특징점 갱신 및 툴박스 요구 확인 |
| 9 | [yjadaa/KLT](https://github.com/yjadaa/KLT) | 제3자 구현 | MATLAB; KLT 원리 비교, 라이선스 확인 후 사용 |
| 10 | [Pwan101/pulsefromheadmotion](https://github.com/Pwan101/pulsefromheadmotion) | 제3자 재구현 | C/C++ OpenCV; 움직임 분석 참고, 필수 범위 아님 |
| 15 | [Rice CameraVitals](https://sh.rice.edu/project/camera-vitals/) | DistancePPG 저자 연구실 공식 프로젝트 | 영역 추적과 goodness metric 설명; 소스 저장소는 확인 못함 |
| 22 | [phuselab/pyVHR](https://github.com/phuselab/pyVHR) | 별도 pyVHR 논문의 저자 공식 코드; SQI 논문에서 사용한 기반 도구 | Python; 비교 평가 및 알고리즘 참고. [pyVHR 논문](https://doi.org/10.7717/peerjcs.929) |
| 22 | [LGI-PPGI-DB](https://github.com/partofthestars/LGI-PPGI-DB) | SQI 논문이 명시한 공개 데이터셋, SQI 자체 코드 아님 | 데이터셋 이용 조건 확인 후 독립 검증용 |

ProPOS, DistancePPG, POS 원 논문 및 Dynamic ROI 논문의 원저자 GitHub는 이번 조사에서 확인하지 못했다. 공개 데이터셋/프로젝트 페이지, 후속 연구 코드, 원 논문 알고리즘을 구분하여 사용한다. 25편 모두에 코드가 있다고 가정하지 않는다.

## 3. 개발 적용 지도

| 개발 영역 | 우선 문헌 ID | 기존 파일 | 확인 사항 |
|---|---|---|---|
| A: RGB 및 FFT | 1, 5, 6, 24 | matlab/extract_rgb.m, matlab/estimate_hr.m | 1.25 Hz → 75 BPM, DC, 대역 밖 잡음, 비균일 시간축, 평탄/결측 신호 |
| B: 공간 필터 | 8, 11 | matlab/extract_rgb.m | 원본 대비 Median/Gaussian 후보; ROI 경계 및 색상 왜곡; MAE 개선 여부 |
| C: 색상 정규화 | 3, 4, 12, 13 | matlab/apply_method.m | 공통 밝기 배율, 분모 0, 채널별 조명 변화; 기존 G/(R+G+B) 유지 후 비교 |
| D: POS와 품질 결합 | 3, 15, 17, 19, 22, 24 | matlab/apply_method.m, matlab/estimate_hr.m | 기본 POS, ROI별 POS 균등 결합, 품질 가중 결합 후보; 불일치/가중치 합 0 처리 |
| ROI | 9, 15, 16, 18 | matlab/extract_rgb.m | 같은 피부 위치 유지, 실패 기록, 픽셀 수 및 추적점 수 |
| 거리 및 GT | 19–23 | matlab/evaluate_results.m | 스마트워치 시간 정렬, MAE/RMSE/유효 추정률, 실패를 누락하지 않음 |

## 4. 강의 연결 및 구현 원칙

### 4.1 rPPG에 연결할 MATLAB 기능

쪽수는 로컬 강의 PDF의 페이지 기준이다. MATLAB 함수는 강의 개념을 기존 rPPG 구조에 적용할 후보이며 아래 표에서 위치를 제시한다.

| 적용 단계 | 강의·실습 근거 | 이 프로젝트에서 활용할 방법 |
|---|---|---|
| ROI RGB 추출 | 2 `Fundamentals` 31–34쪽의 픽셀 배열, `MATLAB_tutorial` 11–15쪽의 인덱싱·배열 연산 | `extract_rgb.m`에서 `VideoReader`와 `readFrame`으로 RGB 프레임을 읽고, 초기 수동 ROI는 `drawrectangle`로 지정한다. 배열 인덱싱과 `mean`으로 채널별 평균을 계산하고 ROI별 유효 픽셀 수를 함께 보관한다. 거리별 픽셀 수는 원본 해상도를 기준으로 기록한다. |
| 시간축과 BPM | 2-2 `Fundamentals` 3–16쪽의 보간, 10-1 `Filtering in freq domain` 5–15쪽의 표본화·앨리어싱·1차원 DFT. 11/04 실습은 공간 다운샘플링 전에 Gaussian 저역통과를 적용했다. | `estimate_hr.m`에서 영상의 프레임 시각과 간격을 확인한다. 프레임 시각이 불균일하고 표본 간 공백이 짧을 때는 `interp1(t, x, tUniform, 'linear')`를 검토한다. 긴 결측을 보간하는 기준은 별도로 정한다. 분석 신호에는 1차원 `fft`를 적용하고, 균일 샘플링 주파수 `Fs`와 FFT 길이 `N`에서 `k*Fs/N`으로 Hz 축을 만든다. 0.7–3.0 Hz 구간의 최대 피크 주파수에 60을 곱한다. |
| 시간 대역통과 | 10-2 `Filtering in freq domain` 7–8·14쪽의 주파수 응답 곱과 순환 경계, 11-1 `Filtering in freq` 6–22쪽의 이상적·Butterworth·Gaussian 응답 비교, 11/11의 2차원 FFT 실습 | 현재 PC에서 `bandpass`를 찾을 수 없으므로 `estimate_hr.m`의 후보로 기본 MATLAB의 `fft → 양·음 주파수에 대칭인 대역 응답 곱 → ifft`를 검토한다. 11-1의 영상용 Butterworth 응답과 시간 영역 IIR Butterworth의 전달함수는 구분한다. 급격한 절단의 링잉과 시작·끝의 경계 영향을 인공 신호로 확인한 후 응답, 패딩 및 윈도우를 결정한다. |
| B 공간 잡음 억제 | 6-1 `Spatial filter` 29–42쪽의 평균 필터, 패딩, 순위통계 필터와 미디언 실습 | `extract_rgb.m`에서 프레임의 R·G·B에 각각 `medfilt2(channel, [3 3], 'symmetric')`를 적용한 뒤 공통 ROI의 픽셀을 평균하는 방식을 우선 검토한다. 전체 채널을 필터링하고 ROI를 자를 때와 ROI를 먼저 자르고 패딩할 때의 경계 결과가 달라질 수 있으므로 처리 범위를 고정한다. `imfilter`의 평균 필터와 `imgaussfilt`는 예비 비교 후보로 둔다. |
| C 밝기 변동과 신호 보존 | 4-1·4-2의 밝기·대비 변환, 5-1 `Histogram matching` 22·24–31쪽의 히스토그램 매칭·국소 통계 | `apply_method.m`에서는 팀이 정한 `G/(R+G+B)`를 유지한다. `imhist`로 원본 ROI의 밝기 분포를 확인한다. 프레임별 `histeq`·`imhistmatch`·감마 보정은 시간에 따른 RGB 변화를 바꿀 수 있으므로 필수 경로에서 보류한다. |
| 거리 실험의 실패 분석 | 2 `Fundamentals` 31–34쪽의 공간 해상도, 12-1 `Image restoration`의 열화·잡음 모델 | 거리별로 ROI가 작아지는 정도와 유효 픽셀 수, 영상의 흐림·잡음을 기록한다. `imresize`로 표시 크기를 키워도 새 피부 샘플을 얻지는 못한다. 샤프닝, 역필터·Wiener 복원, CT 재구성은 필수 파이프라인에서 보류한다. |

`VideoReader.CurrentTime`은 읽을 프레임의 시각을 초 단위로 제공한다. 가변 프레임률 영상에서 `FrameRate`는 평균이므로 고정 30 fps로 시간축을 만들기 전에 `CurrentTime` 차이와 실제 촬영 파일의 읽기 결과를 확인한다. [VideoReader](https://www.mathworks.com/help/matlab/ref/videoreader.html) · [interp1](https://www.mathworks.com/help/matlab/ref/interp1.html) · [fft](https://www.mathworks.com/help/matlab/ref/fft.html)

### 4.2 로컬 MATLAB 점검

- 2026-11-25, MATLAB R2026b에서 인공 입력으로 확인했다. `medfilt2`는 값 100의 5×5 배열에서 값 255인 중앙 픽셀을 100으로 복원했다. 모서리는 대칭 패딩에서 100, 기본 0 패딩에서 0이었다. 비균일한 시각 예제에서 `interp1`의 선형 보간값이 예상과 일치했다. [medfilt2](https://www.mathworks.com/help/images/ref/medfilt2.html)
- 30 Hz로 만든 60초 인공 신호에 1.25 Hz와 5 Hz를 섞고, `fft`의 대역 내 피크에서 75.0 BPM을 계산했다. 확인 범위는 주파수 축과 피크 선택이며, 대역통과 필터와 실제 영상 파이프라인은 미검증이다.
- 기본 MATLAB의 `VideoReader`와 Image Processing Toolbox의 `drawrectangle`은 함수 경로를 확인했다. Signal Processing Toolbox의 `bandpass`와 Computer Vision Toolbox의 `vision.PointTracker`는 현재 MATLAB 경로에서 찾을 수 없었다. 추적과 Method D의 세부 구현에는 기존 MathWorks KLT 예제와 POS 원 논문을 이어서 참고한다. [bandpass](https://www.mathworks.com/help/signal/ref/bandpass.html) · [KLT 예제](https://www.mathworks.com/help/vision/ug/face-detection-and-tracking-using-the-klt-algorithm.html)

### 4.3 실험 적용 원칙

- ROI별 품질 가중 결합은 이미 선행연구에 존재한다. 팀 개선은 기존 POS 대비 세 ROI 결합 방식 및 거리별 평가로 정의하고 원천 기술이라고 주장하지 않는다.
- 품질 점수는 주기 잡음에도 높을 수 있다. 기준 심박으로 피크를 고르지 않는다. 신호/스펙트럼/BPM 결합의 차이를 예비 실험에서 검토한다.
- 예비 실험에서만 필터, 품질 임계값 등을 결정하고 본 실험 전에 고정한다. 코드의 구현 완료와 실제 검증을 구분한다.
- 외부 코드 재사용 시 라이선스, 출처, 정확한 커밋 및 수정 내역을 기록한다. 원문 PDF나 얼굴/심박 데이터를 이 문서 커밋에 추가하지 않는다.

## 5. 우선 읽기 순서

1. Wang et al. (ID 3) — POS 수식과 코드 비교.
2. Kumar et al. (ID 15) — 영역별 품질 및 결합.
3. Rao et al. (ID 19) — 장거리 한계와 ProPOS.
4. McDuff 등의 iPhys (ID 24), Harris (ID 5), Elgendi 등의 SQI (ID 22) — MATLAB 검증 및 피크 품질.

관련 개발 기준: [개발 계획](development-plan.md), [시스템 구조](architecture.md), [실험 프로토콜](experiment-protocol.md), [프로젝트 지침](../AGENTS.md).
