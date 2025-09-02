// in lieu of metaprogramming, to save time, I'm just manually handling entity array datas. here's the list of locations that need to be managed for all datas / allocators:
// - delete_entity()
// - duplicate_entity()
// - world : initialize()
// - world : save_or_load()

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

    use_name := prefix_entity_name_with_id(name, entity.id);
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

duplicate_entity :: (e: *Entity) -> *Entity {
    name_without_prefix := entity_name_strip_prefix(e.name.field);
    duplicate_entity := spawn_entity(name_without_prefix, .[]);
    save_ref := duplicate_entity.ref;
    save_name := duplicate_entity.name;
    // easiest way to start: just copy everything...
    memcpy(duplicate_entity, e, size_of(Entity));
    duplicate_entity.ref = save_ref;
    duplicate_entity.name = save_name;
    duplicate_entity.collision_cell_hash = INVALID_COLLISION_CELL_HASH;
    duplicate_entity.frame_counter = 0;
    // $todo: insane metaprogramming could actually be used to do interesting things with recursive duplication... probably
    duplicate_entity.holding_entity = .{};
    duplicate_entity.attached_camera = .{};
    // then go back and fix the array datas

    duplicate_entity.meshes = .{};
    array_copy(*duplicate_entity.meshes, *e.meshes, *context.world.meshes_allocator);
    duplicate_entity.linear_impulses = .{};
    duplicate_entity.event_volume.overlaps = .{};
    duplicate_entity.gadget_interactions = .{};
    duplicate_entity.gadget_children = .{};
    array_copy(*duplicate_entity.gadget_children, *e.gadget_children, *context.world.gadget_children_allocator);

    return duplicate_entity;
}
