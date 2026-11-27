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
