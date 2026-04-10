function [reserve_req_mw, reserve_ratio] = reserve_profile_24h(total_load_mw, reserve_ratio)
%RESERVE_PROFILE_24H Build a 24-hour spinning reserve requirement.
%   RESERVE_REQ_MW = RESERVE_PROFILE_24H(TOTAL_LOAD_MW) returns a reserve
%   requirement equal to 7 percent of hourly total demand.
%
%   [RESERVE_REQ_MW, RESERVE_RATIO] = RESERVE_PROFILE_24H(TOTAL_LOAD_MW, R)
%   accepts a scalar or 24-element vector reserve ratio R.

if nargin < 1 || isempty(total_load_mw)
    total_load_mw = ones(24, 1);
end
if isscalar(total_load_mw)
    total_load_mw = repmat(total_load_mw, 24, 1);
else
    total_load_mw = total_load_mw(:);
end

if nargin < 2 || isempty(reserve_ratio)
    reserve_ratio = 0.07;
end
if isscalar(reserve_ratio)
    reserve_ratio = repmat(reserve_ratio, numel(total_load_mw), 1);
else
    reserve_ratio = reserve_ratio(:);
end

if numel(total_load_mw) ~= 24
    error('reserve_profile_24h:InvalidLoadLength', ...
        'TOTAL_LOAD_MW must be scalar or contain exactly 24 hourly values.');
end

if numel(reserve_ratio) ~= 24
    error('reserve_profile_24h:InvalidReserveLength', ...
        'RESERVE_RATIO must be scalar or contain exactly 24 hourly values.');
end

if any(reserve_ratio < 0)
    error('reserve_profile_24h:NegativeReserveRatio', ...
        'Reserve ratios must be non-negative.');
end

reserve_req_mw = total_load_mw .* reserve_ratio;
end
