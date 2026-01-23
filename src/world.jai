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
WORLD_SIZE_MAX :: 100 * 1024 * 1024;
INVALID_WORLD_ID : u64 : 0;

Context_Type :: type_of(context);

worlds: [..]World;
world_contexts: [..]*Context_Type;
world_context_datas: [..]Context_Type;
world_heaps: [..]Bump_Allocator_Heap;
world_heap_pool: Pool(s32);
queued_world_load: string;
queued_world_save: s32 = -1;

context_index: s32;

World :: struct {
    world_id: u64;
    world_name := "world";
    
    // entities
    entities: [..]Entity;
    entity_deletion_queue: [..]Entity_Ref;
    entity_ref_layer: Pool(s32);
    entity_id_counter: u32;
    collision_mesh_color_state: Random_State;

    // allocation
    world_heap_index: s32;
    world_runtime_allocator: Bump_Allocator;
    name_allocator: Super_Allocator(NAME_ALLOCATOR_MIN_BLOCK_SIZE);
    meshes_allocator: Super_Allocator(MESHES_ALLOCATOR_MIN_BLOCK_SIZE);
    linear_impulses_allocator: Super_Allocator(LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE);
    event_overlap_allocator: Super_Allocator(EVENT_OVERLAP_ALLOCATOR_MIN_BLOCK_SIZE);
    gadget_interaction_allocator: Super_Allocator(GADGET_INTERACTION_ALLOCATOR_MIN_BLOCK_SIZE);
    gadget_children_allocator: Super_Allocator(GADGET_CHILD_ALLOCATOR_MIN_BLOCK_SIZE);
    
    // collision
    collision_grid: []Collision_Grid_Cell;
    collision_grid_cell_flags: []Collision_Grid_Cell_Flags;
    collision_grid_allocator: Super_Allocator(COLLISION_GRID_ALLOCATOR_MIN_SIZE);
    time_step_accumulator := 0.0;
    contact_pairs: [..]Contact_Pair;
    seen_entity_in_group: Bit_Array(1);
    color_group_random_state: Random_State;
    altered_cells: [..]s32;

    // frame counters
    world_frame: s32; // counted every step of the program that the world is active
    collision_frame: s32; // counted every step of the program wherein collision & physics is run
    physics_frame: s32; // counted every physics step (substeps)

    // misc
    entity_deletion_queue_empty_frame_count: s32;
    save_queued: bool;

    world_is_new_version: bool;

    // cached entity refs
    camera_1_ref: Entity_Ref;
    camera_2_ref: Entity_Ref;
    player_entity_ref: Entity_Ref;
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
        serialization_program.allocator = temp;
    } else {

    }
    return true;
}

_world :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*worlds, WORLD_COUNT_MAX);
        context.world = array_add(*worlds);
        initialize(context.world);

        // just to test switching between worlds
        push_context world_contexts[1].* {
            context.world = array_add(*worlds);
            initialize(context.world);
        }

    } else {

    }
    return true;
}

get_new_world_heap :: () -> s32 {
    i := request_item(*world_heap_pool);
    add_heap_count := i - (world_heaps.count - 1);
    if add_heap_count > 0 {
        old_count := world_heaps.count;
        array_resize(*world_heaps, i + 1);
        for old_count..world_heaps.count-1 {
            allocation := alloc_array(u8, WORLD_SIZE_MAX, program_runtime_allocator);
            assert(allocation.data != null);
            world_heaps[it] = .{bytes=allocation, end=0};
        }
    }
    return xx i;
}

release_world_heap :: (i: s32) {
    return_item(*world_heap_pool, i);
}

