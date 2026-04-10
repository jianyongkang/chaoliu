function sensitivity = run_sensitivity_analysis(ctx, profiles)
%RUN_SENSITIVITY_ANALYSIS Sweep key assumptions around the base scenarios.
%
%   Storage capacity sensitivity: scenario C with scaled storage power and
%   energy ratings.
%   Reserve ratio sensitivity: scenario B with different hourly reserve
%   requirements.
%   Line limit sensitivity: scenario D with different reductions on the
%   primary congestion corridor 14-16.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end

params = sensitivity_params();
base_mpc = loadcase(ctx.case_name);

storage_table = run_storage_capacity_sweep(ctx, profiles, params.storage_capacity_scale);
reserve_table = run_reserve_ratio_sweep(ctx, profiles, params.reserve_ratio_values);
line_limit_table = run_line_limit_sweep(ctx, profiles, params.line_limit_factor_values, ...
    params.line_limit_target_pair, base_mpc);

sensitivity = struct();
sensitivity.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
sensitivity.params = params;
sensitivity.storage_capacity = storage_table;
sensitivity.reserve_ratio = reserve_table;
sensitivity.line_limit = line_limit_table;

save(fullfile(ctx.mats_dir, 'sensitivity_analysis.mat'), 'sensitivity', '-v7');
writetable(storage_table, fullfile(ctx.tables_dir, 'sensitivity_storage_capacity.csv'));
writetable(reserve_table, fullfile(ctx.tables_dir, 'sensitivity_reserve_ratio.csv'));
writetable(line_limit_table, fullfile(ctx.tables_dir, 'sensitivity_line_limit.csv'));

export_sensitivity_figures(ctx, sensitivity);

write_text_log(fullfile(ctx.logs_dir, 'sensitivity_analysis_log.txt'), {
    'Sensitivity analysis completed'
    ['storage_cases: ', num2str(height(storage_table))]
    ['reserve_cases: ', num2str(height(reserve_table))]
    ['line_limit_cases: ', num2str(height(line_limit_table))]
});
end

function storage_table = run_storage_capacity_sweep(ctx, profiles, scale_values)
base_cfg = storage_params();
n = numel(scale_values);

success_col = false(n, 1);
scale_col = zeros(n, 1);
power_col = zeros(n, 1);
energy_col = zeros(n, 1);
objective_col = nan(n, 1);
dispatch_col = nan(n, 1);
peak_col = nan(n, 1);
charge_col = nan(n, 1);
discharge_col = nan(n, 1);
throughput_col = nan(n, 1);
branch_col = nan(n, 1);

for k = 1:n
    scale = scale_values(k);
    storage_cfg = base_cfg;
    storage_cfg.power_rating_mw = base_cfg.power_rating_mw * scale;
    storage_cfg.energy_rating_mwh = base_cfg.energy_rating_mwh * scale;

    result = run_custom_case(ctx, profiles, 'C', ...
        struct('storage_cfg', storage_cfg, ...
               'save_mdi', false, ...
               'mdi_tag', sprintf('sensitivity_storage_%s', make_tag(scale))), ...
        sprintf('sensitivity_storage_%s', make_tag(scale)));

    scale_col(k) = scale;
    power_col(k) = storage_cfg.power_rating_mw;
    energy_col(k) = storage_cfg.energy_rating_mwh;
    success_col(k) = logical(result.success);
    objective_col(k) = result.total_cost;
    dispatch_col(k) = result.dispatch_total_cost_approx;
    peak_col(k) = result.peak_hour_cost;
    branch_col(k) = result.max_branch_loading_pct;
    if ~isempty(result.storage_power)
        charge_col(k) = sum(max(-result.storage_power(:), 0));
        discharge_col(k) = sum(max(result.storage_power(:), 0));
        throughput_col(k) = charge_col(k) + discharge_col(k);
    end
end

storage_table = table( ...
    success_col, scale_col, power_col, energy_col, objective_col, dispatch_col, peak_col, ...
    charge_col, discharge_col, throughput_col, branch_col, ...
    'VariableNames', { ...
        'success', 'storage_capacity_scale', 'power_rating_MW', 'energy_rating_MWh', ...
        'objective_value', 'dispatch_total_cost_approx', 'peak_hour_cost_approx', ...
        'charge_MWh', 'discharge_MWh', 'throughput_MWh', 'max_branch_loading_proxy_pct'});
end

function reserve_table = run_reserve_ratio_sweep(ctx, profiles, ratio_values)
n = numel(ratio_values);

