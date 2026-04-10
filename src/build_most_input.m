function setup = build_most_input(ctx, profiles, scenario_name, options)
%BUILD_MOST_INPUT Assemble deterministic MOST input data for a scenario.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end
if nargin < 3 || isempty(scenario_name)
    error('build_most_input:MissingScenario', ...
        'Scenario name must be one of A, B, C, or D.');
end
if nargin < 4 || isempty(options)
    options = struct();
end
if ~ctx.has_most
    error('build_most_input:MissingMOST', ...
        'MOST is not available on the path. Multi-period scenarios cannot be built.');
end

scenario_name = upper(char(scenario_name));
valid_scenarios = {'A', 'B', 'C', 'D'};
if ~any(strcmp(scenario_name, valid_scenarios))
    error('build_most_input:InvalidScenario', ...
        'Unsupported scenario "%s". Use A, B, C, or D.', scenario_name);
end
options = normalize_build_options(options, scenario_name);

[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen(); %#ok<NASGU,ASGLU>
[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch(); %#ok<ASGLU>
[CT_LABEL, CT_PROB, CT_TABLE, CT_TBUS, CT_TGEN, CT_TBRCH, CT_TAREABUS, ...
    CT_TAREAGEN, CT_TAREABRCH, CT_ROW, CT_COL, CT_CHGTYPE, CT_REP, ...
    CT_REL, CT_ADD, CT_NEWVAL, CT_TLOAD, CT_TAREALOAD, CT_LOAD_ALL_PQ, ...
    CT_LOAD_FIX_PQ, CT_LOAD_DIS_PQ, CT_LOAD_ALL_P, CT_LOAD_FIX_P, ...
    CT_LOAD_DIS_P, CT_TGENCOST, CT_TAREAGENCOST, CT_MODCOST_F, ...
    CT_MODCOST_X] = idx_ct(); %#ok<ASGLU>

mpc = loadcase(ctx.case_name);
mpc.gen(:, RAMP_10) = Inf;
mpc.gen(:, RAMP_30) = Inf;

use_reserve = any(strcmp(scenario_name, {'B', 'D'}));
use_storage = any(strcmp(scenario_name, {'C', 'D'}));
use_congestion = strcmp(scenario_name, 'D');

xgd = [];
sd = [];
storage_cfg = [];
storage_gen_idx = [];
congestion = struct([]);
congestion_table = table();

if use_storage
    xgd = loadxgendata([], mpc);
    storage_cfg = options.storage_cfg;
    if isempty(storage_cfg)
        storage_cfg = storage_params();
    end
    storage_unit = build_storage_unit(storage_cfg, mpc);
    storage_cfg.bus = storage_unit.gen(1);
    [storage_gen_idx, mpc, xgd, sd] = addstorage(storage_unit, mpc, xgd);
    storage_gen_idx = storage_gen_idx(:);
end

if use_congestion
    congestion = options.congestion_cfg;
    if isempty(congestion)
        congestion = congestion_params(mpc);
    end
end

nt = numel(profiles.hours);
load_profile = struct( ...
    'type', 'mpcData', ...
    'table', CT_TLOAD, ...
    'rows', 0, ...
    'col', CT_LOAD_ALL_PQ, ...
    'chgtype', CT_REL, ...
    'values', []);
load_profile.values(:, 1, 1) = profiles.load_scale(:);

profiles_input = load_profile;
branch_rating_reference = mpc.branch(:, RATE_A);
if use_congestion
    [congestion_profile, congestion_table, branch_rating_reference] = ...
        build_congestion_profile(mpc, congestion, nt, CT_TBRCH, CT_REP);
    profiles_input = [profiles_input; congestion_profile]; %#ok<AGROW>
end

mdi = loadmd(mpc, nt, xgd, sd, [], profiles_input);

reserve_template = struct([]);
if use_reserve
    reserve_template = build_reserve_template(mpc, storage_gen_idx);
    for t = 1:nt
        reserve_t = reserve_template;
        reserve_t.req = profiles.reserve_req_mw(t);
        mdi.FixedReserves(t, 1, 1) = reserve_t; %#ok<AGROW>
    end
end

setup = struct();
setup.scenario = scenario_name;
setup.nt = nt;
setup.mpc = mpc;
setup.mdi = mdi;
setup.mpopt = ctx.mpopt_most;
if use_storage
    setup.mpopt = mpoption(setup.mpopt, ...
        'most.storage.terminal_target', 1, ...
        'most.storage.cyclic', 0);
end
setup.profiles = profiles;
setup.use_reserve = use_reserve;
setup.use_storage = use_storage;
setup.use_congestion = use_congestion;
setup.xgd = xgd;
setup.sd = sd;
setup.storage_cfg = storage_cfg;
setup.storage_gen_idx = storage_gen_idx;
setup.reserve_template = reserve_template;
setup.congestion = congestion;
setup.congestion_table = congestion_table;
setup.branch_rating_reference = branch_rating_reference;
setup.build_options = options;
setup.gen_labels = make_gen_labels(mpc);
setup.branch_labels = make_branch_labels(mpc);
setup.note = sprintf('MOST input assembled for scenario %s.', scenario_name);

if options.save_mdi
    save(fullfile(ctx.mats_dir, sprintf('mdi_%s.mat', options.mdi_tag)), 'setup', '-v7');
end
end

function options = normalize_build_options(options, scenario_name)
if ~isstruct(options)
    error('build_most_input:InvalidOptions', ...
        'Optional build settings must be provided as a struct.');
end

if ~isfield(options, 'storage_cfg')
    options.storage_cfg = [];
end
if ~isfield(options, 'congestion_cfg')
    options.congestion_cfg = [];
end
if ~isfield(options, 'save_mdi') || isempty(options.save_mdi)
    options.save_mdi = true;
end
if ~isfield(options, 'mdi_tag') || isempty(options.mdi_tag)
    options.mdi_tag = lower(char(scenario_name));
else
    options.mdi_tag = char(options.mdi_tag);
end
end

function reserve_template = build_reserve_template(mpc, storage_gen_idx)
[~, ~, ~, ~, ~, ~, ~, GEN_STATUS, PMAX, PMIN] = idx_gen();

ng = size(mpc.gen, 1);
qty = max(0, mpc.gen(:, PMAX) - max(mpc.gen(:, PMIN), 0));
qty(mpc.gen(:, GEN_STATUS) <= 0) = 0;
if ~isempty(storage_gen_idx)
    qty(storage_gen_idx) = 0;
end

cost = 5 + 0.02 * max(0, mpc.gen(:, PMAX));
cost(qty == 0) = 0;

reserve_template = struct();
reserve_template.zones = ones(1, ng);
reserve_template.req = 0;
reserve_template.cost = cost(:);
reserve_template.qty = qty(:);
end

function storage_unit = build_storage_unit(cfg, mpc)
[BUS_I, ~, PD] = idx_bus();

bus = cfg.bus;
if isempty(bus) || ~any(mpc.bus(:, BUS_I) == bus)
    [~, row] = max(mpc.bus(:, PD));
    bus = mpc.bus(row, BUS_I);
end

power_rating = cfg.power_rating_mw;
energy_rating = cfg.energy_rating_mwh;
initial_energy = cfg.initial_soc * energy_rating;
min_energy = cfg.min_soc * energy_rating;
max_energy = cfg.max_soc * energy_rating;

storage_unit = struct();
storage_unit.gen = [ ...
    bus, 0, 0, 0, 0, 1, 100, 1, power_rating, -power_rating, ...
    0, 0, 0, 0, 0, 0, power_rating, power_rating, power_rating, 0, 0 ...
];
storage_unit.gencost = [2, 0, 0, 2, cfg.linear_dispatch_cost, 0];

storage_unit.xgd_table.colnames = { ...
    'PositiveActiveReservePrice', ...
    'PositiveActiveReserveQuantity', ...
    'NegativeActiveReservePrice', ...
    'NegativeActiveReserveQuantity', ...
    'PositiveActiveDeltaPrice', ...
    'NegativeActiveDeltaPrice' ...
};
storage_unit.xgd_table.data = [ ...
    cfg.reserve_offer_price, ...
    cfg.reserve_offer_qty_mw, ...
    cfg.reserve_offer_price, ...
    cfg.reserve_offer_qty_mw, ...
    0, ...
    0 ...
];

storage_unit.sd_table.colnames = { ...
    'ExpectedTerminalStorageAim', ...
    'InitialStorage', ...
    'InitialStorageLowerBound', ...
    'InitialStorageUpperBound', ...
    'InitialStorageCost', ...
    'TerminalStoragePrice', ...
    'MinStorageLevel', ...
    'MaxStorageLevel', ...
    'OutEff', ...
    'InEff', ...
    'LossFactor', ...
    'rho' ...
};
storage_unit.sd_table.data = [ ...
    initial_energy, ...
    initial_energy, ...
    initial_energy, ...
    initial_energy, ...
    cfg.initial_energy_value, ...
    cfg.terminal_energy_value, ...
    min_energy, ...
    max_energy, ...
    cfg.discharge_efficiency, ...
    cfg.charge_efficiency, ...
    cfg.loss_factor, ...
    cfg.rho ...
];
end

function [branch_profile, congestion_table, branch_rating_reference] = build_congestion_profile(mpc, congestion, nt, ct_tbrch, ct_rep)
[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch();

branch_id = [];
from_bus = [];
to_bus = [];
orig_rateA = [];
reduced_rateA = [];
scale_factor = [];
active_hours = {};
branch_rating_reference = mpc.branch(:, RATE_A);

for k = 1:size(congestion.target_pairs, 1)
    pair_from = congestion.target_pairs(k, 1);
    pair_to = congestion.target_pairs(k, 2);
    factor = congestion.target_pairs(k, 3);

    match = find((mpc.branch(:, F_BUS) == pair_from & mpc.branch(:, T_BUS) == pair_to) | ...
                 (mpc.branch(:, F_BUS) == pair_to   & mpc.branch(:, T_BUS) == pair_from));
    if isempty(match)
        error('build_most_input:CongestionBranchNotFound', ...
            'Could not locate branch pair %d-%d for congestion setup.', pair_from, pair_to);
    end

    for idx = match(:)'
        old_rate = mpc.branch(idx, RATE_A);
        new_rate = factor * old_rate;

        branch_id = [branch_id; idx]; %#ok<AGROW>
        from_bus = [from_bus; mpc.branch(idx, F_BUS)]; %#ok<AGROW>
        to_bus = [to_bus; mpc.branch(idx, T_BUS)]; %#ok<AGROW>
        orig_rateA = [orig_rateA; old_rate]; %#ok<AGROW>
        reduced_rateA = [reduced_rateA; new_rate]; %#ok<AGROW>
        scale_factor = [scale_factor; factor]; %#ok<AGROW>
        active_hours{end + 1, 1} = sprintf('%d-%d', congestion.active_hours(1), congestion.active_hours(end)); %#ok<AGROW>
        branch_rating_reference(idx) = min(branch_rating_reference(idx), new_rate);
    end
end

rate_values = repmat(orig_rateA(:).', nt, 1);
rate_values(congestion.active_hours, :) = repmat(reduced_rateA(:).', numel(congestion.active_hours), 1);
rate_values = reshape(rate_values, nt, 1, numel(branch_id));

branch_profile = struct( ...
    'type', 'mpcData', ...
    'table', ct_tbrch, ...
    'rows', branch_id(:), ...
    'col', RATE_A, ...
    'chgtype', ct_rep, ...
    'values', rate_values);

congestion_table = table( ...
    branch_id, from_bus, to_bus, orig_rateA, reduced_rateA, scale_factor, active_hours, ...
    'VariableNames', {'branch_id', 'from_bus', 'to_bus', 'original_rateA', 'reduced_rateA', 'scale_factor', 'active_hours'});
end

function labels = make_gen_labels(mpc)
[GEN_BUS, ~, ~, ~, ~, ~, ~, ~, ~, ~, ...
    ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ...
    ~, ~, ~, ~, ~] = idx_gen();
ng = size(mpc.gen, 1);
labels = cell(ng, 1);
for i = 1:ng
    labels{i} = sprintf('G%02d_B%02d', i, mpc.gen(i, GEN_BUS));
end
end

function labels = make_branch_labels(mpc)
[F_BUS, T_BUS, ~, ~, ~, ~, ~, ~, ~, ~, ...
    ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~] = idx_brch();
nl = size(mpc.branch, 1);
labels = cell(nl, 1);
for i = 1:nl
    labels{i} = sprintf('L%02d_%02d_%02d', i, mpc.branch(i, F_BUS), mpc.branch(i, T_BUS));
end
end
