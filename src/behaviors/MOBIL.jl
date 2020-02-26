"""
    MOBIL
See Treiber & Kesting, 'Modeling Lane-Changing Decisions with MOBIL'

# Constructor
	MOBIL(timestep::Float64;rec::SceneRecord=SceneRecord(2,timestep), mlon::LaneFollowingDriver=IntelligentDriverModel(),safe_decel::Float64=2.0,       politeness::Float64=0.35,advantage_threshold::Float64=0.1)

# Fields
- `dir::Int`
- `rec::SceneRecord`
- `mlon::LaneFollowingDriver=IntelligentDriverModel()`
- `safe_decel::Float64=2.0`
- `politeness::Float64=0.35`
- `advantage_threshold::Float64=0.1`
"""
@with_kw mutable struct MOBIL <: LaneChangeModel{LaneChangeChoice}
    dir::Int64
    rec::SceneRecord
    mlon::LaneFollowingDriver
    safe_decel::Float64 # safe deceleration (positive value)
    politeness::Float64 # politeness factor (suggested p ∈ [0.2,0.5])
    advantage_threshold::Float64 # Δaₜₕ
end

function MOBIL(
    timestep::Float64;
    rec::SceneRecord=SceneRecord(2,timestep),
    mlon::LaneFollowingDriver=IntelligentDriverModel(),
    safe_decel::Float64=2.0, # [m/s²]
    politeness::Float64=0.35,
    advantage_threshold::Float64=0.1,
    )
    return MOBIL(DIR_MIDDLE, rec, mlon, safe_decel, politeness, advantage_threshold)
end

"""
Return the name of the lane changing model
"""
get_name(::MOBIL) = "MOBIL"

"""
Set the desired speed of the longitudinal model within MOBIL
"""
function set_desired_speed!(model::MOBIL, v_des::Float64)
    set_desired_speed!(model.mlon, v_des)
    model
