# Plotting

```julia
plot_results(results_input, features::Vector{Symbol};
             format::String="pdf",
             output_dir::String=".",
             day::Union{Nothing,Int}=nothing,
             infrastructure_off::Bool=false,
             ls_off::Bool=false,
             plot_dir::String="",
             kwargs...)
```

**Arguments:**
- `results_input`: Dict from `solve_ots()`, String path to `.jld2`, or `Vector{Dict}` for `:tradeoff_curve`
- `features`: vector of plot symbols to generate (see below)
- `format`: output format — `"pdf"` (default), `"png"`, `"svg"`, `"eps"`
- `output_dir`: directory to write output files
- `plot_dir`: alias for `output_dir`; takes precedence over `output_dir` if non-empty
- `day`: `nothing` (aggregate) or `Int` (day-specific) for the network overview
- `infrastructure_off`: suppress hardened line overlays, battery markers, and solar markers on the network overview
- `ls_off`: suppress load shed bubbles on the network overview
- `census_overlay`: `nothing` (default) or a `Symbol` (`:median_income`, `:pct_poverty`, `:pct_nonwhite`) — color each load bus on `:network_overview` by the metric; requires `data/census_data/{Network}_census_{Year}.csv`. See [Census Demographic Data](../guide/data.md#Census-Demographic-Data).

**Feature symbols:**

| Symbol | Description |
|--------|-------------|
| `:network_overview` | Geographic plot: risk-colored lines, de-energized lines, hardened lines, battery/solar markers, load shed bubbles |
| `:load_shed_timeseries` | Time series of load shedding across all periods |
| `:battery_dispatch` | Per-bus battery charge/discharge/SOC dispatch |
| `:solar_generation` | Per-bus solar active (and reactive, LACOTS) generation |
| `:generation_dispatch` | Generator dispatch over time |
| `:tradeoff_curve` | Load shed vs. risk tradeoff curve (requires `Vector{Dict}` input) |
| `:cost_breakdown` | Bar chart of cost components |

**Examples:**

```julia
# Full network overview with all layers
plot_results(results, [:network_overview, :battery_dispatch]; format="pdf", output_dir="figures/")

# Network overview without infrastructure or load shed overlays
plot_results(results, [:network_overview]; infrastructure_off=true, ls_off=true, output_dir="figures/")

# Load results from file and plot
plot_results("run.jld2", [:load_shed_timeseries, :solar_generation]; output_dir="figures/")

# Tradeoff curve from multiple solves
results_list = [solve_ots(merge(p, Dict(:tradeoff_weight => w))) for w in 0:0.1:1]
plot_results(results_list, [:tradeoff_curve]; format="pdf", output_dir="figures/")
```
