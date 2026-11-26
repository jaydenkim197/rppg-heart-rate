function result = rank_candidates(report, criteria, min_subjects, tie_margin)
%RANK_CANDIDATES Apply pre-registered target-based scoring on development data.
% criteria columns: metric, target, unacceptable, weight, gate.
% An optional gate uses NaN. Set thresholds before collecting results.

if isempty(report.predictions) || any(report.predictions.split ~= "development")
    error('rppg:HoldoutSelection', 'Candidate selection only accepts development predictions.');
end
validateattributes(min_subjects, {'numeric'}, {'scalar', 'integer', 'positive', 'finite'});
validateattributes(tie_margin, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
required = {'metric', 'target', 'unacceptable', 'weight', 'gate'};
if isempty(criteria) || ~all(ismember(required, criteria.Properties.VariableNames))
    error('rppg:InvalidScoringCriteria', 'Missing pre-registered scoring fields.');
end
names = cellstr(string(criteria.metric));
if numel(unique(names)) ~= numel(names) ...
        || any(~isfinite(criteria.target) | ~isfinite(criteria.unacceptable) ...
        | criteria.target == criteria.unacceptable | ~isfinite(criteria.weight) ...
        | criteria.weight < 0 | isinf(criteria.gate)) || sum(criteria.weight) <= 0
    error('rppg:InvalidScoringCriteria', 'Invalid scoring targets, weights, or gates.');
end
ranked = report.metrics(isnan(report.metrics.distance_m), :);
if isempty(ranked) || ~all(ismember(names, ranked.Properties.VariableNames))
    error('rppg:UnknownScoringMetric', 'The report does not contain all requested metrics.');
end

measurements = ranked{:, names};
target = criteria.target';
unacceptable = criteria.unacceptable';
weight = criteria.weight / sum(criteria.weight);
normalized = max(0, min(1, (measurements-unacceptable) ./ (target-unacceptable)));
ranked.score = normalized * weight;
missing = any(~isfinite(measurements), 2);
ranked.score(missing) = NaN;
gate = criteria.gate';
lower_or_higher = sign(target-unacceptable);
passes_gate = all(isnan(gate) | (measurements-gate).*lower_or_higher >= 0, 2);
ranked.n_subjects = zeros(height(ranked), 1);
ranked.rejection_reason = strings(height(ranked), 1);
for index = 1:height(ranked)
    rows = report.predictions.candidate == ranked.candidate(index) ...
        & report.predictions.valid_estimate & report.predictions.has_reference;
    ranked.n_subjects(index) = numel(unique(report.predictions.subject_id(rows)));
    reasons = strings(0, 1);
    if startsWith(ranked.method(index), "Research")
        reasons(end+1) = "research_control"; %#ok<AGROW>
    end
    if ranked.n_subjects(index) < min_subjects
        reasons(end+1) = "too_few_paired_subjects"; %#ok<AGROW>
    end
    if missing(index)
        reasons(end+1) = "missing_metric"; %#ok<AGROW>
    elseif ~passes_gate(index)
        reasons(end+1) = "metric_gate_failed"; %#ok<AGROW>
    end
    if ~isempty(reasons)
        ranked.rejection_reason(index) = join(reasons, ";");
    end
end
ranked.eligible = strlength(ranked.rejection_reason) == 0;
ranked = sortrows(ranked, {'eligible', 'score'}, {'descend', 'descend'});
qualified = ranked(ranked.eligible, :);
selected = "";
state = "no_eligible_candidate";
if height(qualified) == 1 || (height(qualified) >= 2 ...
        && qualified.score(1)-qualified.score(2) > tie_margin)
    state = "selected";
    selected = qualified.candidate(1);
elseif height(qualified) >= 2
    state = "tie";
end
result = struct('state', state, 'selected', selected, 'ranking', ranked);
end
