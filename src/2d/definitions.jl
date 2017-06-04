export
    BicycleModel

immutable BicycleModel
    def::VehicleDef
    a::Float64 # distance between cg and front axle, typically positive [m]
    b::Float64 # distance between cg and rear axle, typically positive [m]
end
function BicycleModel(def::VehicleDef;
    a::Float64 = 1.5,
    b::Float64 = 1.5,
    )

    return BicycleModel(def, a, b)
end