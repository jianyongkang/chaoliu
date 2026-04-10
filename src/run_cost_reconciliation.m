function reconciliation = run_cost_reconciliation(ctx)
%RUN_COST_RECONCILIATION Reconcile MOST objective values against dispatch-based costs.
%
% This script audits the gap between:
%   1) solver_objective_value        -> MOST-reported optimization objective
%   2) dispatch_total_cost_approx    -> ex-post dispatch-based cost reconstruction
%
% For the current storage-enabled scenarios, the observed fixed offset is
% tested against the per-hour zero-output generator cost constant.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

scenario_names = {'A', 'B', 'C', 'D'};
n = numel(scenario_names);
tolerance = 1e-6;

scenario_col = cell(n, 1);
success_col = false(n, 1);
storage_enabled_col = false(n, 1);
nt_col = zeros(n, 1);
solver_objective_value = zeros(n, 1);
dispatch_total_cost_approx = zeros(n, 1);
solver_minus_dispatch = zeros(n, 1);
zero_output_cost_constant_per_hour = zeros(n, 1);
zero_output_cost_constant_total = zeros(n, 1);
applied_reconciliation_offset = zeros(n, 1);
reconciled_dispatch_cost = zeros(n, 1);
solver_minus_reconciled_dispatch = zeros(n, 1);
matches_zero_output_offset_hypothesis = false(n, 1);

results = cell(n, 1);
for k = 1:n
    file_path = fullfile(ctx.mats_dir, sprintf('scenario_%s_result.mat', scenario_names{k}));
    if ~exist(file_path, 'file')
        error('run_cost_reconciliation:MissingResult', ...
            'Expected result file not found: %s', file_path);
    end

    data = load(file_path, 'result');
    r = data.result;
    results{k} = r;

    scenario_col{k} = ['Scenario ', upper(r.scenario)];
    success_col(k) = isfield(r, 'success') && logical(r.success);
    storage_enabled_col(k) = isfield(r, 'setup') && isfield(r.setup, 'use_storage') && logical(r.setup.use_storage);
    nt_col(k) = get_num_periods(r);
    solver_objective_value(k) = get_solver_objective(r);
    dispatch_total_cost_approx(k) = get_dispatch_cost(r);
    solver_minus_dispatch(k) = solver_objective_value(k) - dispatch_total_cost_approx(k);

    gencost = r.setup.mpc.gencost;
    zero_dispatch = zeros(size(gencost, 1), 1);
    zero_output_cost_constant_per_hour(k) = sum(totcost(gencost, zero_dispatch));
    zero_output_cost_constant_total(k) = nt_col(k) * zero_output_cost_constant_per_hour(k);

    if storage_enabled_col(k)
        applied_reconciliation_offset(k) = zero_output_cost_constant_total(k);
    end
    reconciled_dispatch_cost(k) = dispatch_total_cost_approx(k) - applied_reconciliation_offset(k);
    solver_minus_reconciled_dispatch(k) = solver_objective_value(k) - reconciled_dispatch_cost(k);
    matches_zero_output_offset_hypothesis(k) = abs(solver_minus_reconciled_dispatch(k)) <= tolerance;
end

reconciliation_table = table( ...
    scenario_col, success_col, storage_enabled_col, nt_col, ...
    solver_objective_value, dispatch_total_cost_approx, solver_minus_dispatch, ...
    zero_output_cost_constant_per_hour, zero_output_cost_constant_total, ...
    applied_reconciliation_offset, reconciled_dispatch_cost, ...
    solver_minus_reconciled_dispatch, matches_zero_output_offset_hypothesis, ...
    'VariableNames', { ...
        'scenario', 'success', 'storage_enabled', 'num_periods', ...
        'solver_objective_value', 'dispatch_total_cost_approx', 'solver_minus_dispatch', ...
        'zero_output_cost_constant_per_hour', 'zero_output_cost_constant_total', ...
        'applied_reconciliation_offset', 'reconciled_dispatch_cost', ...
        'solver_minus_reconciled_dispatch', 'matches_zero_output_offset_hypothesis'});

