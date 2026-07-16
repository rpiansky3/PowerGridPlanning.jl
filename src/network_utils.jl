"""
Utilities for working with PowerIO network dictionaries.
"""

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
