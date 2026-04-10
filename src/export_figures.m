function export_figures(ctx)
%EXPORT_FIGURES Export report-friendly scenario figures as PNG files.

if nargin < 1 || isempty(ctx)
    ctx = init_env();
end

compare_file = fullfile(ctx.mats_dir, 'scenario_compare.mat');
if ~exist(compare_file, 'file')
    compare_all_scenarios(ctx);
end
summary_data = load(compare_file, 'summary');
summary = summary_data.summary;

plot_load_and_reserve_profile(ctx, summary.results{1}.profiles);
plot_total_cost_compare(ctx, summary.scenario_table);
plot_peak_hour_cost_compare(ctx, summary.scenario_table);
plot_total_cost_delta_vs_A(ctx, summary.scenario_table);
plot_hourly_cost_compare(ctx, summary.results);
plot_storage_compare_cd(ctx, summary.results);
plot_top_generator_compare(ctx, summary.results);
plot_branch_loading_compare_ad(ctx, summary.results);
plot_congestion_heatmap_d(ctx, summary.results);

write_text_log(fullfile(ctx.logs_dir, 'export_figures_log.txt'), {
    'Scenario figures exported'
    ['figures_dir: ', ctx.figures_dir]
});
end

function plot_load_and_reserve_profile(ctx, profiles)
fig = create_figure([100, 100, 920, 620]);
subplot(2, 1, 1);
plot(profiles.hours, profiles.hourly_load_mw, '-o', 'Color', [0.15 0.35 0.70], ...
    'LineWidth', 1.8, 'MarkerSize', 5, 'MarkerFaceColor', [0.15 0.35 0.70]);
style_axes(gca, 'Hour', 'Load (MW)', '24h Load Profile');
xlim([1 24]);

subplot(2, 1, 2);
yyaxis left;
plot(profiles.hours, profiles.load_scale, '-s', 'Color', [0.10 0.50 0.20], ...
    'LineWidth', 1.6, 'MarkerSize', 5, 'MarkerFaceColor', [0.10 0.50 0.20]);
ylabel('Load Scale');
yyaxis right;
bar(profiles.hours, profiles.reserve_req_mw, 0.65, 'FaceColor', [0.80 0.30 0.20], 'EdgeColor', 'none');
ylabel('Reserve (MW)');
grid on;
xlim([1 24]);
xlabel('Hour');
title('Load Scale and Reserve Requirement');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_load_reserve_profile.png'));
close(fig);
end

function plot_total_cost_compare(ctx, scenario_table)
fig = create_figure([100, 100, 860, 430]);
vals = scenario_table.dispatch_total_cost_approx;
b = bar(vals, 'FaceColor', 'flat');
b.CData = scenario_colors(height(scenario_table));
set(gca, 'XTickLabel', scenario_table.scenario);
style_axes(gca, '', 'Dispatch Total Cost Approx', 'Scenario Dispatch Cost Approximation');
add_bar_labels(vals, '%.0f');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_total_cost_compare.png'));
close(fig);
end

function plot_peak_hour_cost_compare(ctx, scenario_table)
fig = create_figure([100, 100, 860, 430]);
vals = scenario_table.peak_hour_cost_approx;
b = bar(vals, 'FaceColor', 'flat');
b.CData = scenario_colors(height(scenario_table));
set(gca, 'XTickLabel', scenario_table.scenario);
style_axes(gca, '', 'Peak-Hour Dispatch Cost Approx', 'Peak-Hour Dispatch Cost Approximation');
add_bar_labels(vals, '%.0f');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_peak_hour_cost_compare.png'));
close(fig);
end

function plot_total_cost_delta_vs_A(ctx, scenario_table)
fig = create_figure([100, 100, 860, 430]);
vals = scenario_table.dispatch_total_cost_delta_vs_A;
b = bar(vals, 'FaceColor', 'flat');
b.CData = scenario_colors(height(scenario_table));
set(gca, 'XTickLabel', scenario_table.scenario);
style_axes(gca, '', 'Dispatch Cost Delta vs Scenario A', 'Dispatch Cost Delta Relative to Scenario A');
yline(0, '--k', 'LineWidth', 1.0);
add_bar_labels(vals, '%.0f');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_total_cost_delta_vs_A.png'));
close(fig);
end

