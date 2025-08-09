
Entity_Component_Data_Structure :: enum {
    INLINE;
    ARRAY_ITEM;
    NESTED_ALLOCATION;
    NESTED_DYNAMIC_ALLOCATION;
    POOL_ITEM;
    STATIC_ARRAY_OR_POOL_ITEM;
}

Entity_Inline_Params :: struct {

}

Entity_Array_Params :: struct {
    count: s32;
}

Entity_Nested_Allocation_Params :: struct {
    min_allocation_size: s32;
    item_count: s32;
    nesting_allocator_name: string;
}

Entity_Pool_Params :: struct {
    count: s32;
    flag_name: string;
}

Entity_Component_Create_Info :: struct {
    data_structure_name: string;
    data_structure: Entity_Component_Data_Structure;
    component_type_name: string;
    component_type_size: s32;
    data_structure_params: union {
        _inline: Entity_Inline_Params;
        array: Entity_Array_Params;
        nested: Entity_Nested_Allocation_Params;
        pool: Entity_Pool_Params;
    }
    get_component_proc_name: string;
    component_default_value: string;
    field_name: string;
    field_is_using: bool;
}

Test_Component :: struct {
    a: s32;
    b: string;
}

entity_surface_layer: Pool(s32);

entity_component_create_infos := Entity_Component_Create_Info.[
    .{
        data_structure_name         = "test_components",
        data_structure              = .ARRAY_ITEM,
        component_type_name         = "Test_Component",
        component_type_size         = size_of(Test_Component),
        data_structure_params       = .{array=.{ENTITY_MAX_COUNT}},
        component_default_value     = ".{}"
    }, .{
        data_structure_name         = "test_components_2",
        data_structure              = .ARRAY_ITEM,
        component_type_name         = "Test_Component",
        component_type_size         = size_of(Test_Component) * 2,
        data_structure_params       = .{array=.{ENTITY_MAX_COUNT}},
        field_name                  = "test2",
        component_default_value     = ".{}"
    }, .{
        data_structure_name         = "test_components_pool",
        data_structure              = .POOL_ITEM,
        component_type_name         = "Test_Component",
        component_type_size         = size_of(Test_Component),
        data_structure_params       = .{pool=.{ENTITY_MAX_COUNT,"TEST"}},
        field_name                  = "test3",
        component_default_value     = ".{}"
    }
];

#insert #run generate_entity_components();

