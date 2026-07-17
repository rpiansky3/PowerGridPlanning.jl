# test/runtests.jl
# CI test suite — no Gurobi license required.
# Run via: Pkg.test()  OR  julia --project=. test/runtests.jl
#
# These tests cover:
#   - Package loading (Gurobi_jll supplies runtime; license only needed for optimize!)
#   - test_data/ file existence
#   - CSV column structure
#   - Parameter validation errors (thrown before build_and_solve_model)
#   - Small RTS solves via the open-source HiGHS solver (Pkg.test() only)
#   - Census tract→bus assignment and aggregation invariants
#
# Full test suite (requires Gurobi license): julia --project=. test/runtests_full.jl

using Test
using CSV
using DataFrames
using PowerGridPlanning
using PowerIO
using JuMP

const PROJECT_ROOT = dirname(@__DIR__)
const TEST_DATA    = joinpath(PROJECT_ROOT, "test_data")

# ── 1. Package load ───────────────────────────────────────────────────────────
@testset "Package loads" begin
    @test PowerGridPlanning.solve_ots isa Function
    @test PowerGridPlanning.plot_results isa Function
    @test PowerGridPlanning.verify_ac isa Function
end

# ── 2. Network files ──────────────────────────────────────────────────────────
@testset "Reference data: network files" begin
    nets = [
        "RTS_GMLC.m",
        "CaliforniaTestSystem.m",
        "Texas7k_20210804.m",
        "case_ACTIVSg2000.m",
        "case_ACTIVSg10k.m",
        "pglib_opf_case240_pserc.m",
    ]
    for f in nets
        path = joinpath(TEST_DATA, "networks", f)
        @test isfile(path)
    end
end

# ── 2a. PowerIO reference helpers ────────────────────────────────────────────
# PowerGridPlanning calls these qualified (PowerIO.build_ref etc.) — confirm the
# installed PowerIO provides them and they behave sanely on a real network.
@testset "PowerIO reference helpers" begin
    path = joinpath(TEST_DATA, "networks", "pglib_opf_case240_pserc.m")
    network_data = PowerIO.to_powermodels(PowerIO.parse_file(path))

    ref = PowerIO.build_ref(network_data)
    @test ref isa Dict{Symbol,<:Any}
    @test haskey(ref, :bus) && !isempty(ref[:bus])
    @test haskey(ref, :branch) && !isempty(ref[:branch])
    @test haskey(ref, :ref_buses)

    branch = first(values(ref[:branch]))
    g, b = PowerIO.calc_branch_y(branch)
    @test g isa Real && b isa Real
    tr, ti = PowerIO.calc_branch_t(branch)
    @test tr isa Real && ti isa Real

    branch_data = Dict{String,Any}(
        "branch" => Dict{String,Any}(
            "1" => Dict{String,Any}("angmin" => -pi / 2, "angmax" => pi / 2),
            "2" => Dict{String,Any}("angmin" => 0.0, "angmax" => 0.0),
        ),
    )
    corrected = PowerIO.correct_voltage_angle_differences!(deepcopy(branch_data))
    @test corrected isa Dict
end

# ── 3. WFPI risk data ─────────────────────────────────────────────────────────
@testset "Reference data: WFPI files" begin
    # CSV-based networks
    @test isfile(joinpath(TEST_DATA, "USGS_FPI", "RTS",  "2020_risk.csv"))
    @test isfile(joinpath(TEST_DATA, "USGS_FPI", "CATS", "2020_risk.csv"))

    # JLD2-based networks — spot-check June 15
    jld2_files = [
        joinpath(TEST_DATA, "USGS_FPI", "Texas7k",  "2020", "forecast_day_1", "FPI_Texas7k_fday1_year2020_month6_day15.jld2"),
        joinpath(TEST_DATA, "USGS_FPI", "texas2k",  "2020", "forecast_day_1", "FPI_Texas2k_fday1_year2020_month6_day15.jld2"),
        joinpath(TEST_DATA, "USGS_FPI", "WECC10k",  "2020", "forecast_day_1", "FPI_WECC10k_fday1_year2020_month6_day15.jld2"),
        joinpath(TEST_DATA, "USGS_FPI", "WECC240",  "2020", "forecast_day_1", "FPI_WECC240_fday1_year2020_month6_day15.jld2"),
    ]
    for f in jld2_files
        @test isfile(f)
    end
