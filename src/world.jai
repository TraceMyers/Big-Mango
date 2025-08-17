WORLD_UP    :: MANGO_UP;
WORLD_DOWN  :: #run -WORLD_UP;
WORLD_FORE  :: MANGO_FORE;
WORLD_BACK  :: #run -WORLD_FORE;
WORLD_RIGHT :: MANGO_RIGHT;
WORLD_LEFT  :: #run -WORLD_RIGHT;

WORLD_X :: Vector3.{1,0,0};
WORLD_Y :: Vector3.{0,1,0};
WORLD_Z :: Vector3.{0,0,1};

WORLD_COUNT_MAX :: 64;
WORLD_FILE_SIZE_MAX :: 20 * 1024 * 1024;

Context_Type :: type_of(context);
worlds: [..]World;
world_contexts: [..]*Context_Type;
world_context_datas: [..]Context_Type;

context_index: s32;

World :: struct {
    world_id: u64;
    world_frame: s32;
    world_name := "world";
    
    // entities
    entities: [..]Entity;
    entity_deletion_queue: [..]Entity_Ref;
    entity_ref_layer: Pool(s32);
    entity_id_counter: u32;
    collision_mesh_color_state: Random_State;

    // allocators
    name_allocator: Nesting_Allocator(NAME_ALLOCATOR_MIN_BLOCK_SIZE);
    meshes_allocator: Nesting_Allocator(MESHES_ALLOCATOR_MIN_BLOCK_SIZE);
    linear_impulses_allocator: Nesting_Allocator(LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE);
    event_overlap_allocator: Nesting_Allocator(EVENT_OVERLAP_ALLOCATOR_MIN_BLOCK_SIZE);
    gadget_interaction_allocator: Nesting_Allocator(GADGET_INTERACTION_ALLOCATOR_MIN_BLOCK_SIZE);
    gadget_children_allocator: Nesting_Allocator(GADGET_CHILD_ALLOCATOR_MIN_BLOCK_SIZE);

    world_runtime_allocator: Allocator;
    world_runtime_flat_pool: Flat_Pool;
    
    // collision
    collision_grid: []Collision_Grid_Allocation;
    collision_grid_cell_flags: []Collision_Grid_Cell_Flags;
    collision_grid_allocator: Nesting_Allocator(COLLISION_GRID_ALLOCATOR_MIN_SIZE);
    collision_grid_origin: Vector2;
    collision_grid_dimensions: Int_Vector2;
    collision_cell_dimensions: Vector2;
    inv_collision_cell_dimensions: Vector2;
    time_step_accumulator := 0.0;
    contact_pairs: [..]Contact_Pair;
    seen_entity_in_group: Bit_Array(1);
    color_group_random_state: Random_State;
    altered_cells: [..]s32;
    collision_frame: s32;
    physics_frame: s32;

    // misc
    entity_deletion_queue_empty_frame_count: s32;
    save_queued: bool;

    // cached entity refs, mostly for development convenience.
    ground_ref: Entity_Ref;
    camera_1_ref: Entity_Ref;
    camera_2_ref: Entity_Ref;
    player_entity_ref: Entity_Ref;
    ball_ref: Entity_Ref;
    door_ref: Entity_Ref;
    ai_guy_ref: Entity_Ref;
    button_ref: Entity_Ref;
}

// $todo: think more on thread safety of allocators, when multithreading is actually called for (but obviously writing terminally single-threaded code and trying to convert it later sucks, so... I'm not trying to make it TOO painful when I add threading in). my current thinking is:
//  - have contexts that are pushed for things like renderer allocator(s), or for any other dynamically allocated data that persists outside of worlds. this way, moving between worlds really interferes zero with what allocators the renderer is using.
_context :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*world_contexts, WORLD_COUNT_MAX);
        program_runtime_reserve(*world_context_datas, WORLD_COUNT_MAX-1);
        array_add(*world_contexts, *context);
        array_add(*world_context_datas, .{});
        array_add(*world_contexts, *world_context_datas[0]);
    } else {

    }
    return true;
}

_world :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*worlds, WORLD_COUNT_MAX);
        context.world = array_add(*worlds);
        initialize(context.world);

        push_context world_contexts[1].* {
            context.world = array_add(*worlds);
            initialize(context.world);
        }

    } else {

    }
    return true;
}

