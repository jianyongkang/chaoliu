# AGENTS.md

## 项目定位

本工作区用于实现一个基于 `case24_ieee_rts` 的 MATPOWER/MOST 课程项目：

1. 先完成基础潮流与单时段 OPF 验证。
2. 再完成 24 小时多时段经济调度。
3. 逐步加入旋转备用、储能、线路拥塞三类扩展场景。
4. 最终统一输出成本、机组出力、储能功率与 SOC、关键线路潮流、对比图表。

本仓库根目录即等价于大纲中的 `matpower_most_project/`。

## 不可违反的约束

1. 不修改 MATPOWER 或 MOST 安装目录中的任何原文件。
2. 所有参数脚本只放在 `data/`。
3. 所有逻辑脚本只放在 `src/`。
4. 所有仿真结果只放在 `results/`。
5. 每个场景必须有独立入口脚本，不把 A/B/C/D 混在一个大脚本里。
6. 优先保证“先能稳定跑通”，再做抽象、复用和绘图美化。
7. 第一版不把 UC 整数决策设为硬要求；先完成可稳定复现的多时段调度主线。
8. 除非明确需要，否则不要引入 Excel、数据库或额外外部依赖；参数优先写在 MATLAB `.m` 文件中。
9. 不要假设本地 MOST 辅助函数签名与网上示例完全一致；写代码前先检查本机已安装版本的函数帮助与示例。

## 目录约定

```text
.
├─ AGENTS.md
├─ PLANS.md
├─ SCRIPT_CHECKLIST.md
├─ README.md
├─ data/
├─ src/
├─ results/
│  ├─ logs/
│  ├─ mats/
│  ├─ figures/
│  └─ tables/
└─ temp/
```

## 推荐实现顺序

严格按下面顺序推进，不要跳步：

1. `src/init_env.m`
2. `src/run_base_pf.m`
3. `src/run_base_opf.m`
4. `src/build_profiles.m`
5. `src/build_most_input.m`
6. `src/run_scenario_A.m`
7. `src/run_scenario_B.m`
8. `src/run_scenario_C.m`
9. `src/run_scenario_D.m`
10. `src/compare_all_scenarios.m`
11. `src/export_tables.m`
12. `src/export_figures.m`

任何阶段如果前置阶段未通过，不要继续向后实现。

## 建模边界

第一版按以下边界实现：

- 基础验证层使用 MATPOWER 完成 AC PF 和单时段 OPF。
- 多时段调度层优先采用 MOST 的稳定主线能力，默认按课程项目可复现的简化多时段调度来实现。
- 负荷曲线采用人工构造的 24 点负荷系数。
- 备用需求先采用总负荷固定比例法。
- 储能先只接入 1 个储能单元。
- 拥塞先通过收紧 1 到 2 条关键支路容量人为制造，不做全网复杂事故集。

## 编码规范

1. MATLAB 函数优先返回结构体，避免依赖大量全局变量。
2. 所有场景脚本都应可单独运行，并在内部调用 `init_env` 或接收 `ctx`。
3. 结果文件命名必须稳定、可预测，例如：
   - `results/mats/base_pf_result.mat`
   - `results/mats/base_opf_result.mat`
   - `results/mats/scenario_A_result.mat`
4. 表格优先导出为 `.csv`，中间结果优先保存为 `.mat`。
5. 图片统一导出到 `results/figures/`，优先使用 `.png`。
6. 日志统一写到 `results/logs/`。
7. 脚本内部的可调参数不要散落在 `src/`，统一回收到 `data/`。
8. 不要过早封装成复杂类或多层对象；普通函数加结构体输入输出即可。

## 结果最小要求

每一阶段至少留下一个可验证产物：

- 阶段 1：PF/OPF MAT 文件与日志
- 阶段 2：24h 负荷与备用曲线 MAT 文件
- 阶段 3：场景 A 总成本与机组出力曲线
- 阶段 4：场景 B 成本增量与备用分配表
- 阶段 5：场景 C 储能功率与 SOC 曲线
- 阶段 6：场景 D 拥塞线路表与关键线路对比图
- 阶段 7：A/B/C/D 总对比表与全部 PNG 图

## 推荐运行方式

建议未来脚本按以下入口风格编写：

```matlab
ctx = init_env();
run_base_pf(ctx);
run_base_opf(ctx);
profiles = build_profiles(ctx);
run_scenario_A(ctx, profiles);
```

如果脚本实现为无输入入口函数，也必须保证其内部能自行定位仓库根目录并创建所需结果目录。

## 交付口径

未来任何 Codex 会话在提交阶段性成果时，都应明确说明：

1. 当前完成到哪个阶段。
2. 新增或修改了哪些文件。
3. 运行了哪些验证。
4. 哪些结果已经写入 `results/`。
5. 还有哪些前置问题未解决。
