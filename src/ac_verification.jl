"""
AC feasibility verification and AC recovery models.

These builders intentionally do not call the DCOTS/LACOTS variable builders:
planning decisions are fixed inputs, while only continuous AC operating
variables are created.
"""

const _AC_SOLVED_STATUSES = Set([
    MOI.OPTIMAL,
    MOI.LOCALLY_SOLVED,
    MOI.ALMOST_OPTIMAL,
    MOI.ALMOST_LOCALLY_SOLVED,
])

"""
    verify_ac(ac_parameters::Dict, planning_results::Union{Dict,Nothing}=nothing)

Run package-owned polar AC feasibility checks (`mode = "ACPF"`) or redispatch
with load shedding (`mode = "ACOPF"`). Planning results are replayed as fixed
line statuses, fixed load allocations, and fixed resource capacities; no AC
planning variables are created.
"""
function verify_ac(ac_parameters::Dict, planning_results::Union{Dict,Nothing}=nothing)
    params = copy(ac_parameters)
    validate_ac_parameters!(params)
    set_ac_defaults!(params)

    preprocessed = _preprocess_ac_parameters(params, planning_results)
    D = preprocessed[:D]
    T = preprocessed[:T]
    mode = params[:mode]

    results = Dict{Symbol,Any}(
        :status => Dict{Tuple{Int,Int},Any}(),
        :feasible => Dict{Tuple{Int,Int},Bool}(),
        :hours => Dict{Tuple{Int,Int},Dict{Symbol,Any}}(),
        :failed_hours => Tuple{Int,Int}[],
        :total_p_load_shed => 0.0,
        :total_q_load_shed => 0.0,
        :total_load_shed => 0.0,
        :mode => mode,
        :model_type => mode,
        :D => D,
        :T => T,
        :times => preprocessed[:times_array],
        :network => params[:network],
        :data_dir => params[:data_dir],
    )

    start_time = time()
    for d in 1:D, t in 1:T
        ctx = _make_ac_hour_context(preprocessed, params, planning_results, d, t)
        model = Model(params[:optimizer])
        set_optimizer_attribute(model, MOI.Silent(), get(params, :silent, true))

        if mode == "ACPF"
            build_acpf_model!(model, ctx)
        else
            build_acopf_recovery_model!(model, ctx)
        end

        optimize!(model)
        hour_result = _extract_ac_hour_result(model, ctx, mode)
        key = (d, t)
        results[:status][key] = hour_result[:status]
        results[:feasible][key] = hour_result[:feasible]
        results[:hours][key] = hour_result
        results[:total_p_load_shed] += hour_result[:total_p_load_shed]
        results[:total_q_load_shed] += hour_result[:total_q_load_shed]
        hour_result[:feasible] || push!(results[:failed_hours], key)
    end

    results[:solve_time] = time() - start_time
    results[:total_load_shed] = results[:total_p_load_shed]
    results[:feasible_all] = isempty(results[:failed_hours])

    return format_ac_output(results, params)
end

function validate_ac_parameters!(params::Dict)
    for key in (:network, :times, :mode)
        haskey(params, key) || error("Missing required AC parameter: $key")
    end
    params[:mode] in ("ACPF", "ACOPF") ||
        error("Invalid AC mode: $(params[:mode]). Must be 'ACPF' or 'ACOPF'")
    if haskey(params, :output_format) && !(params[:output_format] in ("dict", "jld2", "txt"))
        error("Unknown output format: $(params[:output_format])")
    end
    if haskey(params, :output_format) && params[:output_format] in ("jld2", "txt")
        if !haskey(params, :output_path) || params[:output_path] === nothing
            error("output_path required for output_format '$(params[:output_format])'")
        end
    end
end

function set_ac_defaults!(params::Dict)
    defaults = Dict(
        :T => 24,
        :data_dir => "data",
        :optimizer => Ipopt.Optimizer,
        :recovery => true,
        :output_format => "dict",
        :output_path => nothing,
        :load_shed_penalty => 1e6,
        :silent => true,
    )
    for (key, val) in defaults
        haskey(params, key) || (params[key] = val)
    end
