# Models and Methods

## Optimization Models

### DCOTS (DC Optimal Transmission Switching)
- Uses linearized DC power flow approximation
- Decision variables: voltage angles, generation, power flows, load shedding, line switching
- Optional: line hardening decisions (y variables)
- Computationally efficient for large-scale problems
- Ignores reactive power and voltage magnitude constraints

### LACOTS (Linear AC Optimal Transmission Switching)
- Uses linearized AC power flow
- Includes reactive power and voltage magnitude variables
- Optional: line hardening decisions (y variables)
- More accurate representation of AC power systems
- Can warm-start from DCOTS solution for faster convergence (includes z and y values)

### DCOPF / LACOPF (Pure Power Flow — no wildfire switching)
- Same DC / linearized-AC formulations as DCOTS / LACOTS, but with all wildfire-risk machinery disabled:
  no binary `z` switching variables, no risk threshold, no auto-loaded wildfire data
- Lines are never de-energized to mitigate risk — useful as a no-action baseline or for studies that
  shouldn't be biased by wildfire considerations
- Investment options (battery, solar, hardening) still apply and are co-optimized as usual
- Allowed objectives: `"loadshed"` and `"cost"` only (`"wildfire"` and `"tradeoff"` require risk data)
- Use `solve_opf(opt_parameters)` for DCOPF/LACOPF. Legacy `solve_ots` calls with OPF models still work with a warning.
- LACOPF can warm-start from DCOPF (`:warm_start => "auto"`)

### Nonlinear AC Verification / Recovery
- `verify_ac(ac_parameters, planning_results)` builds package-owned JuMP nonlinear AC models using polar AC power-flow equations
- `:mode => "ACPF"` performs strict replay feasibility: fixed topology, fixed allocation, and saved dispatch where available
- `:mode => "ACOPF"` performs AC redispatch/recovery with active/reactive load shedding, while keeping planning decisions fixed
- Planning outputs are treated as fixed data: `:z` / `:switched_off_lines`, `:allocated_load`, solar capacity `:s`, and battery capacity `:x`
- AC models do not create planning variables such as `z`, `y`, `x`, `s`, or `a`; they only create continuous operational AC variables
- Diagnostics are enabled by default and classify solver failures, voltage limit violations, thermal overloads, angle-limit violations, AC recovery load shedding, reactive generator limit binding, and islanding
- PowerIO is used for MATPOWER parsing; reference dictionaries and AC equations are package-owned

## Solution Methods

### Optimal Method (default)
- Solves a Mixed-Integer Programming (MIP) problem for line switching decisions
- Binary `z[d,l]` variables for each risky line switching decision
- If a `threshold` or `threshold_pct` is provided, adds a linear risk constraint: energized risk ≤ threshold × total_risk (hardening is credited toward the threshold)
- If no threshold is provided and the objective includes wildfire risk (e.g., `"wildfire"`, `"tradeoff"`), risk minimization is handled in the objective
- If hardening is enabled, binary `y[l]` variables are always added regardless of switching method
- **Pros**: Globally optimal switching decisions, optimality guarantees
- **Cons**: Slower solve times (seconds to minutes for large systems)

### Thresholded Method
- Fast heuristic that pre-determines switching decisions before solving
- Sorts risky lines by wildfire risk and de-energizes the riskiest ones to meet the specified threshold (`threshold` or `threshold_pct` required)
- Switching variables are fixed scalars; the remaining problem is solved as an LP (or MIP if hardening is enabled)
- If hardening is enabled, binary `y[l]` variables are still solved optimally within the LP/MIP
- **Pros**: 2-10x faster solve times for large-scale studies
- **Cons**: Switching decisions are suboptimal; threshold parameter is required
- **Use cases**: Large-scale studies, Monte Carlo analysis, initial screening

## Generator Ramping and Unit Commitment

Generator ramping and unit commitment are optional for `DCOTS`, `DCOPF`, `LACOTS`, and `LACOPF`; both are disabled by default.

**Generator ramping** adds symmetric active-power inter-hour ramp limits. The default ramp source is generator field `ramp_30` multiplied by `2.0`, so MATPOWER 30-minute ramp data is converted to an hourly limit. Missing or nonpositive ramp data falls back to generator `pmax`.