end
function observe!(model::MOBIL, scene::Frame{Entity{S, D, I}}, roadway::Roadway, egoid::I) where {S, D, I}
    # print("MOBIL: observe! has been called\n")
    rec = model.rec
    update!(rec, scene)

    vehicle_index = findfirst(egoid, rec[0])
    veh_ego = scene[vehicle_index]
    v = vel(veh_ego.state)
    egostate_M = veh_ego.state

    left_lane_exists = convert(Float64, get(N_LANE_LEFT, rec, roadway, vehicle_index)) > 0
    right_lane_exists = convert(Float64, get(N_LANE_RIGHT, rec, roadway, vehicle_index)) > 0
    fore_M = get_neighbor_fore_along_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointRear(), VehicleTargetPointFront())
    rear_M = get_neighbor_rear_along_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointFront(), VehicleTargetPointRear())

    # accel if we do not make a lane change
    accel_M_orig = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, egoid)).a
    model.dir = DIR_MIDDLE

    advantage_threshold = model.advantage_threshold

    if left_lane_exists
    # print("MOBIL: left lane exists\n")
        rear_L = get_neighbor_rear_along_left_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointFront(), VehicleTargetPointRear())

        # candidate position after lane change is over
        footpoint = get_footpoint(veh_ego)
        lane = get_lane(roadway, veh_ego) 
        lane_L = roadway[LaneTag(lane.tag.segment, lane.tag.lane + 1)]
        roadproj = proj(footpoint, lane_L, roadway)
        frenet_L = Frenet(RoadIndex(roadproj), roadway)
        egostate_L = VehicleState(frenet_L, roadway, vel(veh_ego.state))

        Δaccel_n = 0.0
        passes_safety_criterion = true
        if rear_L.ind != nothing
            id = scene[rear_L.ind].id
            accel_n_orig = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a

            # update ego state in scene
            scene[vehicle_index] = Entity(veh_ego, egostate_L)
            accel_n_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a

            body = inertial2body(get_rear(scene[vehicle_index]), get_front(scene[rear_L.ind])) # project ego to be relative to target
            s_gap = body.x
            
            # restore ego state
            scene[vehicle_index] = veh_ego
            passes_safety_criterion = accel_n_test ≥ -model.safe_decel && s_gap ≥ 0
            Δaccel_n = accel_n_test - accel_n_orig
        end

        if passes_safety_criterion

            Δaccel_o = 0.0
            if rear_M.ind != nothing
                id = scene[rear_M.ind].id
                accel_o_orig = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a
                
                # update ego state in scene
                scene[vehicle_index] = Entity(veh_ego, egostate_L)
                accel_o_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a
                
                # restore ego state
                scene[vehicle_index] = veh_ego
                Δaccel_o = accel_o_test - accel_o_orig
            end

            # update ego state in scene
            scene[vehicle_index] = Entity(veh_ego, egostate_L)
            accel_M_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, egoid)).a
            # restore ego state
            scene[vehicle_index] = veh_ego

            Δaccel_M = accel_M_test - accel_M_orig

            Δaₜₕ = Δaccel_M + model.politeness*(Δaccel_n + Δaccel_o)

            if Δaₜₕ > advantage_threshold
                model.dir = DIR_LEFT
                advantage_threshold = Δaₜₕ
            end
        end
    end

    if right_lane_exists
    # print("MOBIL:right lane exists \n")
        rear_R = get_neighbor_rear_along_right_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointFront(), VehicleTargetPointRear())

        # candidate position after lane change is over
        footpoint = get_footpoint(veh_ego)
        lane = roadway[veh_ego.state.posF.roadind.tag]
        lane_R = roadway[LaneTag(lane.tag.segment, lane.tag.lane - 1)]
        roadproj = proj(footpoint, lane_R, roadway)
        frenet_R = Frenet(RoadIndex(roadproj), roadway)
        egostate_R = VehicleState(frenet_R, roadway, vel(veh_ego.state))

        Δaccel_n = 0.0
        passes_safety_criterion = true
        if rear_R.ind != nothing
            id = scene[rear_R.ind].id
            accel_n_orig = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a

            # update ego vehicle in scene
            scene[vehicle_index] = Entity(veh_ego, egostate_R)
            accel_n_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a

            body = inertial2body(get_rear(scene[vehicle_index]), get_front(scene[rear_R.ind])) # project ego to be relative to target
            s_gap = body.x

            # restore ego vehicle state
            scene[vehicle_index] = veh_ego

            passes_safety_criterion = accel_n_test ≥ -model.safe_decel && s_gap ≥ 0
            Δaccel_n = accel_n_test - accel_n_orig
        end

        if passes_safety_criterion

            Δaccel_o = 0.0
            if rear_M.ind != nothing
                id = scene[rear_M.ind].id
                accel_o_orig = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a

                # update ego vehicle in scene
                scene[vehicle_index] = Entity(veh_ego, egostate_R)
                accel_o_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, id)).a
                # restore ego vehicle state
                scene[vehicle_index] = veh_ego

                Δaccel_o = accel_o_test - accel_o_orig
            end

            # update ego vehicle in scene
            scene[vehicle_index] = Entity(veh_ego, egostate_R)
            accel_M_test = rand(observe!(reset_hidden_state!(model.mlon), scene, roadway, egoid)).a
            # restor ego vehicle state
            scene[vehicle_index] = veh_ego
            
            Δaccel_M = accel_M_test - accel_M_orig

            Δaₜₕ = Δaccel_M + model.politeness*(Δaccel_n + Δaccel_o)
            if Δaₜₕ > advantage_threshold
                model.dir = DIR_RIGHT
                advantage_threshold = Δaₜₕ
            elseif Δaₜₕ == advantage_threshold
                # in case of tie, if we are accelerating we go left, else, right
                if Δaccel_M > model.politeness*(Δaccel_n + Δaccel_o)
                    model.dir = DIR_LEFT
                else
                    model.dir = DIR_RIGHT
                end
            end
        end
    end

    model
end
Base.rand(rng::AbstractRNG, model::MOBIL) = LaneChangeChoice(model.dir)
