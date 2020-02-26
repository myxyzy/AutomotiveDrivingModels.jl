"""
	Tim2DDriver
Driver that combines longitudinal driver and lateral driver into one model.

# Constructors
	Tim2DDriver(timestep::Float64;mlon::LaneFollowingDriver=IntelligentDriverModel(), mlat::LateralDriverModel=ProportionalLaneTracker(), mlane::LaneChangeModel=TimLaneChanger(timestep),rec::SceneRecord = SceneRecord(1, timestep))

# Fields
- `rec::SceneRecord` A record that will hold the resulting simulation results
- `mlon::LaneFollowingDriver = IntelligentDriverModel()` Longitudinal driving model
- `mlat::LateralDriverModel = ProportionalLaneTracker()` Lateral driving model
- `mlane::LaneChangeModel =TimLaneChanger` Lane change model
"""
mutable struct Tim2DDriver <: DriverModel{LatLonAccel}
    rec::SceneRecord
    mlon::LaneFollowingDriver
    mlat::LateralDriverModel
    mlane::LaneChangeModel
end
function Tim2DDriver(
        timestep::Float64;
        mlon::LaneFollowingDriver=IntelligentDriverModel(),
        mlat::LateralDriverModel=ProportionalLaneTracker(),
        mlane::LaneChangeModel=TimLaneChanger(timestep),
        rec::SceneRecord = SceneRecord(1, timestep)
        )
    return Tim2DDriver(rec, mlon, mlat, mlane)
end

get_name(::Tim2DDriver) = "Tim2DDriver"
function set_desired_speed!(model::Tim2DDriver, v_des::Float64)
    set_desired_speed!(model.mlon, v_des)
    set_desired_speed!(model.mlane, v_des)
    model
end
function track_longitudinal!(driver::LaneFollowingDriver, scene::Frame{Entity{VehicleState, D, I}}, roadway::Roadway, vehicle_index::I, fore::NeighborLongitudinalResult) where {D, I}
    v_ego = vel(scene[vehicle_index].state)
    print("ego id = $(scene[vehicle_index].id)\n")
    if fore.ind != nothing
        headway, v_oth = fore.Δs, vel(scene[fore.ind].state)
        print("guy in front index = $(scene[fore.ind].id)\n")
    else
        headway, v_oth = NaN, NaN
        print("No guy in front \n")
    end
    
    return track_longitudinal!(driver, v_ego, v_oth, headway)
end
function observe!(driver::Tim2DDriver, scene::Frame{Entity{S, D, I}}, roadway::Roadway, egoid::I) where {S, D, I}
    print("Tim2DDriver observe! says egoid = $(egoid)\n")
    update!(driver.rec, scene)
    observe!(driver.mlane, scene, roadway, egoid)

    vehicle_index = findfirst(egoid, scene)
    lane_change_action = rand(driver.mlane)
    laneoffset = get_lane_offset(lane_change_action, driver.rec, roadway, vehicle_index)
    lateral_speed = convert(Float64, get(VELFT, driver.rec, roadway, vehicle_index))

    if lane_change_action.dir == DIR_MIDDLE
        fore = get_neighbor_fore_along_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointRear(), VehicleTargetPointFront())
    elseif lane_change_action.dir == DIR_LEFT
        fore = get_neighbor_fore_along_left_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointRear(), VehicleTargetPointFront())
    else
        @assert(lane_change_action.dir == DIR_RIGHT)
        fore = get_neighbor_fore_along_right_lane(scene, vehicle_index, roadway, VehicleTargetPointFront(), VehicleTargetPointRear(), VehicleTargetPointFront())
    end

    track_lateral!(driver.mlat, laneoffset, lateral_speed)
    print("Tim2DDriver observe! says: Lateral stuff done. Now I will call longitudinal observe!\n")
    track_longitudinal!(driver.mlon, scene, roadway, vehicle_index, fore)

    driver
end
Base.rand(rng::AbstractRNG, driver::Tim2DDriver) = LatLonAccel(rand(rng, driver.mlat), rand(rng, driver.mlon).a)
Distributions.pdf(driver::Tim2DDriver, a::LatLonAccel) = pdf(driver.mlat, a.a_lat) * pdf(driver.mlon, a.a_lon)
Distributions.logpdf(driver::Tim2DDriver, a::LatLonAccel) = logpdf(driver.mlat, a.a_lat) * logpdf(driver.mlon, a.a_lon)
