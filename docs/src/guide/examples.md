# Examples

## Example 1: Basic DCOTS with Tradeoff Objective

```julia
using PowerGridPlanning

opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "tradeoff",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :tradeoff_weight => 0.7,  # Prioritize wildfire risk reduction
    :time_limit => 300.0
)

results = solve_ots(opt_parameters)

# Access results
println("Optimized in $(results[:solve_time]) seconds")
println("$(results[:risk_reduction_pct])% of wildfire risk removed")
println("$(results[:total_load_shed]) MW of load shed")
```

## Example 2: LACOTS with DCOTS Warm Start

```julia
# Automatically runs DCOTS first, then uses solution to warm-start LACOTS
opt_parameters = Dict(
    :network => "RTS",
    :model => "LACOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :warm_start => "auto"
)

results = solve_ots(opt_parameters)
```

## Example 2b: Pure DCOPF Baseline (no wildfire switching)

```julia
# Use DCOPF when you want a true no-action baseline — lines never get
# de-energized for risk mitigation, even under a "cost" or "loadshed" objective.
opt_parameters = Dict(
    :network   => "RTS",
    :model     => "DCOPF",          # pure DC OPF; no z switching variables
    :objective => "cost",           # generation cost + VOLL × load shed
    :times     => [(2020, 6, 15)],
    :data_dir  => "test_data",
)

results = solve_ots(opt_parameters)

# DCOPF results have no switching: results[:switched_off_lines][d] is empty
# and risk_reduction_pct is 0. Investment options (battery, solar, hardening)
# can still be enabled in the same Dict.
```

## Example 2c: Nonlinear AC Verification and Recovery

```julia
# First solve a planning model
planning_results = solve_ots(Dict(
    :network          => "RTS",
    :model            => "DCOTS",
    :objective        => "loadshed",
    :times            => [(2020, 6, 15)],
    :data_dir         => "test_data",
    :switching_method => "thresholded",
    :threshold_pct    => 0.75,
))

# Then replay those fixed planning decisions in a nonlinear AC recovery model
ac_results = verify_ac(Dict(
    :network  => "RTS",
    :mode     => "ACOPF",        # redispatch + load shedding recovery
    :times    => [(2020, 6, 15)],
    :T        => 1,              # keep examples quick; default is 24
    :data_dir => "test_data",
), planning_results)

println("AC feasible all hours: $(ac_results[:feasible_all])")
println("AC failed hours: $(ac_results[:failed_hours])")
println("AC active load shed: $(ac_results[:total_p_load_shed])")
```

## Example 3: Fast Thresholded Method

```julia
# Remove 50% of wildfire risk using fast heuristic
opt_parameters = Dict(
    :network => "Texas7k",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 11), (2020, 6, 12), (2020, 6, 13)],
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.5,  # De-energize lines to remove 50% of risk
    :time_limit => 300.0
)

results = solve_ots(opt_parameters)

# Compare performance vs optimal method
println("Thresholded solve time: $(results[:solve_time])s")
println("Load shed: $(results[:total_load_shed]) MW")
```

## Example 4: Multi-Period Optimization

```julia
# Optimize for entire month
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "wildfire",
    :times => "June 2020",  # All days in June
    :data_dir => "test_data",
    :T => 24,
    :mip_gap => 0.02
)

results = solve_ots(opt_parameters)

# Analyze daily switching patterns
for (day_idx, lines) in results[:switched_off_lines]
    println("Day $day_idx: $(length(lines)) lines de-energized")
end
```

## Example 5: CATS Network with Custom Risk Metric

```julia
opt_parameters = Dict(
    :network => "CATS",
    :model => "DCOTS",
    :objective => "tradeoff",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :risk_metric => "max_wfpi",  # Use maximum WFPI instead of cumulative
    :tradeoff_weight => 0.6
)

results = solve_ots(opt_parameters)
```

## Example 6: Cost Minimization

```julia
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "cost",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :voll => 10000.0,  # $10,000/MWh value of lost load
    :threshold_pct => 0.3  # Still enforce some risk reduction
)

results = solve_ots(opt_parameters)

println("Total cost: \$$(results[:objective_value])")
```

## Example 7: Save Results to File