**Unit commitment** adds binary `u[d,t,g]`, `startup[d,t,g]`, and `shutdown[d,t,g]` variables. Active dispatch is coupled to effective `pmin`/`pmax` limits, and linear-AC models also force reactive dispatch off when a generator is off. Minimum up/down times are measured in modeled hours; defaults of `1` are nonrestrictive.

When ramping and unit commitment are both enabled, ramp limits are relaxed for startup and shutdown transitions using the commitment variables. Initial status defaults to on only for online generators with positive dispatch or positive `pmin`; otherwise it defaults to off. Initial dispatch defaults to case `pg`, then `(pmin + pmax) / 2`, then `0.0`, clamped to feasible bounds; if initial status is off, initial dispatch is `0.0`.

The Julia API accepts per-generator dictionaries for `:uc_min_up_time`, `:uc_min_down_time`, `:uc_initial_status`, `:uc_initial_dispatch`, and `:uc_no_load_cost`. The CLI supports scalar UC/ramping controls only.

For the `"cost"` objective only, unit commitment adds generator `startup` and `shutdown` costs when those fields are present, plus `:uc_no_load_cost` for each committed generator-hour.

This feature is covered in CI with HiGHS-based RTS smoke tests. It has also been manually validated with Gurobi on the following larger configurations:

- RTS `DCOPF`, `"cost"` objective, 3 modeled days, 24 hours per day, unit commitment plus ramping, `:uc_min_up_time => 2`, `:uc_min_down_time => 2`
- CATS `DCOPF`, `"loadshed"` objective, 1 modeled day, 24 hours, unit commitment plus ramping
- RTS single-day 24-hour edge cases: ramping-only `DCOPF`, UC-only `DCOPF`, UC+ramping `DCOPF` with all generators initially off, UC+ramping `LACOPF`, and UC+ramping `DCOTS`

## Objective Functions

| Objective | Description | Primary Term | Secondary Term | OPF-only models |
|-----------|-------------|--------------|----------------|-----------------|
| `"loadshed"` | Minimize load shedding | Total load shed | Small switching cost penalty | ✅ |
| `"wildfire"` | Minimize wildfire risk | Normalized active risk | Small load shedding penalty | ❌ (requires risk) |
| `"cost"` | Minimize operational cost | Generation cost + VOLL × load shed | N/A | ✅ |
| `"tradeoff"` | Weighted combination | (1-w) × normalized load shed | w × normalized risk | ❌ (requires risk) |

## Line Hardening

The package supports transmission line hardening as a wildfire risk mitigation strategy alongside operational switching decisions. The hardening decision represents a permanent physical intervention — vegetation management, covered conductors, or undergrounding — that reduces a line's wildfire risk contribution by a user-defined effectiveness factor. The default cost parameter (`$7M/mile`) reflects undergrounding; adjust `:hardening_cost_per_mile` to model other methods.

**Key Concepts:**
- **Decision variable y[l]**: Binary variable indicating whether line l is hardened (1) or not (0)
- **Risk mitigation**: Hardened lines have their wildfire risk reduced by an effectiveness factor (default: 100%)
- **Energization enforcement**: Hardened lines must remain energized (cannot be switched off)
- **Cost-based optimization**: Balances hardening cost against operational benefits

**Budget Handling:**
- **Non-cost objectives** (loadshed, wildfire, tradeoff): Budget is required (default: \$1B if not specified)
- **Cost objective**: Budget is optional (default: unlimited). Hardening cost appears in objective function.

**Thresholded Method with Hardening:**
When using the thresholded method with hardening enabled, switching and hardening decisions are decoupled:
- Switching decisions (`z`) are pre-computed by sorting lines by risk and de-energizing the riskiest ones to meet the threshold
- Hardening decisions (`y`) remain binary optimization variables solved optimally by the LP/MIP solver
- Hardenable lines that were thresholded off use `y[l]` as their effective energization variable in power flow constraints — a hardened line is re-energized with zero wildfire risk contribution
- The shared infrastructure budget is enforced as a linear constraint over the binary `y` variables (and any battery/solar variables)

**Objective Modifications:**
- **loadshed**: Adds small penalty for not hardening: `+ 0.01 * Σ(1-y[l])`
- **wildfire**: Risk from hardened lines is reduced: `risk[l] * (1 - effectiveness * y[l])`
- **cost**: Adds hardening cost: `+ Σ(cost_per_mile * length[l] * y[l])`
- **tradeoff**: Uses modified risk calculation from wildfire objective