initialize :: (using world: *World) {
    world_runtime_allocator.proc = flat_pool_allocator_proc;
    world_runtime_allocator.data = *world_runtime_flat_pool;

    if world_id == 0 {
        world_id = get_new_world_id();
    }

    // entities
    {
        world_runtime_reserve(world, *entities, ENTITY_MAX_COUNT);
        world_runtime_initialize(world, *entity_ref_layer, ENTITY_MAX_COUNT);
        random_seed(*collision_mesh_color_state, 257);
        entity_deletion_queue.allocator = temp;
    }

    na_chunk_list_size := 4096 * 16;
    na_chunk_list_size_large := 4096 * 32;

    // entity arrays
    {
        mesh_ptrs_array_data_size := ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT * size_of(Mesh_Instance);
        world_runtime_initialize(world, *meshes_allocator, na_chunk_list_size, mesh_ptrs_array_data_size);
        entity_name_data_size := ENTITY_MAX_COUNT * ENTITY_NAME_MAX_CHAR_COUNT;
        world_runtime_initialize(world, *name_allocator, na_chunk_list_size, entity_name_data_size);
        linear_impulse_array_data_size := ENTITY_MAX_COUNT * size_of(Linear_Physics_Impulse) * 2;
        world_runtime_initialize(world, *linear_impulses_allocator, na_chunk_list_size_large, linear_impulse_array_data_size);
        event_overlap_arrays_data_size := ENTITY_MAX_COUNT * size_of(Event_Overlap);
        world_runtime_initialize(world, *event_overlap_allocator, na_chunk_list_size_large, event_overlap_arrays_data_size);
        gadget_interaction_arrays_data_size := ENTITY_MAX_COUNT / 4 * size_of(Gadget_Interaction);
        world_runtime_initialize(world, *gadget_interaction_allocator, na_chunk_list_size_large, gadget_interaction_arrays_data_size);
        gadget_child_arrays_data_size := ENTITY_MAX_COUNT / 4 * size_of(Gadget_Child);
        world_runtime_initialize(world, *gadget_children_allocator, na_chunk_list_size_large, gadget_child_arrays_data_size);
    }

    // collisions
    {
        center := Vector2.{};
        dimensions := Int_Vector2.{100, 100};
        cell_dimensions := Vector2.{25, 25};

        array_reserve(*altered_cells, 4096);
        flt_dimensions := to_vector2(dimensions);
        half_world_dimensions := (flt_dimensions * cell_dimensions) * 0.5;
        collision_grid_origin = center - half_world_dimensions;
        collision_grid_dimensions = dimensions;
        collision_cell_dimensions = cell_dimensions;
        inv_collision_cell_dimensions = 1.0 / cell_dimensions;
        cell_count := dimensions.x * dimensions.y;
        world_runtime_allocate(world, *collision_grid, cell_count);
        world_runtime_allocate(world, *collision_grid_cell_flags, cell_count);
        memset(collision_grid_cell_flags.data, 0, cell_count * size_of(Collision_Grid_Cell_Flags));
        max_data_size := ENTITY_MAX_COUNT * size_of(Collision_Grid_Item) * 4;
        world_runtime_initialize(world, *collision_grid_allocator, na_chunk_list_size, max_data_size);
    }
}

begin_world_frame :: () {
    using context.world;

    scope_timer();

    array_reserve(*entity_deletion_queue, 128);
    if entity_deletion_queue.count == 0 {
        entity_deletion_queue_empty_frame_count += 1;
    } else {
        entity_deletion_queue_empty_frame_count = 0;
    }
}

end_world_frame :: () {
    scope_timer();
    using context.world;

    new_non_render_time := seconds_since_init();
    simulation_dt = exponential_interp(simulation_dt, xx (new_non_render_time - non_render_time), 2.0, delta_time);
    render_frame();
    non_render_time = seconds_since_init();

    world_frame += 1;

    entity_frame_turnover();

    reset_temporary_storage();
}

reset :: (world: *World) {
    fini(*world.world_runtime_flat_pool);
}

