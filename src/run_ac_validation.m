function ac = run_ac_validation(ctx, scenario_names)
%RUN_AC_VALIDATION Replay hourly MOST dispatch through AC power flow checks.
%
%   This script treats the multi-period MOST schedules as fixed active-power
%   setpoints and performs an hourly AC PF validation for the saved
%   scenario A/B/C/D results.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

params = ac_validation_params();
if nargin < 2 || isempty(scenario_names)
    scenario_names = params.scenario_names;
end
scenario_names = cellstr(scenario_names(:));

n = numel(scenario_names);
summary_rows = repmat(struct( ...
    'scenario', '', ...
    'successful_hours', 0, ...
    'min_voltage_pu', NaN, ...
    'max_voltage_pu', NaN, ...
    'ac_undervoltage_hours', 0, ...
    'ac_overvoltage_hours', 0, ...
    'worst_min_voltage_hour', NaN, ...
    'worst_max_voltage_hour', NaN, ...
    'max_branch_loading_pct_ac', NaN, ...
    'ac_overloaded_hours', 0, ...
    'max_slack_adjustment_MW', NaN, ...
    'max_slack_adjustment_pct_of_peak_load', NaN, ...
    'mean_system_loss_MW', NaN), n, 1);
hourly_tables = cell(n, 1);

for k = 1:n
    scenario_name = upper(char(scenario_names{k}));
    result_file = fullfile(ctx.mats_dir, sprintf('scenario_%s_result.mat', scenario_name));
    if ~exist(result_file, 'file')
        error('run_ac_validation:MissingScenarioResult', ...
            'Expected scenario result file not found: %s', result_file);
    end

    data = load(result_file, 'result');
    result = data.result;
    [hourly_table, summary_rows(k)] = validate_single_scenario(ctx, result, params);
    hourly_tables{k} = hourly_table;
    writetable(hourly_table, fullfile(ctx.tables_dir, ...
        sprintf('ac_validation_scenario_%s_hourly.csv', lower(scenario_name))));
end

summary_table = struct2table(summary_rows);

ac = struct();
ac.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ac.params = params;
ac.summary_table = summary_table;
ac.hourly_tables = hourly_tables;
ac.scenario_names = scenario_names;

save(fullfile(ctx.mats_dir, 'ac_validation.mat'), 'ac', '-v7');
writetable(summary_table, fullfile(ctx.tables_dir, 'ac_validation_summary.csv'));

plot_ac_validation_voltage(ctx, scenario_names, hourly_tables, params);
plot_ac_validation_loading(ctx, scenario_names, hourly_tables, params);

write_text_log(fullfile(ctx.logs_dir, 'ac_validation_log.txt'), {
    'AC validation completed'
    ['scenario_count: ', num2str(n)]
    ['summary_file: ', fullfile(ctx.tables_dir, 'ac_validation_summary.csv')]
});
end

function [hourly_table, summary_row] = validate_single_scenario(ctx, result, params)
[~, ~, ~, ~, ~, ~, PD, QD, ~, ~, ~, VM] = idx_bus();
[~, PG, ~, ~, ~, ~, ~, GEN_STATUS] = idx_gen();
[F_BUS, T_BUS, ~, ~, ~, RATE_A, ~, ~, ~, ~, ~, PF, QF, PT, QT] = idx_brch();

hours = result.profiles.hours(:);
nt = numel(hours);
base_mpc = result.setup.mpc;
pfopt = mpoption(ctx.mpopt_pf, 'verbose', 0, 'out.all', 0);

success = false(nt, 1);
min_vm = nan(nt, 1);
max_vm = nan(nt, 1);
undervoltage_flag = false(nt, 1);
overvoltage_flag = false(nt, 1);
max_branch_loading = nan(nt, 1);
slack_adjustment = nan(nt, 1);
system_loss = nan(nt, 1);
worst_branch_id = nan(nt, 1);
worst_branch_label = strings(nt, 1);

