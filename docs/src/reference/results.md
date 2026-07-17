# Results Dictionary

The `solve_ots()` function returns a dictionary with the following keys:

## Optimization Status
- `:status` - Termination status (e.g., `OPTIMAL`, `TIME_LIMIT`)
- `:solve_time` - Solver runtime in seconds
- `:objective_value` - Final objective function value
- `:switching_method` - Solution method used (`"optimal"` or `"thresholded"`)

## Decision Variables
- `:z` - Line switching decisions `[D × risky_lines]` (1=energized, 0=de-energized)
- `:va` - Voltage angles `[D × T × buses]` (radians)
- `:p` - Real power flows `[D × T × branches]` (MW)
- `:g` or `:pg` - Real power generation `[D × T × generators]` (MW)
- `:load_shedding` or `:p_load_shedding` - Load shedding `[D × T × buses]` (MW)

**LACOTS only:**
- `:vm` - Voltage magnitudes `[D × T × buses]` (per unit)
- `:q` - Reactive power flows `[D × T × branches]` (MVAr)
- `:qg` - Reactive power generation `[D × T × generators]` (MVAr)
- `:q_load_shedding` - Reactive load shedding `[D × T × buses]` (MVAr)

## Summary Metrics
- `:total_load_shed` - Total load shedding across all periods (MW)
- `:total_risk` - Total possible wildfire risk (baseline)
- `:active_risk` - Wildfire risk from energized lines (accounts for hardening if enabled)
- `:removed_risk` - Wildfire risk eliminated by switching
- `:risk_reduction_pct` - Percentage of risk removed
- `:switched_off_lines` - Dict mapping day index to list of de-energized line IDs

**Hardening Results (if hardening enabled):**
- `:y` - Line hardening decisions `[hardenable_lines]` (1=hardened, 0=not hardened)
- `:hardened_lines` - Vector of hardened line IDs
- `:hardening_cost` - Total hardening cost in USD
- `:mitigated_risk` - Wildfire risk mitigated by hardening

**Battery Results (if battery enabled):**
- `:x` - Battery capacity decisions `[battery_locs]` (p.u., where 1 p.u. = 100 MWh)
- `:soc` - State of charge `[D × (0:T) × battery_locs]` (p.u.)
- `:p_charge` - Active power charging `[D × T × battery_locs]` (p.u.)
- `:p_discharge` - Active power discharging `[D × T × battery_locs]` (p.u.)
- `:q_charge` - Reactive power charging (LACOTS only, p.u.)
- `:q_discharge` - Reactive power discharging (LACOTS only, p.u.)
- `:batteries_installed` - Vector of bus IDs with installed capacity ≥ 0.01 p.u.
- `:total_battery_capacity` - Sum of all installed capacity (p.u.)
- `:battery_cost` - Total battery installation cost in USD

**Solar Results (if solar enabled):**
- `:s` - Solar capacity decisions `[solar_locs]` (p.u., where 1 p.u. = 100 MW)
- `:p_solar` - Active power generation `[D × T × solar_locs]` (p.u.)
- `:q_solar` - Reactive power injection (LACOTS only, p.u., bidirectional)
- `:solar_installed` - Vector of bus IDs with installed capacity ≥ 0.01 p.u.
- `:total_solar_capacity` - Sum of all installed capacity (p.u.)
- `:solar_cost` - Total solar installation cost in USD
- `:total_solar_generation` - Total active power generated (p.u.·h)
- `:total_solar_q_injection` - Total reactive power injected (LACOTS only, p.u.·h)

**Notes:**
- For the thresholded method, `:z` values are pre-computed fixed scalars (0 or 1), not optimization variables
- `:y` values are always binary optimization variables when hardening is enabled, regardless of switching method
- When hardening is enabled, `:active_risk` accounts for risk reduction from hardened lines
- Battery capacity `:x[n]` is a continuous variable (p.u.); buses with capacity < 0.01 p.u. are considered uninstalled
- Solar capacity `:s[n]` is a continuous variable (p.u.); buses with capacity < 0.01 p.u. are considered uninstalled

## AC Verification Results

`verify_ac()` returns a dictionary organized by `(day, hour)`:

- `:status` - Dict mapping `(d, t)` to the nonlinear solver termination status
- `:feasible` - Dict mapping `(d, t)` to a Boolean feasibility flag
- `:feasible_all` - `true` if every checked hour solved to a feasible point
- `:failed_hours` - Vector of `(d, t)` pairs that did not solve feasibly
- `:hours` - Per-hour detailed results with bus voltages, generator dispatch, branch flows, load shed, and fixed branch statuses
- `:total_p_load_shed` - Total active load shed across all checked hours
- `:total_q_load_shed` - Total reactive load shed across all checked hours
- `:total_load_shed` - Alias for total active load shed

Each `results[:hours][(d,t)]` includes:
- `:vm`, `:va` - Bus voltage magnitudes and angles
- `:pg`, `:qg` - Generator active/reactive dispatch
- `:p`, `:q` - Branch active/reactive flows in both directions
- `:branch_status` - Fixed energized/off status used by the AC model
- `:p_load_shed`, `:q_load_shed` - Present for `ACOPF` recovery runs
