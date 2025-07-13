
IMMOVABLE_ENTITY_MASS :: 0.0;

PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS :: Physics_Property_Template_Create_Info.[
    .{
        "CAPSULE_MAN", .{
            mass = 1,
            body_collider = .{
                type = .CAPSULE,
                data = .{
                    capsule = .{
                        half_height = 21.4*0.5,
                        radius = 2.15
                    }
                }
            }
        }
    },
    .{
        "BOX_MAN", .{
            mass = 2,
            body_collider = .{
                type = .BOX,
                data = .{
                    box = .{
                        half_height = 21.4*0.5,
                        width = 5.15,
                        length = 2.15
                    }
                }
            }
        }
    },
    .{
        "SPHERE_MAN", .{
            mass = 2,
            body_collider = .{
                type = .SPHERE,
                data = .{
                    sphere = .{
                        radius = 10.0
                    }
                }
            }
        }
    },
    .{
        "GROUND", .{
            mass = IMMOVABLE_ENTITY_MASS,
            body_elasticity = 0
        }
    }
];

Collision_Channels :: enum_flags u64 {
    DEFAULT :: 0x1;
}


Physics_Properties :: struct {
    mass := 1.0;
    friction_bias := 0.0;
    // todo: linear accel discrete (or continuous?) function
    friction_multiplier := 1.0;
    linear_acceleration := 250.0;
    accel_opposite_direction_multiplier := 2.0;
    fast_start_speed_max := 5.0;
    linear_speed_max := 30.0;
    gravity_accel := 150.0;
    jump_delta_velocity := 50.0;
    body_collider: Entity_Collider;
    body_elasticity := 0.1;
    body_collision_channels: Collision_Channels = .DEFAULT;
    // collision bounciness is a combination of the elasticities of the two colliding objects
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

// the idea here is that two equally elastic things meeting each other should not bounce off of each other AND two inelastic things should not also bounce. this is achieved by mapping input to output like so:
// (0,0) -> 0; (1,1) -> 0; (1,0)-> 1; (0,1) -> 1
collision_bounciness :: (props_a: *Physics_Properties, props_b: *Physics_Properties) -> float {
    a := props_a.body_elasticity;
    b := -props_b.body_elasticity;
    assert(a >= 0 && a <= 1 && b <= 0 && b >= -1);
    return abs(a + b);
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