end

# ── 4. Solar data ─────────────────────────────────────────────────────────────
# Note: CATS, Texas7k, WECC10k solar CSVs are 200+ MB and not tracked in git;
# only the three smaller networks are included in test_data/.
@testset "Reference data: solar CSV files" begin
    solar_dirs = ["RTS", "texas2k", "WECC240"]
    for d in solar_dirs
        path = joinpath(TEST_DATA, "solar_data", d, "solar_data.csv")
        @test isfile(path)
    end
end

# ── 5. CATS support files ─────────────────────────────────────────────────────
@testset "Reference data: CATS support files" begin
    cats_files = [
        "CATS_buses.csv",
        "CATS_gens.csv",
        "HourlyProduction2019.csv",
        "Load_Agg_Post_Assignment_v3_latest.csv",
        "cats_metadata.json",
    ]
    for f in cats_files
        @test isfile(joinpath(TEST_DATA, "CATS", f))
    end
end

# ── 6. Bus coordinate files ───────────────────────────────────────────────────
@testset "Reference data: bus coordinate files" begin
    coord_files = [
        "RTS_GMLC_bus.csv",
        "CATS_bus.csv",
        "Texas7k_lat_long.csv",
        "Texas2k_lat_long.csv",
        "WECC10k_lat_long.csv",
        "wecc_lat_lon_good.csv",
    ]
    for f in coord_files
        @test isfile(joinpath(TEST_DATA, "bus_lat_lons", f))
    end
end

# ── 7. CSV column structure ───────────────────────────────────────────────────
@testset "CSV column structure" begin
    # RTS risk CSV has expected columns (date_of_risk, branch_id, risk metrics)
    rts_risk = CSV.read(joinpath(TEST_DATA, "USGS_FPI", "RTS", "2020_risk.csv"), DataFrame)
    @test "date_of_risk" in names(rts_risk)
    @test "branch_id" in names(rts_risk)
    @test any(occursin.(r"wfpi"i, names(rts_risk)))

    # Solar CSV has Bus_ID and Hour columns
    rts_solar = CSV.read(joinpath(TEST_DATA, "solar_data", "RTS", "solar_data.csv"), DataFrame)
    col_names = names(rts_solar)
    @test any(occursin.(r"bus"i, col_names))
    @test any(occursin.(r"hour"i, col_names))
    @test any(occursin.(r"ac_output|capacity_factor|cf"i, col_names))
end

# ── 8. Parameter validation (pre-solver errors) ───────────────────────────────
@testset "Parameter validation" begin
    # Missing required key
    @test_throws ErrorException solve_ots(Dict(
        :model => "DCOTS", :objective => "loadshed", :times => [(2020, 6, 15)]
    ))

    # Invalid model type
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "BADMODEL",
        :objective => "loadshed", :times => [(2020, 6, 15)]
    ))

    # Invalid objective
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS",
        :objective => "invalid_obj", :times => [(2020, 6, 15)]
    ))

    # Invalid switching_method
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS", :objective => "loadshed",
        :times => [(2020, 6, 15)], :switching_method => "random"
    ))

    # Negative battery_cost_per_pu — caught in preprocess() before optimizer
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS", :objective => "loadshed",
        :times => [(2020, 6, 15)], :data_dir => "test_data",
        :battery_enabled => true, :battery_cost_per_pu => -1.0,
        :infrastructure_budget => 1e9,
    ))

    # solar_capacity_factor_default outside [0,1] — caught in preprocess()
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS", :objective => "loadshed",
        :times => [(2020, 6, 15)], :data_dir => "test_data",
        :solar_enabled => true, :solar_capacity_factor_default => 1.5,
        :infrastructure_budget => 1e9,
    ))

    # allocate_mw <= 0 — caught in validate_allocation_parameters()
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS", :objective => "loadshed",
        :times => [(2020, 6, 15)], :data_dir => "test_data",
        :allocate_mw => -100.0,
    ))

    # allocate_candidate_buses wrong type — caught in validate_allocation_parameters()
    @test_throws ErrorException solve_ots(Dict(
        :network => "RTS", :model => "DCOTS", :objective => "loadshed",
        :times => [(2020, 6, 15)], :data_dir => "test_data",
        :allocate_mw => 100.0, :allocate_candidate_buses => "all",
    ))