for t = 1:nt
    mpc_t = base_mpc;
    scale = result.profiles.load_scale(t);
    mpc_t.bus(:, PD) = base_mpc.bus(:, PD) * scale;
    mpc_t.bus(:, QD) = base_mpc.bus(:, QD) * scale;
    mpc_t.gen(:, PG) = result.gen_dispatch(:, t);
    mpc_t = apply_hourly_limit_adjustment(mpc_t, result.setup, t);

    pf = runpf(mpc_t, pfopt);
    success(t) = logical(pf.success);
    if ~success(t)
        continue;
    end

    apparent_from = hypot(pf.branch(:, PF), pf.branch(:, QF));
    apparent_to = hypot(pf.branch(:, PT), pf.branch(:, QT));
    branch_loading = nan(size(apparent_from));
    mask = pf.branch(:, RATE_A) > 0;
    branch_loading(mask) = 100 * max(apparent_from(mask), apparent_to(mask)) ./ pf.branch(mask, RATE_A);

    [max_branch_loading(t), idx] = max_ignore_nan(branch_loading);
    if ~isempty(idx) && ~isnan(max_branch_loading(t))
        worst_branch_id(t) = idx;
        worst_branch_label(t) = sprintf('L%02d_%02d_%02d', idx, pf.branch(idx, F_BUS), pf.branch(idx, T_BUS));
    end

    min_vm(t) = min(pf.bus(:, VM));
    max_vm(t) = max(pf.bus(:, VM));
    undervoltage_flag(t) = min_vm(t) < params.vm_lower_limit;
    overvoltage_flag(t) = max_vm(t) > params.vm_upper_limit;

    scheduled_generation = sum(result.gen_dispatch(:, t));
    actual_generation = sum(pf.gen(pf.gen(:, GEN_STATUS) > 0, PG));
    total_load = sum(pf.bus(:, PD));
    slack_adjustment(t) = actual_generation - scheduled_generation;
    system_loss(t) = actual_generation - total_load;
end

hourly_table = table( ...
    hours, success, min_vm, max_vm, undervoltage_flag, overvoltage_flag, max_branch_loading, ...
    slack_adjustment, system_loss, worst_branch_id, worst_branch_label, ...
    'VariableNames', {'hour', 'success', 'min_vm_pu', 'max_vm_pu', ...
    'undervoltage_flag', 'overvoltage_flag', 'max_branch_loading_pct_ac', ...
    'slack_adjustment_MW', 'system_loss_MW', 'worst_branch_id', 'worst_branch_label'});

summary_row = struct();
summary_row.scenario = ['Scenario ', result.scenario];
summary_row.successful_hours = nnz(success);
summary_row.min_voltage_pu = min_ignore_nan(min_vm);
summary_row.max_voltage_pu = max_value_ignore_nan(max_vm);
summary_row.ac_undervoltage_hours = nnz(undervoltage_flag);
summary_row.ac_overvoltage_hours = nnz(overvoltage_flag);
summary_row.worst_min_voltage_hour = worst_hour(hours, min_vm, 'min');
summary_row.worst_max_voltage_hour = worst_hour(hours, max_vm, 'max');
summary_row.max_branch_loading_pct_ac = max_value_ignore_nan(max_branch_loading);
summary_row.ac_overloaded_hours = nnz(max_branch_loading >= params.branch_loading_threshold_pct);
summary_row.max_slack_adjustment_MW = max_value_ignore_nan(abs(slack_adjustment));
summary_row.max_slack_adjustment_pct_of_peak_load = ...
    100 * summary_row.max_slack_adjustment_MW / max(result.profiles.hourly_load_mw);
summary_row.mean_system_loss_MW = mean_ignore_nan(system_loss);
end

function mpc = apply_hourly_limit_adjustment(mpc, setup, hour_idx)
if ~isfield(setup, 'use_congestion') || ~setup.use_congestion || ...
        ~isfield(setup, 'congestion') || isempty(setup.congestion)
    return;