initialize :: (using world: *World, id := INVALID_WORLD_ID) {
    if id == INVALID_WORLD_ID {
        world_id = get_new_world_id();
    } else {
        world_id = id;
    }

    world_heap_index = get_new_world_heap();
    world_runtime_allocator.heap = world_heaps[world_heap_index];
    world_runtime_allocator.parent_allocator = no_allocator;
    world_runtime_allocator.proc = bump_allocator_proc;
    world_runtime_allocator.data = *world_runtime_allocator;

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
        world_runtime_reserve(world, *altered_cells, 8192);
        cell_count := COLLISION_GRID_DIMENSIONS.x * COLLISION_GRID_DIMENSIONS.y;
        world_runtime_allocate(world, *collision_grid, cell_count);
        world_runtime_allocate(world, *collision_grid_cell_flags, cell_count);
        memset(collision_grid_cell_flags.data, 0, cell_count * size_of(Collision_Grid_Cell_Flags));
        max_data_size := ENTITY_MAX_COUNT * size_of(Collision_Grid_Item) * 4;
        world_runtime_initialize(world, *collision_grid_allocator, na_chunk_list_size, max_data_size);
    }
}

begin_world_frame :: () {
    scope_timer();
    using context.world;

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
    release_world_heap(world.world_heap_index);
    world.* = .{};
}

