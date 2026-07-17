# PowerGridPlanning.jl

[![CI](https://github.com/rpiansky3/PowerGridPlanning.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/rpiansky3/PowerGridPlanning.jl/actions/workflows/ci.yml)
[![Stable docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/)
[![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://rpiansky3.github.io/PowerGridPlanning.jl/dev/)

A Julia package for transmission grid planning on realistic power system networks. Provides DC and linearized AC formulations for co-optimizing line switching, line hardening, battery storage siting, and solar PV siting against load shedding, cost, and risk-exposure objectives, plus nonlinear AC verification/recovery runs for checking planned decisions. Applications include planning under severe-weather risk such as wildfires, with built-in support for USGS Fire Potential Index data.

**Key Features:**
- **Four formulations**: wildfire-aware switching (DCOTS, LACOTS) and pure power-flow baselines (DCOPF, LACOPF) sharing the same investment-planning interface
- **Nonlinear AC verification**: Replay fixed planning decisions with AC power flow (`ACPF`) or run AC redispatch/recovery with load shedding (`ACOPF`)
- **Investment planning**: Line hardening, battery energy storage (BESS), and solar PV siting under a shared infrastructure budget
- **Multiple objectives**: Load shedding, risk exposure, generation cost, or a weighted tradeoff
- **Two switching methods**: Optimal MIP-based and fast thresholded heuristic
- **Hazard-agnostic risk interface**: Accept any per-line risk signal; built-in loader for USGS Fire Potential Index (wildfire) included
- **Multi-period optimization**: Single days, date ranges, or entire months/years
- **Flexible network support**: Pre-configured for 6+ realistic test cases (RTS-GMLC, CATS, Texas7k, ACTIVSg2000/10k, WECC240), or bring any MATPOWER case via `:case_file` with explicit hooks for supplying risk and coordinate data

## Documentation

Full documentation lives at **[rpiansky3.github.io/PowerGridPlanning.jl](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/)**:

- [Models and Methods](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/guide/models/) — formulations, switching methods, objectives, hardening
- [Data](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/guide/data/) — bundled reference data, supported networks, solar/census/wildfire pipelines
- [Usage Guide](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/guide/usage/) — every `solve_ots` and `verify_ac` parameter
- [Command-Line Interface](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/guide/cli/) — running studies from the terminal
- [Examples](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/guide/examples/) — 17 worked examples
- [Results Dictionary](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/reference/results/) and [Plotting](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/reference/plotting/)
- [API Reference](https://rpiansky3.github.io/PowerGridPlanning.jl/stable/reference/api/)

## Installation

Requires Julia 1.10+. Planning solves default to Gurobi ([academic licenses available](https://www.gurobi.com/academia/academic-program-and-licenses/)), but any JuMP-compatible MIP solver can be supplied via the `:optimizer` parameter — e.g. the open-source [HiGHS](https://github.com/jump-dev/HiGHS.jl) (`:optimizer => HiGHS.Optimizer`). Ipopt, included, handles AC verification.

```julia
using Pkg
Pkg.add("PowerGridPlanning")
```

To track the latest development version on `main` instead of the registered release:
```julia
Pkg.add(url="https://github.com/rpiansky3/PowerGridPlanning.jl")
```

## Quick Start

The repository ships with a reference dataset in `test_data/` covering June 2020 for all six networks. Use `:data_dir => "test_data"` to run immediately after cloning — no additional data download required.

```julia
using PowerGridPlanning

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

A Jupyter notebook walkthrough covering the full API is included at [`tutorial.ipynb`](tutorial.ipynb).

## Testing

```bash
julia --project=. test/runtests.jl                       # CI suite — no Gurobi license required
julia --project=. test/runtests_full.jl                  # Full suite — requires Gurobi license
PGP_LIVE_TESTS=1 julia --project=. test/runtests.jl      # Opt-in: adds live Census API test
```

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

This package is released under the [MIT License](LICENSE).

## Contact

For questions, bug reports, or feature requests, please open an issue on the [GitHub repository](https://github.com/rpiansky3/PowerGridPlanning.jl/issues).

## Acknowledgments

This package builds upon optimal transmission switching formulations for wildfire risk mitigation, incorporating both DC and linearized AC power flow models.