end

# ── 8a. User-supplied networks (pre-solver validation) ───────────────────────
@testset "User-supplied networks (validation)" begin
    rts_case = joinpath(TEST_DATA, "networks", "RTS_GMLC.m")

    # Nonexistent case file
    @test_throws ErrorException solve_ots(Dict(
        :case_file => joinpath(TEST_DATA, "networks", "no_such_case.m"),
        :model => "DCOPF", :objective => "loadshed", :times => [(2020, 6, 15)],
    ))

    # OTS models require user-supplied risk on a custom case
    err = try
        solve_ots(Dict(
            :case_file => rts_case, :model => "DCOTS",
            :objective => "loadshed", :times => [(2020, 6, 15)],
        ))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("risk_per_line", err.msg)

    # Plots require bus coordinates on a custom case
    @test_throws ErrorException solve_ots(Dict(
        :case_file => rts_case, :model => "DCOPF",
        :objective => "loadshed", :times => [(2020, 6, 15)],
        :plots => "all",
    ))

    # Hardening requires a line-length source on a custom case
    @test_throws ErrorException solve_ots(Dict(
        :case_file => rts_case, :model => "DCOPF",
        :objective => "loadshed", :times => [(2020, 6, 15)],
        :hardening_enabled => true, :infrastructure_budget => 1e9,
    ))

    # Coordinate normalization: aliases map to canonical names, missing columns error
    df = DataFrame(bus_id=[1, 2], latitude=[33.0, 34.0], lon=[-113.0, -114.0])
    normalized = PowerGridPlanning.normalize_bus_coords!(copy(df))
    @test all(c -> c in names(normalized), ["Bus_ID", "lat", "lng"])
    @test_throws ErrorException PowerGridPlanning.normalize_bus_coords!(DataFrame(a=[1]))

    # resolve_bus_coordinates: DataFrame passthrough and custom-case empty fallback
    resolved = PowerGridPlanning.resolve_bus_coordinates(Dict{Symbol,Any}(
        :bus_coords => df, :case_file => rts_case, :network => "custom"))
    @test nrow(resolved) == 2
    empty_coords = PowerGridPlanning.resolve_bus_coordinates(Dict{Symbol,Any}(
        :bus_coords => nothing, :case_file => rts_case, :network => "custom"))
    @test isempty(empty_coords)
end

# ── 9. AC verification pre-solver API and structure ──────────────────────────
@testset "AC verification validation and structure" begin
    @test_throws ErrorException verify_ac(Dict(
        :network => "RTS", :mode => "BADMODE", :times => [(2020, 6, 15)]
    ))

    acpf = Dict(:network => "RTS", :mode => "ACPF",
                :times => [(2020, 6, 15)], :T => 1, :data_dir => "test_data")
    acopf = Dict(:network => "RTS", :mode => "ACOPF",
                 :times => [(2020, 6, 15)], :T => 1, :data_dir => "test_data")
    @test_nowarn begin
        p = copy(acpf)
        PowerGridPlanning.validate_ac_parameters!(p)
        PowerGridPlanning.set_ac_defaults!(p)
    end
    @test_nowarn begin
        p = copy(acopf)
        PowerGridPlanning.validate_ac_parameters!(p)
        PowerGridPlanning.set_ac_defaults!(p)
    end

    planning_results = Dict{Symbol,Any}(
        :z => Dict((1, 1) => 0.0),
        :y => Dict(1 => 1.0),
        :x => Dict(101 => 0.5),
        :s => Dict(102 => 0.25),
        :allocated_load => Dict(103 => 0.1),
    )
    params = copy(acopf)
    PowerGridPlanning.validate_ac_parameters!(params)
    PowerGridPlanning.set_ac_defaults!(params)
    pre = PowerGridPlanning._preprocess_ac_parameters(params, planning_results)
    ctx = PowerGridPlanning._make_ac_hour_context(pre, params, planning_results, 1, 1)
    model = Model()
    PowerGridPlanning.build_acopf_recovery_model!(model, ctx)
    variable_names = name.(all_variables(model))

    @test !any(startswith.(variable_names, "z"))
    @test !any(startswith.(variable_names, "y"))
    @test !any(startswith.(variable_names, "x"))
    @test !any(startswith.(variable_names, "s"))
    @test !any(startswith.(variable_names, "a"))
