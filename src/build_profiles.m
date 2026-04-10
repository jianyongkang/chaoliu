function profiles = build_profiles(ctx)
%BUILD_PROFILES Build the 24-hour load and reserve profiles.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

define_constants;
[~, ~, PD] = idx_bus();

mpc = loadcase(ctx.case_name);
base_total_load_mw = sum(mpc.bus(:, PD));
hours = (1:24)';

load_scale = load_profile_24h();
hourly_load_mw = base_total_load_mw * load_scale;
[reserve_req_mw, reserve_ratio] = reserve_profile_24h(hourly_load_mw);

profiles = struct();
profiles.hours = hours;
profiles.load_scale = load_scale;
profiles.base_total_load_mw = base_total_load_mw;
profiles.hourly_load_mw = hourly_load_mw;
profiles.reserve_ratio = reserve_ratio;
profiles.reserve_req_mw = reserve_req_mw;
profiles.peak_hour = find(hourly_load_mw == max(hourly_load_mw), 1, 'first');
profiles.valley_hour = find(hourly_load_mw == min(hourly_load_mw), 1, 'first');

profile_table = table( ...
    hours, load_scale, hourly_load_mw, reserve_ratio, reserve_req_mw, ...
    'VariableNames', {'hour', 'load_scale', 'hourly_load_MW', 'reserve_ratio', 'reserve_req_MW'});

save(fullfile(ctx.mats_dir, 'profiles_24h.mat'), 'profiles', '-v7');
writetable(profile_table, fullfile(ctx.tables_dir, 'profiles_24h.csv'));
writetable(table(hours, load_scale, 'VariableNames', {'hour', 'load_scale'}), ...
    fullfile(ctx.tables_dir, 'load_profile_24h.csv'));
writetable(table(hours, reserve_req_mw, 'VariableNames', {'hour', 'reserve_req_MW'}), ...
    fullfile(ctx.tables_dir, 'reserve_profile_24h.csv'));

export_profile_figure(ctx, hours, load_scale, hourly_load_mw, reserve_req_mw);

write_text_log(fullfile(ctx.logs_dir, 'build_profiles_log.txt'), {
    '24-hour profiles created'
    ['peak_hour: ', num2str(profiles.peak_hour)]
    ['peak_load_mw: ', sprintf('%.2f', hourly_load_mw(profiles.peak_hour))]
    ['valley_hour: ', num2str(profiles.valley_hour)]
    ['valley_load_mw: ', sprintf('%.2f', hourly_load_mw(profiles.valley_hour))]
    ['peak_reserve_mw: ', sprintf('%.2f', max(reserve_req_mw))]
});
end

function export_profile_figure(ctx, hours, load_scale, hourly_load_mw, reserve_req_mw)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 880, 620]);

subplot(3, 1, 1);
plot(hours, hourly_load_mw, '-o', 'LineWidth', 1.6, 'MarkerSize', 5);
grid on;
xlim([1 24]);
xlabel('Hour');
ylabel('Load (MW)');
title('24h System Load');

subplot(3, 1, 2);
plot(hours, load_scale, '-s', 'LineWidth', 1.4, 'MarkerSize', 5);
ylabel('Load Scale');
grid on;
xlim([1 24]);
xlabel('Hour');
title('Normalized Load Profile');

subplot(3, 1, 3);
bar(hours, reserve_req_mw, 0.6);
ylabel('Reserve (MW)');
grid on;
xlim([1 24]);
xlabel('Hour');
title('Reserve Requirement');

saveas(fig, fullfile(ctx.figures_dir, 'load_profile_24h.png'));
close(fig);
end