end
if ~ismember(hour_idx, setup.congestion.active_hours)
    return;
end

[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch();
for k = 1:size(setup.congestion.target_pairs, 1)
    from_bus = setup.congestion.target_pairs(k, 1);
    to_bus = setup.congestion.target_pairs(k, 2);
    factor = setup.congestion.target_pairs(k, 3);
    match = find((mpc.branch(:, F_BUS) == from_bus & mpc.branch(:, T_BUS) == to_bus) | ...
                 (mpc.branch(:, F_BUS) == to_bus   & mpc.branch(:, T_BUS) == from_bus));
    mpc.branch(match, RATE_A) = factor * mpc.branch(match, RATE_A);
end
end

function plot_ac_validation_voltage(ctx, scenario_names, hourly_tables, params)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 920, 500]);
hold on;
colors = lines(numel(scenario_names));
for k = 1:numel(scenario_names)
    tbl = hourly_tables{k};
    plot(tbl.hour, tbl.min_vm_pu, '-o', 'LineWidth', 1.6, 'Color', colors(k, :), 'MarkerSize', 4);
end
yline(params.vm_lower_limit, '--k', 'LineWidth', 1.0, 'HandleVisibility', 'off');
hold off;
grid on;
box on;
xlabel('Hour');
ylabel('Minimum Bus Voltage (p.u.)');
title('AC Validation: Hourly Minimum Voltage');
legend(compose_labels(scenario_names), 'Location', 'best');
saveas(fig, fullfile(ctx.figures_dir, 'ac_validation_min_voltage.png'));
close(fig);
end

function plot_ac_validation_loading(ctx, scenario_names, hourly_tables, params)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 920, 500]);
hold on;
colors = lines(numel(scenario_names));
for k = 1:numel(scenario_names)
    tbl = hourly_tables{k};
    plot(tbl.hour, tbl.max_branch_loading_pct_ac, '-s', 'LineWidth', 1.6, 'Color', colors(k, :), 'MarkerSize', 4);
end
yline(params.branch_loading_threshold_pct, '--k', 'LineWidth', 1.0, 'HandleVisibility', 'off');
hold off;
grid on;
box on;
xlabel('Hour');
ylabel('Maximum AC Branch Loading (%)');
title('AC Validation: Hourly Maximum Branch Loading');
legend(compose_labels(scenario_names), 'Location', 'best');
saveas(fig, fullfile(ctx.figures_dir, 'ac_validation_branch_loading.png'));
close(fig);
end

function labels = compose_labels(scenario_names)
labels = cell(numel(scenario_names), 1);
for k = 1:numel(scenario_names)
    labels{k} = ['Scenario ', upper(char(scenario_names{k}))];
end
end

function [value, idx] = max_ignore_nan(x)
idx = [];
mask = ~isnan(x);
if ~any(mask)
    value = NaN;
    return;
end

valid_idx = find(mask);
[value, local_idx] = max(x(valid_idx));
idx = valid_idx(local_idx);
end

function value = min_ignore_nan(x)
mask = ~isnan(x);
if ~any(mask)
    value = NaN;
else
    value = min(x(mask));
end
end

function value = max_value_ignore_nan(x)
mask = ~isnan(x);
if ~any(mask)
    value = NaN;
else
    value = max(x(mask));
end
end

function value = mean_ignore_nan(x)
mask = ~isnan(x);
if ~any(mask)
    value = NaN;
else
    value = mean(x(mask));
end
end

function hour = worst_hour(hours, values, mode_name)
mask = ~isnan(values);
if ~any(mask)
    hour = NaN;
    return;
end

valid_hours = hours(mask);
valid_values = values(mask);
switch lower(mode_name)
    case 'min'
        [~, idx] = min(valid_values);
    case 'max'
        [~, idx] = max(valid_values);
    otherwise
        error('run_ac_validation:InvalidWorstHourMode', ...
            'Unsupported mode "%s". Use "min" or "max".', mode_name);
end
hour = valid_hours(idx);
end