end

function _preprocess_ac_parameters(params::Dict, planning_results::Union{Dict,Nothing})
    prep_params = Dict{Symbol,Any}(
        :network => params[:network],
        :model => "DCOPF",
        :objective => "loadshed",
        :times => params[:times],
        :T => params[:T],
        :data_dir => params[:data_dir],
        :output_format => "dict",
    )

    solar_caps = _planning_capacity_dict(planning_results, (:s, :solar_capacity))
    if !isempty(solar_caps)
        prep_params[:solar_enabled] = true
        prep_params[:solar_candidate_buses] = sort(collect(keys(solar_caps)))
        if haskey(params, :solar_data_path)
            prep_params[:solar_data_path] = params[:solar_data_path]
        end
        if haskey(params, :solar_capacity_factor_default)
            prep_params[:solar_capacity_factor_default] = params[:solar_capacity_factor_default]
        end
    end

    set_defaults!(prep_params)
    return preprocess(prep_params)
end

function _make_ac_hour_context(preprocessed::Dict, params::Dict, planning_results::Union{Dict,Nothing}, d::Int, t::Int)
    ref = preprocessed[:is_cats] ? preprocessed[:hourly_refs][d][t] : preprocessed[:base_ref]
    bus_names = sort(collect(keys(ref[:bus])))
    branch_ids = sort(collect(keys(ref[:branch])))
    gen_names = sort(collect(keys(ref[:gen])))
    arc_names = sort(collect(ref[:arcs]))

    base_pd = Dict{Int,Float64}()
    base_qd = Dict{Int,Float64}()
    for bus in bus_names
        if preprocessed[:is_cats]
            base_pd[bus] = reduce(+, ref[:load][j]["pd"] for j in ref[:bus_loads][bus]; init=0.0)
            base_qd[bus] = reduce(+, ref[:load][j]["qd"] for j in ref[:bus_loads][bus]; init=0.0)
        else
            base_pd[bus] = preprocessed[:hourly_loads][d]["pd"][bus][t]
            base_qd[bus] = preprocessed[:hourly_loads][d]["qd"][bus][t]
        end
    end

    allocated_p = _allocated_load_by_bus(planning_results, bus_names)
    tan_phi = tan(acos(0.95))
    pd = Dict(bus => base_pd[bus] + get(allocated_p, bus, 0.0) for bus in bus_names)
    qd = Dict(bus => base_qd[bus] + get(allocated_p, bus, 0.0) * tan_phi for bus in bus_names)

    branch_status = Dict(l => _fixed_branch_status(ref, planning_results, d, l) for l in branch_ids)

    return Dict{Symbol,Any}(
        :ref => ref,
        :params => params,
        :planning_results => planning_results,
        :d => d,
        :t => t,
        :bus_names => bus_names,
        :branch_ids => branch_ids,
        :gen_names => gen_names,
        :arc_names => arc_names,
        :pd => pd,
        :qd => qd,
        :branch_status => branch_status,
        :solar_capacity => _planning_capacity_dict(planning_results, (:s, :solar_capacity)),
        :battery_capacity => _planning_capacity_dict(planning_results, (:x, :battery_capacity)),
        :solar_cf => get(preprocessed, :solar_cf, Dict{Tuple{Int,Int,Int},Float64}()),
    )
end

function build_acpf_model!(model::JuMP.Model, ctx::Dict)
    _add_ac_operational_variables!(model, ctx; recovery=false)
    _add_ac_network_constraints!(model, ctx; recovery=false)
    _fix_acpf_replay_dispatch!(model, ctx)
    @objective(model, Min, 0.0)
    return model
end

