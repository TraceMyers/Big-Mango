
Entity :: struct {
    scale := 1.0;
    position: Vector3;
    orientation: Quaternion;
}

Static_Mesh_Entity :: struct {
    using #as entity: Entity;
    mesh: s32;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// methods

set_orientation :: inline (e: *Entity, forward: Vector3, right: Vector3) {
    set_orientation(*e.orientation, forward, right);
}

rotate :: inline (e: *Entity, axis: Vector3, angle_degrees: float32) {
    rotate(*e.orientation, axis, angle_degrees);
}

right_direction :: inline (e: *Entity) -> Vector3 {
    return right_direction(*e.orientation);
}

right_direction_xy :: inline (e: *Entity) -> Vector3 {
    right_3d := right_direction(e);
    right_3d.z = 0;
    return normalize(right_3d);
}

up_direction :: inline (e: *Entity) -> Vector3 {
    return up_direction(*e.orientation);
}

fore_direction :: inline (e: *Entity) -> Vector3 {
    return fore_direction(*e.orientation);
}

interp_rotate :: inline (e: *Entity, target: Quaternion, norm: float32) {
    e.orientation = interp_rotate(e.orientation, target, norm);
}

interp_rotate :: inline (e: *Entity, target: Quaternion, speed: float32, delta_time: float32) {
    e.orientation = interp_rotate(e.orientation, target, speed, delta_time);
}

static_mesh_entities: Pool(Static_Mesh_Entity);