# Scenario Summary

Peak reference hour: 19

| Scenario | Dispatch Total Cost Approx | Delta vs A | Delta vs A (%) | Solver Objective Value | Objective Delta vs A | Peak Hour Dispatch Cost Approx | Max DC Branch Loading Proxy (%) | Congested Hours | Peak Reserve (MW) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Scenario A | 1273778.34 | 0.00 | 0.00 | 1273778.34 | 0.00 | 75329.18 | 80.41 | 0 | 0.00 |
| Scenario B | 1299475.03 | 25696.69 | 2.02 | 1299475.03 | 25696.69 | 76826.08 | 80.41 | 0 | 219.45 |
| Scenario C | 1266558.60 | -7219.74 | -0.57 | 1009481.32 | -264297.01 | 71272.81 | 80.41 | 0 | 0.00 |
| Scenario D | 1310314.80 | 36536.47 | 2.87 | 1053237.53 | -220540.81 | 79844.47 | 100.00 | 4 | 219.45 |

## Notes
- Dispatch Total Cost Approx is the primary economic comparison metric used in this project.
- Solver Objective Value is retained as a secondary MOST-internal reference; `cost_reconciliation.csv` shows that the storage-scenario gap is exactly a fixed zero-output cost constant over the full horizon.
- Branch loading is a DC congestion proxy, not an AC MVA validation result.