function build_acopf_recovery_model!(model::JuMP.Model, ctx::Dict)
    _add_ac_operational_variables!(model, ctx; recovery=true)
    _add_ac_network_constraints!(model, ctx; recovery=true)
    _add_fixed_capacity_resource_constraints!(model, ctx; recovery=true)
    penalty = ctx[:params][:load_shed_penalty]
    @objective(model, Min,
        penalty * sum(model[:p_load_shed][i] + model[:q_load_shed][i] for i in ctx[:bus_names]) +
        sum(model[:pg][g] for g in ctx[:gen_names])
    )
    return model
end

function _add_ac_operational_variables!(model::JuMP.Model, ctx::Dict; recovery::Bool)
    ref = ctx[:ref]
    buses = ctx[:bus_names]
    gens = ctx[:gen_names]
    arcs = ctx[:arc_names]

    @variable(model, ref[:bus][i]["vmin"] <= vm[i in buses] <= ref[:bus][i]["vmax"])
    @variable(model, -pi <= va[i in buses] <= pi)
    @variable(model, ref[:gen][g]["pmin"] <= pg[g in gens] <= ref[:gen][g]["pmax"])
    @variable(model, ref[:gen][g]["qmin"] <= qg[g in gens] <= ref[:gen][g]["qmax"])
    @variable(model, p[a in arcs])
    @variable(model, q[a in arcs])

    if recovery
        @variable(model, 0 <= p_load_shed[i in buses] <= max(0.0, ctx[:pd][i]))
        @variable(model, 0 <= q_load_shed[i in buses] <= max(0.0, ctx[:qd][i]))
    end

    solar_buses = sort([i for i in keys(ctx[:solar_capacity]) if i in buses])
    if !isempty(solar_buses)
        if recovery
            @variable(model, 0 <= p_solar[i in solar_buses])
            @variable(model, q_solar[i in solar_buses])
        else
            @variable(model, p_solar[i in solar_buses])
            @variable(model, q_solar[i in solar_buses])
        end
        model[:ac_solar_buses] = solar_buses
    else
        model[:ac_solar_buses] = Int[]
    end

    battery_buses = sort([i for i in keys(ctx[:battery_capacity]) if i in buses])
    if !isempty(battery_buses)
        if recovery
            @variable(model, p_battery[i in battery_buses])
            @variable(model, q_battery[i in battery_buses])
        else
            @variable(model, p_battery[i in battery_buses])
            @variable(model, q_battery[i in battery_buses])
        end
        model[:ac_battery_buses] = battery_buses
    else
        model[:ac_battery_buses] = Int[]
    end

    for i in buses
        set_start_value(vm[i], get(ref[:bus][i], "vm", 1.0))
        set_start_value(va[i], get(ref[:bus][i], "va", 0.0))
    end
    for g in gens
        set_start_value(pg[g], get(ref[:gen][g], "pg", (ref[:gen][g]["pmin"] + ref[:gen][g]["pmax"]) / 2))
        set_start_value(qg[g], get(ref[:gen][g], "qg", (ref[:gen][g]["qmin"] + ref[:gen][g]["qmax"]) / 2))
    end
end

