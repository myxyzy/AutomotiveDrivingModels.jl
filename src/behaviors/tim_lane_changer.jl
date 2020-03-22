"""
	TimLaneChanger
A simple lane change behavior that changes lanes whenever the lead car is going slower than our desired speed.
Lane changes are made when there is an available lane, fore/rear gaps exceed our thresholds, we are faster 
than a rear vehicle in the target lane, and any lead vehicle in the target lane is faster than we can currently go.

Has not been published anywhere, so first use in a paper would have to describe this.
See MOBIL if you want a lane changer you can cite.

# Constructors
	TimLaneChanger(v_des::Float64=29.0, threshold_fore::Float64 = 50.0,threshold_lane_change_gap_fore::Float64 = 10.0, threshold_lane_change_gap_rear::Float64 = 10.0,dir::Int=DIR_MIDDLE)

# Fields
- `dir::Int = DIR_MIDDLE` the desired lane to go to eg: left,middle (i.e. stay in same lane) or right
- `v_des::Float64 = 29.0` desired velocity
- `threshold_fore::Float64 = 50.0` Distance from lead vehicle
- `threshold_lane_change_gap_fore::Float64 = 10.0` Space in front
- `threshold_lane_change_gap_rear::Float64 = 10.0` Space rear
"""
@with_kw mutable struct TimLaneChanger <: LaneChangeModel{LaneChangeChoice}
    dir::Int = DIR_MIDDLE
    v_des::Float64 = 29.0
    threshold_fore::Float64 = 50.0
    threshold_lane_change_gap_fore::Float64 = 10.0
    threshold_lane_change_gap_rear::Float64 = 10.0
end

function set_desired_speed!(model::TimLaneChanger, v_des::Float64)
    model.v_des = v_des
    model
end

function observe!(model::TimLaneChanger, scene::Scene{Entity{S, D, I}}, roadway::Roadway, egoid::I) where {S, D, I}

    vehicle_index = findfirst(egoid, scene)

    veh_ego = scene[vehicle_index]
    v = vel(veh_ego.state)

    left_lane_exists = has_lane_left(roadway, veh_ego)
    right_lane_exists = has_lane_right(roadway, veh_ego)
    fore_M = find_neighbor(scene, roadway, veh_ego,
                          targetpoint_ego = VehicleTargetPointFront(), 
                          targetpoint_neighbor = VehicleTargetPointRear(),
                          max_distance = model.threshold_fore)
    fore_L = find_neighbor(scene, roadway, veh_ego,
                          targetpoint_ego = VehicleTargetPointFront(), 
                          targetpoint_neighbor = VehicleTargetPointRear(),
                          lane = leftlane(roadway, veh_ego)
                          )
    fore_R = find_neighbor(scene, roadway, veh_ego,
                          targetpoint_ego = VehicleTargetPointFront(), 
                          targetpoint_neighbor = VehicleTargetPointRear(),
                          lane = rightlane(roadway, veh_ego))
    rear_L = find_neighbor(scene, roadway, veh_ego,
                          targetpoint_ego = VehicleTargetPointFront(), 
                          targetpoint_neighbor = VehicleTargetPointRear(),
                          lane = leftlane(roadway, veh_ego), rear=true)
    rear_R = find_neighbor(scene, roadway, veh_ego,
                          targetpoint_ego = VehicleTargetPointFront(), 
                          targetpoint_neighbor = VehicleTargetPointRear(),
                          lane = rightlane(roadway, veh_ego), rear=true)

    model.dir = DIR_MIDDLE
    if fore_M.Δs < model.threshold_fore # there is a lead vehicle
        veh_M = scene[fore_M.ind]
        speed_M = vel(veh_M.state)
        if speed_M ≤ min(model.v_des, v) # they are driving slower than we want

            speed_ahead = speed_M

            # consider changing to a different lane
            if right_lane_exists &&
               fore_R.Δs > model.threshold_lane_change_gap_rear && # there is space rear
               rear_R.Δs > model.threshold_lane_change_gap_fore && # there is space fore
               (rear_R.ind == nothing || vel(scene[rear_R.ind].state) ≤ v) && # we are faster than any follower
               (fore_R.ind == nothing || vel(scene[fore_R.ind].state) > speed_ahead) # lead is faster than current speed

                speed_ahead = fore_R.ind != nothing ? vel(scene[fore_R.ind].state) : Inf
                model.dir = DIR_RIGHT
            end
            if left_lane_exists &&
               fore_L.Δs > model.threshold_lane_change_gap_rear && # there is space rear
               rear_L.Δs > model.threshold_lane_change_gap_fore && # there is space fore
               (rear_L.ind == nothing || vel(scene[rear_L.ind].state) ≤ v) && # we are faster than any follower
               (fore_L.ind == nothing || vel(scene[fore_L.ind].state) > speed_ahead) # lead is faster than current speed

                speed_ahead = fore_L.ind != nothing ? vel(scene[fore_L.ind].state) : Inf
                model.dir = DIR_LEFT
            end
        end
    end

    model
end

Base.rand(rng::AbstractRNG, model::TimLaneChanger) = LaneChangeChoice(model.dir)
