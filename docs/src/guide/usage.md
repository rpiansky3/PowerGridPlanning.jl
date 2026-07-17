# Usage Guide

## Basic API

The main function is `solve_ots(opt_parameters)` which takes a single dictionary and returns a results dictionary.

```julia
using PowerGridPlanning
results = solve_ots(opt_parameters)
```

## Required Parameters

```julia
opt_parameters = Dict(
    :network => "RTS",                    # Network name (see Available Data)
    :model => "DCOTS",                    # "DCOTS", "LACOTS", "DCOPF", or "LACOPF"
                                          #   DCOTS/LACOTS: wildfire-aware optimal transmission switching
                                          #   DCOPF/LACOPF: pure OPF (no wildfire switching);
                                          #                 investments still apply; objective restricted to "loadshed"/"cost"
    :objective => "tradeoff",             # "loadshed", "wildfire", "cost", "tradeoff" (DCOPF/LACOPF: "loadshed"/"cost" only)
    :times => [(2021, 7, 15)]             # Time specification (see below)
)
```

## User-Supplied Networks

Any MATPOWER `.m` case can be used instead of the pre-configured network names by
passing a file path via `:case_file`:

```julia
opt_parameters = Dict(
    :case_file => "path/to/my_case.m",    # absolute, or relative to the current directory
    :network   => "my_case",              # optional label for outputs (default: file basename)
    :model     => "DCOPF",
    :objective => "loadshed",
    :times     => [(2021, 7, 15)],
)
results = solve_ots(opt_parameters)
```

Loads default to the case's `Pd`/`Qd` scaled by the built-in synthetic hourly profile,
so a bare case file solves out of the box with `DCOPF`/`LACOPF`.

A bare MATPOWER case carries no geographic data, so features that correlate the grid
with external geodata cannot be auto-wired. Each degrades explicitly, at validation
time, with an error naming the parameter to supply:

| Feature | Requirement on a custom case |
|---|---|
| `DCOTS`/`LACOTS` switching | `:risk_per_line => Dict(day => Dict(line_id => risk))` — USGS FPI auto-load is unavailable. To build a risk file from geography, see `scripts/fetch_wfpi_data.jl` (needs bus coordinates). |
| Hardening | `:bus_coords` (line lengths computed via haversine) or `:line_lengths => Dict(line_id => miles)` |
| Plotting (`:plots`, `plot_results`) | `:bus_coords` |
| Solar siting | Works without geodata: flat `:solar_capacity_factor_default` (default 0.3), or per-bus profiles via `:solar_data_path` |
| Battery siting, load allocation | No geodata needed |
| AC verification (`verify_ac`) | Pass the same `:case_file` |

`:bus_coords` accepts a CSV path or a `DataFrame` with columns `Bus_ID`, `lat`, `lng`
(common aliases such as `bus_id`, `latitude`, `lon` are recognized). It also works for
named networks, overriding the bundled coordinate file.

```julia
# Wildfire-aware switching + hardening on a custom case
opt_parameters = Dict(
    :case_file         => "path/to/my_case.m",
    :model             => "DCOTS",
    :objective         => "loadshed",
    :times             => [(2021, 7, 15)],
    :risk_per_line     => Dict(1 => Dict(12 => 80.0, 47 => 55.0)),  # day => (line => risk)
    :hardening_enabled => true,
    :bus_coords        => "path/to/my_case_lat_lon.csv",
    :infrastructure_budget => 1e8,
)
```

## Optional Parameters

