function export_tables(ctx)
%EXPORT_TABLES Export consolidated CSV and Markdown summaries.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

compare_file = fullfile(ctx.mats_dir, 'scenario_compare.mat');
if ~exist(compare_file, 'file')
    compare_all_scenarios(ctx);
end
summary_data = load(compare_file, 'summary');
summary = summary_data.summary;

writetable(summary.scenario_table, fullfile(ctx.tables_dir, 'scenario_compare.csv'));
writetable(summary.hourly_cost_compare, fullfile(ctx.tables_dir, 'scenario_hourly_cost_compare.csv'));
if ~isempty(summary.branch_compare)
    writetable(summary.branch_compare, fullfile(ctx.tables_dir, 'scenario_key_branch_compare.csv'));
end

for k = 1:numel(summary.results)
    export_single_result_tables(ctx, summary.results{k});
end

reconciliation = run_cost_reconciliation(ctx);
if isfield(reconciliation, 'table') && ~isempty(reconciliation.table)
    writetable(reconciliation.table, fullfile(ctx.tables_dir, 'cost_reconciliation.csv'));
end

write_summary_markdown(ctx, summary);

write_text_log(fullfile(ctx.logs_dir, 'export_tables_log.txt'), {
    'Scenario tables exported'
    ['scenario_count: ', num2str(numel(summary.results))]
    ['reconciliation_rows: ', num2str(height(reconciliation.table))]
    ['tables_dir: ', ctx.tables_dir]
});
end

function export_single_result_tables(ctx, result)
hours = result.profiles.hours(:);
scenario_tag = result.name;

gen_tbl = array2table([hours, result.gen_dispatch.'], ...
    'VariableNames', [{'hour'}, matlab.lang.makeValidName(result.gen_labels(:).')]);
writetable(gen_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_gen_dispatch.csv']));

cost_tbl = table(hours, result.hourly_energy_cost, result.hourly_reserve_cost, result.hourly_dispatch_total_cost_approx, ...
    'VariableNames', {'hour', 'dispatch_energy_cost_approx', 'reserve_cost_from_flow', 'dispatch_total_cost_approx'});
writetable(cost_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_hourly_cost.csv']));

if ~isempty(result.reserve_dispatch)
    reserve_tbl = array2table([hours, result.reserve_dispatch.'], ...
        'VariableNames', [{'hour'}, matlab.lang.makeValidName(result.gen_labels(:).')]);
    writetable(reserve_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_reserve_dispatch.csv']));
end

if ~isempty(result.storage_power)
    power_names = make_storage_labels('storage_power', size(result.storage_power, 1));
    soc_names = make_storage_labels('storage_soc', size(result.storage_soc, 1));
    power_tbl = array2table([hours, result.storage_power.'], ...
        'VariableNames', [{'hour'}, matlab.lang.makeValidName(power_names(:).')]);
    soc_tbl = array2table([hours, result.storage_soc.'], ...
        'VariableNames', [{'hour'}, matlab.lang.makeValidName(soc_names(:).')]);
    writetable(power_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_storage_power.csv']));
    writetable(soc_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_storage_soc.csv']));
end

if ~isempty(result.key_branch_idx)
    key_names = result.branch_labels(result.key_branch_idx);
    key_tbl = array2table([hours, result.branch_loading_pct(result.key_branch_idx, :).'], ...
        'VariableNames', [{'hour'}, matlab.lang.makeValidName(key_names(:).')]);
    writetable(key_tbl, fullfile(ctx.tables_dir, [scenario_tag, '_key_branch_loading.csv']));
end
end

function write_summary_markdown(ctx, summary)
tbl = summary.scenario_table;
lines = {
    '# Scenario Summary'
    ''
    ['Peak reference hour: ', num2str(summary.peak_hour)]
    ''
    '| Scenario | Dispatch Total Cost Approx | Delta vs A | Delta vs A (%) | Solver Objective Value | Objective Delta vs A | Peak Hour Dispatch Cost Approx | Max DC Branch Loading Proxy (%) | Congested Hours | Peak Reserve (MW) |'
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
};

for k = 1:height(tbl)
    lines{end + 1} = sprintf('| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %d | %.2f |', ...
        tbl.scenario{k}, ...
        tbl.dispatch_total_cost_approx(k), ...
        tbl.dispatch_total_cost_delta_vs_A(k), ...
        tbl.dispatch_total_cost_delta_pct_vs_A(k), ...
        tbl.solver_objective_value(k), ...
        tbl.solver_objective_delta_vs_A(k), ...
        tbl.peak_hour_cost_approx(k), ...
        tbl.max_branch_loading_pct(k), ...
        tbl.congested_hours(k), ...
        tbl.peak_reserve_dispatch_MW(k));
end

lines{end + 1} = '';
lines{end + 1} = '## Notes';
lines{end + 1} = '- Dispatch Total Cost Approx is the primary economic comparison metric used in this project.';
lines{end + 1} = '- Solver Objective Value is retained as a secondary MOST-internal reference; `cost_reconciliation.csv` shows that the storage-scenario gap is exactly a fixed zero-output cost constant over the full horizon.';
lines{end + 1} = '- Branch loading is a DC congestion proxy, not an AC MVA validation result.';

write_text_log(fullfile(ctx.tables_dir, 'scenario_summary.md'), lines);
end

function labels = make_storage_labels(prefix, n)
labels = cell(n, 1);
for i = 1:n
    labels{i} = sprintf('%s_%02d', prefix, i);
end
end
