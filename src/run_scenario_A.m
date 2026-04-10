function result = run_scenario_A(ctx, profiles)
%RUN_SCENARIO_A 24-hour dispatch without storage and without reserves.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end

setup = build_most_input(ctx, profiles, 'A');
mdo = most(setup.mdi, setup.mpopt);
result = postprocess_most_result(ctx, setup, mdo);
end
