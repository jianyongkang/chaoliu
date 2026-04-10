# Cost Reconciliation

Tolerance: 1.000e-06

| Scenario | Storage Enabled | Solver Objective | Dispatch Cost Approx | Solver - Dispatch | Zero-Output Constant Total | Applied Offset | Reconciled Dispatch Cost | Solver - Reconciled | Hypothesis Match |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Scenario A | false | 1273778.336557 | 1273778.336557 | -0.000000 | 257077.274400 | 0.000000 | 1273778.336557 | -0.000000 | true |
| Scenario B | false | 1299475.025382 | 1299475.025382 | -0.000000 | 257077.274400 | 0.000000 | 1299475.025382 | -0.000000 | true |
| Scenario C | true | 1009481.323134 | 1266558.597534 | -257077.274400 | 257077.274400 | 257077.274400 | 1009481.323134 | 0.000000 | true |
| Scenario D | true | 1053237.529167 | 1310314.803567 | -257077.274400 | 257077.274400 | 257077.274400 | 1053237.529167 | 0.000000 | true |

## Interpretation
- In non-storage scenarios, no reconciliation offset is applied.
- In storage-enabled scenarios, the audited offset equals the full-horizon zero-output generator cost constant.
- If `solver_minus_reconciled_dispatch` is numerically zero, the fixed gap is fully explained by this constant term.
