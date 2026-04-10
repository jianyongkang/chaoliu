# SCRIPT_CHECKLIST.md

## 说明

本文件用于固定后续 MATLAB 文件的职责边界。除非出现明确实现障碍，否则按这里的文件名、阶段顺序和输入输出关系推进。

推荐约定：

- `data/` 下文件优先写成返回参数的函数，而不是无输出脚本。
- `src/` 下文件优先写成函数入口，并返回结构体结果。
- 各入口函数统一接收 `ctx` 或在内部调用 `init_env()`。

## 数据层文件

| 文件 | 阶段 | 推荐入口 | 职责 | 关键输出 |
| --- | --- | --- | --- | --- |
| `data/load_profile_24h.m` | 2 | `function load_scale = load_profile_24h()` | 提供 24 点负荷系数向量 | `24x1` 或 `1x24` 负荷系数 |
| `data/reserve_profile_24h.m` | 2 | `function reserve_req = reserve_profile_24h(total_load)` | 根据总负荷或负荷曲线生成备用需求 | `24x1` 备用需求向量 |
| `data/storage_params.m` | 5 | `function s = storage_params()` | 提供储能额定能量、功率、效率、SOC 上下限、接入母线等参数 | `struct` |
| `data/congestion_params.m` | 6 | `function c = congestion_params(mpc)` | 指定要收紧的支路及容量缩放比例 | `struct` |

## 逻辑层文件

| 文件 | 阶段 | 推荐入口 | 职责 | 主要输入 | 主要输出 |
| --- | --- | --- | --- | --- | --- |
| `src/init_env.m` | 1 | `function ctx = init_env()` | 检查 MATPOWER/MOST、设置路径和 `mpoption`、创建结果目录 | 无 | `ctx` |
| `src/run_base_pf.m` | 1 | `function result = run_base_pf(ctx)` | 读取 `case24_ieee_rts` 并运行基础潮流 | `ctx` | PF 结果结构体、MAT 文件、母线/支路表 |
| `src/run_base_opf.m` | 1 | `function result = run_base_opf(ctx)` | 运行单时段 OPF 并提取基准成本与潮流 | `ctx` | OPF 结果结构体、MAT 文件、成本摘要 |
| `src/build_profiles.m` | 2 | `function profiles = build_profiles(ctx)` | 组合负荷曲线、备用曲线和公共场景参数 | `ctx` | `profiles` 结构体、曲线 MAT 文件 |
| `src/build_most_input.m` | 3 | `function mdi = build_most_input(ctx, profiles, scenario_name)` | 将 case、时序负荷、备用、储能、拥塞参数组装为 MOST 输入 | `ctx`, `profiles`, `scenario_name` | `mdi` 结构体 |
| `src/run_scenario_A.m` | 3 | `function result = run_scenario_A(ctx, profiles)` | 24h 无储能、无备用基准调度 | `ctx`, `profiles` | 场景 A 结果与图表数据 |
| `src/run_scenario_B.m` | 4 | `function result = run_scenario_B(ctx, profiles)` | 在 A 基础上加入备用 | `ctx`, `profiles` | 场景 B 结果、备用分配表 |
| `src/run_scenario_C.m` | 5 | `function result = run_scenario_C(ctx, profiles)` | 在 A 基础上加入单储能 | `ctx`, `profiles` | 场景 C 结果、储能功率与 SOC |
| `src/run_scenario_D.m` | 6 | `function result = run_scenario_D(ctx, profiles)` | 在 C/B 基础上叠加备用与拥塞 | `ctx`, `profiles` | 场景 D 结果、拥塞线路分析 |
| `src/compare_all_scenarios.m` | 7 | `function summary = compare_all_scenarios(ctx)` | 汇总 A/B/C/D 结果并计算对比指标 | `ctx` | `summary` 结构体、对比表 |
| `src/export_tables.m` | 7 | `function export_tables(ctx)` | 将关键结果导出为 CSV/MAT | `ctx` | `results/tables/*.csv` |
| `src/export_figures.m` | 7 | `function export_figures(ctx)` | 统一生成并导出 PNG 图 | `ctx` | `results/figures/*.png` |

## 建议的 `ctx` 字段

为了减少脚本之间的隐式依赖，`init_env()` 返回的 `ctx` 建议至少包含：

- `ctx.root_dir`
- `ctx.data_dir`
- `ctx.src_dir`
- `ctx.results_dir`
- `ctx.logs_dir`
- `ctx.mats_dir`
- `ctx.tables_dir`
- `ctx.figures_dir`
- `ctx.case_name`
- `ctx.case_loader`
- `ctx.mpopt`
- `ctx.has_most`

## 场景脚本统一输出建议

每个场景结果结构体建议包含以下字段，便于统一对比：

- `result.name`
- `result.success`
- `result.total_cost`
- `result.hourly_cost`
- `result.gen_dispatch`
- `result.branch_flow`
- `result.branch_loading_pct`
- `result.reserve_dispatch`
- `result.storage_power`
- `result.storage_soc`
- `result.binding_branches`
- `result.notes`

未使用的字段可留空，但字段名尽量保持一致。

## 关键依赖关系

1. `run_base_pf` 和 `run_base_opf` 依赖 `init_env`。
2. `build_profiles` 依赖 `init_env`，但不依赖 MOST。
3. `build_most_input` 依赖 `init_env`、`build_profiles`，并可能依赖 `storage_params`、`congestion_params`。
4. `run_scenario_B/C/D` 不要各自重复写一套参数装配逻辑，应复用 `build_most_input`。
5. `compare_all_scenarios`、`export_tables`、`export_figures` 只读取 `results/mats/` 中的标准化结果，不直接重跑调度。

## 优先级清单

第一优先级：

1. `src/init_env.m`
2. `src/run_base_pf.m`
3. `src/run_base_opf.m`
4. `src/build_profiles.m`

第二优先级：

1. `src/build_most_input.m`
2. `src/run_scenario_A.m`

第三优先级：

1. `src/run_scenario_B.m`
2. `src/run_scenario_C.m`
3. `src/run_scenario_D.m`

第四优先级：

1. `src/compare_all_scenarios.m`
2. `src/export_tables.m`
3. `src/export_figures.m`