success_col = false(n, 1);
ratio_col = zeros(n, 1);
peak_req_col = zeros(n, 1);
objective_col = nan(n, 1);
dispatch_col = nan(n, 1);
peak_col = nan(n, 1);
reserve_peak_col = nan(n, 1);
branch_col = nan(n, 1);

for k = 1:n
    ratio = ratio_values(k);
    case_profiles = profiles;
    [reserve_req_mw, reserve_ratio] = reserve_profile_24h(case_profiles.hourly_load_mw, ratio);
    case_profiles.reserve_ratio = reserve_ratio;
    case_profiles.reserve_req_mw = reserve_req_mw;

    result = run_custom_case(ctx, case_profiles, 'B', ...
        struct('save_mdi', false, ...
               'mdi_tag', sprintf('sensitivity_reserve_%s', make_tag(ratio))), ...
        sprintf('sensitivity_reserve_%s', make_tag(ratio)));

    ratio_col(k) = ratio;
    peak_req_col(k) = max(reserve_req_mw);
    success_col(k) = logical(result.success);
    objective_col(k) = result.total_cost;
    dispatch_col(k) = result.dispatch_total_cost_approx;
    peak_col(k) = result.peak_hour_cost;
    branch_col(k) = result.max_branch_loading_pct;
    reserve_peak_col(k) = peak_reserve_dispatch(result.reserve_dispatch);
end

reserve_table = table( ...
    success_col, ratio_col, peak_req_col, objective_col, dispatch_col, peak_col, reserve_peak_col, branch_col, ...
    'VariableNames', { ...
        'success', 'reserve_ratio', 'peak_reserve_requirement_MW', 'objective_value', ...
        'dispatch_total_cost_approx', 'peak_hour_cost_approx', ...
        'peak_reserve_dispatch_MW', 'max_branch_loading_proxy_pct'});
end

function line_limit_table = run_line_limit_sweep(ctx, profiles, factor_values, target_pair, base_mpc)
n = numel(factor_values);
base_congestion = congestion_params(base_mpc);
base_rate = locate_base_branch_rate(base_mpc, target_pair);

success_col = false(n, 1);
factor_col = zeros(n, 1);
rate_col = zeros(n, 1);
objective_col = nan(n, 1);
dispatch_col = nan(n, 1);
peak_col = nan(n, 1);
branch_col = nan(n, 1);
binding_col = nan(n, 1);
hours_col = nan(n, 1);

for k = 1:n
    factor = factor_values(k);
    congestion_cfg = base_congestion;
    congestion_cfg.target_pairs = override_target_pair_factor(congestion_cfg.target_pairs, target_pair, factor);

    result = run_custom_case(ctx, profiles, 'D', ...
        struct('congestion_cfg', congestion_cfg, ...
               'save_mdi', false, ...
               'mdi_tag', sprintf('sensitivity_line_%s', make_tag(factor))), ...
        sprintf('sensitivity_line_%s', make_tag(factor)));

    factor_col(k) = factor;
    rate_col(k) = base_rate * factor;
    success_col(k) = logical(result.success);
    objective_col(k) = result.total_cost;
    dispatch_col(k) = result.dispatch_total_cost_approx;
    peak_col(k) = result.peak_hour_cost;
    branch_col(k) = result.max_branch_loading_pct;
    binding_col(k) = height_or_zero(result.binding_branches);
    hours_col(k) = result.congested_hours;
end

line_limit_table = table( ...
    success_col, factor_col, rate_col, objective_col, dispatch_col, peak_col, ...
    branch_col, binding_col, hours_col, ...
    'VariableNames', { ...
        'success', 'line_limit_factor_14_16', 'rateA_MVA_14_16', 'objective_value', ...
        'dispatch_total_cost_approx', 'peak_hour_cost_approx', ...
        'max_branch_loading_proxy_pct', 'binding_branch_count', 'congested_hours'});
end

function export_sensitivity_figures(ctx, sensitivity)
plot_storage_sensitivity(ctx, sensitivity.storage_capacity);
plot_reserve_sensitivity(ctx, sensitivity.reserve_ratio);
plot_line_limit_sensitivity(ctx, sensitivity.line_limit);
end

function plot_storage_sensitivity(ctx, tbl)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 900, 520]);
yyaxis left;
plot(tbl.energy_rating_MWh, tbl.dispatch_total_cost_approx, '-o', 'LineWidth', 1.8, ...
    'Color', [0.15 0.40 0.80], 'MarkerFaceColor', [0.15 0.40 0.80]);