serialize :: (using world: *World, record: *Serializer(.STATIC), operation: World_Serialization_Operation = 0, running_serialization_program := false) -> World_Serialization_Operation {
    assert(!serialization_eof_written);

    if running_serialization_program {
        // when running a serialization program, operationss are being fed in from an array, so they aren't and shouldn't be serialized.
        assert(operation != .BEGIN_SUBROUTINE);
        assert(operation != .RUN_SUBROUTINE);
    } else {
        serialize(record, *operation);
        // $todo: this crashes and it's annoying
        // if record.rw_mode == .READ {
        //     array_add(*read_operation_history, operation);
        // }
        if recording_serialization_program {
            if operation == .RUN_SUBROUTINE {
                recording_serialization_program = false;
            } else {
                array_add(*serialization_program, operation);
                return 0;
            }
        }
    }

    serializing_entity: *Entity;
    if entity_serialization_target != INVALID_ENTITY_SERIALIZATION_TARGET {
        serializing_entity = *entities[entity_serialization_target];
    }

    if operation == {
    case .END_OF_FILE;
        if record.rw_mode == .WRITE {
            serialization_eof_written = true;
        }
    case .WORLD_ID;
        serialize(record, *world_id);
    case .WORLD_FRAME;
        serialize(record, *world_frame);
    case .WORLD_NAME;
        serialize(record, *world_name);
    case .ENTITY_ID_COUNTER;
        serialize(record, *entity_id_counter); 
    case .TIME_STEP_ACCUMULATOR;
        serialize(record, *time_step_accumulator);
    case .COLOR_GROUP_RANDOM_STATE;
        serialize(record, (*color_group_random_state).(*u8), size_of(Random_State));
    case .COLLISION_FRAME;
        serialize(record, *collision_frame);
    case .PHYSICS_FRAME;
        serialize(record, *physics_frame);
    case .CAMERA_1_REF;
        serialize(record, *camera_1_ref);
    case .CAMERA_2_REF;
        serialize(record, *camera_2_ref);
    case .PLAYER_ENTITY_REF;
        serialize(record, *player_entity_ref);
    case .ENTITIES;
        serialize_preallocated_dynamic_array(record, *entities);
    case .ENTITY_DELETION_QUEUE;
        serialize_preallocated_dynamic_array(record, *entity_deletion_queue);
    case .ENTITY_REF_LAYER;
        serialize_preallocated_pool(record, *entity_ref_layer);
    case .SET_FIRST_ENTITY_AS_SERIALIZATION_TARGET;
        entity_serialization_target = 0;
    case .INCREMENT_ENTITY_SERIALIZATION_TARGET;
        // if INVALID_ENTITY_SERIALIZATION_TARGET changes, this increment wrap is no longer valid.
        #run assert(INVALID_ENTITY_SERIALIZATION_TARGET == -1);
        entity_serialization_target = increment_wrap(entity_serialization_target, INVALID_ENTITY_SERIALIZATION_TARGET, (entities.count-1).(s32));
    case ._READONLY_SET_ENTITY_NESTED_ALLOCATIONS_TO_DEFAULT;
        // $todo: any field that points to an allocation should be automatically defaulted.
        // this isn't currently the case because load-serialization depends on inline data being copied directly
        // into the entity array, which takes care of the saving and loading of most fields.
        if record.rw_mode == .READ {
            reset_without_free(*serializing_entity.name);
            reset_without_free(*serializing_entity.meshes);
            reset_without_free(*serializing_entity.linear_impulses);
            reset_without_free(*serializing_entity.gadget_interactions);
            reset_without_free(*serializing_entity.gadget_children);
            reset_without_free(*serializing_entity.event_volume.overlaps);
            // $todo: should be able to automate this as well
            serializing_entity.meshes.allocator = meshes_allocator;
            serializing_entity.linear_impulses.allocator = linear_impulses_allocator;
            serializing_entity.gadget_interactions.allocator = gadget_interaction_allocator;
            serializing_entity.gadget_children.allocator = gadget_children_allocator;
            serializing_entity.event_volume.overlaps.allocator = event_overlap_allocator;
        }
    case .ENTITY_NAME;
        {
            scope_set_allocator(name_allocator);
            serialize(record, *serializing_entity.name);
        }
    case .ENTITY_MESHES;
        serialize(record, *serializing_entity.meshes);
    case .ENTITY_MESH_DATAS;
        if record.rw_mode == .WRITE {
            for mesh : serializing_entity.meshes {
                asset_ref := find_mesh_loader_asset_reference(mesh.data);
                if asset_ref == null {
                    hash := create_mesh_loader_asset(mesh.data);
                    serialize(record, *hash);
                } else {
                    serialize(record, *asset_ref.name_hash);
                }
            }
        } else {
            for *mesh : serializing_entity.meshes {
                hash: u64;
                serialize(record, *hash);
                asset_ref := find_mesh_loader_asset_reference(hash);
                // $todo: probably just set it to a default mesh with a default 'bad load' tex instead
                assert(asset_ref != null);
                mesh.data = get_or_load_mesh(asset_ref);
            }
        }
    case .ENTITY_LINEAR_IMPULSES;
        serialize(record, *serializing_entity.linear_impulses);
    case .ENTITY_GADGET_INTERACTIONS;
        if is_set(*serializing_entity.flags, .USES_GADGET) {
            serialize(record, *serializing_entity.gadget_interactions);
        }
    case .ENTITY_GADGET_CHILDREN;
        if is_set(*serializing_entity.flags, .USES_GADGET) {
            serialize(record, *serializing_entity.gadget_children);
        }
    case .ENTITY_EVENT_VOLUME_OVERLAPS;
        serialize(record, *serializing_entity.event_volume.overlaps);
    case ._READONLY_ENTITY_COLLISION_CELL_HASH;
        if record.rw_mode == .READ {
            serializing_entity.collision_cell_hash = INVALID_COLLISION_CELL_HASH;
        }
    case .BEGIN_SUBROUTINE;
        assert(!recording_serialization_program);
        // keeping memory should be fine even though the allocator is temp because temp isn't reset until the end of saving or loading.
        array_reset_keeping_memory(*serialization_program);
        recording_serialization_program = true;
    case .RUN_SUBROUTINE;
        assert(serialization_program.count > 0);
        for serialization_program {
            serialize(world, record, it, true);
        }
    case .WORLD_IS_NEW_VERSION;
        serialize(record, *world_is_new_version);
    case;
        assert(false, "unaccounted-for operation %", operation);
    }

    return operation; // loading wants to know what was done
}

