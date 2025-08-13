
spawn_entity :: (name: string, flags: []Entity_Flags, center := Vector3.{}, orientation := QUATERNION_IDENTITY, physics_properties := Physics_Properties.{}) -> *Entity {
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

remove_entity :: (ref: Entity_Ref) {
    deleting_entity := get_entity(ref);
    if deleting_entity.collision_cell_hash != INVALID_COLLISION_CELL_HASH {
        remove_entity_from_collision_grid(deleting_entity);
    }

    // todo: metaprogram some procedures to manage this stuff.
    if deleting_entity == context.ground {
        context.ground = null;
    } else if deleting_entity == context.camera_1 {
        context.camera_1 = null;
    } else if deleting_entity == context.camera_2 {
        context.camera_2 = null;
    } else if deleting_entity == context.active_camera {
        context.active_camera = null;
    } else if deleting_entity == context.player_entity {
        context.player_entity = null;
    } else if deleting_entity == context.ball {
        context.ball = null;
    } else if deleting_entity == context.ai_guy {
        context.ai_guy = null;
    }

    ref_layer_index := ref.index;
    return_item(*entity_ref_layer, ref_layer_index);

    array_resize(*deleting_entity.name, *name_allocator, 0);
    array_resize(*deleting_entity.meshes, *meshes_allocator, 0);
    array_resize(*deleting_entity.linear_impulses, *linear_impulses_allocator, 0);

    data_index := deleting_entity - entities.data;
    assert(data_index >= 0 && data_index < entities.count);
    if data_index < entities.count-1 {
        ref_layer_index_of_last_entity := entities[entities.count-1].ref.index;
        assert(is_item_in_use(*entity_ref_layer, ref_layer_index_of_last_entity));
        entities[data_index] = entities[entities.count-1];

        // todo: metaprogram some procedures to manage this stuff.
        if *entities[entities.count-1] == context.ground {
            context.ground = *entities[data_index];
        } else if *entities[entities.count-1] == context.camera_1 {
            context.camera_1 = *entities[data_index];
        } else if *entities[entities.count-1] == context.camera_2 {
            context.camera_2 = *entities[data_index];
        } else if *entities[entities.count-1] == context.active_camera {
            context.active_camera = *entities[data_index];
        } else if *entities[entities.count-1] == context.player_entity {
            context.player_entity = *entities[data_index];
        } else if *entities[entities.count-1] == context.ball {
            context.ball = *entities[data_index];
        } else if *entities[entities.count-1] == context.ai_guy {
            context.ai_guy = *entities[data_index];
        }

        entity_ref_layer[ref_layer_index_of_last_entity] = xx data_index;
    }
    entities.count -= 1;
}

spawn_human :: (name: string, center := Vector3.{}, sphere_radius := 10.0, orientation := QUATERNION_IDENTITY) -> *Entity {
    default_props := Physics_Properties.{
        linear_acceleration = 500,
        linear_speed_max=35
    };

    e := spawn_entity(name, .[.MOVED_BY_PHYSICS, .APPLY_GRAVITY], center, orientation, default_props);
    e.physics_properties.elasticity = 0.09;

    set_shape_and_mass(e, .{type=.SPHERE, sphere=.{radius=sphere_radius}}, 1);

    reorient_mesh_quat: Quaternion;
    set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
    mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});
    set_meshes(e, .[.{mesh, .{tint=.{0.7,0.7,0.9,1.0}}}]);

    return e;
}

spawn_camera :: (name: string, center := Vector3.{}, orientation := QUATERNION_IDENTITY) -> *Entity {
    e := spawn_entity(name, .[.USES_CAMERA], center, orientation);
    e.collision_channels = 0;
    return e;
}

collision_mesh_color_state: Random_State;