ylabel('Dispatch Cost Approx');
yyaxis right;
plot(tbl.energy_rating_MWh, tbl.peak_hour_cost_approx, '-s', 'LineWidth', 1.8, ...
    'Color', [0.85 0.35 0.15], 'MarkerFaceColor', [0.85 0.35 0.15]);
ylabel('Peak-Hour Cost Approx');
grid on;
box on;
xlabel('Storage Energy Rating (MWh)');
title('Sensitivity: Storage Capacity');
saveas(fig, fullfile(ctx.figures_dir, 'sensitivity_storage_capacity.png'));
close(fig);
end

function plot_reserve_sensitivity(ctx, tbl)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 900, 520]);
yyaxis left;
plot(100 * tbl.reserve_ratio, tbl.dispatch_total_cost_approx, '-o', 'LineWidth', 1.8, ...
    'Color', [0.20 0.55 0.25], 'MarkerFaceColor', [0.20 0.55 0.25]);
ylabel('Dispatch Cost Approx');
yyaxis right;
plot(100 * tbl.reserve_ratio, tbl.peak_reserve_dispatch_MW, '-s', 'LineWidth', 1.8, ...
    'Color', [0.80 0.30 0.20], 'MarkerFaceColor', [0.80 0.30 0.20]);
ylabel('Peak Reserve Dispatch (MW)');
grid on;
box on;
xlabel('Reserve Ratio (%)');
title('Sensitivity: Reserve Requirement');
saveas(fig, fullfile(ctx.figures_dir, 'sensitivity_reserve_ratio.png'));
close(fig);
end

function plot_line_limit_sensitivity(ctx, tbl)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 900, 520]);
yyaxis left;
plot(tbl.rateA_MVA_14_16, tbl.dispatch_total_cost_approx, '-o', 'LineWidth', 1.8, ...
    'Color', [0.10 0.45 0.75], 'MarkerFaceColor', [0.10 0.45 0.75]);
ylabel('Dispatch Cost Approx');
yyaxis right;
plot(tbl.rateA_MVA_14_16, tbl.congested_hours, '-s', 'LineWidth', 1.8, ...
    'Color', [0.85 0.40 0.10], 'MarkerFaceColor', [0.85 0.40 0.10]);
ylabel('Congested Hours');
grid on;
box on;
xlabel('14-16 Branch Limit (MVA Proxy)');
title('Sensitivity: Critical Line Limit');
saveas(fig, fullfile(ctx.figures_dir, 'sensitivity_line_limit.png'));
close(fig);
end

function result = run_custom_case(ctx, profiles, scenario_name, build_options, result_name)
setup = build_most_input(ctx, profiles, scenario_name, build_options);
mdo = most(setup.mdi, setup.mpopt);
result = postprocess_most_result(ctx, setup, mdo, ...
    struct('save_outputs', false, 'result_name', result_name));
end

function updated_pairs = override_target_pair_factor(target_pairs, target_pair, factor)
updated_pairs = target_pairs;
match = find(updated_pairs(:, 1) == target_pair(1) & updated_pairs(:, 2) == target_pair(2), 1, 'first');
if isempty(match)
    match = find(updated_pairs(:, 1) == target_pair(2) & updated_pairs(:, 2) == target_pair(1), 1, 'first');
end
if isempty(match)
    error('run_sensitivity_analysis:MissingTargetPair', ...
        'Target pair %d-%d was not found in congestion settings.', target_pair(1), target_pair(2));
end
updated_pairs(match, 3) = factor;
end

function rate = locate_base_branch_rate(mpc, target_pair)
[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch();
match = find((mpc.branch(:, F_BUS) == target_pair(1) & mpc.branch(:, T_BUS) == target_pair(2)) | ...
             (mpc.branch(:, F_BUS) == target_pair(2) & mpc.branch(:, T_BUS) == target_pair(1)), ...
             1, 'first');
if isempty(match)
    error('run_sensitivity_analysis:MissingTargetPair', ...
        'Base case branch pair %d-%d was not found.', target_pair(1), target_pair(2));
end
rate = mpc.branch(match, RATE_A);
end

function tag = make_tag(value)
tag = strrep(sprintf('%.2f', value), '.', 'p');
end

function n = height_or_zero(tbl)
if isempty(tbl)
    n = 0;
else
    n = height(tbl);
end
end

function value = peak_reserve_dispatch(reserve_dispatch)
if isempty(reserve_dispatch)
    value = NaN;
else
    value = max(sum(reserve_dispatch, 1));
end
end
