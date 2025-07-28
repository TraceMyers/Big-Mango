
command_line_procedures: []Command_Line_Procedure;

code_string :: ($code: Code, allocator := temp) -> string #expand {
    builder: String_Builder;
    builder.allocator = allocator;
    assert(Program_Print.print_expression(*builder, Compiler.compiler_get_nodes(code)));
    return builder_to_string(*builder);
}

is_type :: (info: *Type_Info, base_name: string) -> bool {
    if info.type != .STRUCT return false;
    info_struct := cast(*Type_Info_Struct) info;
    return info_struct.name == base_name;
}

is_subtype :: (info: *Type_Info, base_name: string, $check_equal_base_type := false) -> bool {
    #if (check_equal_base_type) {
        using Type_Info_Tag;
        if info.type != STRUCT return false;
        info_struct := cast(*Type_Info_Struct) info;
        if info_struct.name == base_name {
            return true;
        }
    }
    return Compiler.is_subclass_of(info, base_name);
}

is_array_type :: (T: Type) -> bool {
    info := T.(*Type_Info);
    return info.type == .ARRAY;
}

is_string_type :: (T: Type) -> bool {
    info := T.(*Type_Info);
    return info.type == .STRING;
}

align_of :: inline ($T: Type) -> u8 {
    return align_of(T.(*Type_Info));
}

align_of_element_type :: inline ($T: Type) -> u8 {
    info := T.(*Type_Info);
    assert(info.type == .ARRAY);
    array_info := T.(*Type_Info_Array);
    return type_alignment(info.element_type);
}

struct_alignment :: (info: *Type_Info) -> u8 {
    assert(info.type == .STRUCT);
    struct_info := info.(*Type_Info_Struct);
    max_align : u8 = 1;
    for struct_info.members {
        max_align = max(max_align, align_of(xx it.type));
    }
    return max_align;
}

align_of :: inline (info: *Type_Info) -> u8 {
    t := info.type;
    if t == .INTEGER    then return xx info.runtime_size;
    if t == .FLOAT      then return xx info.runtime_size; 
    if t == .POINTER    then return xx info.runtime_size;
    if t == .PROCEDURE  then return xx info.runtime_size;
    if t == .ENUM       then return xx info.runtime_size;
    if t == .BOOL       then return xx info.runtime_size;
    if t == .STRING     then return 8;
    if t == .STRUCT     then return struct_alignment(info);
    if t == .ARRAY      then return 8;
    return 1;
}

Command_Line_Argument :: struct {
    _int: s64; 
    _float: float64;
    _string: string;
    parse_int_success: bool;
    parse_float_success: bool;
}

Command_Line_Procedure :: struct {
    name: string;
    proc: ([]Command_Line_Argument);
}

command_line_procedure_index :: (cmd: string) -> s32 {
    for command_line_procedures {
        if cmd == it.name {
            return xx it_index;
        }
    }
    return -1;
}

is_command_line_procedure :: (cmd: string) -> bool {
    return command_line_procedure_index(cmd) >= 0;
}

try_call_command_line_procedure :: (cmd: string, args: []Command_Line_Argument) -> bool {
    index := command_line_procedure_index(cmd);
    if index >= 0 {
        command_line_procedures[index].proc(args);
        return true;
    } else return false;
}

try_parse_command_line_arg :: (in_arg: *Command_Line_Argument, $T: Type) -> T, bool #expand {
    parse_success := true;
    arg_type_info_type :: #run T.(*Type_Info).type;
    var: T = ---;
    #if arg_type_info_type == .INTEGER {
        var, parse_success = in_arg._int, in_arg.parse_int_success;
    } else #if arg_type_info_type == .FLOAT {
        var, parse_success = in_arg._float, in_arg.parse_float_success;
    } else #if arg_type_info_type == .ENUM {
        arg := in_arg._string;
        var, parse_success = parse_enum(*arg, T);
    } else #if arg_type_info_type == .STRING {
        var = in_arg._string;
    } else {
        assert(false);
    }
    if !parse_success {
        rm_error("unable to create arg type % from %", T, in_arg.*);
    }
    return var, parse_success;
}

init_command_line_proc_or_return :: (args: []Command_Line_Argument, expected_min_count: s64, expected_max_count := S64_MAX) #expand {
    use_max := expected_max_count;
    if expected_max_count == S64_MAX {
        use_max = expected_min_count;
    }
    if args.count < expected_min_count || args.count > use_max {
        if expected_min_count == expected_max_count {
            rm_error("expected % args. got %. arglist: %", expected_min_count, args.count, args);
        } else {
            rm_error("expected %-% args. got %. arglist: %", expected_min_count, expected_max_count, args.count, args);
        }
        `return;
    }
}

// ----------------------------------------------------------------------------------------------------------
// for generating an enum and array parallel to each other. I really don't like maintaining order between
// the enum and the array. so, why not just declare them at the same time in a JSON-ish way? the example
// below looks silly because it is; this is moreso for when the combined enum-array construct gets really
// long.
//
// usage:
//
// Some_Struct :: struct { a: int; };
//
// EXAMPLE_CREATE_INFOS :: EnumArray_Create_Info.[
//      "ENUM_VALUE_1", .{
//          a=1
//      },
//      "ENUM_VALUE_2", .{
//          a=500
//      }
// ];
// 
// #run define_enum(..EXAMPLE_CREATE_INFOS, "Some_Enum", u8);
// #run define_array(..EXAMPLE_CREATE_INFOS, "Some_Structs", Some_Struct, true);
//
// this will generate...
//
// Some_Enum :: { ENUM_VALUE_1; ENUM_VALUE_2; }  
// Some_Structs :: Some_Struct.[.{a=1}, .{a=500}];
//

Enumarray_Create_Info :: struct {
    name: string;
    props: Code;
}

define_enum :: ($create_infos: ..Enumarray_Create_Info, enum_name: string, $backing_type: Type) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "% :: enum % {\n", enum_name, backing_type);
    for create_infos {
        print_to_builder(*builder, "\t%;\n", it.name);
    }
    print_to_builder(*builder, "};");
    return builder_to_string(*builder);
}

define_array :: ($create_infos: ..Enumarray_Create_Info, array_name: string, $struct_type: Type, array_is_constant: bool) -> string {
    builder: String_Builder;
    assignment_operator := ifx array_is_constant then "::" else ":=";
    print_to_builder(*builder, "% % %.[\n", array_name, assignment_operator, struct_type);

    props_type_info := cast(*Type_Info_Struct)struct_type;
    for create_infos {
        print_to_builder(*builder, "\t%,\n", code_string(it.props));
    }

    print_to_builder(*builder, "];");
    return builder_to_string(*builder);
}

// ----------------------------------------------------------------------------------------------------------