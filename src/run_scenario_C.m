function result = run_scenario_C(ctx, profiles)
%RUN_SCENARIO_C 24-hour dispatch with one storage unit and no reserves.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end

setup = build_most_input(ctx, profiles, 'C');
mdo = most(setup.mdi, setup.mpopt);
result = postprocess_most_result(ctx, setup, mdo);
end
