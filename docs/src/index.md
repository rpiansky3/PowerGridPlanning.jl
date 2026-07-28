# PowerGridPlanning.jl

A Julia package for transmission grid planning on realistic power system networks. Provides DC and linearized AC formulations for co-optimizing line switching, line hardening, battery storage siting, and solar PV siting against load shedding, cost, and risk-exposure objectives, plus nonlinear AC verification/recovery runs for checking planned decisions. Applications include planning under severe-weather risk such as wildfires, with built-in support for USGS Fire Potential Index data.

## Overview

This package provides a unified interface for transmission grid planning problems on realistic power system networks. Operational decisions (line switching) and capital investments (line hardening, battery storage siting, solar PV siting) are co-optimized under a single objective — load shedding, generation cost, risk exposure, or a weighted tradeoff. The per-line risk interface is hazard-agnostic; the package ships with built-in data loaders for severe-weather risk applications, currently wildfire risk via the USGS Fire Potential Index.

**Key Features:**
- **Four formulations**: wildfire-aware switching (DCOTS, LACOTS) and pure power-flow baselines (DCOPF, LACOPF) sharing the same investment-planning interface
- **Nonlinear AC verification with diagnostics**: Replay fixed planning decisions with AC power flow (`ACPF`) or run AC redispatch/recovery with load shedding (`ACOPF`), including voltage, thermal, islanding, and recovery-stress diagnostics
- **Multiple objective functions**: Load shedding minimization, risk-exposure minimization, generation cost minimization, and customizable tradeoffs
- **Two switching methods**: Optimal MIP-based and fast thresholded heuristic
- **Line hardening**: Optimize infrastructure investments (vegetation management, covered conductors, or undergrounding) to permanently reduce per-line risk exposure
- **Battery energy storage systems (BESS)**: Optimize battery installation and operation for load shedding mitigation
- **Solar PV installation**: Optimize solar capacity placement with hourly capacity factors and inverter reactive power support (LACOTS)
- **Hazard-agnostic risk interface**: Accept any per-line risk signal; built-in loader for USGS Fire Potential Index (wildfire) included
- **Multi-period optimization**: Solve for single days, specific date ranges, or entire months/years
- **Flexible network support**: Pre-configured for 6+ realistic power system test cases (RTS-GMLC, CATS, Texas7k, ACTIVSg2000/10k, WECC240), or bring any MATPOWER case via `:case_file` (see the [Usage Guide](guide/usage.md#User-Supplied-Networks))

## Installation

### Prerequisites
- Julia 1.10 or higher (LTS; 1.6+ is technically compatible but 1.10 is recommended)
- Gurobi optimizer with valid license for planning solves (`solve_ots`; [academic licenses available](https://www.gurobi.com/academia/academic-program-and-licenses/))
- Ipopt is included as the default nonlinear solver for AC verification (`verify_ac`)

### Setup

**Option A — install from the Julia General registry (recommended):**
```julia
using Pkg
Pkg.add("PowerGridPlanning")
using PowerGridPlanning
```

To track the latest development version on `main` instead of the registered release:
```julia
Pkg.add(url="https://github.com/rpiansky3/PowerGridPlanning.jl")
```

**Option B — clone and develop locally:**

1. Clone this repository:
```bash
git clone https://github.com/rpiansky3/PowerGridPlanning.jl.git
cd PowerGridPlanning.jl
```

2. Instantiate the package environment:
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

3. Test the installation:
```julia
julia --project=. -e 'using PowerGridPlanning; println("OK")'
```

## Quick Start

The repository ships with a reference dataset in `test_data/` covering June 2020 for all six networks. Use `:data_dir => "test_data"` to run immediately after cloning — no additional data download required.

```julia
using PowerGridPlanning

# Works out of the box using the included test_data/ reference dataset
opt_parameters = Dict(
    :network   => "RTS",
    :model     => "DCOTS",
    :objective => "loadshed",
    :times     => [(2020, 6, 15)],   # June 15, 2020 — available for all 6 networks
    :data_dir  => "test_data"
)

results = solve_ots(opt_parameters)

println("Solve time: $(results[:solve_time]) seconds")
println("Total load shed: $(results[:total_load_shed]) MW")
println("Risk reduction: $(results[:risk_reduction_pct])%")
println("Lines switched off: $(length(results[:switched_off_lines][1]))")
```

To verify all six networks load and solve correctly:

```bash
julia --project=. scripts/verify_reference_data.jl
```

!!! note
    `test_data/` covers June 2020 (June 15–16 for CATS; June 4–30 for RTS; full June for all others). For other dates or the full dataset, omit `:data_dir` (defaults to `"data/"`) and download wildfire risk data via `scripts/fetch_wfpi_data.jl`.

## Tutorial

A Jupyter notebook walkthrough is included at [`tutorial.ipynb`](https://github.com/rpiansky3/PowerGridPlanning.jl/blob/main/tutorial.ipynb). It covers the core API end-to-end on the RTS network — basic solve, switching methods, hardening, battery and solar siting, nonlinear AC verification/recovery, the tradeoff curve, and plotting — using only the bundled `test_data/` so it runs out of the box after `Pkg.instantiate()` and a Gurobi license.

```bash
julia --project=. -e 'using IJulia; notebook(dir=".")'
```

Then open `tutorial.ipynb` from the Jupyter file browser.

## Where to go next

- [Models and Methods](guide/models.md) — the DCOTS/LACOTS/DCOPF/LACOPF formulations, switching methods, objectives, and hardening
- [Data](guide/data.md) — bundled reference data, supported networks, and the solar/census/wildfire data pipelines
- [Usage Guide](guide/usage.md) — every `solve_ots`, `solve_opf`, and `verify_ac` parameter
- [Command-Line Interface](guide/cli.md) — running studies from the terminal
- [Examples](guide/examples.md) — 17 worked examples
- [Results Dictionary](reference/results.md) — every key in the results
- [Plotting](reference/plotting.md) — geographic overviews, dispatch time series, and tradeoff curves
- [API Reference](reference/api.md) — docstrings for the public API

## Citation

If you use this package in your research, please cite:

```bibtex
@software{PowerGridPlanning_jl,
  author = {Piansky, Ryan},
  title = {PowerGridPlanning.jl: Transmission Grid Planning with Co-Optimized Switching, Hardening, and Storage},
  year = {2026},
  version = {0.2.0},
  url = {https://github.com/rpiansky3/PowerGridPlanning.jl}
}
```

## License

This package is released under the [MIT License](https://github.com/rpiansky3/PowerGridPlanning.jl/blob/main/LICENSE).
