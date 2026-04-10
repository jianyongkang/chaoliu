function result = run_scenario_B(ctx, profiles)
%RUN_SCENARIO_B 24-hour dispatch with fixed reserves and no storage.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end

setup = build_most_input(ctx, profiles, 'B');
mdo = most(setup.mdi, setup.mpopt);
result = postprocess_most_result(ctx, setup, mdo);
end