function plot_hourly_cost_compare(ctx, results)
fig = create_figure([100, 100, 960, 480]);
hold on;
colors = scenario_colors(numel(results));
for k = 1:numel(results)
    plot(results{k}.profiles.hours, results{k}.hourly_dispatch_total_cost_approx, 'LineWidth', 1.8, ...
        'Color', colors(k, :));
end
hold off;
style_axes(gca, 'Hour', 'Hourly Dispatch Cost Approx', 'Hourly Dispatch Cost Approximation');
xlim([1 24]);
legend(extract_scenario_labels(results), 'Location', 'best');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_hourly_cost_compare.png'));
close(fig);
end

function plot_storage_compare_cd(ctx, results)
resultC = find_result(results, 'C');
resultD = find_result(results, 'D');
if isempty(resultC) || isempty(resultD) || isempty(resultC.storage_power) || isempty(resultD.storage_power)
    return;
end

hours = resultC.profiles.hours(:);
powerC = sum(resultC.storage_power, 1);
powerD = sum(resultD.storage_power, 1);
socC = sum(resultC.storage_soc, 1);
socD = sum(resultD.storage_soc, 1);

fig = create_figure([100, 100, 960, 620]);
subplot(2, 1, 1);
plot(hours, powerC, '-o', 'LineWidth', 1.8, 'Color', [0.10 0.55 0.85], 'MarkerSize', 4);
hold on;
plot(hours, powerD, '-s', 'LineWidth', 1.8, 'Color', [0.85 0.35 0.15], 'MarkerSize', 4);
yline(0, '--k', 'LineWidth', 1.0, 'HandleVisibility', 'off');
hold off;
style_axes(gca, 'Hour', 'Storage Power (MW)', 'Storage Dispatch: Scenario C vs D');
xlim([1 24]);
legend({'Scenario C', 'Scenario D'}, 'Location', 'best');

subplot(2, 1, 2);
plot(hours, socC, '-o', 'LineWidth', 1.8, 'Color', [0.10 0.55 0.85], 'MarkerSize', 4);
hold on;
plot(hours, socD, '-s', 'LineWidth', 1.8, 'Color', [0.85 0.35 0.15], 'MarkerSize', 4);
hold off;
style_axes(gca, 'Hour', 'Stored Energy (MWh)', 'Storage State of Charge: Scenario C vs D');
xlim([1 24]);
legend({'Scenario C', 'Scenario D'}, 'Location', 'best');
saveas(fig, fullfile(ctx.figures_dir, 'scenario_storage_compare_CD.png'));
close(fig);
end

function plot_top_generator_compare(ctx, results)
resultA = find_result(results, 'A');
if isempty(resultA)
    return;
end

avg_dispatch = mean(resultA.gen_dispatch, 2);
[~, order] = sort(avg_dispatch, 'descend');
top_idx = order(1:min(3, numel(order)));
colors = scenario_colors(numel(results));

fig = create_figure([100, 100, 960, 760]);
for p = 1:numel(top_idx)
    subplot(numel(top_idx), 1, p);
    hold on;
    for k = 1:numel(results)
        plot(results{k}.profiles.hours, results{k}.gen_dispatch(top_idx(p), :), ...
            'LineWidth', 1.7, 'Color', colors(k, :));
    end
        hold off;
        style_axes(gca, 'Hour', 'Dispatch (MW)', ...
            sprintf('Generator %s Dispatch Across Scenarios', resultA.gen_labels{top_idx(p)}));
        xlim([1 24]);
        if p == 1
            legend(extract_scenario_labels(results), 'Location', 'best');
        end
end
saveas(fig, fullfile(ctx.figures_dir, 'scenario_top_generator_compare.png'));
close(fig);
end

function plot_branch_loading_compare_ad(ctx, results)
resultA = find_result(results, 'A');
resultD = find_result(results, 'D');
if isempty(resultA) || isempty(resultD) || isempty(resultD.key_branch_idx)
    return;