function _add_ac_network_constraints!(model::JuMP.Model, ctx::Dict; recovery::Bool)
    ref = ctx[:ref]
    branch_status = ctx[:branch_status]
    vm = model[:vm]
    va = model[:va]
    p = model[:p]
    q = model[:q]
    pg = model[:pg]
    qg = model[:qg]

    for i in keys(ref[:ref_buses])
        @constraint(model, va[i] == 0)
    end

    for l in ctx[:branch_ids]
        branch = ref[:branch][l]
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_idx = (l, f_bus, t_bus)
        t_idx = (l, t_bus, f_bus)
        rate_a = branch_rate_a(branch)

        if branch_status[l] == 0
            @constraint(model, p[f_idx] == 0)
            @constraint(model, q[f_idx] == 0)
            @constraint(model, p[t_idx] == 0)
            @constraint(model, q[t_idx] == 0)
            continue
        end

        g, b = calc_branch_y(branch)
        tr, ti = calc_branch_t(branch)
        g_fr = branch["g_fr"]
        b_fr = branch["b_fr"]
        g_to = branch["g_to"]
        b_to = branch["b_to"]
        tm = branch["tap"]

        @NLconstraint(model, p[f_idx] == (g + g_fr) / tm^2 * vm[f_bus]^2 +
            (-g * tr + b * ti) / tm^2 * vm[f_bus] * vm[t_bus] * cos(va[f_bus] - va[t_bus]) +
            (-b * tr - g * ti) / tm^2 * vm[f_bus] * vm[t_bus] * sin(va[f_bus] - va[t_bus]))
        @NLconstraint(model, q[f_idx] == -(b + b_fr) / tm^2 * vm[f_bus]^2 -
            (-b * tr - g * ti) / tm^2 * vm[f_bus] * vm[t_bus] * cos(va[f_bus] - va[t_bus]) +
            (-g * tr + b * ti) / tm^2 * vm[f_bus] * vm[t_bus] * sin(va[f_bus] - va[t_bus]))
        @NLconstraint(model, p[t_idx] == (g + g_to) * vm[t_bus]^2 +
            (-g * tr - b * ti) / tm^2 * vm[t_bus] * vm[f_bus] * cos(va[t_bus] - va[f_bus]) +
            (-b * tr + g * ti) / tm^2 * vm[t_bus] * vm[f_bus] * sin(va[t_bus] - va[f_bus]))
        @NLconstraint(model, q[t_idx] == -(b + b_to) * vm[t_bus]^2 -
            (-b * tr + g * ti) / tm^2 * vm[t_bus] * vm[f_bus] * cos(va[t_bus] - va[f_bus]) +
            (-g * tr - b * ti) / tm^2 * vm[t_bus] * vm[f_bus] * sin(va[t_bus] - va[f_bus]))

        @constraint(model, va[f_bus] - va[t_bus] <= branch["angmax"])
        @constraint(model, va[f_bus] - va[t_bus] >= branch["angmin"])
        @constraint(model, p[f_idx]^2 + q[f_idx]^2 <= rate_a^2)
        @constraint(model, p[t_idx]^2 + q[t_idx]^2 <= rate_a^2)
    end

    for bus in ctx[:bus_names]
        shed_p = recovery ? model[:p_load_shed][bus] : 0.0
        shed_q = recovery ? model[:q_load_shed][bus] : 0.0
        solar_p = (bus in model[:ac_solar_buses]) ? model[:p_solar][bus] : 0.0
        solar_q = (bus in model[:ac_solar_buses]) ? model[:q_solar][bus] : 0.0
        battery_p = (bus in model[:ac_battery_buses]) ? model[:p_battery][bus] : 0.0
        battery_q = (bus in model[:ac_battery_buses]) ? model[:q_battery][bus] : 0.0
        gs = sum(ref[:shunt][s]["gs"] for s in ref[:bus_shunts][bus]; init=0.0)
        bs = sum(ref[:shunt][s]["bs"] for s in ref[:bus_shunts][bus]; init=0.0)

        @NLconstraint(model,
            sum(p[a] for a in ref[:bus_arcs][bus]) ==
            sum(pg[g] for g in ref[:bus_gens][bus]) -
            ctx[:pd][bus] - gs * vm[bus]^2 + shed_p + solar_p + battery_p
        )
        @NLconstraint(model,
            sum(q[a] for a in ref[:bus_arcs][bus]) ==
            sum(qg[g] for g in ref[:bus_gens][bus]) -
            ctx[:qd][bus] + bs * vm[bus]^2 + shed_q + solar_q + battery_q
        )
    end
end

