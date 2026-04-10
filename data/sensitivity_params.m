function p = sensitivity_params()
%SENSITIVITY_PARAMS Default parameter sweeps for sensitivity analysis.

p = struct();

% Scale both storage power and energy ratings to keep duration constant.
p.storage_capacity_scale = [0.50; 1.00; 1.50; 2.00];

% Reserve ratio sweep for scenario B.
p.reserve_ratio_values = [0.03; 0.05; 0.07; 0.08; 0.09; 0.095; 0.10];

% Tightening factors applied to the primary congestion corridor 14-16.
p.line_limit_factor_values = [0.60; 0.70; 0.80; 0.90];
p.line_limit_target_pair = [14, 16];
end