```julia
# Save results as JLD2 file
opt_parameters = Dict(
    :network => "Texas2k",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => "June 2020",
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.4,
    :output_format => "jld2",
    :output_path => "results/texas2k_june2020_results.jld2"
)

results = solve_ots(opt_parameters)

# Load results later
using JLD2
loaded_results = load("results/texas2k_june2020_results.jld2")
```

## Example 8: Export Model and Solver Logs

```julia
# Save the optimization model formulation and Gurobi solver log
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "tradeoff",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :tradeoff_weight => 0.5,
    :lp_str => "models/rts_dcots_tradeoff.lp",  # Save model to LP file
    :log_str => "logs/rts_dcots_solve.log"      # Save Gurobi log to file
)

results = solve_ots(opt_parameters)

# The LP file contains the full model formulation:
# - Decision variables, objective function, all constraints
# The log file contains Gurobi's detailed solver output:
# - Presolve reductions, barrier/simplex iterations, MIP progress
# - Useful for debugging, performance analysis, and verification
```

## Example 9: Comparison Study

```julia
# Compare optimal vs thresholded methods
function compare_methods(network, date, threshold_pct)
    # Optimal method
    opt_params_optimal = Dict(
        :network => network,
        :model => "DCOTS",
        :objective => "loadshed",
        :times => [date],
        :data_dir => "test_data",
        :switching_method => "optimal",
        :threshold_pct => threshold_pct
    )
    results_optimal = solve_ots(opt_params_optimal)

    # Thresholded method
    opt_params_threshold = Dict(
        :network => network,
        :model => "DCOTS",
        :objective => "loadshed",
        :times => [date],
        :data_dir => "test_data",
        :switching_method => "thresholded",
        :threshold_pct => threshold_pct
    )
    results_threshold = solve_ots(opt_params_threshold)

    # Compare
    println("\nComparison for $network on $date:")
    println("Optimal    - Time: $(results_optimal[:solve_time])s, Load shed: $(results_optimal[:total_load_shed]) MW")
    println("Thresholded - Time: $(results_threshold[:solve_time])s, Load shed: $(results_threshold[:total_load_shed]) MW")
    println("Speedup: $(results_optimal[:solve_time] / results_threshold[:solve_time])x")
    println("Load shed increase: $(results_threshold[:total_load_shed] - results_optimal[:total_load_shed]) MW")
end

compare_methods("RTS", (2020, 6, 15), 0.5)
```

## Example 10: Line Hardening with Loadshed Objective

```julia
# Optimize line hardening to reduce wildfire risk while minimizing load shedding
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :hardening_enabled => true,
    :infrastructure_budget => 50e6,  # $50M shared budget
    :hardening_cost_per_mile => 7e6,  # $7M per mile
    :hardening_effectiveness => 1.0,  # 100% risk mitigation
    :hardening_enforce_energization => true
)

results = solve_ots(opt_parameters)

# Analyze hardening results
println("Lines hardened: $(length(results[:hardened_lines]))")
println("Hardening cost: \$$(results[:hardening_cost]/1e6)M")
println("Risk mitigated by hardening: $(results[:mitigated_risk])")
println("Remaining active risk: $(results[:active_risk])")
println("Total risk reduction: $(results[:risk_reduction_pct])%")

# View which lines were hardened
for line_id in results[:hardened_lines]
    println("  Line $line_id: hardened (y=$( results[:y][line_id]))")
end
```

## Example 11: Cost Minimization with Hardening

```julia
# Optimize hardening and operations together to minimize total cost
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "cost",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :voll => 10000.0,
    :hardening_enabled => true,
    :hardening_cost_per_mile => 7e6
    # No budget limit - optimizer decides based on cost-benefit analysis
)

results = solve_ots(opt_parameters)

println("Total cost: \$$(results[:objective_value])")
println("Hardening cost: \$$(results[:hardening_cost]/1e6)M")
println("Generation + load shed cost: \$$(results[:objective_value] - results[:hardening_cost])")
```

## Example 12: Thresholded Switching with Optimal Hardening

```julia
# Switching decisions pre-computed (thresholded), hardening solved optimally (MIP)
# Hardenable lines that were thresholded off can be re-energized by hardening them
opt_parameters = Dict(
    :network => "Texas7k",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 11), (2020, 6, 12)],
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.5,  # Pre-de-energize top-50%-risk lines
    :hardening_enabled => true,
    :infrastructure_budget => 100e6,  # $100M shared budget
    :hardening_effectiveness => 0.9   # 90% risk reduction when hardened
)

results = solve_ots(opt_parameters)

# Compare hardening vs switching for risk mitigation
println("Risk mitigated by hardening: $(results[:mitigated_risk])")
println("Risk removed by switching: $(results[:removed_risk])")
println("Total risk reduction: $(results[:risk_reduction_pct])%")
println("Solve time: $(results[:solve_time])s")
```

