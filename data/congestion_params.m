function c = congestion_params(mpc)
%CONGESTION_PARAMS Return branch limit reductions for scenario D.
%   The selected corridors are around the heavier load area near bus 15.
%   Parallel branches are all affected if a bus pair appears multiple times.

c = struct();
c.description = ['Tighten selected transfer paths only during evening peak ', ...
    'hours so congestion is predominantly a peak-period phenomenon.'];
c.active_hours = (18:21).';
c.target_pairs = [
    14 16 0.60;
    15 21 0.80
];

if nargin < 1 || isempty(mpc)
    c.branch_index = [];
    c.original_rateA = [];
    return;
end

[F_BUS, T_BUS, ~, ~, ~, RATE_A] = idx_brch();
branch_index = [];
original_rateA = [];

for k = 1:size(c.target_pairs, 1)
    from_bus = c.target_pairs(k, 1);
    to_bus = c.target_pairs(k, 2);

    match = find((mpc.branch(:, F_BUS) == from_bus & mpc.branch(:, T_BUS) == to_bus) | ...
                 (mpc.branch(:, F_BUS) == to_bus   & mpc.branch(:, T_BUS) == from_bus));
    if isempty(match)
        error('congestion_params:BranchNotFound', ...
            'Could not locate branch pair %d-%d in the supplied case.', ...
            from_bus, to_bus);
    end

    branch_index = [branch_index; match(:)]; %#ok<AGROW>
    original_rateA = [original_rateA; mpc.branch(match, RATE_A)]; %#ok<AGROW>
end

c.branch_index = branch_index;
c.original_rateA = original_rateA;
end