end

branch_idx = resultD.key_branch_idx(1:min(3, numel(resultD.key_branch_idx)));
fig = create_figure([100, 100, 960, 760]);
for p = 1:numel(branch_idx)
    idx = branch_idx(p);
    subplot(numel(branch_idx), 1, p);
    plot(resultA.profiles.hours, resultA.branch_loading_pct(idx, :), '-o', ...
        'LineWidth', 1.6, 'Color', [0.15 0.35 0.75], 'MarkerSize', 4);
    hold on;
    plot(resultD.profiles.hours, resultD.branch_loading_pct(idx, :), '-s', ...
        'LineWidth', 1.6, 'Color', [0.85 0.30 0.15], 'MarkerSize', 4);
    yline(100, '--k', 'LineWidth', 1.0);
    hold off;
    style_axes(gca, 'Hour', 'DC Branch Loading Proxy (%)', ...
        sprintf('Branch %s Loading Proxy: Scenario A vs D', resultD.branch_labels{idx}));
    xlim([1 24]);
    if p == 1
        legend({'Scenario A', 'Scenario D', 'Binding Threshold'}, 'Location', 'best');
    end
end
saveas(fig, fullfile(ctx.figures_dir, 'scenario_branch_loading_compare_AD.png'));
close(fig);
end

function plot_congestion_heatmap_d(ctx, results)
resultD = find_result(results, 'D');
if isempty(resultD) || isempty(resultD.key_branch_idx)
    return;
end

branch_idx = resultD.key_branch_idx(:);
heatmap_data = resultD.branch_loading_pct(branch_idx, :);
window_label = '';
if isfield(resultD.setup, 'congestion') && isfield(resultD.setup.congestion, 'active_hours') && ...
        ~isempty(resultD.setup.congestion.active_hours)
    active_hours = resultD.setup.congestion.active_hours(:);
    window_label = sprintf(' (active congestion window %02d:00-%02d:00)', ...
        active_hours(1), active_hours(end));
end

fig = create_figure([100, 100, 960, 460]);
imagesc(resultD.profiles.hours(:).', 1:numel(branch_idx), heatmap_data);
set(gca, 'YTick', 1:numel(branch_idx), 'YTickLabel', resultD.branch_labels(branch_idx));
xlabel('Hour');
ylabel('Key Branch');
title(['Scenario D Congestion Heatmap (DC Branch Loading Proxy %)', window_label]);
colorbar;
colormap(parula(256));
set(gca, 'FontName', 'Arial', 'FontSize', 10, 'LineWidth', 1.0);
saveas(fig, fullfile(ctx.figures_dir, 'scenario_D_congestion_heatmap.png'));
close(fig);
end

function fig = create_figure(position)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', position);
end

function style_axes(ax, xlab, ylab, ttl)
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontName', 'Arial', 'FontSize', 10, 'LineWidth', 1.0);
if ~isempty(xlab)
    xlabel(ax, xlab);
end
if ~isempty(ylab)
    ylabel(ax, ylab);
end
title(ax, ttl, 'FontWeight', 'bold');
end

function add_bar_labels(vals, fmt)
for i = 1:numel(vals)
    if vals(i) >= 0
        y = vals(i) + 0.01 * max(abs(vals));
        va = 'bottom';
    else
        y = vals(i) - 0.01 * max(abs(vals));
        va = 'top';
    end
    text(i, y, sprintf(fmt, vals(i)), 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', va, 'FontSize', 9);
end
end

function colors = scenario_colors(n)
base = [
    0.20 0.40 0.80;
    0.85 0.55 0.15;
    0.15 0.65 0.40;
    0.80 0.25 0.20
];
colors = base(1:n, :);
end

function labels = extract_scenario_labels(results)
labels = cell(numel(results), 1);
for k = 1:numel(results)
    labels{k} = ['Scenario ', results{k}.scenario];
end
end

function result = find_result(results, scenario_name)
result = [];
for k = 1:numel(results)
    if strcmpi(results{k}.scenario, scenario_name)
        result = results{k};
        return;
    end
end
end
