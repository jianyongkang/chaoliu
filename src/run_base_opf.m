function result = run_base_opf(ctx)
%RUN_BASE_OPF Run the base single-period AC OPF for case24_ieee_rts.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

define_constants;
[F_BUS, T_BUS, ~, ~, ~, RATE_A, ~, ~, ~, ~, ~, PF, QF, PT, QT] = idx_brch();
[GEN_BUS, PG, QG, ~, ~, ~, ~, GEN_STATUS, PMAX, PMIN] = idx_gen();
[BUS_I, ~, PD, QD, ~, ~, ~, VM, VA, ~, ~, ~, ~, LAM_P, LAM_Q] = idx_bus();

mpc = loadcase(ctx.case_name);
timer_ref = tic;
[opf_result, success] = runopf(mpc, ctx.mpopt_opf);
elapsed_sec = toc(timer_ref);

if ~success
    error('run_base_opf:OpfFailed', ...
        'Base OPF did not solve successfully for %s.', ctx.case_name);
end

branch_loading_pct = compute_loading( ...
    opf_result.branch(:, PF), opf_result.branch(:, QF), ...
    opf_result.branch(:, PT), opf_result.branch(:, QT), ...
    opf_result.branch(:, RATE_A));
max_branch_loading_pct = max_or_nan(branch_loading_pct);

bus_table = table( ...
    opf_result.bus(:, BUS_I), ...
    opf_result.bus(:, PD), ...
    opf_result.bus(:, QD), ...
    opf_result.bus(:, VM), ...
    opf_result.bus(:, VA), ...
    opf_result.bus(:, LAM_P), ...
    opf_result.bus(:, LAM_Q), ...
    'VariableNames', {'bus', 'Pd_MW', 'Qd_MVAr', 'Vm_pu', 'Va_deg', 'LMP_P', 'LMP_Q'});

gen_table = table( ...
    (1:size(opf_result.gen, 1))', ...
    opf_result.gen(:, GEN_BUS), ...
    opf_result.gen(:, PG), ...
    opf_result.gen(:, QG), ...
    opf_result.gen(:, PMAX), ...
    opf_result.gen(:, PMIN), ...
    opf_result.gen(:, GEN_STATUS), ...
    'VariableNames', {'gen_id', 'bus', 'Pg_MW', 'Qg_MVAr', 'Pmax_MW', 'Pmin_MW', 'status'});

branch_table = table( ...
    (1:size(opf_result.branch, 1))', ...
    opf_result.branch(:, F_BUS), ...
    opf_result.branch(:, T_BUS), ...
    opf_result.branch(:, PF), ...
    opf_result.branch(:, QF), ...
    opf_result.branch(:, PT), ...
    opf_result.branch(:, QT), ...
    opf_result.branch(:, RATE_A), ...
    branch_loading_pct, ...
    'VariableNames', {'branch_id', 'from_bus', 'to_bus', 'Pf_MW', 'Qf_MVAr', 'Pt_MW', 'Qt_MVAr', 'rateA_MVA', 'loading_pct'});

summary_table = table( ...
    {ctx.case_name}, logical(success), elapsed_sec, opf_result.f, ...
    safe_sum(opf_result.gen(:, PG)), safe_sum(opf_result.bus(:, PD)), ...
    max_branch_loading_pct, ...
    'VariableNames', {'case_name', 'success', 'elapsed_sec', 'total_cost', 'total_generation_MW', 'total_load_MW', 'max_branch_loading_pct'});

result = struct();
result.name = 'base_opf';
result.success = logical(success);
result.elapsed_sec = elapsed_sec;
result.total_cost = opf_result.f;
result.total_generation_mw = safe_sum(opf_result.gen(:, PG));
result.total_load_mw = safe_sum(opf_result.bus(:, PD));
result.max_branch_loading_pct = max_branch_loading_pct;
result.bus_table = bus_table;
result.gen_table = gen_table;
result.branch_table = branch_table;
result.summary_table = summary_table;
result.raw = opf_result;

save(fullfile(ctx.mats_dir, 'base_opf_result.mat'), 'result', '-v7');
writetable(bus_table, fullfile(ctx.tables_dir, 'base_opf_bus.csv'));
writetable(gen_table, fullfile(ctx.tables_dir, 'base_opf_gen.csv'));
writetable(branch_table, fullfile(ctx.tables_dir, 'base_opf_branch.csv'));
writetable(summary_table, fullfile(ctx.tables_dir, 'base_opf_summary.csv'));

write_text_log(fullfile(ctx.logs_dir, 'run_base_opf_log.txt'), {
    'Base OPF completed'
    ['case_name: ', ctx.case_name]
    ['success: ', logical_to_text(result.success)]
    ['elapsed_sec: ', sprintf('%.4f', result.elapsed_sec)]
    ['total_cost: ', sprintf('%.4f', result.total_cost)]
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