reconciliation = struct();
reconciliation.tolerance = tolerance;
reconciliation.table = reconciliation_table;
reconciliation.results = results;

save(fullfile(ctx.mats_dir, 'cost_reconciliation.mat'), 'reconciliation', '-v7');
writetable(reconciliation_table, fullfile(ctx.tables_dir, 'cost_reconciliation.csv'));
write_reconciliation_markdown(ctx, reconciliation_table, tolerance);

write_text_log(fullfile(ctx.logs_dir, 'cost_reconciliation_log.txt'), {
    'Cost reconciliation completed'
    ['tolerance: ', sprintf('%.3e', tolerance)]
    ['max_abs_solver_minus_dispatch: ', sprintf('%.6f', max(abs(solver_minus_dispatch)))]
    ['max_abs_solver_minus_reconciled_dispatch: ', sprintf('%.6f', max(abs(solver_minus_reconciled_dispatch)))]
    ['all_rows_match_hypothesis: ', logical_to_text(all(matches_zero_output_offset_hypothesis))]
});
end

function write_reconciliation_markdown(ctx, tbl, tolerance)
lines = {
    '# Cost Reconciliation'
    ''
    ['Tolerance: ', sprintf('%.3e', tolerance)]
    ''
    '| Scenario | Storage Enabled | Solver Objective | Dispatch Cost Approx | Solver - Dispatch | Zero-Output Constant Total | Applied Offset | Reconciled Dispatch Cost | Solver - Reconciled | Hypothesis Match |'
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |'
};

for k = 1:height(tbl)
    lines{end + 1} = sprintf('| %s | %s | %.6f | %.6f | %.6f | %.6f | %.6f | %.6f | %.6f | %s |', ...
        tbl.scenario{k}, ...
        logical_to_text(tbl.storage_enabled(k)), ...
        tbl.solver_objective_value(k), ...
        tbl.dispatch_total_cost_approx(k), ...
        tbl.solver_minus_dispatch(k), ...
        tbl.zero_output_cost_constant_total(k), ...
        tbl.applied_reconciliation_offset(k), ...
        tbl.reconciled_dispatch_cost(k), ...
        tbl.solver_minus_reconciled_dispatch(k), ...
        logical_to_text(tbl.matches_zero_output_offset_hypothesis(k)));
end

lines{end + 1} = '';
lines{end + 1} = '## Interpretation';
lines{end + 1} = '- In non-storage scenarios, no reconciliation offset is applied.';
lines{end + 1} = '- In storage-enabled scenarios, the audited offset equals the full-horizon zero-output generator cost constant.';
lines{end + 1} = '- If `solver_minus_reconciled_dispatch` is numerically zero, the fixed gap is fully explained by this constant term.';

write_text_log(fullfile(ctx.tables_dir, 'cost_reconciliation_summary.md'), lines);
end

function value = get_solver_objective(result)
if isfield(result, 'objective_value') && ~isempty(result.objective_value)
    value = result.objective_value;
else
    value = result.total_cost;
end
end

function value = get_dispatch_cost(result)
if isfield(result, 'dispatch_total_cost_approx') && ~isempty(result.dispatch_total_cost_approx)
    value = result.dispatch_total_cost_approx;
else
    value = result.total_cost;
end
end

function nt = get_num_periods(result)
if isfield(result, 'setup') && isfield(result.setup, 'nt') && ~isempty(result.setup.nt)
    nt = result.setup.nt;
elseif isfield(result, 'profiles') && isfield(result.profiles, 'hours')
    nt = numel(result.profiles.hours);
else
    nt = size(result.gen_dispatch, 2);
end
end

function txt = logical_to_text(tf)
if tf
    txt = 'true';
else
    txt = 'false';
end
end
