
spawn_human :: (name: string, center := Vector3.{}, sphere_radius := 10.0, orientation := QUATERNION_IDENTITY) -> *Entity {
    default_props := Physics_Properties.{
        linear_acceleration=500,
        linear_speed_max=35
    };

    e := spawn_entity(name, .[.MOVED_BY_PHYSICS, .APPLY_GRAVITY], center, orientation, default_props);
    e.physics_properties.elasticity = 0.09;

    set_shape_and_mass(e, .{type=.SPHERE, sphere=.{radius=sphere_radius}}, 1);

    mesh := get_or_load_mesh(*MESH_FINALBASEMESH);
    set_meshes(e, .[.{data=mesh, albedo=.{tint=.{0.7,0.7,0.9,1.0}}}]);

    set(*e.flags, .CAN_INTERACT_WITH_GADGETS_IN_PROXIMITY);

    return e;
}

spawn_camera :: (name: string, center := Vector3.{}, orientation := QUATERNION_IDENTITY) -> *Entity {
    e := spawn_entity(name, .[.USES_CAMERA, .ACCELERATE_IN_3D, .APPLY_AIR_FRICTION, .MOVED_BY_PHYSICS, .DOES_NOT_DIE_TO_Z_FLOOR], center, orientation);
    e.collision_channels = 0;
    e.physics_properties.linear_acceleration = 400;
    e.physics_properties.air_friction_multiplier = 3.0;
    e.physics_properties.linear_speed_max = 50;
    return e;
}

// also spawns an owned event volume
spawn_gadget :: (name: string, in_gadget: Gadget, center := Vector3.{}, orientation := Quaternion.{}, event_volume_extent := Vector3.{10,10,10}, event_volume_offset := Vector3.{}, event_volume_offset_is_local := true) -> *Entity {
    gadget := spawn_entity(name, .[.USES_GADGET], center=center, orientation=orientation);
    gadget.gadget = in_gadget;
    gadget.ray_channels = .GADGET;
    gadget.overlap_channels = 0;

    volume := spawn_entity(tprint("%'s event volume", name), .[.USES_EVENT_VOLUME]);
    // initialize event volume that keeps track of which entities are within range
    {
        volume.ray_channels = 0;
        volume.collision_channels = 0;
        volume.overlap_channels = ALL_OVERLAP_CHANNELS;
        set_shape_and_mass(volume, .{type=.AABB, aabb=.{extent=event_volume_extent}}, IMMOVABLE_ENTITY_MASS);
        if event_volume_offset_is_local {
            set(*volume.flags, .EVENT_VOLUME_OFFSET_IS_LOCAL);
        }

        using volume.event_volume;
        on_begin_overlap = .ON_GADGET_EVENT_VOLUME_BEGIN_OVERLAP;
        on_end_overlap = .ON_GADGET_EVENT_VOLUME_END_OVERLAP;
        attached_to = gadget.ref;
        offset_from_attachment = event_volume_offset;

        set_event_volume_center(volume, gadget, offset_from_attachment);
    }

    gadget.gadget_interaction_volume = volume.ref;

    if in_gadget.gadget_type == {
    case .DOOR;
    case .BUTTON;
        gadget.delay_interacting_with_gadgets = .{type=.BY_DISTANCE, value=.{by_distance=.{constant=0.1, time_per_unit=0.003}}};
    }

    return gadget;
}


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
    set_meshes(door, .[
        .{data=cube_mesh, albedo=.{tint=color}, scale=.{half_width*2, half_width*0.1, half_height*2}, flags=.IS_COLLISION_SHAPE_PARENT}
    ]);

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
        .{data=capsule_mesh, albedo=.{tint=button_color}, flags=.IS_COLLISION_SHAPE_PARENT}
    ]);
    set(*button.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT);

    return button;
}

spawn_wall :: (location: Vector3, color: Color4f, scale := 10.0) -> *Entity {
    wall := spawn_entity("wall", .[], location);
    set_shape_and_mass(wall, .{type=.RECT, rect=.{scale*0.5, scale*0.5, true}}, IMMOVABLE_ENTITY_MASS);
    cube := get_or_load_mesh(*MESH_CUBE);
    set_meshes(wall, .[
        .{data=cube, albedo=.{tint=color}, scale=.{scale, scale*(1./200), scale}, flags=.IS_COLLISION_SHAPE_PARENT}
    ]);
    return wall;
}

spawn_floor :: (location: Vector3, color: Color4f, scale := 10.0) -> *Entity {
    orientation: Quaternion;
    set_orientation(*orientation, .{0,0,1}, .{1,0,0});
    floor := spawn_entity("floor", .[], location, orientation);
    set_shape_and_mass(floor, .{type=.RECT, rect=.{scale*0.5, scale*0.5, false}}, IMMOVABLE_ENTITY_MASS);

    plane := get_or_load_mesh(*MESH_PLANE);
    set_meshes(floor, .[
        .{data=plane, albedo=.{tint=color}, scale=.{scale, 1.0, scale}, flags=.IS_COLLISION_SHAPE_PARENT}
    ]);

    // cube := get_or_load_mesh(*MESH_CUBE);
    // set_meshes(floor, .[
    //     .{data=cube, albedo=.{tint=color}, scale=.{scale, 1.0, scale}, flags=.IS_COLLISION_SHAPE_PARENT}
    // ]);

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
        .{data=sphere, albedo=.{tint=color}, scale=.{radius, radius, radius}, flags=.IS_COLLISION_SHAPE_PARENT}
    ]);

    ball.physics_properties.elasticity = 0.9;
    ball.physics_properties.linear_speed_max = 1000;

    return ball;
}