function _fix_acpf_replay_dispatch!(model::JuMP.Model, ctx::Dict)
    ref = ctx[:ref]
    d = ctx[:d]
    t = ctx[:t]
    planning_results = ctx[:planning_results]

    for g in ctx[:gen_names]
        pg_val = _lookup_dispatch(planning_results, (:pg, :g), d, t, g, get(ref[:gen][g], "pg", 0.0))
        qg_val = _lookup_dispatch(planning_results, (:qg,), d, t, g, get(ref[:gen][g], "qg", 0.0))
        fix(model[:pg][g], pg_val; force=true)
        fix(model[:qg][g], qg_val; force=true)
    end

    _add_fixed_capacity_resource_constraints!(model, ctx; recovery=false)
end

function _add_fixed_capacity_resource_constraints!(model::JuMP.Model, ctx::Dict; recovery::Bool)
    d = ctx[:d]
    t = ctx[:t]
    planning_results = ctx[:planning_results]

    for bus in model[:ac_solar_buses]
        cap = ctx[:solar_capacity][bus]
        if recovery
            cf = get(ctx[:solar_cf], (d, t, bus), 1.0)
            @constraint(model, model[:p_solar][bus] <= cf * cap)
            @constraint(model, model[:q_solar][bus]^2 + model[:p_solar][bus]^2 <= cap^2)
        else
            pval = _lookup_dispatch(planning_results, (:p_solar,), d, t, bus, 0.0)
            qval = _lookup_dispatch(planning_results, (:q_solar,), d, t, bus, 0.0)
            fix(model[:p_solar][bus], pval; force=true)
            fix(model[:q_solar][bus], qval; force=true)
        end
    end

    for bus in model[:ac_battery_buses]
        cap = ctx[:battery_capacity][bus]
        if recovery
            @constraint(model, model[:p_battery][bus]^2 + model[:q_battery][bus]^2 <= cap^2)
        else
            pval = _lookup_dispatch(planning_results, (:p_discharge,), d, t, bus, 0.0) -
                   _lookup_dispatch(planning_results, (:p_charge,), d, t, bus, 0.0)
            qval = _lookup_dispatch(planning_results, (:q_discharge,), d, t, bus, 0.0) -
                   _lookup_dispatch(planning_results, (:q_charge,), d, t, bus, 0.0)
            fix(model[:p_battery][bus], pval; force=true)
            fix(model[:q_battery][bus], qval; force=true)
        end
    end
end

function _extract_ac_hour_result(model::JuMP.Model, ctx::Dict, mode::String)
    status = termination_status(model)
    has_solution = primal_status(model) == MOI.FEASIBLE_POINT
    feasible = status in _AC_SOLVED_STATUSES && has_solution
    result = Dict{Symbol,Any}(
        :status => status,
        :feasible => feasible,
        :total_p_load_shed => 0.0,
        :total_q_load_shed => 0.0,
        :vm => Dict{Int,Float64}(),
        :va => Dict{Int,Float64}(),
        :pg => Dict{Int,Float64}(),
        :qg => Dict{Int,Float64}(),
        :p => Dict{Tuple{Int,Int,Int},Float64}(),
        :q => Dict{Tuple{Int,Int,Int},Float64}(),
        :branch_status => copy(ctx[:branch_status]),
    )
    has_solution || return result

    for i in ctx[:bus_names]
        result[:vm][i] = value(model[:vm][i])
        result[:va][i] = value(model[:va][i])
    end
    for g in ctx[:gen_names]
        result[:pg][g] = value(model[:pg][g])
        result[:qg][g] = value(model[:qg][g])
    end
    for a in ctx[:arc_names]
        result[:p][a] = value(model[:p][a])
        result[:q][a] = value(model[:q][a])
    end
    if mode == "ACOPF"
        result[:p_load_shed] = Dict(i => max(0.0, value(model[:p_load_shed][i])) for i in ctx[:bus_names])
        result[:q_load_shed] = Dict(i => max(0.0, value(model[:q_load_shed][i])) for i in ctx[:bus_names])
        result[:total_p_load_shed] = sum(values(result[:p_load_shed]); init=0.0)
        result[:total_q_load_shed] = sum(values(result[:q_load_shed]); init=0.0)
    end

    return result
