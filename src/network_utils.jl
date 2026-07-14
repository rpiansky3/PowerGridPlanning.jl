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
    return PowerIO.correct_voltage_angle_differences!(
        network_data;
        default_pad=default_pad,
    )
end

"""
    build_ref(network_data::Dict) -> Dict

Build the subset of the network reference dictionary used by this package.
"""
function build_ref(network_data::Dict{String,<:Any})
    return PowerIO.build_ref(network_data)
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