// $todo: could serialize all of the code block enums into an array rather than serializing them at the same time as the data represented by the enum, which would no doubt speed up the saving/loading process if needed.
// if it is done that way, file size could also be brought down (can more easily generically compress repeated sets of encodings)
save :: (using world: *World) {
    auto_release_temp();

    reset_serialization_program();

    record: Serializer(.STATIC);
    set_rw_mode(*record, .WRITE, true);

    file_path: string;

    scope_set_allocator(temp);
    make_directory_if_it_does_not_exist("worlds");
    file_path = tprint("worlds/%_%.world", world.world_name, world.world_id);
    record.memory = alloc_string(WORLD_FILE_SIZE_MAX);
    record.read_array_allocator = no_allocator;
    rm_log("saving world %", file_path);

    defer {
        serialize(world, *record, .END_OF_FILE);
        record.memory.count = record.head;
        imprint_checksum(*record);
        write_entire_file(file_path, *record);
        serialization_eof_written = false;
    }

    // will be false if loading the old version because it's only set to true here
    world_is_new_version = true;

    serialize(world, *record, .WORLD_ID);
    serialize(world, *record, .WORLD_FRAME);
    serialize(world, *record, .WORLD_NAME);
    serialize(world, *record, .ENTITY_ID_COUNTER);
    serialize(world, *record, .TIME_STEP_ACCUMULATOR);
    serialize(world, *record, .COLOR_GROUP_RANDOM_STATE);
    serialize(world, *record, .COLLISION_FRAME);
    serialize(world, *record, .PHYSICS_FRAME);
    serialize(world, *record, .CAMERA_1_REF);
    serialize(world, *record, .CAMERA_2_REF);
    serialize(world, *record, .PLAYER_ENTITY_REF);
    serialize(world, *record, .WORLD_IS_NEW_VERSION);

    serialize(world, *record, .ENTITIES);
    serialize(world, *record, .ENTITY_DELETION_QUEUE);
    serialize(world, *record, .ENTITY_REF_LAYER);

    serialize(world, *record, .SET_FIRST_ENTITY_AS_SERIALIZATION_TARGET);

    // making a program out of the serialization of an individual entity
    serialize(world, *record, .BEGIN_SUBROUTINE);
    serialize(world, *record, ._READONLY_SET_ENTITY_NESTED_ALLOCATIONS_TO_DEFAULT);
    serialize(world, *record, .ENTITY_NAME);
    serialize(world, *record, .ENTITY_MESHES);
    serialize(world, *record, .ENTITY_MESH_DATAS);
    serialize(world, *record, .ENTITY_LINEAR_IMPULSES);
    serialize(world, *record, .ENTITY_GADGET_INTERACTIONS);
    serialize(world, *record, .ENTITY_GADGET_CHILDREN);
    serialize(world, *record, .ENTITY_EVENT_VOLUME_OVERLAPS);
    serialize(world, *record, ._READONLY_ENTITY_COLLISION_CELL_HASH);
    // this is the line that increments the entity in the loop
    serialize(world, *record, .INCREMENT_ENTITY_SERIALIZATION_TARGET);

    for entities {
        // run the array of operations (in other words, a program), serializing one entity's data
        serialize(world, *record, .RUN_SUBROUTINE);
    }
}

load :: (using world: *World, load_file_path := "") {
    auto_release_temp();
    record: Serializer(.STATIC);
    set_rw_mode(*record, .READ, true);

    reset_serialization_program();

    file_path: string;

    scope_set_allocator(temp);
    read_success: bool;
    file_path = load_file_path;
    if file_path == "" {
        file_path = tprint("worlds/%_%.world", world.world_name, world.world_id);
    }
    record.memory, read_success = read_entire_file(file_path);
    if !read_success {
        rm_error("tried to read file % for world loading, but failed.", file_path);
        return;
    }
    if !validate_checksum(*record) {
        rm_error("checksum compare failure on %", file_path);
        return;
    }
    rm_log("loading world %", file_path);

    reset(world);
    initialize(world);

    prev_head := record.head;
    ran_operation: World_Serialization_Operation = 0;
    record.read_array_allocator = world.world_runtime_allocator;

    // $todo: should probably look ahead and make sure we're not actually reaching eof too soon (or not at all).
    // catch it, print an error and return early instead of crashing
    while ran_operation != .END_OF_FILE {
        ran_operation = serialize(world, *record); 
        // make sure progress is being made through the file
        assert(prev_head != record.head);
        prev_head = record.head;
    }

    rm_log("world is new version: %", world_is_new_version);
}