generate_entity_components :: () -> string {
    builder: String_Builder;
    // generate one-for-alls:
    // - procedure that allocates all of the data (x)
    // - procedure that swaps all of the array datas from one index to another
    // generate individuals:
    // - data structure declaration;
    // procecure that initializes a new Entity
    // generate Entity definition;

    // Entity_Patch_Flags -> Entity_Component_Flags. just whatever pool components. don't need to make it a type union

    // sort components by size so they pack well
    sort_infos :: (a: Entity_Component_Create_Info, b: Entity_Component_Create_Info) -> s32 {
        a_size := ifx a.data_structure == .INLINE then a.component_type_size else 8;
        b_size := ifx b.data_structure == .INLINE then b.component_type_size else 8;
        return b_size - a_size;
    }
    quick_sort(entity_component_create_infos, sort_infos);

    // preprocess the inputs
    for *create_info : entity_component_create_infos {
        using create_info;
        assert(component_type_size > 0);
        assert(component_default_value != "");
        log("type size: %", component_type_size);
        if data_structure == {
        case .ARRAY_ITEM;
        case .NESTED_ALLOCATION; 
            #through;
        case .NESTED_DYNAMIC_ALLOCATION;
            if data_structure_params.nested.nesting_allocator_name == "" {
                data_structure_params.nested.nesting_allocator_name = tprint("%_allocator", data_structure_name);;
            }
        case .POOL_ITEM;
            if data_structure_params.pool.flag_name == "" {
                data_structure_params.pool.flag_name = to_upper(component_type_name);
            }
        case .STATIC_ARRAY_OR_POOL_ITEM;
        }
        if get_component_proc_name == "" {
            get_component_proc_name = tprint("get_%", to_lower(component_type_name));
        }
        if field_name == "" {
            field_name = to_lower(component_type_name);
        }
    }

    // generate Entity type
    print_to_builder(*builder, 
#string HERE
Entity_2 :: struct {
    ref : Entity_Ref;
    component_flags: Entity_Component_Flags;
HERE
    );
    for create_info : entity_component_create_infos {
        using create_info;
        using_text := ifx field_is_using "using " else "";
        if data_structure == .INLINE {
            print_to_builder(*builder, "\t%0%: %;\n", using_text, field_name, component_type_name);
        } else {
            print_to_builder(*builder, "\t%0%: *%;\n", using_text, field_name, component_type_name);
        }
    }
    print_to_builder(*builder, "}\n\n");

    // declare the data structures
    for create_info : entity_component_create_infos {
        using create_info;

        if data_structure == {
        case .ARRAY_ITEM;
            print_to_builder(*builder, "%: []%;\n", data_structure_name, component_type_name);
        case .NESTED_ALLOCATION; 
            print_to_builder(*builder, "%: []Nested_Allocation;\n%: Nesting_Allocator(%);\n",
                data_structure_name, 
                data_structure_params.nested.nesting_allocator_name, data_structure_params.nested.min_allocation_size
            );
        case .NESTED_DYNAMIC_ALLOCATION;
            print_to_builder(*builder, "%: []Nested_Dynamic_Allocation;\n%: Nesting_Allocator(%);\n",
                data_structure_name, 
                data_structure_params.nested.nesting_allocator_name, data_structure_params.nested.min_allocation_size
            );
        case .POOL_ITEM;
            #through;
        case .STATIC_ARRAY_OR_POOL_ITEM;
            print_to_builder(*builder, "%: Pool(%);\n", data_structure_name, component_type_name);
        }
    }
    print_to_builder(*builder, "\n");

    // initialize components
    // NOTE: pretty sure I was wrong to just take the array count here. the surface array needs to be a pool of s32s
    print_to_builder(*builder, 
#string HERE
intitialize :: (e: *Entity_2, component_flags: Entity_Component_Flags) {
    new_id := entity_id_counter;
    entity_id_counter += 1;
    surface_layer_index := request_item(*entity_surface_layer);
    storage_layer_index := e - entities.data;

    assert(is_null(e.ref));
    e.ref = .{xx surface_layer_index, xx new_id};
    assert(e.component_flags == 0);
    e.component_flags = Entity_Component_Flags;

HERE
    );
    for create_info : entity_component_create_infos {
        using create_info;

        if data_structure == {
        case .INLINE;
            print_to_builder(*builder, "\te.% = %;\n\n", field_name, component_default_value);
        case .ARRAY_ITEM;
            print_to_builder(*builder, "\tassert(e.% == null);\n", field_name);
            print_to_builder(*builder, "\te.% = *%[storage_layer_index];\n", field_name, data_structure_name);
            print_to_builder(*builder, "\te.%.* = %;\n\n", field_name, component_default_value);
        case .NESTED_ALLOCATION; 
            #through;
        case .NESTED_DYNAMIC_ALLOCATION;
            print_to_builder(*builder, "\tassert(e.% == null);\n", field_name);
            print_to_builder(*builder, "\te.% = *%[storage_layer_index];\n", field_name, data_structure_name);
            print_to_builder(*builder, "\te.%.* = %;\n\n", field_name, component_default_value);
        case .POOL_ITEM;
            print_to_builder(*builder, 
#string HERE
    if (component_flags & .%) != 0 {
        index := request_item(*%);
        assert(index >= 0 && index < %);
        assert(e.% == null);
        e.% = *%[index];
        e.%.* = %;
    }

HERE,
                data_structure_params.pool.flag_name,
                data_structure_name,
                data_structure_params.pool.count,
                field_name, 
                field_name, data_structure_name,
                field_name, component_default_value
            );
        case .STATIC_ARRAY_OR_POOL_ITEM;
        }
    }
    print_to_builder(*builder, "}\n\n");

    // generate the procedure that gets the data structure allocations
    print_to_builder(*builder, "allocate_entity_components :: () {\n");
    for create_info : entity_component_create_infos {
        using create_info;
        if data_structure == {
        case .ARRAY_ITEM;
            print_to_builder(*builder, "\tprogram_runtime_allocate(*%, %);\n", data_structure_name, data_structure_params.array.count);
        case .NESTED_ALLOCATION; 
            #through;
        case .NESTED_DYNAMIC_ALLOCATION;
            DEFAULT_LIST_SIZE :: 4096 * 16;
            total_allocation_size := data_structure_params.nested.item_count * component_type_size;
            print_to_builder(*builder, "\t%_data_size := %;\n\tprogram_runtime_initialize(*%, %, %_data_size);\n",
                data_structure_name, total_allocation_size,
                data_structure_params.nested.nesting_allocator_name, min(DEFAULT_LIST_SIZE, total_allocation_size), data_structure_name
            );
        case .POOL_ITEM;
            print_to_builder(*builder, "\tprogram_runtime_initialize(*%, %);", data_structure_name, data_structure_params.pool.count);
        case .STATIC_ARRAY_OR_POOL_ITEM;
            print_to_builder(*builder, "\tprogram_runtime_initialize(*%, %);", data_structure_name, data_structure_params.pool.count);
        }
    }
    print_to_builder(*builder, "}\n\n");

    // generate the procedure that aids in deleting entities with a remove-swap
    print_to_builder(*builder, "swap_entity_component_datas :: (dst: s32, src: s32) {\n");
    for create_info : entity_component_create_infos {
        using create_info;
        if data_structure == {
        case .ARRAY_ITEM;
            print_to_builder(*builder, "\t%[dst] = %[src];\n", data_structure_name, data_structure_name);
        case .NESTED_ALLOCATION;
        case .NESTED_DYNAMIC_ALLOCATION;
        case .POOL_ITEM;
        case .STATIC_ARRAY_OR_POOL_ITEM;
        }       
    }
    print_to_builder(*builder, "}\n\n");

    // generate the procedure that aids in deleting entities by freeing their dynamic allocations
    print_to_builder(*builder, "free_entity_allocations :: (i: s32) {\n");
    for create_info : entity_component_create_infos {
        using create_info;
        if data_structure == {
        case .ARRAY_ITEM;
        case .NESTED_ALLOCATION;
            #through;
        case .NESTED_DYNAMIC_ALLOCATION;
            print_to_builder(*builder,
#string HERE
    if basic_validity_check(*%[i].allocation_ref) {
        na_free(*%, %[i].allocation_ref);
    }
    %[i] = .{};
HERE,
                data_structure_name, 
                data_structure_params.nested.nesting_allocator_name, data_structure_name,
                data_structure_name
            );
        case .POOL_ITEM;
            #through;
        case .STATIC_ARRAY_OR_POOL_ITEM;
            print_to_builder(*builder,
#string HERE
    if (entities[i].component_flags & .%) != 0 {
        assert(entities[i].% != null);
        index := entities[i].% - %.data;
        return_item(*%, index);
        entities[i].% = null;
    } else {
        assert(entities[i].% == null);
    }
HERE,
                data_structure_params.pool.flag_name,
                field_name,
                field_name, data_structure_name,
                data_structure_name,
                field_name
            );
        }       
    }
    print_to_builder(*builder, "}\n\n");

    return builder_to_string(*builder);
}


Entity_Patch_Info :: struct {
    type: Entity_Type;
    using patch: Entity_Patch_Type_Union;
    using ref: Entity_Ref;
    physics_properties: u16;
    meshes: u16;
    camera: u8 = INVALID_CAMERA_INDEX;
    frame_counter: s32 = 0;
}

Entity :: struct {
    component_flags: Entity_Component_Flags;
    type: Entity_Type;
    using patch: Entity_Patch_Type_Union;
    using camera: *Entity_Camera;
    using ref: Entity_Ref;
    using body: *Collision_Body;
    using movement: *Entity_Movement;
    compressed_axes: *Compressed_Axes;
    physics_properties: *Physics_Properties;
    collision_channels: *Collision_Channels;
    meshes: []Entity_Mesh;
    flags: *Long_Flag_Array(Entity_Flags);
    name: string;
    generation: s32 = -1;
    using data: *Entity_Data;
}