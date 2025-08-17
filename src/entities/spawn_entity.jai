
spawn_entity :: (name: string, flags: []Entity_Flags, center := Vector3.{}, orientation := QUATERNION_IDENTITY, physics_properties := Physics_Properties.{}) -> *Entity {
    using context.world;

    assert(name != "");
    entity_id_counter += 1;

    new_ref: Entity_Ref = ---;
    new_ref.index = xx request_item(*entity_ref_layer);
    new_ref.id = entity_id_counter;

    entity_data_index := entities.count;
    entity_ref_layer[new_ref.index] = xx entity_data_index;

    use_orientation := orientation;
    normalize_or_identity(*use_orientation);

    entity := array_add(*entities);
    entity.* = .{
        ref = new_ref,
        body = .{
            collision_channels=.DEFAULT, 
            ray_channels=.DEFAULT,
            overlap_channels=.DEFAULT,
            center=center, 
            orientation=use_orientation, 
            physics_properties=physics_properties,
            collision_cell_hash=INVALID_COLLISION_CELL_HASH
        }
    };

    if flags.count > 0 {
        for flags {
            set(*entity.flags, it);
            if it == {
            case .USES_CAMERA;
                entity.camera = camera_make(.PERSPECTIVE);
            }
        }
    }
    set(*entity.flags, .JUST_SPAWNED);

    use_name := tprint("[%]: %", entity.id, name);
    set_name(entity, use_name);

    get_axes(entity.orientation, *entity.axes.fore, *entity.axes.up, *entity.axes.right);

    entity.collision_mesh_albedo = .{.CONSTANT, random_color4f(a=0.25, random_state=*collision_mesh_color_state)};

    return entity;
}

delete_entity :: (ref: Entity_Ref) {
    using context.world;

    deleting_entity := get_entity(ref);
    if deleting_entity.collision_cell_hash != INVALID_COLLISION_CELL_HASH {
        remove_entity_from_collision_grid(deleting_entity);
    }

    ref_layer_index := ref.index;
    return_item(*entity_ref_layer, ref_layer_index);

    array_resize(*deleting_entity.name, *name_allocator, 0);
    array_resize(*deleting_entity.meshes, *meshes_allocator, 0);
    array_resize(*deleting_entity.linear_impulses, *linear_impulses_allocator, 0);
    array_resize(*deleting_entity.event_volume.overlaps, *event_overlap_allocator, 0);
    array_resize(*deleting_entity.gadget_interactions, *gadget_interaction_allocator, 0);
    array_resize(*deleting_entity.gadget_children, *gadget_children_allocator, 0);

    data_index := deleting_entity - entities.data;
    assert(data_index >= 0 && data_index < entities.count);
    if data_index < entities.count-1 {
        ref_layer_index_of_last_entity := entities[entities.count-1].ref.index;
        assert(is_item_in_use(*entity_ref_layer, ref_layer_index_of_last_entity));
        entities[data_index] = entities[entities.count-1];

        entity_ref_layer[ref_layer_index_of_last_entity] = xx data_index;
    }
    entities.count -= 1;
}

spawn_human :: (name: string, center := Vector3.{}, sphere_radius := 10.0, orientation := QUATERNION_IDENTITY) -> *Entity {
    default_props := Physics_Properties.{
        linear_acceleration=500,
        linear_speed_max=35
    };

    e := spawn_entity(name, .[.MOVED_BY_PHYSICS, .APPLY_GRAVITY], center, orientation, default_props);
    e.physics_properties.elasticity = 0.09;

    set_shape_and_mass(e, .{type=.SPHERE, sphere=.{radius=sphere_radius}}, 1);

    reorient_mesh_quat: Quaternion;
    set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
    mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});
    set_meshes(e, .[.{data=mesh, albedo=.{tint=.{0.7,0.7,0.9,1.0}}}]);

    set(*e.flags, .CAN_INTERACT_WITH_GADGETS_IN_PROXIMITY);

    return e;
}

spawn_camera :: (name: string, center := Vector3.{}, orientation := QUATERNION_IDENTITY) -> *Entity {
    e := spawn_entity(name, .[.USES_CAMERA], center, orientation);
    e.collision_channels = 0;
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
        on_begin_overlap = on_gadget_event_volume_begin_overlap;
        on_end_overlap = on_gadget_event_volume_end_overlap;
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
