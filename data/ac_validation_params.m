function p = ac_validation_params()
%AC_VALIDATION_PARAMS Defaults for AC validation of MOST dispatch results.

p = struct();
p.scenario_names = {'A', 'B', 'C', 'D'};
p.vm_lower_limit = 0.95;
p.vm_upper_limit = 1.05;
p.branch_loading_threshold_pct = 100;
end