save_or_load :: (world: *World, rw_mode: Rw_Mode, load_file_path := "") {
    auto_release_temp();

    record: Serializer(.STATIC);
    set_rw_mode(*record, rw_mode);

    using context.world;

    file_path: string;

    if rw_mode == .READ {
        scope_set_allocator(temp);
        read_success: bool;
        file_path = load_file_path;
        assert(file_path != "");
        record.memory, read_success = read_entire_file(file_path);
        assert(read_success);
        validate_checksum(*record);
    } else {
        scope_set_allocator(temp);
        make_directory_if_it_does_not_exist("worlds");
        file_path = tprint("worlds/%_%.world", world.world_name, world.world_id);
        record.memory = alloc_string(WORLD_FILE_SIZE_MAX);
    }

    if rw_mode == .WRITE {
        rm_log("saving world %", file_path);
    } else {
        rm_log("loading world %", file_path);
    }

    // maybe better to just to slowly & carefully expand the saving & loading support for data that appears stable and would be immediately useful rather than trying to generally serialize all world data. that seems like an endless black hole of work the more I think about it.

    for *e : entities {
        id := e.id;
        serialize(*record, *id);
        if rw_mode == .READ {
            assert(id == e.id);
        }

        serialize(*record, (*e.center).(*u8), size_of(type_of(e.center)));

        orientation := e.orientation;
        serialize(*record, (*orientation).(*u8), size_of(type_of(e.orientation)));
        set_orientation(e, orientation);

        // a little extra validation
        has_any_meshes : u8 = xx (e.meshes.field.count > 0);
        serialize(*record, *has_any_meshes, 1);
        if rw_mode == .READ {
            assert(has_any_meshes == xx (e.meshes.field.count > 0));
        }

        for e.meshes.field {
            serialize(*record, (*it.albedo).(*u8), size_of(type_of(it.albedo)));
            serialize(*record, (*it.scale).(*u8), size_of(type_of(it.scale)));
            serialize(*record, (*it.offset).(*u8), size_of(type_of(it.offset)));
            serialize(*record, (*it.orientation).(*u8), size_of(type_of(it.orientation)));
            
        }
    }

    zero : u32 = 0;
    serialize(*record, *zero);
    assert(zero == 0);

    if rw_mode == .WRITE {
        imprint_checksum(*record);
        write_entire_file(file_path, *record);
    }

    // $note: because the runtime allocators were switched to Flat_Pool, I can serialize by recording pointers as offsets from the base address.
    // note that pointers not within the pool's allocation are probably statically allocated...
    // uh
    // this probably has a lot of edge cases I'm not thinking of, too
    // yes, pointers to global data.
    // I think it's just render data
    // but even just dealing with that is like 20 minutes blehhhhhhhhhhhh
    // I need to seriously think about how to make it feasible to save and load worlds.
    // is there any way I can make a prototype level without it...?

    // #insert #run -> string {
    //     builder: String_Builder;

    //     world_type_info := (World).(*Type_Info_Struct);
    //     for field : world_type_info.members {
    //         if field.type.type == {
    //         case .INTEGER;
    //         case .FLOAT;
    //         case .BOOL;
    //         case .STRING;
    //         case .POINTER;
    //         case .PROCEDURE;
    //         case .VOID;
    //         case .STRUCT;
    //         case .ARRAY;
    //         case .OVERLOAD_SET;
    //         case .ANY;
    //         case .ENUM;
    //         case .POLYMORPHIC_VARIABLE;
    //         case .TYPE;
    //         case .CODE;
    //         case .UNTYPED_LITERAL;
    //         case .UNTYPED_ENUM;
    //         }
    //     }

    //     return builder_to_string(*builder);
    // }   

}

save :: #bake_arguments save_or_load(rw_mode=.WRITE);
load :: #bake_arguments save_or_load(rw_mode=.READ);

get_world_main_camera :: (using world: *World) -> *Entity {
    player_entity := try_get_entity(*player_entity_ref);
    if player_entity != null {
        attached_camera := try_get_entity(*player_entity.attached_camera);
        if attached_camera != null {
            return attached_camera;
        }
    }
    return null;
}

add_world_draw_commands :: (cmd: VkCommandBuffer, using world: *World, vp_mat: Matrix4) {
    if world == null {
        return;
    }

    player_entity := try_get_entity(*player_entity_ref);

    for *e : entities {
        if player_entity && e.id == player_entity.id && control_mode & FIRST_PERSON_PLAYER_CONTROL_MODE {
            continue;
        }
        meshes := e.meshes.field;
        if meshes.count == 0 then continue;
        for *emesh : meshes {
            draw_mesh(cmd, e, emesh, *vp_mat);
        }
    }

    #if DRAW_COLLISION_MESHES {
        for *e : entities {
            if player_entity && e.id == player_entity.id && control_mode & FIRST_PERSON_PLAYER_CONTROL_MODE {
                continue;
            }
            draw_collision_mesh(cmd, e, *vp_mat);
        }
    }
}