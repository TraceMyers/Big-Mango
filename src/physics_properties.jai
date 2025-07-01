PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS :: Physics_Property_Template_Create_Info.[
    .{
        "DEFAULT_MAN", .{
            mass = 1,
            body_collider = .{
                type = .CAPSULE,
                data = .{
                    capsule = .{
                        height = 21.4,
                        radius = 2.15
                    }
                }
            }
        }
    }
];

Physics_Properties :: struct {
    mass := 1.0;
    friction_bias := 0.0;
    friction_multiplier := 1.0;
    // todo: linear accel discrete (or continuous?) function
    linear_acceleration := 500.0;
    accel_opposite_direction_multiplier := 2.0;
    fast_start_speed_max := 10.0;
    linear_speed_max := 30.0;
    body_collider: Entity_Collider;
}

Physics_Properties_Dynamic :: struct {
    template: Physics_Properties_Template;
    using #as base: Physics_Properties;
}

#insert #run define_enum(..PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS);
#insert #run define_array(..PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS);

Physics_Property_Template_Create_Info :: struct {
    name: string;
    props: Code;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

#import "Basic";
Program_Print :: #import "Program_Print";
Compiler :: #import "Compiler";

_code_string :: ($code: Code, allocator := temp) -> string #expand {
    builder: String_Builder;
    builder.allocator = allocator;
    assert(Program_Print.print_expression(*builder, Compiler.compiler_get_nodes(code)));
    return builder_to_string(*builder);
}

define_enum :: ($create_infos: ..Physics_Property_Template_Create_Info) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "Physics_Properties_Template :: enum u16 {\n");
    for create_infos {
        print_to_builder(*builder, "\t%;\n", it.name);
    }
    print_to_builder(*builder, "};");
    return builder_to_string(*builder);
}

define_array :: ($create_infos: ..Physics_Property_Template_Create_Info) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "PHYSICS_PROPERTIES_TEMPLATES :: Physics_Properties.[\n");

    props_type_info := cast(*Type_Info_Struct)Physics_Properties;
    for create_infos {
        print_to_builder(*builder, "\t%,\n", _code_string(it.props));
    }

    print_to_builder(*builder, "];");
    return builder_to_string(*builder);
}