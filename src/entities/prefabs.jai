
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

    cube_mesh := get_or_load_mesh(*MESH_CUBE);
    set_meshes(door, .[.{data=cube_mesh, albedo=.{tint=color}, scale=.{half_width*2, half_width*0.1, half_height*2},
    }]);

    return door;
}

spawn_button :: (location: Vector3, forward_direction: Vector3, base_color: Color4f, button_color: Color4f) -> *Entity {
    orientation: Quaternion;
    assert(forward_direction.z == 0);
    assert(is_normalized(forward_direction.xy));
    set_orientation(*orientation, forward_direction, WORLD_UP);

    button := spawn_gadget(
        "button", 
        .{
            gadget_type=.BUTTON, 
            button=.{}
        }, 
        location,
        orientation
    );

    radius := 0.5;
    half_height := 0.8;

    set_shape_and_mass(button, .{type=.CAPSULE, capsule=.{half_height, radius}}, IMMOVABLE_ENTITY_MASS);
    button.collision_mesh_albedo.tint = .{g=0.8};
    capsule_mesh := get_or_create_capsule_mesh(half_height*2, radius);
    cube := get_or_load_mesh(*MESH_CUBE);
    set_meshes(button, .[
        .{data=cube, albedo=.{tint=base_color}, scale=.{1.5,1.5,2.0}, offset=.{z=-0.7}},
        .{data=capsule_mesh, albedo=.{tint=button_color}}
    ]);
    set(*button.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT);

    return button;
}

spawn_wall :: (location: Vector3, color: Color4f, scale := 10.0) -> *Entity {
    wall := spawn_entity("wall", .[], location);
    set_shape_and_mass(wall, .{type=.RECT, rect=.{scale*0.5, scale*0.5, true}}, IMMOVABLE_ENTITY_MASS);
    cube := get_or_load_mesh(*MESH_CUBE);
    set_meshes(wall, .[
        .{data=cube, albedo=.{tint=color}, scale=.{scale, scale*(1./200), scale}}
    ]);
    return wall;
}

spawn_floor :: (location: Vector3, color: Color4f, scale := 10.0) -> *Entity {
    orientation: Quaternion;
    set_orientation(*orientation, .{0,0,1}, .{1,0,0});
    floor := spawn_entity("floor", .[], location, orientation);
    set_shape_and_mass(floor, .{type=.RECT, rect=.{scale*0.5, scale*0.5, false}}, IMMOVABLE_ENTITY_MASS);
    cube := get_or_load_mesh(*MESH_CUBE);
    set_meshes(floor, .[
        .{data=cube, albedo=.{tint=color}, scale=.{scale, scale*(1./200), scale}}
    ]);

    return floor;
}

spawn_ball :: (location: Vector3, color: Color4f, radius := 3.0) -> *Entity {
    ball := spawn_entity("ball", .[.PHYSICS_DRIVEN_ROTATION, .APPLY_GRAVITY, .ACCELERATE_IN_3D, .CAN_BE_HELD], location);

    // just having some fun making mass a function of radius
    MASS_FACTOR :: 3.0 / PI; // the factor that takes an input radius of 0.5 and outputs a mass of 0.5
    radius_cubed := radius * radius * radius;
    sphere_volume := (4./3) * PI * radius_cubed;
    mass := sphere_volume * MASS_FACTOR;

    set_shape_and_mass(ball, .{type=.SPHERE, sphere=.{radius}}, mass);

    sphere := get_or_load_mesh(*MESH_SPHERE_MID_POLY);
    set_meshes(ball, .[
        .{data=sphere, albedo=.{tint=color}, scale=.{radius, radius, radius}}
    ]);

    ball.physics_properties.elasticity = 0.9;
    ball.physics_properties.linear_speed_max = 1000;

    return ball;
}