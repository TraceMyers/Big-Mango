
spawn_swinging_door :: (floor_location: Vector3, forward_direction: Vector3, color: Color4f, half_height := 14.0, half_width := 14.0 * (3./5.)) -> *Entity {
    center := floor_location + WORLD_UP * half_height;

    orientation: Quaternion;
    assert(forward_direction.z == 0);
    assert(is_normalized(forward_direction.xy));
    set_orientation(*orientation, forward_direction, WORLD_UP);

    door := spawn_gadget(
        "door", 
        .{
            gadget_type=.DOOR, 
            door = .{pivot_local_offset = .{x=half_width}}
        },
        center = center,
        orientation = orientation,
        event_volume_extent = .{half_width * 2 + 5, half_width * 2 + 5, half_height * 2}
    );

    set_shape_and_mass(door, .{type=.RECT, rect=.{half_height, half_width, true}}, IMMOVABLE_ENTITY_MASS);
    door.collision_mesh_albedo.tint = color;
    door.door.closed_orientation = door.orientation;

    return door;
}