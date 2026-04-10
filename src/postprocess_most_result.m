function result = postprocess_most_result(ctx, setup, mdo, options)
%POSTPROCESS_MOST_RESULT Standardize and export MOST scenario outputs.

if nargin < 4 || isempty(options)
    options = struct();
end

[F_BUS, T_BUS, ~, ~, ~, RATE_A, ~, ~, ~, ~, ~, PF, ~, PT] = idx_brch();
scenario_name = upper(setup.scenario);
options = normalize_postprocess_options(options, scenario_name);
scenario_tag = options.result_name;
nt = setup.nt;
ng = size(setup.mpc.gen, 1);
nl = size(setup.mpc.branch, 1);
hours = setup.profiles.hours(:);

gen_dispatch = nan(ng, nt);
if isfield(mdo, 'results') && isfield(mdo.results, 'ExpectedDispatch')
    gen_dispatch = mdo.results.ExpectedDispatch;
end

hourly_energy_cost = nan(nt, 1);
hourly_reserve_cost = zeros(nt, 1);
reserve_dispatch = [];
branch_pf = nan(nl, nt);
branch_pt = nan(nl, nt);
branch_loading_pct = nan(nl, nt);

for t = 1:nt
    hourly_energy_cost(t) = compute_generation_cost(setup.mpc.gencost, gen_dispatch(:, t));
    flow_mpc = extract_flow_case(mdo, t);
    branch_pf(:, t) = flow_mpc.branch(:, PF);
    branch_pt(:, t) = flow_mpc.branch(:, PT);
    branch_loading_pct(:, t) = compute_loading(branch_pf(:, t), branch_pt(:, t), flow_mpc.branch(:, RATE_A));

    if isfield(flow_mpc, 'reserves') && isfield(flow_mpc.reserves, 'R')
        if isempty(reserve_dispatch)
            reserve_dispatch = nan(size(flow_mpc.reserves.R, 1), nt);
        end
        reserve_dispatch(:, t) = flow_mpc.reserves.R(:);
        if isfield(flow_mpc.reserves, 'totalcost')
            hourly_reserve_cost(t) = flow_mpc.reserves.totalcost;
        end
    end
end

hourly_total_cost = hourly_energy_cost + hourly_reserve_cost;
operating_cost_total = sum(hourly_total_cost);
objective_value = operating_cost_total;
if isfield(mdo, 'results') && isfield(mdo.results, 'f') && ~isempty(mdo.results.f)
    objective_value = mdo.results.f;
end

storage_power = [];
storage_soc = [];
if isfield(mdo, 'Storage') && isfield(mdo.Storage, 'ExpectedStorageDispatch')
    storage_power = mdo.Storage.ExpectedStorageDispatch;
end
if isfield(mdo, 'Storage') && isfield(mdo.Storage, 'ExpectedStorageState')
    storage_soc = mdo.Storage.ExpectedStorageState;
end

branch_max_loading_pct = row_max(branch_loading_pct);
max_branch_loading_pct = max_or_nan(branch_max_loading_pct);
binding_idx = find(branch_max_loading_pct >= 99);
congested_hours = nnz(any(branch_loading_pct >= 99, 1));

key_branch_idx = select_key_branches(setup, branch_max_loading_pct);
branch_rating_reference = [];
if isfield(setup, 'branch_rating_reference')
    branch_rating_reference = setup.branch_rating_reference;
end
key_branch_table = build_branch_summary_table(setup.mpc, branch_max_loading_pct, key_branch_idx, branch_rating_reference);
binding_branch_table = build_branch_summary_table(setup.mpc, branch_max_loading_pct, binding_idx, branch_rating_reference);

