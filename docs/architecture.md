# Proposed architecture (not implemented)

| Module | Responsibility |
|---|---|
| `src/video.py` | Video input, frame timestamps, FPS |
| `src/roi.py` | Face/skin ROI detection and tracking |
| `src/enhancement.py` | Spatial and color/illumination processing |
| `src/signal.py` | RGB temporal extraction, Green/POS/CHROM, bandpass |
| `src/estimation.py` | FFT and BPM peak detection |
| `src/evaluation.py` | MAE, RMSE, valid rate and comparison plots |
| `src/visualization.py` | Optional real-time display |

Proposed interfaces: frame BGR → tracked ROI/mask → timestamped RGB means → filtered signal → BPM and validity. Finalize data shapes, timestamps, failure handling and API with the team before coding.
