function load_scale = load_profile_24h()
%LOAD_PROFILE_24H Return a deterministic 24-hour load scaling profile.
%   The profile is normalized relative to the original case load in
%   case24_ieee_rts and is intentionally embedded in code to keep the
%   project self-contained.

load_scale = [
    0.65;
    0.62;
    0.60;
    0.58;
    0.60;
    0.68;
    0.78;
    0.88;
    0.94;
    0.97;
    0.96;
    0.95;
    0.93;
    0.92;
    0.94;
    0.98;
    1.02;
    1.08;
    1.10;
    1.06;
    0.98;
    0.88;
    0.78;
    0.70
];

if numel(load_scale) ~= 24
    error('load_profile_24h:InvalidLength', ...
        'The 24-hour load profile must contain exactly 24 points.');
end

if any(load_scale <= 0)
    error('load_profile_24h:InvalidValue', ...
        'All load scaling coefficients must be strictly positive.');
end
end
