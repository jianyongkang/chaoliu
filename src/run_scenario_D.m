function result = run_scenario_D(ctx, profiles)
%RUN_SCENARIO_D 24-hour dispatch with reserves, storage, and congestion.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end
if nargin < 2 || isempty(profiles)
    profiles = build_profiles(ctx);
end

setup = build_most_input(ctx, profiles, 'D');
mdo = most(setup.mdi, setup.mpopt);
result = postprocess_most_result(ctx, setup, mdo);
end
