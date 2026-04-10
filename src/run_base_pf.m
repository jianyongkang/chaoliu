function result = run_base_pf(ctx)
%RUN_BASE_PF Run the base AC power flow for case24_ieee_rts.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

define_constants;
[F_BUS, T_BUS, ~, ~, ~, RATE_A, ~, ~, ~, ~, ~, PF, QF, PT, QT] = idx_brch();
[GEN_BUS, PG, QG, ~, ~, ~, ~, GEN_STATUS, PMAX, PMIN] = idx_gen();
[BUS_I, ~, PD, QD, ~, ~, ~, VM, VA] = idx_bus();

mpc = loadcase(ctx.case_name);
timer_ref = tic;
[pf_result, success] = runpf(mpc, ctx.mpopt_pf);
elapsed_sec = toc(timer_ref);

if ~success
    error('run_base_pf:PowerFlowFailed', ...
        'Base power flow did not converge for %s.', ctx.case_name);
end

branch_loading_pct = compute_loading( ...
    pf_result.branch(:, PF), pf_result.branch(:, QF), ...
    pf_result.branch(:, PT), pf_result.branch(:, QT), ...
    pf_result.branch(:, RATE_A));
max_branch_loading_pct = max_or_nan(branch_loading_pct);

bus_table = table( ...
    pf_result.bus(:, BUS_I), ...
    pf_result.bus(:, PD), ...
    pf_result.bus(:, QD), ...
    pf_result.bus(:, VM), ...
    pf_result.bus(:, VA), ...
    'VariableNames', {'bus', 'Pd_MW', 'Qd_MVAr', 'Vm_pu', 'Va_deg'});

gen_table = table( ...
    (1:size(pf_result.gen, 1))', ...
    pf_result.gen(:, GEN_BUS), ...
    pf_result.gen(:, PG), ...
    pf_result.gen(:, QG), ...
    pf_result.gen(:, PMAX), ...
    pf_result.gen(:, PMIN), ...
    pf_result.gen(:, GEN_STATUS), ...
    'VariableNames', {'gen_id', 'bus', 'Pg_MW', 'Qg_MVAr', 'Pmax_MW', 'Pmin_MW', 'status'});

branch_table = table( ...
    (1:size(pf_result.branch, 1))', ...
    pf_result.branch(:, F_BUS), ...
    pf_result.branch(:, T_BUS), ...
    pf_result.branch(:, PF), ...
    pf_result.branch(:, QF), ...
    pf_result.branch(:, PT), ...
    pf_result.branch(:, QT), ...
    pf_result.branch(:, RATE_A), ...
    branch_loading_pct, ...
    'VariableNames', {'branch_id', 'from_bus', 'to_bus', 'Pf_MW', 'Qf_MVAr', 'Pt_MW', 'Qt_MVAr', 'rateA_MVA', 'loading_pct'});

summary_table = table( ...
    {ctx.case_name}, logical(success), elapsed_sec, ...
    safe_sum(pf_result.gen(:, PG)), safe_sum(pf_result.bus(:, PD)), ...
    max_branch_loading_pct, ...
    'VariableNames', {'case_name', 'success', 'elapsed_sec', 'total_generation_MW', 'total_load_MW', 'max_branch_loading_pct'});

result = struct();
result.name = 'base_pf';
result.success = logical(success);
result.elapsed_sec = elapsed_sec;
result.total_generation_mw = safe_sum(pf_result.gen(:, PG));
result.total_load_mw = safe_sum(pf_result.bus(:, PD));
result.max_branch_loading_pct = max_branch_loading_pct;
result.bus_table = bus_table;
result.gen_table = gen_table;
result.branch_table = branch_table;
result.summary_table = summary_table;
result.raw = pf_result;

save(fullfile(ctx.mats_dir, 'base_pf_result.mat'), 'result', '-v7');
writetable(bus_table, fullfile(ctx.tables_dir, 'base_pf_bus.csv'));
writetable(gen_table, fullfile(ctx.tables_dir, 'base_pf_gen.csv'));
writetable(branch_table, fullfile(ctx.tables_dir, 'base_pf_branch.csv'));
writetable(summary_table, fullfile(ctx.tables_dir, 'base_pf_summary.csv'));

write_text_log(fullfile(ctx.logs_dir, 'run_base_pf_log.txt'), {
    'Base PF completed'
    ['case_name: ', ctx.case_name]
    ['success: ', logical_to_text(result.success)]
    ['elapsed_sec: ', sprintf('%.4f', result.elapsed_sec)]
    ['total_generation_mw: ', sprintf('%.2f', result.total_generation_mw)]
    ['total_load_mw: ', sprintf('%.2f', result.total_load_mw)]
    ['max_branch_loading_pct: ', sprintf('%.2f', result.max_branch_loading_pct)]
});
end

function loading_pct = compute_loading(pf_from, qf_from, pf_to, qf_to, rateA)
apparent_from = hypot(pf_from(:), qf_from(:));
apparent_to = hypot(pf_to(:), qf_to(:));
apparent_flow = max([apparent_from, apparent_to], [], 2);
loading_pct = nan(size(apparent_flow));
mask = rateA > 0;
loading_pct(mask) = 100 * apparent_flow(mask) ./ rateA(mask);
end

function value = max_or_nan(x)
x = x(~isnan(x));
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function total = safe_sum(x)
if isempty(x)
    total = 0;
else
    total = sum(x(:));
end
end

function txt = logical_to_text(tf)
if tf
    txt = 'true';
else
    txt = 'false';
end
end
