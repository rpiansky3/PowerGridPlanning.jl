# Command-Line Interface

For users who prefer working from the terminal, PowerGridPlanning includes a command-line interface (CLI) via the `scripts/run_ots.jl` script.

## Basic CLI Usage

```bash
julia --project=. scripts/run_ots.jl --network RTS --objective loadshed --date 2021-07-15
```

## CLI Arguments

**Required Arguments:**
- `--network, -n` - Network name (RTS, CATS, Texas7k, Texas2k, WECC10k, WECC240)
- `--objective, -o` - Objective function (loadshed, wildfire, cost, tradeoff)

**Date Specification (choose one):**
- `--date, -d` - Single date (YYYY-MM-DD)
- `--dates` - Multiple dates comma-separated (YYYY-MM-DD,YYYY-MM-DD,...)
- `--month` - Full month (e.g., "June 2021")
- `--year, -y` - Full year (e.g., "2020")

**Model and Method:**
- `--model, -m` - Model type: DCOTS, LACOTS, DCOPF, or LACOPF (default: DCOTS). DCOPF/LACOPF disable wildfire switching but still support battery/solar/hardening investments.
- `--method` - Solution method: optimal or thresholded (default: optimal)

**Method Parameters:**
- `--threshold` - Absolute risk threshold (required for thresholded; adds risk constraint for optimal)
- `--threshold-pct` - Percentage risk threshold, 0-1 (required for thresholded; adds risk constraint for optimal)

**Objective Parameters:**
- `--tradeoff-weight, -w` - Weight for tradeoff objective, 0-1 (default: 0.5)
- `--voll` - Value of lost load in USD/MWh for cost objective (default: 10000.0)

**CATS-Specific:**
- `--risk-metric` - Risk metric for CATS: max_wfpi, mean_wfpi, cum_wfpi (default: cum_wfpi)

**Solver Parameters:**
- `--time-limit, -t` - Solver time limit in seconds (default: 86400.0)
- `--mip-gap` - MIP optimality gap, e.g., 0.01 = 1% (default: 0.01)

**Output Options:**
- `--save, -s` - Save results to file (JLD2 or TXT based on extension)
- `--quiet, -q` - Suppress detailed output
- `--T` - Hours per day (default: 24)

**Hardening Parameters:**
- `--hardening` - Enable line hardening optimization (vegetation management, covered conductors, or undergrounding)
- `--hardening-effectiveness` - Risk reduction effectiveness, 0-1 (default: 1.0)
- `--hardening-cost-per-mile` - Hardening cost per mile in USD (default: \$7M)
- `--hardening-budget` - Hardening budget in USD (default: \$1B for non-cost objectives)
- `--hardening-no-enforce-energization` - Allow hardened lines to be de-energized

**Battery Parameters:**
- `--battery` - Enable battery energy storage installation
- `--battery-cost-per-pu` - Cost per p.u. (100MWh) in USD (default: \$100M)
- `--battery-charge-efficiency` - Charging efficiency, 0-1 (default: 0.95)
- `--battery-discharge-efficiency` - Discharging efficiency, 0-1 (default: 0.95)
- `--battery-charge-rate` - Max charge rate as fraction of capacity (default: 1.0)
- `--battery-discharge-rate` - Max discharge rate as fraction of capacity (default: 1.0)
- `--battery-max-network` - Network-wide capacity limit in p.u. (default: unlimited)
- `--battery-max-per-node` - Per-node capacity limit in p.u. (default: 10000)
- `--battery-exclusive-operation` - Limit simultaneous charging and discharging
- `--battery-candidate-buses` - Comma-separated bus IDs or "load_buses"
- `--linearized-battery-power` - Linear (true) or nonlinear (false) reactive power for LACOTS (default: true)

**Solar Parameters:**
- `--solar` - Enable solar PV installation
- `--solar-cost-per-pu` - Cost per p.u. (100MW) in USD (default: \$100M)
- `--solar-data-path` - Path to CSV with hourly capacity factors
- `--solar-capacity-factor-default` - Default capacity factor, 0-1 (default: 0.3)
- `--solar-max-network` - Network-wide capacity limit in p.u. (default: unlimited)
- `--solar-max-per-node` - Per-node capacity limit in p.u. (default: 10000)
- `--solar-candidate-buses` - Comma-separated bus IDs for solar candidates
- `--linearized-solar-power` - Linear (true) or nonlinear (false) inverter capability for LACOTS (default: true)

