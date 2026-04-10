function summary = compare_all_scenarios(ctx)
%COMPARE_ALL_SCENARIOS Compare the outputs of scenarios A/B/C/D.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

scenario_names = {'A', 'B', 'C', 'D'};
results = cell(numel(scenario_names), 1);

for k = 1:numel(scenario_names)
    file_path = fullfile(ctx.mats_dir, sprintf('scenario_%s_result.mat', scenario_names{k}));
    if ~exist(file_path, 'file')
        error('compare_all_scenarios:MissingResult', ...
            'Expected result file not found: %s', file_path);
    end
    data = load(file_path, 'result');
    results{k} = data.result;
end

base_result = results{1};
peak_hour = base_result.peak_hour;
base_solver_objective = base_result.total_cost;
base_peak_cost = base_result.peak_hour_cost;
base_dispatch_total_cost = get_dispatch_total_cost(base_result);

n = numel(results);
scenario_col = cell(n, 1);
dispatch_total_cost_approx = zeros(n, 1);
dispatch_total_cost_delta = zeros(n, 1);
dispatch_total_cost_delta_pct = zeros(n, 1);
solver_objective_value = zeros(n, 1);
solver_objective_delta = zeros(n, 1);
solver_objective_delta_pct = zeros(n, 1);
peak_hour_cost = zeros(n, 1);
peak_hour_cost_delta = zeros(n, 1);
max_gen_output = zeros(n, 1);
storage_charge = zeros(n, 1);
storage_discharge = zeros(n, 1);
storage_throughput = zeros(n, 1);
storage_rte = nan(n, 1);
max_branch_loading = zeros(n, 1);
binding_branch_count = zeros(n, 1);
congested_hours = zeros(n, 1);
peak_reserve = zeros(n, 1);
energy_cost_total = zeros(n, 1);
reserve_cost_total = zeros(n, 1);

for k = 1:n
    r = results{k};
    scenario_col{k} = ['Scenario ', r.scenario];
    solver_objective_value(k) = r.total_cost;
    dispatch_total_cost_approx(k) = get_dispatch_total_cost(r);
    peak_hour_cost(k) = r.peak_hour_cost;
    max_gen_output(k) = max_value(r.gen_dispatch);
    max_branch_loading(k) = r.max_branch_loading_pct;
    congested_hours(k) = r.congested_hours;
    binding_branch_count(k) = table_height_or_zero(r.binding_branches);
    energy_cost_total(k) = sum(r.hourly_energy_cost);
    reserve_cost_total(k) = sum(r.hourly_reserve_cost);

    if ~isempty(r.reserve_dispatch)
        peak_reserve(k) = max(sum(r.reserve_dispatch, 1));
    end

    if ~isempty(r.storage_power)
        storage_charge(k) = sum(max(-r.storage_power(:), 0));
        storage_discharge(k) = sum(max(r.storage_power(:), 0));
        storage_throughput(k) = storage_charge(k) + storage_discharge(k);
        if storage_charge(k) > 0
            storage_rte(k) = storage_discharge(k) / storage_charge(k);
        end
    end
end

solver_objective_delta = solver_objective_value - base_solver_objective;
peak_hour_cost_delta = peak_hour_cost - base_peak_cost;
dispatch_total_cost_delta = dispatch_total_cost_approx - base_dispatch_total_cost;
if abs(base_solver_objective) > 0
    solver_objective_delta_pct = 100 * solver_objective_delta / base_solver_objective;
end
if abs(base_dispatch_total_cost) > 0
    dispatch_total_cost_delta_pct = 100 * dispatch_total_cost_delta / base_dispatch_total_cost;
end