```julia
# Solution method
:switching_method => "optimal"    # "optimal" (MIP) or "thresholded" (heuristic)

# Wildfire data
:risk_per_line => nothing         # Custom risk data: Dict{Int => Dict{Int => Float64}}
                                   # day => (line_id => risk_value). Auto-loaded if not provided
:risk_metric => "cum_wfpi"        # For CATS: "max_wfpi", "mean_wfpi", "cum_wfpi"

# Temporal parameters
:T => 24                          # Hours per day (default: 24)

# Objective-specific parameters
:tradeoff_weight => 0.5           # For "tradeoff": 0=loadshed only, 1=wildfire only
:voll => 10000.0                  # Value of Lost Load ($/MWh) for "cost" objective

# Threshold parameters
# - Required for switching_method="thresholded" (determines which lines are pre-de-energized)
# - Optional for switching_method="optimal": adds a risk constraint (energized risk ≤ threshold × total_risk)
#   Hardening is credited toward the constraint (hardened lines reduce active risk)
:threshold => nothing             # Absolute risk threshold (in risk units)
:threshold_pct => nothing         # Percentage threshold (0.8 = keep 80% of risk active, remove 20%)

# Linear-AC warm start (LACOTS / LACOPF)
:warm_start => nothing            # Dict from DCOTS/DCOPF results, or "auto" to run the DC counterpart first
:non_linear => false              # Use non-linear apparent power constraints

# Solver parameters
:optimizer => nothing             # JuMP optimizer constructor (default: Gurobi.Optimizer)
                                  # Any JuMP-compatible MIP solver works, e.g. HiGHS.Optimizer
                                  # (open source, no license). Gurobi-specific tuning
                                  # (:log_str, MIPFocus/Method) applies only with Gurobi.
:time_limit => 86400.0            # Solver time limit (seconds, default: 24 hours)
:mip_gap => 0.01                  # MIP optimality gap (default: 1%)

# Output parameters
:output_format => "dict"          # "dict", "jld2", or "txt"
:output_path => nothing           # File path (required for jld2/txt formats)
:lp_str => ""                     # If provided, save model to LP file at this path
:log_str => ""                    # If provided, save Gurobi log to file at this path

# Auto-plotting (triggered at end of solve_ots)
:plots    => false,               # false/"none" = no plots; "all" = network_overview + timeseries;
                                  # "inv_only" = network_overview only; "timeseries_only" = timeseries only
:plot_dir => ""                   # Directory to save plots (default: current directory)
                                  # Created automatically if it does not exist

# Hardening parameters (models vegetation management, covered conductors, or undergrounding)
:hardening_enabled => false                # Enable line hardening optimization
:hardening_effectiveness => 1.0            # Risk reduction factor, 0-1 (1.0 = full mitigation)
:hardening_cost_per_mile => 7e6            # Cost per mile in USD (default: $7M)
:hardening_enforce_energization => true    # If hardened, must remain energized
:hardening_candidate_lines => nothing      # Vector{Int}: specific lines to consider (default: all risky lines)

# Battery energy storage system (BESS) parameters
:battery_enabled => false                  # Enable battery installation optimization
:battery_cost_per_pu => 1e8                # Cost per p.u. (100MWh) of battery capacity ($)
:battery_charge_efficiency => 0.95         # Charging efficiency (0-1)
:battery_discharge_efficiency => 0.95      # Discharging efficiency (0-1)
:battery_soc_carryover => 0.999958         # SOC decay between hours (~1%/week)
:battery_charge_rate => 1.0                # Max charge rate as fraction of capacity (p.u./hour)
:battery_discharge_rate => 1.0             # Max discharge rate as fraction of capacity (p.u./hour)
:battery_max_network => nothing            # Network-wide capacity limit (p.u., default: unlimited)
:battery_max_per_node => nothing           # Per-node capacity limit (p.u., default: 10000)
:battery_exclusive_operation => false      # Limit simultaneous charge/discharge
:battery_candidate_buses => nothing        # Vector{Int}, "load buses", or nothing (all buses)
:linearized_battery_power => true          # For LACOTS: linear (true) or nonlinear (false) reactive power

# Solar PV installation parameters
:solar_enabled => false                    # Enable solar installation optimization
:solar_cost_per_pu => 1e8                  # Cost per p.u. (100MW) of solar capacity ($)
:solar_data_path => nothing                # Path to CSV with hourly capacity factors
:solar_capacity_factor_default => 0.3      # Default CF if no data provided (0-1)
:solar_max_network => nothing              # Network-wide capacity limit (p.u., default: unlimited)
:solar_max_per_node => nothing             # Per-node capacity limit (p.u., default: 10000)
:solar_candidate_buses => nothing          # Vector{Int} or nothing (all buses)
:linearized_solar_power => true            # For LACOTS: linear (true) or nonlinear (false) inverter capability

# Shared infrastructure budget (batteries + solar + hardening)
:infrastructure_budget => nothing          # Budget in USD (default: $1B for non-cost objectives, unlimited for cost)
```

## AC Verification API

Use `verify_ac` after a planning solve when you want to check the fixed planning decisions in a nonlinear AC model. Baseline runs are also supported by omitting the planning results argument.

```julia
using PowerGridPlanning

# Baseline AC redispatch with no wildfire switching or new infrastructure
baseline_ac = verify_ac(Dict(
    :network  => "RTS",
    :mode     => "ACOPF",          # "ACPF" or "ACOPF"
    :times    => [(2020, 6, 15)],
    :T        => 1,
    :data_dir => "test_data",
))

# Verify an existing DCOTS/LACOTS planning result under nonlinear AC equations
planning_results = solve_ots(Dict(
    :network          => "RTS",
    :model            => "DCOTS",
    :objective        => "loadshed",
    :times            => [(2020, 6, 15)],
    :data_dir         => "test_data",
    :switching_method => "thresholded",
    :threshold_pct    => 0.75,
))

ac_check = verify_ac(Dict(
    :network  => "RTS",
    :mode     => "ACOPF",
    :times    => [(2020, 6, 15)],
    :T        => 1,
    :data_dir => "test_data",
), planning_results)

println("AC feasible all hours: $(ac_check[:feasible_all])")
println("Failed hours: $(ac_check[:failed_hours])")
println("AC recovery load shed: $(ac_check[:total_p_load_shed])")
```

Required `ac_parameters` keys:
- `:network` - Network name
- `:times` - Same time formats accepted by `solve_ots`
- `:mode` - `"ACPF"` for strict replay feasibility or `"ACOPF"` for AC redispatch/recovery

Optional AC parameters:
- `:T => 24`
- `:data_dir => "data"`
- `:optimizer => Ipopt.Optimizer`
- `:output_format => "dict"` (`"jld2"` and `"txt"` are also supported)
- `:output_path => nothing` (required for `"jld2"` or `"txt"`)
- `:load_shed_penalty => 1e6`
- `:silent => true`

## Time Specification Formats

```julia
# Single day
:times => [(2021, 7, 15)]

# Multiple specific days
:times => [(2021, 7, 15), (2021, 7, 16), (2021, 7, 17)]

# Full year (all 365/366 days)
:times => "2020"

# Full month
:times => "June 2021"
:times => "Jun 2021"
```

The number of days `D` is automatically calculated, resulting in `D × T` time periods.
