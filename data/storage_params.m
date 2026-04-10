function s = storage_params()
%STORAGE_PARAMS Return the default single-storage configuration.
%   Parameters are intentionally moderate relative to the RTS 24 system so
%   that charging at low load and discharging at peak hours is observable.

s = struct();
s.name = 'ESS_1';
s.bus = 15;
s.power_rating_mw = 80;
s.energy_rating_mwh = 240;
s.initial_soc = 0.50;
s.min_soc = 0.20;
s.max_soc = 0.90;
s.charge_efficiency = 0.92;
s.discharge_efficiency = 0.92;
s.loss_factor = 0.00;
s.rho = 0.00;
s.initial_energy_value = 0;
s.terminal_energy_value = 0;
s.enforce_terminal_soc = true;
s.reserve_offer_price = 3;
s.reserve_offer_qty_mw = 0;
s.linear_dispatch_cost = 0;
end