end

# ── 10. Result saving ────────────────────────────────────────────────────────
@testset "OTS result saving includes islanding metrics" begin
    load_shedding = JuMP.Containers.DenseAxisArray(zeros(1, 1, 3), 1:1, 1:1, [1, 2, 3])

    results = Dict{Symbol,Any}(
        :status => "OPTIMAL",
        :solve_time => 0.1,
        :objective_value => 0.0,
        :model_type => "DCOTS",
        :D => 1,
        :T => 1,
        :times => [(2020, 6, 15)],
        :network => "RTS",
        :switching_method => "thresholded",
        :switched_off_lines => Dict(1 => [2]),
        :islanded_buses => Dict(1 => [3]),
        :islanded_bus_count => Dict(1 => 1),
        :total_islanded_buses => 1,
        :total_load_shed => 0.0,
        :load_shedding => load_shedding,
        :total_risk => 10.0,
        :active_risk => 5.0,
        :removed_risk => 5.0,
        :risk_reduction_pct => 50.0,
        :z => Dict((1, 2) => 0.0),
    )
    opt_parameters = Dict{Symbol,Any}(
        :network => "RTS",
        :objective => "loadshed",
        :time_limit => 60.0,
        :mip_gap => 0.01,
    )

    mktemp() do path, io
        close(io)
        PowerGridPlanning.save_txt(results, path, opt_parameters)
        txt = read(path, String)

        @test occursin("Islanded Buses:   1", txt)
        @test occursin("Islanded buses: 1", txt)
        @test occursin("[islanded_bus_count - Islanded Bus Count by Day]", txt)
        @test occursin("1 => 1", txt)
        @test occursin("[islanded_buses - Islanded Buses by Day]", txt)
        @test occursin("1 => [3]", txt)
    end
end

# ── 11. Optimization core with an open-source solver ─────────────────────────
# Solves small RTS cases with HiGHS so CI exercises the model-building and
# solve path (variables/constraints/objective/extraction) without a Gurobi
# license. HiGHS is a test-target dependency: available under Pkg.test(), and
# skipped gracefully for direct `julia --project=. test/runtests.jl` runs in
# environments without it.
const HIGHS_AVAILABLE = Base.find_package("HiGHS") !== nothing
HIGHS_AVAILABLE && @eval using HiGHS