**Infrastructure Budget:**
- `--infrastructure-budget` - Shared budget for batteries + solar + hardening in USD (default: \$1B for non-cost, unlimited for cost)

## CLI Examples

**Example 1: Basic single-day optimization**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective loadshed \
    --date 2021-07-15
```

**Example 2: Fast thresholded method**
```bash
julia --project=. scripts/run_ots.jl \
    --network Texas7k \
    --objective loadshed \
    --date 2021-06-11 \
    --method thresholded \
    --threshold-pct 0.5 \
    --time-limit 300 \
    --quiet
```

**Example 3: Tradeoff objective with custom weight**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective tradeoff \
    --date 2021-07-15 \
    --tradeoff-weight 0.7 \
    --method optimal
```

**Example 4: Multiple dates**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective wildfire \
    --dates "2021-07-15,2021-07-16,2021-07-17"
```

**Example 5: Full month optimization**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective loadshed \
    --month "July 2021" \
    --mip-gap 0.02
```

**Example 6: Save results to file**
```bash
julia --project=. scripts/run_ots.jl \
    --network Texas2k \
    --objective loadshed \
    --year "2020" \
    --method thresholded \
    --threshold-pct 0.4 \
    --save results/texas2k_2020.jld2
```

**Example 7: CATS network with custom risk metric**
```bash
julia --project=. scripts/run_ots.jl \
    --network CATS \
    --objective tradeoff \
    --date 2021-08-15 \
    --risk-metric max_wfpi \
    --tradeoff-weight 0.6
```

**Example 8: Cost minimization**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective cost \
    --date 2021-07-15 \
    --voll 10000 \
    --quiet
```

**Example 9: Line hardening optimization**
```bash
julia --project=. scripts/run_ots.jl \
    --network RTS \
    --objective loadshed \
    --date 2021-07-15 \
    --hardening \
    --hardening-budget 50000000 \
    --hardening-effectiveness 1.0 \
    --save results/rts_hardening.jld2
```

**Example 10: Thresholded method with hardening**
```bash
julia --project=. scripts/run_ots.jl \
    --network Texas7k \
    --objective loadshed \
    --dates "2021-06-11,2021-06-12,2021-06-13" \
    --method thresholded \
    --threshold-pct 0.5 \
    --hardening \
    --hardening-budget 100000000
```

## CLI Output

The CLI displays optimization progress and results in a formatted output:

**Detailed Output (default):**
```
======================================================================
WILDFIRE SWITCHING OPTIMIZATION
======================================================================

Network:   RTS
Model:     DCOTS
Objective: loadshed
Method:    optimal

Running optimization...

======================================================================
OPTIMIZATION RESULTS
======================================================================

Solution Status
   Status:          OPTIMAL
   Solve Time:      0.35 seconds
   Method:          optimal
   Objective Value: 125.4321

Load Shedding
   Total Load Shed: 125.43 MW

Wildfire Risk
   Total Risk:      1234.56
   Active Risk:     617.28
   Removed Risk:    617.28
   Risk Reduction:  50.0%

Line Switching
   Total Lines Switched Off: 15

🛡️  Line Hardening
   Lines Hardened:      8
   Hardening Cost:      $48.30M
   Risk Mitigated:      425.12
   Risk Mitigation:     34.4%

🔋 Battery Storage
   Buses Installed:     5
   Total Capacity:      250.0 MWh (2.5000 p.u.)
   Battery Cost:        $50.00M

☀️  Solar PV
   Buses Installed:     3
   Total Capacity:      150.0 MW (1.5000 p.u.)
   Solar Cost:          $75.00M
   Total Generation:    12.3456 p.u.·h

======================================================================
```

**Note:** The Line Hardening, Battery Storage, and Solar PV sections only appear when the respective features are enabled.

**Quiet Output (--quiet flag):**
```
Status: OPTIMAL | Time: 0.35s | Load Shed: 125.43 MW | Risk Reduction: 50.0%
```
