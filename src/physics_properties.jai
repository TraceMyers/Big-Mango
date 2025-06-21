PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS :: Physics_Property_Template_Create_Info.[
    .{
        "DEFAULT", .{
            mass=1
        }
    }, .{
        "HEAVY", .{
            mass=2
        }
    }, .{
        "WHO_CARES", .{
            mass=4
        }
    }
];

Physics_Properties :: struct {
    mass := 1.0;
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