## Example 13: Battery Installation on CATS Network

```julia
# Install batteries on the California Test System during a high wildfire risk day
# Verified result: 29 buses, ~1517 MWh installed, $303M cost, 0 MW load shed
opt_parameters = Dict(
    :network => "CATS",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 21)],
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.75,          # De-energize lines to remove 75% of risk
    :battery_enabled => true,
    :battery_cost_per_pu => 2e7,     # $20M per 100 MWh
    :infrastructure_budget => 500e6, # $500M shared budget
    :time_limit => 3600.0
)

results = solve_ots(opt_parameters)

# Confirm batteries were installed
println("Buses with batteries: $(length(results[:batteries_installed]))")
println("Total capacity: $(round(results[:total_battery_capacity]*100, digits=1)) MWh")
println("Battery cost: \$$(round(results[:battery_cost]/1e6, digits=1))M")
println("Load shed: $(results[:total_load_shed]) MW")

# Inspect 24-hour dispatch for a specific bus
bus = results[:batteries_installed][1]
capacity = results[:x][bus]
println("\nDispatch at bus $bus ($(round(capacity*100, digits=1)) MWh):")
println("Hour | Charge (p.u.) | Discharge (p.u.) | SOC (%)")
for t in 1:24
    charge    = results[:p_charge][(1, t, bus)]
    discharge = results[:p_discharge][(1, t, bus)]
    soc_pct   = 100 * results[:soc][(1, t, bus)] / capacity
    println("  $t  |   $(round(charge, digits=4))   |   $(round(discharge, digits=4))   |  $(round(soc_pct, digits=1))%")
end
```

**Notes on this example:**
- CATS is a large network (8,870 buses, 10,823 lines) — expect ~4 minute solve time
- On a single high-risk day, batteries start fully charged and purely discharge to cover load shed from de-energized lines (no charging needed within the day)
- The `time_limit` of 3600s is recommended for CATS; smaller networks solve much faster

## Example 14: Custom Wildfire Risk Data

You can bypass automatic data loading by providing your own wildfire risk data via the `:risk_per_line` parameter. This is useful for custom risk models, sensitivity analysis, or external data sources.

```julia
using PowerGridPlanning

# Define custom risk: Dict{day_index => Dict{line_id => risk_value}}
custom_risk = Dict{Int, Dict{Int, Float64}}(
    1 => Dict(5 => 0.8, 12 => 1.2, 23 => 0.5, 45 => 0.9),  # Day 1
    2 => Dict(5 => 0.9, 12 => 1.1, 23 => 0.4),              # Day 2
    3 => Dict(8 => 0.7, 23 => 0.6, 45 => 1.0)               # Day 3
)

opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "tradeoff",
    :times => [(2020, 6, 15), (2020, 6, 16), (2020, 6, 17)],
    :data_dir => "test_data",
    :risk_per_line => custom_risk,
    :tradeoff_weight => 0.5
)

results = solve_ots(opt_parameters)

# Output includes validation:
# ✓ risk_per_line validation passed:
#   - 3 days of data
#   - 11 total line-day risk entries
#   - Min/Max risky lines per day: 3/4
# ✓ Using user-provided risk_per_line data

println("Active risk: $(results[:active_risk])")
println("Risk reduction: $(results[:risk_reduction_pct])%")
```

**Notes:**
- The outer key is the day index (1 to D), matching the order of `:times`
- The inner dict maps line IDs to risk values — only lines with nonzero risk need entries
- The package validates the structure and reports statistics when custom data is provided

## Example 15: Combined Infrastructure Optimization

Jointly optimize solar PV, battery storage, and line hardening under a shared infrastructure budget.

