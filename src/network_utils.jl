"""
Utilities for working with PowerIO network dictionaries.
"""

"""
    calc_branch_t(branch::Dict) -> (Real, Real)

Calculate transformer tap components from tap ratio and phase shift.
"""
function calc_branch_t(branch::Dict{String,<:Any})
    tap_ratio = branch["tap"]
    angle_shift = branch["shift"]

    return tap_ratio * cos(angle_shift), tap_ratio * sin(angle_shift)
end

"""
    calc_branch_y(branch::Dict) -> (Real, Real)

Calculate branch conductance and susceptance from branch impedance.
"""
function calc_branch_y(branch::Dict{String,<:Any})
    y = LinearAlgebra.pinv(branch["br_r"] + im * branch["br_x"])
    return real(y), imag(y)
end

"""
    correct_voltage_angle_differences!(network_data::Dict)

Match the legacy MATPOWER data correction for unsupported angle bounds.
"""
function correct_voltage_angle_differences!(network_data::Dict{String,<:Any}; default_pad=1.0472)
    for (_, branch) in get(network_data, "branch", Dict{String,Any}())
        angmin = branch["angmin"]
        angmax = branch["angmax"]

        if angmin <= -pi / 2
            branch["angmin"] = -default_pad
        end

        if angmax >= pi / 2
            branch["angmax"] = default_pad
        end

        if angmin == 0.0 && angmax == 0.0
            branch["angmin"] = -default_pad
            branch["angmax"] = default_pad
        end
    end

    return network_data
end

function _component_dict(network_data::Dict{String,<:Any}, name::String)
    raw = get(network_data, name, Dict{String,Any}())
    return Dict(parse(Int, string(k)) => deepcopy(v) for (k, v) in raw)
end

"""
    build_ref(network_data::Dict) -> Dict

Build the subset of the network reference dictionary used by this package.
"""
function build_ref(network_data::Dict{String,<:Any})
    ref = Dict{Symbol,Any}()

    ref[:baseMVA] = network_data["baseMVA"]
    ref[:bus] = _component_dict(network_data, "bus")
    ref[:gen] = _component_dict(network_data, "gen")
    ref[:branch] = _component_dict(network_data, "branch")
    ref[:load] = _component_dict(network_data, "load")
    ref[:shunt] = _component_dict(network_data, "shunt")

    ref[:bus] = Dict(k => v for (k, v) in ref[:bus] if get(v, "bus_type", 1) != 4)
    active_buses = keys(ref[:bus])

    ref[:load] = Dict(k => v for (k, v) in ref[:load]
                      if get(v, "status", 1) != 0 && v["load_bus"] in active_buses)
    ref[:gen] = Dict(k => v for (k, v) in ref[:gen]
                     if get(v, "gen_status", 1) != 0 && v["gen_bus"] in active_buses)
    ref[:shunt] = Dict(k => v for (k, v) in ref[:shunt]
                       if get(v, "status", 1) != 0 && v["shunt_bus"] in active_buses)
    ref[:branch] = Dict(k => v for (k, v) in ref[:branch]
                        if get(v, "br_status", 1) != 0 &&
                           v["f_bus"] in active_buses &&
                           v["t_bus"] in active_buses)

    correct_voltage_angle_differences!(Dict("branch" => ref[:branch]))

    ref[:arcs_from] = [(i, branch["f_bus"], branch["t_bus"]) for (i, branch) in ref[:branch]]
    ref[:arcs_to] = [(i, branch["t_bus"], branch["f_bus"]) for (i, branch) in ref[:branch]]
    ref[:arcs] = [ref[:arcs_from]; ref[:arcs_to]]

    ref[:bus_loads] = Dict((i, Int[]) for (i, _) in ref[:bus])
    for (i, load) in ref[:load]
        push!(ref[:bus_loads][load["load_bus"]], i)
    end

    ref[:bus_shunts] = Dict((i, Int[]) for (i, _) in ref[:bus])
    for (i, shunt) in ref[:shunt]
        push!(ref[:bus_shunts][shunt["shunt_bus"]], i)
    end

    ref[:bus_gens] = Dict((i, Int[]) for (i, _) in ref[:bus])
    for (i, gen) in ref[:gen]
        push!(ref[:bus_gens][gen["gen_bus"]], i)
    end

    ref[:bus_arcs] = Dict((i, Tuple{Int,Int,Int}[]) for (i, _) in ref[:bus])
    for (l, i, j) in ref[:arcs]
        push!(ref[:bus_arcs][i], (l, i, j))
    end

    ref[:ref_buses] = Dict{Int,Any}(
        i => bus for (i, bus) in ref[:bus] if bus["bus_type"] == 3
    )

    return ref
end
