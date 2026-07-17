# Data

## Repository Structure

```
PowerGridPlanning.jl/
├── src/
│   ├── PowerGridPlanning.jl             # Main module and solve_ots() function
│   ├── preprocessing.jl            # Time parsing, data loading, load generation
│   ├── add_variables.jl            # Variable definitions for DCOTS/LACOTS (and DCOPF/LACOPF)
│   ├── add_constraints.jl          # Power flow and operational constraints
│   ├── add_objective.jl            # Objective function formulations
│   ├── base_OPS.jl                 # Core optimization solver
│   ├── ac_verification.jl          # Nonlinear AC verification/recovery models
│   ├── save_results.jl             # Output formatting and serialization
│   ├── plotting.jl                 # plot_results() and all plot generation
│   ├── plotting_helpers.jl         # Shared plotting utilities and color maps
│   ├── solar_data.jl               # PVWatts solar capacity-factor fetcher
│   ├── population_assignment.jl    # Tract → bus radius assignment for census aggregation
│   └── census_data.jl              # Census ACS fetch + per-bus demographic aggregation
├── data/                           # Full dataset (gitignored — see test_data/ for GitHub subset)
│   ├── networks/                   # Power system test cases (.m format)
│   ├── CATS/                       # California Test System specific data
│   ├── USGS_FPI/                   # Wildfire risk data
│   ├── bus_lat_lons/               # Geographic coordinates for networks
│   ├── US_Shapefiles/              # US state and tract boundaries for visualization
│   ├── solar_data/                 # PVWatts hourly capacity factors per network
│   └── census_data/                # Per-bus Census ACS demographics
├── test_data/                      # June reference subset (June 2020; June 2021 for RTS)
│   ├── networks/                   # Same structure as data/
│   ├── CATS/                       # June-only CATS time-series
│   ├── USGS_FPI/                   # Wildfire risk data (June only)
│   ├── bus_lat_lons/
│   ├── US_Shapefiles/
│   └── solar_data/                 # Solar capacity factors (small networks only)
├── tutorial.ipynb                  # Jupyter notebook walkthrough
├── LICENSE                         # MIT license
├── Project.toml                    # Package dependencies
└── README.md                       # This file
```

# Available Data

## Included Reference Dataset

This repository ships with a **reference dataset (`test_data/`) limited to June 2020** (June 2021 for RTS) for all six networks. This subset is sufficient for testing, demos, and single-month analyses. For other time periods, use `fetch_wfpi_data.jl` to download WFPI risk data, or supply custom data via the `:risk_per_line` parameter.

The full dataset lives in `data/` (gitignored). To regenerate `test_data/` from `data/`, run:
```bash
julia scripts/generate_reference_data.jl
```

## Solar Capacity Factor Data

Solar capacity factor data (TMY hourly profiles from NREL PVWatts) is included in `test_data/solar_data/` for small networks only, due to GitHub's 100 MB file size limit:

| Network | Included in repo |
|---------|-----------------|
| RTS     | ✓ |
| WECC240 | ✓ |
| texas2k | ✓ |
| Texas7k | ✗ (157 MB) |
| CATS    | ✗ (196 MB) |
| WECC10k | ✗ (230 MB) |

To generate solar data locally for any network, run:
```bash
export NREL_API_KEY=your_key_here  # get a free key at https://developer.nlr.gov/signup/
julia --project=scripts scripts/generate_solar_data.jl --network Texas7k
```
This fetches TMY data from the NREL PVWatts API and writes to `data/solar_data/{Network}/solar_data.csv`. Then re-run `generate_reference_data.jl` to populate `test_data/solar_data/`.

## Census Demographic Data

Per-bus Census ACS 5-year demographics (total population, households, race, Hispanic/Latino ethnicity, poverty, household-income brackets, median income) are pulled via the Census Data API and aggregated from census tracts to load buses.

The pipeline runs in three stages:

1. **Tract selection.** Every census tract whose centroid lies within a per-bus radius (default 25 km) of *any* bus is selected. This union-of-disks filter keeps sparse networks (e.g. WECC240) from pulling tracts in the empty regions between distant buses.
2. **ACS fetch.** The Census Data API (`api.census.gov/data`, free) returns demographics for each selected tract. A free key is optional — anonymous access is capped at ~500 requests per day. Get one at <https://api.census.gov/data/key_signup.html>.
3. **Tract → bus aggregation.** A 3-pass radius algorithm assigns tract populations to load buses (guaranteeing every populated tract is covered and every load bus receives population), then tract-level counts are summed with weights to per-bus totals. `median_income` is population-weighted across assigned tracts.

Generate data for a network:
```bash
export CENSUS_API_KEY=your_key_here   # optional
julia --project=. scripts/generate_census_data.jl --network RTS
julia --project=. scripts/generate_census_data.jl --network WECC240 --radius-km 50
julia --project=. scripts/generate_census_data.jl --network RTS --weighting proportional
julia --project=. scripts/generate_census_data.jl --network RTS --acs-year 2021
```