result = struct();
result.name = scenario_tag;
result.scenario = scenario_name;
result.success = infer_success(mdo);
result.total_cost = objective_value;
result.objective_value = objective_value;
result.dispatch_total_cost_approx = operating_cost_total;
result.hourly_cost = hourly_total_cost;
result.hourly_energy_cost = hourly_energy_cost;
result.hourly_reserve_cost = hourly_reserve_cost;
result.hourly_dispatch_total_cost_approx = hourly_total_cost;
result.gen_dispatch = gen_dispatch;
result.gen_labels = setup.gen_labels;
result.branch_pf = branch_pf;
result.branch_pt = branch_pt;
result.branch_loading_pct = branch_loading_pct;
result.branch_max_loading_pct = branch_max_loading_pct;
result.branch_labels = setup.branch_labels;
result.max_branch_loading_pct = max_branch_loading_pct;
result.key_branch_idx = key_branch_idx(:);
result.key_branch_table = key_branch_table;
result.binding_branches = binding_branch_table;
result.congested_hours = congested_hours;
result.reserve_dispatch = reserve_dispatch;
result.storage_power = storage_power;
result.storage_soc = storage_soc;
result.storage_gen_idx = setup.storage_gen_idx;
result.storage_bus = [];
if setup.use_storage
    result.storage_bus = setup.storage_cfg.bus;
end
result.peak_hour = setup.profiles.peak_hour;
result.peak_hour_cost = hourly_total_cost(setup.profiles.peak_hour);
result.profiles = setup.profiles;
result.setup = rmfield(setup, 'mdi');
result.mdo = mdo;

if options.save_outputs
    save(fullfile(ctx.mats_dir, [scenario_tag, '_result.mat']), 'result', '-v7');
    export_scenario_tables(ctx, result);
    write_text_log(fullfile(ctx.logs_dir, [scenario_tag, '_log.txt']), {
        [scenario_tag, ' completed']
        ['success: ', logical_to_text(result.success)]
        ['objective_total_cost: ', sprintf('%.4f', result.total_cost)]
        ['dispatch_total_cost_approx: ', sprintf('%.4f', result.dispatch_total_cost_approx)]
        ['objective_value: ', sprintf('%.4f', result.objective_value)]
        ['peak_hour: ', num2str(result.peak_hour)]
        ['peak_hour_cost: ', sprintf('%.4f', result.peak_hour_cost)]
        ['max_branch_loading_pct: ', sprintf('%.2f', result.max_branch_loading_pct)]
        ['congested_hours: ', num2str(result.congested_hours)]
    });
end
end

function options = normalize_postprocess_options(options, scenario_name)
if ~isstruct(options)
    error('postprocess_most_result:InvalidOptions', ...
        'Optional postprocess settings must be provided as a struct.');
end

if ~isfield(options, 'result_name') || isempty(options.result_name)
    options.result_name = sprintf('scenario_%s', scenario_name);
else
    options.result_name = char(options.result_name);
end
if ~isfield(options, 'save_outputs') || isempty(options.save_outputs)
    options.save_outputs = true;
end
end

function export_scenario_tables(ctx, result)
scenario_tag = result.name;
hours = result.profiles.hours(:);

summary_table = table( ...
    {result.scenario}, result.success, result.total_cost, result.dispatch_total_cost_approx, ...
    result.peak_hour, result.peak_hour_cost, result.max_branch_loading_pct, result.congested_hours, ...
    'VariableNames', {'scenario', 'success', 'objective_total_cost', 'dispatch_total_cost_approx', 'peak_hour', 'peak_hour_cost_approx', 'max_branch_loading_proxy_pct', 'congested_hours'});
writetable(summary_table, fullfile(ctx.tables_dir, [scenario_tag, '_summary.csv']));

gen_table = matrix_with_hour_table(hours, result.gen_dispatch, result.gen_labels, 'hour');
writetable(gen_table, fullfile(ctx.tables_dir, [scenario_tag, '_gen_dispatch.csv']));

cost_table = table(hours, result.hourly_energy_cost, result.hourly_reserve_cost, result.hourly_dispatch_total_cost_approx, ...
    'VariableNames', {'hour', 'dispatch_energy_cost_approx', 'reserve_cost_from_flow', 'dispatch_total_cost_approx'});
writetable(cost_table, fullfile(ctx.tables_dir, [scenario_tag, '_hourly_cost.csv']));

if ~isempty(result.reserve_dispatch)
    reserve_table = matrix_with_hour_table(hours, result.reserve_dispatch, result.gen_labels, 'hour');
    writetable(reserve_table, fullfile(ctx.tables_dir, [scenario_tag, '_reserve_dispatch.csv']));
end