@testset "Optimization core (HiGHS)" begin
    if !HIGHS_AVAILABLE
        @info "Skipping HiGHS solve tests — HiGHS not installed (run via Pkg.test() to include it)"
    else
        base = Dict(
            :network    => "RTS",
            :objective  => "loadshed",
            :times      => [(2020, 6, 15)],
            :T          => 4,
            :data_dir   => "test_data",
            :optimizer  => HiGHS.Optimizer,
            :time_limit => 300.0,
        )

        # DCOTS: MIP with binary switching variables
        r_ots = solve_ots(merge(base, Dict{Symbol,Any}(:model => "DCOTS")))
        @test r_ots[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test r_ots[:total_load_shed] >= -1e-6
        @test haskey(r_ots, :z) && !isempty(r_ots[:z])
        @test haskey(r_ots, :switched_off_lines)
        @test 0.0 <= r_ots[:risk_reduction_pct] <= 100.0

        # DCOPF: pure power-flow LP baseline (no switching variables)
        r_opf = solve_ots(merge(base, Dict{Symbol,Any}(:model => "DCOPF")))
        @test r_opf[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test r_opf[:total_load_shed] >= -1e-6
        @test isempty(r_opf[:switched_off_lines][1])

        # Thresholded switching: statuses pre-computed, LP solve
        r_thr = solve_ots(merge(base, Dict{Symbol,Any}(
            :model => "DCOTS",
            :switching_method => "thresholded",
            :threshold_pct => 0.75,
        )))
        @test r_thr[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test r_thr[:risk_reduction_pct] >= 25.0 - 1e-6

        # Hardening + tradeoff objective must stay a MILP (regression: the z*y
        # risk term was quadratic, which HiGHS rejects — Gurobi-only before).
        # Cover both energization modes: linear decomposition (default) and
        # the linearized-product path (:hardening_enforce_energization=false).
        for enforce in (true, false)
            r_hard = solve_ots(merge(base, Dict{Symbol,Any}(
                :model => "DCOTS",
                :objective => "tradeoff",
                :tradeoff_weight => 0.5,
                :T => 2,
                :hardening_enabled => true,
                :hardening_effectiveness => 0.9,
                :hardening_enforce_energization => enforce,
                :infrastructure_budget => 1e8,
            )))
            @test r_hard[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
            # Risk decomposition: total = active + switched-removed + hardened-removed
            @test isapprox(r_hard[:total_risk],
                           r_hard[:active_risk] + r_hard[:switched_risk_removed] +
                           r_hard[:hardened_risk_removed]; rtol=1e-6)
            if enforce
                # Hardened lines must be energized on every day they carry risk
                off = Set(l for d in 1:1 for l in r_hard[:switched_off_lines][d])
                @test isempty(intersect(Set(r_hard[:hardened_lines]), off))
            end
        end
    end
end

# ── 12. User-supplied networks: end-to-end solves ────────────────────────────
# The bundled RTS case file stands in for "any MATPOWER case": it is loaded via
# :case_file (arbitrary path), so none of the named-network wiring is exercised.
@testset "User-supplied networks (HiGHS)" begin
    if !HIGHS_AVAILABLE
        @info "Skipping custom-network solve tests — HiGHS not installed (run via Pkg.test() to include it)"
    else
        rts_case = joinpath(TEST_DATA, "networks", "RTS_GMLC.m")
        base = Dict(
            :case_file  => rts_case,
            :objective  => "loadshed",
            :times      => [(2020, 6, 15)],
            :T          => 4,
            :optimizer  => HiGHS.Optimizer,
            :time_limit => 300.0,
        )

        # DCOPF from a bare case file: no geography, no risk data, label defaulted
        # from the file name. Solar siting works via the flat default capacity factor.
        r_opf = solve_ots(merge(base, Dict{Symbol,Any}(
            :model => "DCOPF",
            :solar_enabled => true, :infrastructure_budget => 1e8,
        )))
        @test r_opf[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test r_opf[:network] == "RTS_GMLC"
        @test r_opf[:total_load_shed] >= -1e-6

        # DCOTS with user-supplied per-line risk (line IDs from the parsed case)
        ref = PowerIO.build_ref(PowerIO.to_powermodels(PowerIO.parse_file(rts_case)))
        risky = sort(collect(keys(ref[:branch])))[1:3]
        risk = Dict(1 => Dict(l => 10.0 for l in risky))
        r_ots = solve_ots(merge(base, Dict{Symbol,Any}(
            :model => "DCOTS", :risk_per_line => deepcopy(risk), :network => "MyCase",
        )))
        @test r_ots[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test r_ots[:network] == "MyCase"
        @test haskey(r_ots, :z) && !isempty(r_ots[:z])

        # Hardening with user-supplied coordinates (CSV path)
        coords_csv = joinpath(TEST_DATA, "bus_lat_lons", "RTS_GMLC_bus.csv")
        r_hard = solve_ots(merge(base, Dict{Symbol,Any}(
            :model => "DCOTS", :risk_per_line => deepcopy(risk),
            :hardening_enabled => true, :bus_coords => coords_csv,
            :infrastructure_budget => 1e9,
        )))
        @test r_hard[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        @test haskey(r_hard, :hardened_lines)

        # Hardening with explicit line lengths instead of coordinates
        lengths = Dict(l => 10.0 for l in keys(ref[:branch]))
        r_len = solve_ots(merge(base, Dict{Symbol,Any}(
            :model => "DCOTS", :risk_per_line => deepcopy(risk),
            :hardening_enabled => true, :line_lengths => lengths,
            :infrastructure_budget => 1e9,
        )))
        @test r_len[:status] in (MOI.OPTIMAL, MOI.TIME_LIMIT)
    end
end

include("test_population_assignment.jl")
