# AC Feasibility Diagnostic Report

- Network: RTS
- Mode: ACOPF
- Feasible all: true
- Failed hours: Tuple{Int64, Int64}[]

## Violation Summary
- `active_load_shed`: 1 violations, max severity 0.481815
- `islanding`: 1 violations, max severity 4.0
- `reactive_load_shed`: 1 violations, max severity 0.118615

## Top Violations
- `islanding` hour (1, 1), component 207, severity 4.0: 4 load or generator bus(es) are disconnected from all reference buses.
- `active_load_shed` hour (1, 1), bus 208, severity 0.481815: AC recovery shed active load at bus 208.
- `reactive_load_shed` hour (1, 1), bus 203, severity 0.118615: AC recovery shed reactive load at bus 203.

## Feedback Hints
- **load_shed_recovery**: AC recovery shed load. Review buses with recovery actions and consider strengthening local supply, transmission paths, or siting decisions.
- **connectivity**: Planning decisions appear to create disconnected AC islands. Consider connectivity constraints or switchable-line exclusions for the listed branches.