if ~isempty(result.storage_power)
    power_labels = make_storage_labels('P', size(result.storage_power, 1));
    soc_labels = make_storage_labels('SOC', size(result.storage_soc, 1));
    storage_power_table = matrix_with_hour_table(hours, result.storage_power, power_labels, 'hour');
    storage_soc_table = matrix_with_hour_table(hours, result.storage_soc, soc_labels, 'hour');
    writetable(storage_power_table, fullfile(ctx.tables_dir, [scenario_tag, '_storage_power.csv']));
    writetable(storage_soc_table, fullfile(ctx.tables_dir, [scenario_tag, '_storage_soc.csv']));
end

if ~isempty(result.key_branch_idx)
    key_loading = result.branch_loading_pct(result.key_branch_idx, :);
    key_labels = result.branch_labels(result.key_branch_idx);
    key_branch_hourly = matrix_with_hour_table(hours, key_loading, key_labels, 'hour');
    writetable(key_branch_hourly, fullfile(ctx.tables_dir, [scenario_tag, '_key_branch_loading.csv']));
    writetable(result.key_branch_table, fullfile(ctx.tables_dir, [scenario_tag, '_key_branch_summary.csv']));
end
end

function tbl = matrix_with_hour_table(hours, data_matrix, labels, hour_name)
data_matrix = data_matrix.';
var_names = [{hour_name}, matlab.lang.makeValidName(labels(:).')];
tbl = array2table([hours, data_matrix], 'VariableNames', var_names);
end

function labels = make_storage_labels(prefix, n)
labels = cell(n, 1);
for i = 1:n
    labels{i} = sprintf('%s_%02d', prefix, i);
end
end

function flow_mpc = extract_flow_case(mdo, t)
if numel(mdo.flow) == 1
    if isstruct(mdo.flow) && isfield(mdo.flow, 'mpc')
        flow_mpc = mdo.flow.mpc;
    else
        flow_mpc = mdo.flow(1).mpc;
    end
else
    flow_mpc = mdo.flow(t, 1, 1).mpc;
end
end

function total_cost = compute_generation_cost(gencost, dispatch)
if any(isnan(dispatch))
    total_cost = NaN;
else
    total_cost = sum(totcost(gencost, dispatch(:)));
end
end

function loading_pct = compute_loading(pf_from, pf_to, rateA)
apparent_flow = max(abs([pf_from(:), pf_to(:)]), [], 2);
loading_pct = nan(size(apparent_flow));
mask = rateA > 0;
loading_pct(mask) = 100 * apparent_flow(mask) ./ rateA(mask);
end

function values = row_max(x)
values = nan(size(x, 1), 1);
for i = 1:size(x, 1)
    row = x(i, :);
    row = row(~isnan(row));
    if ~isempty(row)
        values(i) = max(row);
    end
end
end

function value = max_or_nan(x)
x = x(~isnan(x));
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function success = infer_success(mdo)
success = false;
if isfield(mdo, 'QP') && isfield(mdo.QP, 'exitflag')
    success = mdo.QP.exitflag > 0;
elseif isfield(mdo, 'results') && isfield(mdo.results, 'success')
    success = logical(mdo.results.success);
end
end

function branch_idx = select_key_branches(setup, branch_max_loading_pct)
if setup.use_congestion && ~isempty(setup.congestion_table)
    branch_idx = unique(setup.congestion_table.branch_id(:));
    return;
end

[~, order] = sort(branch_max_loading_pct, 'descend');
order = order(~isnan(branch_max_loading_pct(order)));
branch_idx = order(1:min(5, numel(order)));
end

function branch_table = build_branch_summary_table(mpc, branch_max_loading_pct, branch_idx, branch_rating_reference)
[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch();

if isempty(branch_idx)
    branch_table = table();
    return;
end

branch_idx = branch_idx(:);
if nargin < 4 || isempty(branch_rating_reference)
    branch_rating_reference = mpc.branch(:, RATE_A);
end
branch_table = table( ...
    branch_idx, ...
    mpc.branch(branch_idx, F_BUS), ...
    mpc.branch(branch_idx, T_BUS), ...
    branch_rating_reference(branch_idx), ...
    branch_max_loading_pct(branch_idx), ...
    'VariableNames', {'branch_id', 'from_bus', 'to_bus', 'rateA', 'max_loading_pct'});
end

function txt = logical_to_text(tf)
if tf
    txt = 'true';
else
    txt = 'false';
end
end
