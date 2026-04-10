function outputs = run_all()
%RUN_ALL Execute the full PF/OPF/MOST workflow and export all artifacts.

ctx = init_env();
base_pf = run_base_pf(ctx);
base_opf = run_base_opf(ctx);
profiles = build_profiles(ctx);

scenario_A = run_scenario_A(ctx, profiles);
scenario_B = run_scenario_B(ctx, profiles);
scenario_C = run_scenario_C(ctx, profiles);
scenario_D = run_scenario_D(ctx, profiles);

summary = compare_all_scenarios(ctx);
reconciliation = run_cost_reconciliation(ctx);
export_tables(ctx);
export_figures(ctx);

outputs = struct();
outputs.ctx = ctx;
outputs.base_pf = base_pf;
outputs.base_opf = base_opf;
outputs.profiles = profiles;
outputs.scenario_A = scenario_A;
outputs.scenario_B = scenario_B;
outputs.scenario_C = scenario_C;
outputs.scenario_D = scenario_D;
outputs.summary = summary;
outputs.reconciliation = reconciliation;
end
