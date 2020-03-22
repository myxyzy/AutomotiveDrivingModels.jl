"""
    propagate(veh::Entity{S,D,I}, action::A, roadway::R, Δt::Float64) where {S,D,I,A,R}

Take an entity of type {S,D,I} and move it over Δt seconds to produce a new
entity based on the action on the given roadway.
"""
propagate(veh::Entity{S,D,I}, action::A, roadway::R, Δt::Float64) where {S,D,I,A,R} = error("propagate not implemented for Entity{$S, $D, $I}, actions $A, and roadway $R")

propagate(veh::Entity{S,D,I}, state::S, roadway::R, Δt::Float64) where {S,D,I,R} = state

"""
Mapping from actions to entity ids. The main use case is for keeping track of the action history
in the same way as the scene history in the `simulate!` function.

Initialize as

    EntityAction(a, id)

where `a` is an action which can be used to propagate entities. `id` is the entity identifier.
"""
struct EntityAction{A,I}
    action::A
    id::I
end

function Base.findfirst(id, scene::Scene{A}) where {A<:EntityAction}
    for am_index in 1 : scene.n
        am = scene.entities[am_index]
        if am.id == id
            return am_index
        end
    end
    return nothing
end

function id2index(scene::Scene{A}, id) where {A<:EntityAction}
    entity_index = findfirst(id, scene)
    if (entity_index === nothing)
        throw(BoundsError(scene, [id]))
    end
    return entity_index
end

get_by_id(scene::Scene{A}, id) where {A<:EntityAction} = scene[id2index(scene, id)] 