```julia
using PowerGridPlanning

opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.75,
    # Solar
    :solar_enabled => true,
    :solar_cost_per_pu => 5e7,                                        # $50M per 100 MW
    :solar_data_path => "test_data/solar_data/RTS/solar_data.csv",
    # Battery
    :battery_enabled => true,
    :battery_cost_per_pu => 2e7,     # $20M per 100 MWh
    # Hardening
    :hardening_enabled => true,
    :hardening_cost_per_mile => 7e6,
    # Shared budget for all three
    :infrastructure_budget => 500e6  # $500M
)

results = solve_ots(opt_parameters)

# The optimizer allocates the shared budget across all three investments
println("Solar:     \$$(round(results[:solar_cost]/1e6, digits=1))M — $(length(results[:solar_installed])) buses")
println("Batteries: \$$(round(results[:battery_cost]/1e6, digits=1))M — $(length(results[:batteries_installed])) buses")
println("Hardening: \$$(round(results[:hardening_cost]/1e6, digits=1))M — $(length(results[:hardened_lines])) lines")
total_infra = results[:solar_cost] + results[:battery_cost] + results[:hardening_cost]
println("Total:     \$$(round(total_infra/1e6, digits=1))M / \$500M budget")
println("Load shed: $(results[:total_load_shed]) MW")
```

## Example 16: Auto-Plotting via opt_parameters

Trigger plotting automatically at the end of `solve_ots()` using the `:plots` and `:plot_dir` parameters, without calling `plot_results()` separately.

```julia
using PowerGridPlanning

# "all" generates network_overview + relevant timeseries plots
opt_parameters = Dict(
    :network => "RTS",
    :model => "DCOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :battery_enabled => true,
    :battery_cost_per_pu => 2e7,
    :infrastructure_budget => 500e6,
    :plots => "all",                    # Auto-plot after solve
    :plot_dir => "figures/rts_run1"     # Directory created automatically if needed
)

results = solve_ots(opt_parameters)
# Plots saved to figures/rts_run1/ automatically

# Other :plots options:
#   false or "none"       — no plots (default)
#   "all"                 — network_overview + all applicable timeseries
#   "inv_only"            — network_overview only
#   "timeseries_only"     — timeseries plots only (load_shed, battery_dispatch, etc.)
```

## Example 17: Solar PV Installation with Reactive Power Support

Solar PV installation planning with real solar irradiance data and inverter reactive power capability in the LACOTS model.

```julia
using PowerGridPlanning

# LACOTS solar with reactive power support
opt_parameters = Dict(
    :network => "RTS",
    :model => "LACOTS",
    :objective => "loadshed",
    :times => [(2020, 6, 15)],
    :data_dir => "test_data",
    :switching_method => "thresholded",
    :threshold_pct => 0.75,
    :solar_enabled => true,
    :solar_cost_per_pu => 5e7,                                       # $50M per 100 MW
    :solar_data_path => "test_data/solar_data/RTS/solar_data.csv",   # Hourly capacity factors
    :infrastructure_budget => 500e6,
    :linearized_solar_power => true    # Rectangular inverter capability: |Q| ≤ cf × S
    # Alternative: linearized_solar_power => false  for circular: P² + Q² ≤ S²
)

results = solve_ots(opt_parameters)

println("Solar installed: $(length(results[:solar_installed])) buses")
println("Total capacity: $(round(results[:total_solar_capacity]*100, digits=1)) MW")
println("Total P generation: $(round(results[:total_solar_generation], digits=2)) p.u.·h")
println("Total Q injection: $(round(results[:total_solar_q_injection], digits=2)) p.u.·h")
println("Solar cost: \$$(round(results[:solar_cost]/1e6, digits=1))M")

# Show hourly dispatch for an installed bus
bus = results[:solar_installed][1]
cap = results[:s][bus]
println("\nBus $bus ($(round(cap*100, digits=1)) MW) hourly P/Q:")
for t in 1:24
    p = round(results[:p_solar][(1, t, bus)], digits=4)
    q = round(results[:q_solar][(1, t, bus)], digits=4)
    println("  Hour $t: P=$p, Q=$q")
end
```

**Notes on this example:**
- Solar capacity factors are loaded from CSV with columns `Bus_ID, Hour, AC_Output_pu, DC_Output_pu`
- AC output (post-inverter) is used as the capacity factor — the correct value for grid-side modeling
- `q_solar` is bidirectional: positive = injection (capacitive), negative = absorption (inductive)
- At night (cf=0), `q_solar` is forced to zero (inverter offline)
- The linearized mode bounds Q by `cf × s[n]`, while nonlinear allows Q up to `s[n]` when P is low