scenario_table = table( ...
    scenario_col, ...
    dispatch_total_cost_approx, dispatch_total_cost_delta, dispatch_total_cost_delta_pct, ...
    solver_objective_value, solver_objective_delta, solver_objective_delta_pct, ...
    peak_hour_cost, peak_hour_cost_delta, max_gen_output, ...
    storage_charge, storage_discharge, storage_throughput, storage_rte, ...
    max_branch_loading, binding_branch_count, congested_hours, ...
    peak_reserve, energy_cost_total, reserve_cost_total, ...
    'VariableNames', { ...
        'scenario', ...
        'dispatch_total_cost_approx', 'dispatch_total_cost_delta_vs_A', 'dispatch_total_cost_delta_pct_vs_A', ...
        'solver_objective_value', 'solver_objective_delta_vs_A', 'solver_objective_delta_pct_vs_A', ...
        'peak_hour_cost_approx', 'peak_hour_cost_delta_vs_A', 'max_gen_output_MW', ...
        'storage_charge_MWh', 'storage_discharge_MWh', 'storage_throughput_MWh', 'storage_round_trip_ratio', ...
        'max_branch_loading_pct', 'binding_branch_count', 'congested_hours', ...
        'peak_reserve_dispatch_MW', 'energy_cost_total', 'reserve_cost_total'});

hourly_cost_compare = build_hourly_cost_table(results);
branch_compare = build_key_branch_compare_table(results);

summary = struct();
summary.scenario_table = scenario_table;
summary.hourly_cost_compare = hourly_cost_compare;
summary.branch_compare = branch_compare;
summary.peak_hour = peak_hour;
summary.results = results;
summary.base_scenario = 'A';

save(fullfile(ctx.mats_dir, 'scenario_compare.mat'), 'summary', '-v7');
writetable(scenario_table, fullfile(ctx.tables_dir, 'scenario_compare.csv'));
writetable(hourly_cost_compare, fullfile(ctx.tables_dir, 'scenario_hourly_cost_compare.csv'));
if ~isempty(branch_compare)
    writetable(branch_compare, fullfile(ctx.tables_dir, 'scenario_key_branch_compare.csv'));
end

write_text_log(fullfile(ctx.logs_dir, 'compare_all_scenarios_log.txt'), {
    'Scenario comparison completed'
    ['peak_hour_reference: ', num2str(summary.peak_hour)]
    ['min_dispatch_total_cost_approx: ', sprintf('%.4f', min(dispatch_total_cost_approx))]
    ['max_dispatch_total_cost_approx: ', sprintf('%.4f', max(dispatch_total_cost_approx))]
    ['largest_dispatch_cost_reduction_vs_A_pct: ', sprintf('%.2f', min(dispatch_total_cost_delta_pct))]
    ['max_branch_loading_pct: ', sprintf('%.2f', max(max_branch_loading))]
});
end

function hourly_cost_compare = build_hourly_cost_table(results)
hours = results{1}.profiles.hours(:);
n = numel(results);
data = hours;
var_names = {'hour'};

for k = 1:n
    r = results{k};
    data = [data, r.hourly_dispatch_total_cost_approx(:)]; %#ok<AGROW>
    var_names{end + 1} = sprintf('scenario_%s_dispatch_total_cost_approx', lower(r.scenario)); %#ok<AGROW>
end

hourly_cost_compare = array2table(data, 'VariableNames', var_names);
end

function branch_compare = build_key_branch_compare_table(results)
resultD = [];
resultA = [];
for k = 1:numel(results)
    if strcmpi(results{k}.scenario, 'D')
        resultD = results{k};
    elseif strcmpi(results{k}.scenario, 'A')
        resultA = results{k};
    end
end

if isempty(resultD) || isempty(resultD.key_branch_idx)
    branch_compare = table();
    return;
end

branch_idx = resultD.key_branch_idx(:);
branch_labels = resultD.branch_labels(branch_idx);
max_loading_A = resultA.branch_max_loading_pct(branch_idx);
max_loading_D = resultD.branch_max_loading_pct(branch_idx);
delta_loading = max_loading_D - max_loading_A;

branch_compare = table( ...
    branch_idx, branch_labels, max_loading_A, max_loading_D, delta_loading, ...
    'VariableNames', {'branch_id', 'branch_label', 'scenario_A_max_loading_pct', 'scenario_D_max_loading_pct', 'delta_loading_pct'});
end

function value = max_value(x)
if isempty(x)
    value = 0;
else
    value = max(x(:));
end
end

function n = table_height_or_zero(tbl)
if isempty(tbl)
    n = 0;
else
    n = height(tbl);
end
end

function value = get_dispatch_total_cost(result)
if isfield(result, 'dispatch_total_cost_approx') && ~isempty(result.dispatch_total_cost_approx)
    value = result.dispatch_total_cost_approx;
else
    value = result.total_cost;
end
end