reset_serialization_program :: () {
    array_reset(*serialization_program);
    array_reserve(*serialization_program, 256);
    recording_serialization_program = false;
}

serialize_preallocated_dynamic_array :: (record: *Serializer, array: *[..]$T) {
    serialize(record, *array.count);
    serialize(record, array.data.(*u8), array.count * size_of(T));
}

serialize_preallocated_pool :: (record: *Serializer, pool: *Pool($T)) {
    serialize_preallocated_dynamic_array(record, *pool.items);
    serialize_preallocated_dynamic_array(record, *pool.in_use.items);
    serialize(record, *pool.in_use.groups_bit_size);
    serialize(record, *pool.top);
    serialize(record, *pool.shrink_to_min);
    serialize(record, *pool.allow_grow_default);
    serialize(record, *pool.allow_shrink_default);
}

// save :: #bake_arguments save_or_load(rw_mode=.WRITE);
// load :: #bake_arguments save_or_load(rw_mode=.READ);

get_world_main_camera :: (using world: *World) -> *Entity {
    if control_mode == .BUILD {
        return try_get_entity(*camera_2_ref);
    } else if control_mode & ORTHO_CONTROL_MODE {
        return try_get_entity(*camera_2_ref);
    }
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
        meshes := e.meshes;
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

save_world :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 0);
    queued_world_save = context_index;
} @command_line

load_world :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 1);
    world_name, success := try_parse_command_line_arg(*args[0], string);
    if success {
        scope_set_allocator(context.default_allocator);
        reset(*queued_world_load);
        queued_world_load = sprint("worlds/%.world", world_name);
    }
} @command_line

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

INVALID_ENTITY_SERIALIZATION_TARGET : s32 : -1;
entity_serialization_target := INVALID_ENTITY_SERIALIZATION_TARGET;
serialization_eof_written: bool;

serialization_program: [..]World_Serialization_Operation;
recording_serialization_program: bool;
read_operation_history: [..] World_Serialization_Operation;

dbg_loading_entity_id: u32; // 132

World_Serialization_Operation :: enum s32 {
    END_OF_FILE :: 1;
    WORLD_ID; // 2
    WORLD_FRAME; // 3
    WORLD_NAME; // 4
    ENTITY_ID_COUNTER; // 5
    TIME_STEP_ACCUMULATOR; // 6
    COLOR_GROUP_RANDOM_STATE; // 7
    COLLISION_FRAME; // 8
    PHYSICS_FRAME; // 9
    CAMERA_1_REF; // 10
    CAMERA_2_REF; // 11
    PLAYER_ENTITY_REF; // 12
    ENTITIES; // 13
    ENTITY_DELETION_QUEUE; // 14
    ENTITY_REF_LAYER; // 15
    _READONLY_SET_ENTITY_NESTED_ALLOCATIONS_TO_DEFAULT; // 16
    SET_FIRST_ENTITY_AS_SERIALIZATION_TARGET; // 17
    INCREMENT_ENTITY_SERIALIZATION_TARGET; // 18
    ENTITY_NAME; // 19
    ENTITY_MESHES; // 20
    ENTITY_MESH_DATAS; // 21
    ENTITY_LINEAR_IMPULSES; // 22
    ENTITY_GADGET_INTERACTIONS; // 23
    ENTITY_GADGET_CHILDREN; // 24
    ENTITY_EVENT_VOLUME_OVERLAPS; // 25
    _READONLY_ENTITY_COLLISION_CELL_HASH; // 26
    ENTITY_REF_LAYER_V2; // 27
    BEGIN_SUBROUTINE; // 28
    RUN_SUBROUTINE; // 29
    WORLD_IS_NEW_VERSION; // 30
};