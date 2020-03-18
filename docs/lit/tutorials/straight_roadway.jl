# # Driving on a Straight Roadway

#md # [![](https://img.shields.io/badge/show-nbviewer-579ACA.svg)](@__NBVIEWER_ROOT_URL__/notebooks/straight_roadway.ipynb)

# This example demonstrates a simple, one-dimensional driving simulation in which
# cars drive along a straight roadway.
# The types are:
#
# - `S` - `State1D`, containing the vehicle position and speed
# - `D` - `VehicleDef`, containing length, width, and class
# - `I` - `Int`, a unique label for each vehicle`
#
# We use a `StraightRoadway` as our environment and `LaneFollowingDriver`s that produce `LaneFollowingAccel`s.

using AutomotiveDrivingModels
using AutoViz
AutoViz.colortheme["background"] = colorant"white"; # hide

roadway = StraightRoadway(200.)  # 200m long straight roadway
scene = Scene1D([
    Entity(State1D(10.0,  8.0), VehicleDef(), 1),
    Entity(State1D(50.0, 12.5), VehicleDef(), 2),
    Entity(State1D(150.0, 6.0), VehicleDef(), 3),
])

camera = StaticCamera(position=VecE2(100.0,0.0), zoom=4.75, canvas_height=100)
renderables = [roadway, scene]::Vector{Any}
snapshot = render(renderables, camera=camera)
#md write("straight_roadway.svg", snapshot) # hide
#md # ![three cars on road](straight_roadway.svg)

# In this call to the `render` function, we use the default rendering behavior for
# entities. More advanced examples will show how the rendering of entities can be customized.

# We can add an overlay that displays the car id:

for veh in scene
    push!(renderables,
        TextOverlay(text=["$(veh.id)"], coordinate_system=:scene, pos=VecE2(veh.state.s-0.7, 3))
    )
end
snapshot = render(renderables, camera=camera)
#md write("straight_roadway_with_id.svg", snapshot) # hide
#md # ![three cars with id](straight_roadway_with_id.svg)


# Alternatively, we can create a new `SceneOverlay` object which takes care of
# displaying information for us:

using Parameters
@with_kw struct CarIDOverlay <: SceneOverlay
    scene::Scene1D
    roadway::StraightRoadway
    textparams::TextParams=TextParams()
end
function AutoViz.add_renderable!(rendermodel::RenderModel, overlay::CarIDOverlay)
    for veh in overlay.scene
        x = veh.state.s - 0.7
        y = 3.0
        text = string(veh.id)
        add_instruction!(rendermodel, render_text, (text, x, y, overlay.textparams.size, overlay.textparams.color), coordinate_system=:scene)
    end
    return rendermodel
end

snapshot = render([roadway, scene, CarIDOverlay(scene=scene, roadway=roadway)], camera=camera)
#md write("straight_roadway_with_overlay.svg", snapshot) # hide
#md # ![three vehicles with custom overlay](straight_roadway_with_overlay.svg)


# To run a simulation we need driving models that produce actions.
# For this we will use `LaneFollowingDriver`s that produce `LaneFollowingAccel`s.
# For this demo, we will give each car a different model.

models = Dict{Int, LaneFollowingDriver}(
    1 => StaticLaneFollowingDriver(0.0), # always produce zero acceleration
    2 => IntelligentDriverModel(v_des=12.0), # default IDM with a desired speed of 12 m/s
    3 => PrincetonDriver(v_des = 10.0), # default Princeton driver with a desired speed of 10m/s
)

nticks = 100
timestep = 0.1
scenes = simulate(scene, roadway, models, nticks, timestep)
#md nothing # hide

# We can visualize the simulation as a sequence of images, for example using the
# `Reel` package

using Reel

animation = roll(fps=1.0/timestep, duration=nticks*timestep) do t, dt
    i = Int(floor(t/dt)) + 1
    renderables = [roadway, scenes[i], CarIDOverlay(scene=scenes[i], roadway=roadway)]
    render(renderables, camera=camera)
end
#md write("straight_roadway_animated.gif", animation) # hide
#md nothing # hide
#md # ![three vehicles animated](straight_roadway_animated.gif)

# In order to inspect the simulation interactively, we can use the `Interact` package

#md using Interact
#md using Blink
#md using ElectronDisplay
#md
#md w = Window()
#md viz = @manipulate for step in 1 : length(scenes)
#md     renderables = [roadway, scenes[step], CarIDOverlay(scene=scenes[step], roadway=roadway)]
#md     render(renderables, camera=camera)
#md end
#md body!(w, viz)
