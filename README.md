# matpower_most_project

本目录用于实现一个基于 `case24_ieee_rts` 的 MATPOWER/MOST 24 小时多时段经济调度课程项目。

当前阶段已固定三份项目控制文档：

- `AGENTS.md`：约束、目录与执行规则
- `PLANS.md`：分阶段计划与验收标准
- `SCRIPT_CHECKLIST.md`：脚本职责边界与推荐接口

后续实现顺序：

1. 环境验证
2. 24h 曲线构建
3. 场景 A
4. 场景 B
5. 场景 C
6. 场景 D
7. 统一对比与导出

建议所有 MATLAB 文件按 `data/`、`src/`、`results/` 分层维护，不修改 MATPOWER 安装目录。

扩展分析入口：

- `src/run_sensitivity_analysis.m`
  - 储能容量灵敏度
  - 备用比例灵敏度
  - 关键线路限额灵敏度
- `src/run_ac_validation.m`
  - 基于已保存的 A/B/C/D MOST 调度结果，逐小时回代执行 AC PF 校核
  - 输出 AC 电压、AC 支路载荷、平衡机组调整量与系统损耗摘要