Requires the national tract shapefile (~100 MB, gitignored):
```bash
curl -L -o data/US_Shapefiles/cb_2023_us_tract_500k.zip \
  https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_tract_500k.zip
unzip -o data/US_Shapefiles/cb_2023_us_tract_500k.zip -d data/US_Shapefiles/
```

Output: a single CSV per (network, ACS year) at `data/census_data/{Network}_census_{Year}.csv`:

| Column | Description |
|---|---|
| `Bus_ID` | Bus identifier matching the network case file |
| `total_pop` | Weighted sum of tract population (B01003_001E) |
| `num_households` | Weighted sum of households (B11001_001E) |
| `num_white`, `num_black`, `num_native`, `num_asian` | Race counts (B02001_002–005E) |
| `num_hispanic` | Hispanic/Latino count (B03003_003E) |
| `num_below_poverty`, `num_above_poverty` | Poverty counts (B17001_001/002E) |
| `num_low_income`, `num_middle_income`, `num_high_income` | Households with income <\$35k / \$35–100k / ≥\$100k (B19001 brackets) |
| `median_income` | Population-weighted median household income (\$) (B19013_001E) |

All `num_*` columns are absolute counts (`Σ weight × tract_count` over assigned tracts); derive percentages downstream as needed. Rows are emitted only for load buses (buses with non-zero active load).

**Weighting modes** (`--weighting`):

- `inverse` (default) — `w_i = (1/d_i) / Σ(1/d_j)`. Closer buses get larger shares.
- `proportional` — `w_i = d_i / Σ d_j`. Matches the original spec literally; farther buses get larger shares.

**Plot overlay** on `:network_overview`: pass `census_overlay=:median_income` (or `:pct_poverty`, `:pct_nonwhite`) to `plot_results` to color each load bus by the metric. The plot falls back gracefully with a warning if the CSV is absent.

Load results back into Julia with `load_census_data(network; acs_year=2022)`.

## Data Sources

**Full CATS Load Data:**
- The full California Test System load data file can be downloaded from the [CATS-CaliforniaTestSystem repository](https://github.com/WISPO-POP/CATS-CaliforniaTestSystem)
- The included reference dataset contains June hours only

**Full Wildfire Risk Data:**
- Wildfire risk data for additional time periods is available upon request
- Contact the repository maintainers for access

## Power System Networks

| Network Name | Buses | Generators | Lines | Aliases |
|-------------|-------|------------|-------|---------|
| RTS-GMLC | 73 | 158 | 120 | `"RTS"`, `"RTS_GMLC"` |
| California Test System | 8,870 | 3,892 | 10,823 | `"CATS"`, `"CaliforniaTestSystem"` |
| Texas 7k | 6,717 | 731 | 9,140 | `"Texas7k"` |
| ACTIVSg 2000 | 2,000 | 544 | 3,206 | `"Texas2k"`, `"ACTIVSg2000"` |
| ACTIVSg 10k | 10,000 | 2,485 | 12,706 | `"WECC10k"`, `"ACTIVSg10k"` |
| WECC 240 | 240 | 143 | 448 | `"WECC240"`, `"pserc240"` |

## Network Credits and Sources

- **California Test System (CATS)**: Obtained from the [CATS-CaliforniaTestSystem](https://github.com/WISPO-POP/CATS-CaliforniaTestSystem) repository by WISPO-POP
- **RTS-GMLC**: From the [RTS-GMLC](https://github.com/GridMod/RTS-GMLC) repository, developed by the Grid Modernization Lab Consortium
- **ACTIVSg Test Cases** (Texas2k, WECC10k): Synthetic test cases from Texas A&M University. See [ACTIVSg documentation](https://electricgrids.engr.tamu.edu/electric-grid-test-cases/)
- **Texas 7k**: Texas synthetic 7000-bus test case
- **WECC 240**: PSERC 240-bus test case from the [PGLib-OPF](https://github.com/power-grid-lib/pglib-opf) library

## Wildfire Risk Data

Wildfire risk data is automatically loaded from the USGS Fire Potential Index (FPI) based on the network and time specification.

> **Note:** The included dataset only covers **June 2020** (June 2021 for RTS). For other time periods, supply custom data via the `:risk_per_line` parameter or contact the maintainers for the full dataset.

**Standard Networks** (RTS, Texas7k, Texas2k, WECC10k, WECC240):
- Data stored per day in JLD2 format
- Location: `data/USGS_FPI/{network}/{year}/forecast_day_1/`
- File format: `FPI_{network}_fday1_year{year}_month{month}_day{day}.jld2`
- Contains: `Dict{Int,Float64}` mapping line ID to risk value

**CATS Network**:
- Data stored in annual CSV files
- Location: `data/USGS_FPI/CATS/{year}_risk.csv`
- Columns: `date_of_forecast`, `branch_id`, `max_wfpi`, `mean_wfpi`, `cum_wfpi`, etc.
- Select risk metric via `:risk_metric` parameter (default: `"cum_wfpi"`)
