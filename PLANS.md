# PLANS.md

## 总目标

基于 `case24_ieee_rts`，完成一个 24 小时多时段经济调度项目，并形成四类可对比场景：

- 场景 A：无储能、无备用
- 场景 B：有备用、无储能
- 场景 C：有储能、无备用
- 场景 D：有储能、有备用、有拥塞

## 总体策略

采用“两层推进”：

1. 基础验证层
   - 跑通潮流
   - 跑通单时段 OPF
   - 确认 MATPOWER 路径、求解器、案例读取都正常
2. 多时段调度层
   - 构造 24h 负荷与备用曲线
   - 构造 MOST 输入
   - 逐场景求解并统一导出结果

## 阶段计划

### 阶段 1：环境验证

目标：
完成 MATPOWER/MOST 环境确认，并验证 `case24_ieee_rts` 的 PF 与单时段 OPF 能稳定运行。

主要文件：

- `src/init_env.m`
- `src/run_base_pf.m`
- `src/run_base_opf.m`

关键任务：

1. 检查 MATPOWER 与 MOST 路径是否可用。
2. 配置统一的 `mpoption`。
3. 创建 `results/logs/`、`results/mats/`、`results/tables/`、`results/figures/`。
4. 读取 `case24_ieee_rts` 并运行基础潮流。
5. 运行单时段 OPF，保存成本、发电机出力和支路负载。

验收标准：

- 无路径错误
- PF 成功收敛
- OPF 成功求解
- `results/mats/` 下至少生成两个结果文件

建议验证：

- MATLAB 中执行 `ctx = init_env();`
- MATLAB 中执行 `run_base_pf(ctx);`
- MATLAB 中执行 `run_base_opf(ctx);`

### 阶段 2：时序输入构建

目标：
生成 24 小时负荷曲线、备用需求曲线及公共参数。

主要文件：

- `data/load_profile_24h.m`
- `data/reserve_profile_24h.m`
- `src/build_profiles.m`

关键任务：

1. 固化 24 点负荷系数向量。
2. 基于总负荷比例生成备用需求向量。
3. 将曲线保存到 `results/mats/`，并导出基础曲线图。

验收标准：

- 生成的负荷与备用向量长度均为 24
- 负荷曲线峰谷关系符合预期
- 至少导出一张负荷曲线图

建议验证：

- MATLAB 中执行 `profiles = build_profiles(ctx);`

### 阶段 3：场景 A

目标：
完成 24h 无储能、无备用的基准多时段调度。

主要文件：

- `src/build_most_input.m`
- `src/run_scenario_A.m`

关键任务：

1. 将基础 case 与 24h 负荷曲线映射到 MOST 输入结构。
2. 先不引入储能和备用，只验证负荷驱动的多时段调度。
3. 保存总成本、机组出力、关键线路潮流。

验收标准：

- 24h 调度成功完成
- 生成 `scenario_A_result.mat`
- 至少输出机组出力曲线与总成本摘要

建议验证：

- MATLAB 中执行 `resultA = run_scenario_A(ctx, profiles);`

### 阶段 4：场景 B

目标：
在场景 A 基础上加入旋转备用，量化成本和出力变化。

主要文件：

- `src/run_scenario_B.m`

关键任务：

1. 将备用需求写入 MOST 输入。
2. 求解有备用、无储能场景。
3. 对比 A/B 的成本和机组出力差异。

验收标准：

- 生成 `scenario_B_result.mat`
- 能导出备用分配表
- 能报告相对场景 A 的成本增量

建议验证：

- MATLAB 中执行 `resultB = run_scenario_B(ctx, profiles);`

### 阶段 5：场景 C

目标：
在无备用条件下引入 1 个储能单元，观察削峰填谷行为。

主要文件：

- `data/storage_params.m`
- `src/run_scenario_C.m`

关键任务：

1. 定义储能功率、能量、效率、SOC 上下限、初始 SOC。
2. 将储能数据接入 MOST。
3. 导出储能功率曲线、SOC 曲线和成本变化。

验收标准：

- 生成 `scenario_C_result.mat`
- SOC 全时段均在合法范围内
- 能从结果上看出低谷充电、高峰放电趋势

建议验证：

- MATLAB 中执行 `resultC = run_scenario_C(ctx, profiles);`

### 阶段 6：场景 D

目标：
在储能和备用同时存在的前提下，人为制造可解释的网络拥塞。

主要文件：

- `data/congestion_params.m`
- `src/run_scenario_D.m`

关键任务：

1. 选择 1 到 2 条关键支路。
2. 将其容量下调到原值的 60% 到 80%。
3. 在高峰时段形成绑定约束。
4. 分析拥塞对成本、储能策略、关键线路潮流的影响。

验收标准：

- 生成 `scenario_D_result.mat`
- 至少出现一条绑定或接近绑定的支路
- 场景 D 与场景 C/B/A 的成本、潮流或储能策略存在可解释差异

建议验证：

- MATLAB 中执行 `resultD = run_scenario_D(ctx, profiles);`

### 阶段 7：统一对比与导出

目标：
将 A/B/C/D 四个场景统一汇总，形成课程报告可直接使用的图表与表格。

主要文件：

- `src/compare_all_scenarios.m`
- `src/export_tables.m`
- `src/export_figures.m`

关键任务：

1. 读取所有场景结果。
2. 生成总成本、峰时成本、机组峰值、最大线路载荷率、拥塞时段数等指标。
3. 导出 CSV 表和 PNG 图。

验收标准：

- 生成总对比 MAT 文件
- `results/tables/` 下有总对比表
- `results/figures/` 下有完整图集

建议验证：

- MATLAB 中执行 `summary = compare_all_scenarios(ctx);`
- MATLAB 中执行 `export_tables(ctx);`
- MATLAB 中执行 `export_figures(ctx);`

## 风险与取舍

1. 如果 MOST 多时段输入结构与预期不一致，先查本机 `loadmd`、`apply_profile`、`md_init` 等帮助和示例，不要硬套外部博客写法。
2. 如果 AC 多时段链路过重或版本兼容性差，优先确保课程项目主线可复现，不要在第一版就扩大复杂度。
3. 储能与备用先做单储能、固定备用比例，先保证结果可解释。
4. 拥塞只需制造少量明确绑定线路，不追求全网复杂拥塞图景。

## 完成定义

满足以下条件时，项目主线视为完成：

1. PF 与单时段 OPF 均可运行。
2. 24h 负荷与备用曲线可独立生成。
3. 场景 A/B/C/D 全部能独立运行并生成 MAT 结果。
4. 储能功率与 SOC 曲线可导出。
5. 至少 1 到 2 条关键线路的潮流曲线可导出。
6. 成本、出力、储能、拥塞四类指标已统一形成对比表和图。
