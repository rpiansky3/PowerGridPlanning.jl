"""
Utilities for working with PowerIO network dictionaries.
"""

_ref_key(k::Integer) = Int(k)
_ref_key(k::AbstractString) = parse(Int, k)
_ref_key(k) = Int(k)

"""
    build_ref(network_data::Dict) -> Dict{Symbol,Any}

Build the reference dictionary used by the optimization models from a
PowerModels-style dictionary returned by `PowerIO.to_powermodels`.
"""
function build_ref(network_data::Dict)
    ref = Dict{Symbol,Any}()

    ref[:baseMVA] = network_data["baseMVA"]
    ref[:bus] = Dict(_ref_key(k) => v for (k, v) in get(network_data, "bus", Dict()))
    ref[:gen] = Dict(_ref_key(k) => v for (k, v) in get(network_data, "gen", Dict()))
    ref[:branch] = Dict(_ref_key(k) => v for (k, v) in get(network_data, "branch", Dict()))
    ref[:load] = Dict(_ref_key(k) => v for (k, v) in get(network_data, "load", Dict()))
    ref[:shunt] = Dict(_ref_key(k) => v for (k, v) in get(network_data, "shunt", Dict()))

    ref[:bus_loads] = Dict(bus => Int[] for bus in keys(ref[:bus]))
    for (load_id, load) in ref[:load]
        bus = _ref_key(load["load_bus"])
        push!(get!(ref[:bus_loads], bus, Int[]), load_id)
    end

    ref[:bus_gens] = Dict(bus => Int[] for bus in keys(ref[:bus]))
    for (gen_id, gen) in ref[:gen]
        bus = _ref_key(gen["gen_bus"])
        push!(get!(ref[:bus_gens], bus, Int[]), gen_id)
    end

    ref[:bus_shunts] = Dict(bus => Int[] for bus in keys(ref[:bus]))
    for (shunt_id, shunt) in ref[:shunt]
        bus = _ref_key(shunt["shunt_bus"])
        push!(get!(ref[:bus_shunts], bus, Int[]), shunt_id)
    end

    ref[:arcs] = Tuple{Int,Int,Int}[]
    ref[:arcs_from] = Tuple{Int,Int,Int}[]
    ref[:arcs_to] = Tuple{Int,Int,Int}[]
    ref[:bus_arcs] = Dict(bus => Tuple{Int,Int,Int}[] for bus in keys(ref[:bus]))
    for (branch_id, branch) in ref[:branch]
        f_bus = _ref_key(branch["f_bus"])
        t_bus = _ref_key(branch["t_bus"])
        f_arc = (branch_id, f_bus, t_bus)
        t_arc = (branch_id, t_bus, f_bus)
        push!(ref[:arcs], f_arc)
        push!(ref[:arcs], t_arc)
        push!(ref[:arcs_from], f_arc)
        push!(ref[:arcs_to], t_arc)
        push!(get!(ref[:bus_arcs], f_bus, Tuple{Int,Int,Int}[]), f_arc)
        push!(get!(ref[:bus_arcs], t_bus, Tuple{Int,Int,Int}[]), t_arc)
    end

    ref[:ref_buses] = Dict(
        bus_id => bus for (bus_id, bus) in ref[:bus]
        if get(bus, "bus_type", 1) == 3
    )
    if isempty(ref[:ref_buses]) && !isempty(ref[:bus])
        first_bus = first(sort(collect(keys(ref[:bus]))))
        ref[:ref_buses][first_bus] = ref[:bus][first_bus]
    end

    return ref
end

"""
    calc_branch_y(branch::Dict) -> (Float64, Float64)

Return branch series conductance and susceptance from resistance/reactance.
"""
function calc_branch_y(branch::Dict)
    r = Float64(branch["br_r"])
    x = Float64(branch["br_x"])
    y = inv(complex(r, x))
    return real(y), imag(y)
end

"""
    calc_branch_t(branch::Dict) -> (Float64, Float64)

Return the real and imaginary transformer tap components used by the AC branch
flow equations.
"""
function calc_branch_t(branch::Dict)
    tap = Float64(get(branch, "tap", 1.0))
    tap == 0.0 && (tap = 1.0)
    shift = Float64(get(branch, "shift", 0.0))
    return tap * cos(shift), tap * sin(shift)
end

"""
    correct_voltage_angle_differences!(network_data::Dict) -> Dict

Normalize missing or zero branch angle-difference limits to the conventional
MATPOWER default of +/- pi/2 radians.
"""
function correct_voltage_angle_differences!(network_data::Dict)
    for branch in values(get(network_data, "branch", Dict()))
        angmin = Float64(get(branch, "angmin", 0.0))
        angmax = Float64(get(branch, "angmax", 0.0))
        if angmin == 0.0 && angmax == 0.0
            branch["angmin"] = -pi / 2
            branch["angmax"] = pi / 2
        end
    end
    return network_data
end

"""
    islanded_buses_for_branch_status(ref::Dict, branch_status::Dict) -> Vector{Int}

Return buses disconnected from every reference bus under the supplied branch
status map, where status 1 means energized and status 0 means out of service.
"""
function islanded_buses_for_branch_status(ref::Dict, branch_status::Dict)
    bus_names = sort(collect(keys(ref[:bus])))
    adjacency = Dict(i => Int[] for i in bus_names)

    for (l, branch) in ref[:branch]
        get(branch_status, l, 1) == 1 || continue

        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        haskey(adjacency, f_bus) && haskey(adjacency, t_bus) || continue

        push!(adjacency[f_bus], t_bus)
        push!(adjacency[t_bus], f_bus)
    end

    visited = Set{Int}()
    queue = collect(keys(ref[:ref_buses]))
    idx = 1
    while idx <= length(queue)
        bus = queue[idx]
        idx += 1

        bus in visited && continue
        push!(visited, bus)

        for neighbor in get(adjacency, bus, Int[])
            neighbor in visited || push!(queue, neighbor)
        end
    end

    return [bus for bus in bus_names if !(bus in visited)]
end