end

function _fixed_branch_status(ref::Dict, planning_results::Union{Dict,Nothing}, d::Int, l::Int)
    base_status = Int(get(ref[:branch][l], "br_status", 1) != 0)
    planning_results === nothing && return base_status

    if haskey(planning_results, :z)
        z = planning_results[:z]
        val = _dict_get_any(z, ((d, l), (string(d), string(l)), string((d, l))))
        val !== nothing && return Int(Float64(val) >= 0.5)
    end
    if haskey(planning_results, :switched_off_lines)
        off = _dict_get_any(planning_results[:switched_off_lines], (d, string(d)))
        if off !== nothing && l in Set(_to_int.(off))
            return 0
        end
    end
    return base_status
end

function _allocated_load_by_bus(planning_results::Union{Dict,Nothing}, buses)
    allocated = Dict{Int,Float64}()
    planning_results === nothing && return allocated
    haskey(planning_results, :allocated_load) || return allocated
    for bus in buses
        val = _dict_get_any(planning_results[:allocated_load], (bus, string(bus)))
        val === nothing || (allocated[bus] = Float64(val))
    end
    return allocated
end

function _planning_capacity_dict(planning_results::Union{Dict,Nothing}, keys_to_try)
    caps = Dict{Int,Float64}()
    planning_results === nothing && return caps
    for key in keys_to_try
        haskey(planning_results, key) || continue
        for (bus, val) in planning_results[key]
            v = Float64(val)
            if v > 1e-8
                caps[_to_int(bus)] = v
            end
        end
        return caps
    end
    return caps
end

function _lookup_dispatch(planning_results::Union{Dict,Nothing}, keys_to_try, d::Int, t::Int, idx::Int, default::Real)
    planning_results === nothing && return Float64(default)
    for key in keys_to_try
        haskey(planning_results, key) || continue
        val = _dict_get_any(planning_results[key], ((d, t, idx), (d, t, string(idx)), string((d, t, idx))))
        val === nothing || return Float64(val)
        container = planning_results[key]
        if container isa Containers.DenseAxisArray
            try
                return Float64(container[d, t, idx])
            catch
            end
        end
    end
    return Float64(default)
end

function _dict_get_any(dct, keys_to_try)
    for key in keys_to_try
        try
            haskey(dct, key) && return dct[key]
        catch
        end
    end
    return nothing
end

_to_int(x::Integer) = Int(x)
_to_int(x::AbstractString) = parse(Int, x)
_to_int(x) = Int(x)

function format_ac_output(results::Dict, params::Dict)
    output_format = params[:output_format]
    output_path = params[:output_path]

    if output_format == "dict"
        return results
    elseif output_format == "jld2"
        save_jld2(results, output_path)
        println("AC verification results saved to: $output_path")
        return results
    elseif output_format == "txt"
        save_ac_txt(results, output_path)
        println("AC verification results saved to: $output_path")
        return results
    else
        error("Unknown output format: $output_format")
    end
end

function save_ac_txt(results::Dict, filepath::String)
    dir = dirname(filepath)
    if !isempty(dir) && !isdir(dir)
        mkpath(dir)
    end

    open(filepath, "w") do io
        println(io, "AC VERIFICATION RESULTS")
        println(io, "=" ^ 80)
        println(io, "Network: $(results[:network])")
        println(io, "Mode: $(results[:mode])")
        println(io, "Days: $(results[:D])")
        println(io, "Hours per day: $(results[:T])")
        println(io, "Feasible all: $(results[:feasible_all])")
        println(io, "Total active load shed: $(results[:total_p_load_shed])")
        println(io, "Total reactive load shed: $(results[:total_q_load_shed])")
        println(io, "Failed hours: $(results[:failed_hours])")
        println(io)
        println(io, "[hour_status]")
        for key in sort(collect(keys(results[:status])))
            println(io, "$key => $(results[:status][key]), feasible=$(results[:feasible][key])")
        end
    end
end
