
// BUILDVAR_ ...
// options that change the program to something different whenever they are changed.
PROFILERS_ACTIVE :: false;
COLLISION_DEBUG :: true;
GENERATE_PRIMITIVE_MESH_LOADER_FILES :: true;

// options that need to be turned on whenever some new stuff needs to be generated
COMPILE_SHADERS :: false;
REGENERATE_ASSET_REFERENCES :: true;
GENERATE_PROCEDURE_BODY_CAPTURES :: true;

#run {
    // make sure environment is set up
    make_directory_if_it_does_not_exist("bin");
    make_directory_if_it_does_not_exist("modules");
    make_directory_if_it_does_not_exist("src/generated");


    {
        file, success := file_open("src/generated/procedure_captures.jai", true, true);
        file_close(*file);
        if !success {
            write_entire_file("src/generated/procedure_captures.jai", "");
        }
    }

    #if COMPILE_SHADERS {{
        scope_set_working_directory("shaders");
        log("compiling shaders...");
        run_command("compile.bat");
    }}

    clone_red_mango_core := !is_directory("modules/Red_Mango_Core");
    if clone_red_mango_core {
        scope_set_working_directory("modules");
        run_command("git", "clone", "https://github.com/TraceMyers/Red_Mango_Core");
    }

    clone_vulkan := !is_directory("modules/Vulkan_With_VMA");
    if clone_vulkan {
        scope_set_working_directory("modules");
        run_command("git", "clone", "https://github.com/TraceMyers/Vulkan_With_VMA");
    }

    clone_imgui := !is_directory("modules/ImGui_VulkanWin32");
    if clone_imgui {
        scope_set_working_directory("modules");
        run_command("git", "clone", "https://github.com/TraceMyers/ImGui_VulkanWin32");
    }

    clone_zlib := !is_directory("modules/zlib");
    if clone_zlib {
        scope_set_working_directory("modules");
        run_command("git", "clone", "https://github.com/TraceMyers/zlib");
    }

    set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    build_options := get_build_options(w);

    // react to arguments
    args : []string = build_options.compile_time_command_line;
    build_release: bool;
    updating := false;
    for args {
        k := it_index;
        if it == "release" {
            build_release = true;
        } else if it == "update" {
            updating = true;
        } else if updating {
            if !update_module(it) {
                return;
            }
        }
    }

    build_options.output_type = .EXECUTABLE;
    build_options.entry_point_name = "main";
    build_options.output_executable_name = "game";
    build_options.output_path = "bin";
    build_options.backend = .X64;

    optimization: Optimization_Type;
    if build_release {
        build_options.backend = .LLVM;
        optimization = .VERY_OPTIMIZED;
        set_optimization(*build_options, optimization);
    } else {
        optimization = .DEBUG;
        set_optimization(*build_options, optimization);
    }

    linker_args: [..]string;
    for build_options.additional_linker_arguments {
        array_add(*linker_args, it);
    }
    // vulkan memory allocator depends on this
    array_add(*linker_args, "libcpmt.lib");
    array_add(*linker_args, "concrt.lib");
    build_options.additional_linker_arguments = linker_args;

    set_build_options(build_options, w);

    log("\ncompiling game...\n ");

    // build

    // force the compiler to wait for compiler_wait_for_message() calls so that the compilation process can be customized during compilation
    compiler_begin_intercept(w);

    // buildvars
    add_build_string(tprint(
#string HERE
BUILDVAR_PROFILERS_ACTIVE :: %;
BUILDVAR_COLLISION_DEBUG :: %;
BUILDVAR_GENERATE_PRIMITIVE_MESH_LOADER_FILES :: %;
HERE, 
        PROFILERS_ACTIVE,
        COLLISION_DEBUG,
        GENERATE_PRIMITIVE_MESH_LOADER_FILES
    ), w);

    add_build_string(tprint("Compiler :: #import \"Compiler\";\nBUILDVAR_BUILD_CONFIG :: Compiler.Optimization_Type.%;", optimization), w);

    add_build_file("src/prebuild/scope_timer.jai", w);
    // add the definition of get_scope_timer_id() to compilation. its id counter is declared in this file, so it is only usable during compilation.
    add_build_string(tprint(GET_SCOPE_TIMER_ID_PROC_DEF_FMT_STRING, *scope_timer_id_counter), w);

    add_build_file("src/game.jai", w);

    procs_to_capture_as_structs: [..]*Code_Procedure_Header;
    gen_float_command_line_var_procs: [..]string;
    gen_bool_command_line_var_procs: [..]string;
    command_line_proc_names: [..]string;
    generated_code: bool;

    while true {
        m := compiler_wait_for_message();
        if m.kind == .COMPLETE {
            m_complete := cast(*Message_Complete)m;
            if m_complete.error_code != .NONE {
                log("compile error: %. exiting", m_complete.error_code);
            }
            break;
        }
        // collect command line procedures
        if m.kind == .TYPECHECKED {
            m_typechecked := cast(*Message_Typechecked)m;
            for m_typechecked.declarations {
                if it.expression.kind != .DECLARATION then continue;
                if it.expression.type.type == .FLOAT {
                    for note : it.expression.notes {
                        if note.text == "command_line" {
                            log("found command line var: %", it.expression.name);
                            array_add(*gen_float_command_line_var_procs, it.expression.name);
                            command_line_proc_name := tprint("vset_%", it.expression.name);
                            array_add(*command_line_proc_names, command_line_proc_name);
                        }
                    }
                } else if it.expression.type.type == .BOOL {
                    for note : it.expression.notes {
                        if note.text == "command_line" {
                            log("found command line var: %", it.expression.name);
                            array_add(*gen_bool_command_line_var_procs, it.expression.name);
                            set_command_line_proc_name := tprint("vset_%", it.expression.name);
                            toggle_command_line_proc_name := tprint("vtoggle_%", it.expression.name);
                            array_add(*command_line_proc_names, set_command_line_proc_name);
                            array_add(*command_line_proc_names, toggle_command_line_proc_name);
                        }
                    }
                } else if it.expression.type.type == .PROCEDURE {
                    decl := it.expression.(*Code_Declaration);
                    if decl.expression != null && decl.expression.kind == .PROCEDURE_HEADER {
                        proc_header := decl.expression.(*Code_Procedure_Header);
                        for note : proc_header.notes {
                            if note.text == "command_line" {
                                log("found command line proc: %", proc_header.name);
                                array_add(*command_line_proc_names, proc_header.name);
                            } else {
                                #if GENERATE_PROCEDURE_BODY_CAPTURES {
                                    if note.text == "capture_body_as_struct" {
                                        #if GENERATE_PROCEDURE_BODY_CAPTURES {
                                            array_add(*procs_to_capture_as_structs, proc_header);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if m.kind == .PHASE {
            m_phase := cast(*Message_Phase)m;
            if m_phase.phase == .TYPECHECKED_ALL_WE_CAN && !generated_code {
                #if REGENERATE_ASSET_REFERENCES {
                    create_assets_file();
                }
                generate_captured_procedures(procs_to_capture_as_structs, w);
                generate_command_line_code(gen_float_command_line_var_procs, gen_bool_command_line_var_procs, command_line_proc_names, w);
                log("\nend code generation\n");
                generated_code = true;
            }
        }
    }

    compiler_end_intercept(w);
}

// pull this repository when the argument to do so is passed.
update_module :: (module_name: string) -> bool {
    log("\nupdating %\n ", module_name);
    module_dir := tprint("modules/%", module_name);
    if !is_directory(module_dir) {
        log("failed to update because ($project dir)/% does not exist", module_dir);
        return false;
    }
    scope_set_working_directory(module_dir);
    run_command("git", "pull");
    log("   ");
    return true;
}

scope_set_working_directory :: (dir: string) #expand {
    cwd := get_working_directory();
    set_working_directory(dir);
    `defer set_working_directory(cwd);   
}

capitalize_for_type_name :: (str: *string) {
    last_char_was_letter := false;
    for *(str.*) {
        if (it.* >= "a" && it.* <= "z") || (it.* >= "A" && it.* <= "Z") {
            if !last_char_was_letter &&  (it.* >= "a" && it.* <= "z") {
                it.* += (#char "A").(u8) - (#char "a").(u8);
            }
            last_char_was_letter = true;
        } else {
            last_char_was_letter = false;
        }
    }
}

get_generated_struct_name :: (str: string) -> string {
    GENERATED :: "Procedure_Block_Capture__";
    out_str := alloc_string(str.count + GENERATED.count);
    memcpy(out_str.data, GENERATED.data, GENERATED.count);
    memcpy(out_str.data + GENERATED.count, str.data, str.count);
    // capitalize_for_type_name(*out_str);
    return out_str;
}

process_per_line :: (str: string, per_line_proc: (line: *string, line_index: s64, in_data: *void), in_data: *void) -> line_count: s64 {
    line_count: s64;
    left, right: string;
    right = str;
    success: bool;
    while true {
        prev_right := right;
        success, left, right = split_from_left(right, #char "\n");
        if !success {
            if prev_right.count > 0 {
                per_line_proc(*prev_right, line_count, in_data); 
                line_count += 1;
            }
            break;
        }
        if left.count > 0 && left[left.count-1] == #char "\r" {
            left.count -= 1;
        }
        per_line_proc(*left, line_count, in_data); 
        line_count += 1;
    }
    return line_count;
}

generate_command_line_code :: (gen_float_command_line_var_procs: [..]string, gen_bool_command_line_var_procs: [..]string, command_line_proc_names: [..]string, w: Workspace) {
    if gen_float_command_line_var_procs.count == 0 && gen_bool_command_line_var_procs.count == 0 {
        return;
    }

    builder: String_Builder;

    for varname : gen_float_command_line_var_procs {
        print_to_builder(*builder, 
#string HERE
vset_% :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 1);
    x, success := try_parse_command_line_arg(*args[0], float64);
    if success {
        % = xx x;
    } else {
        rm_error("failed parsing input as float: %%", args[0]._string);
    }
}
HERE,
            varname, varname
        );
    }

    for varname : gen_bool_command_line_var_procs {
        print_to_builder(*builder, 
#string HERE
vset_% :: (args: []Command_Line_Argument) {
    if args.count == 1 {
        x, success := try_parse_command_line_arg(*args[0], s64);
        if success {
            % = x != 0;
        }
    } else if args.count == 0 {
        % = true;
    }
}
vtoggle_% :: (args: []Command_Line_Argument) {
    if args.count > 0 then return;
    % = !%;
}
HERE,
            varname, varname, varname, varname, varname, varname
        );
    }

    print_to_builder(*builder, "COMMAND_LINE_PROCEDURES :: Command_Line_Procedure.[\n");
    for command_line_proc_names {
        input_string := it;
        if begins_with(input_string, "vset") {
            input_string = copy_string(input_string);
            input_string[4] = " ";
        } else if begins_with(input_string, "vtoggle") {
            input_string = copy_string(input_string);
            input_string[7] = " ";
        }

        hash := native_XXH64(input_string.data, xx input_string.count, 0xDEADBEEF);
        print_to_builder(*builder, "\t.{name=\"%\", proc=%, hash=%},\n", input_string, it, hash);
    }
    print_to_builder(*builder, "];\n");

    // add command line proc stuff to the build
    add_build_string(builder_to_string(*builder), w);
}

generate_captured_procedures :: (procs_to_capture_as_structs: [..]*Code_Procedure_Header, w: Workspace) {
    #if !GENERATE_PROCEDURE_BODY_CAPTURES {
        add_build_file("src/generated/procedure_captures.jai", w);
        return;
    }

    log("generating captured procedures...");

    procedures_builder: String_Builder;
    struct_definitions_builder: String_Builder;
    struct_declarations_builder: String_Builder;

    print_to_builder(*procedures_builder, "Procedure_Capture_Duplicate :: struct {\n\n");
    print_to_builder(*struct_definitions_builder, "Procedure_Capture_Type :: struct {\n\n");
    print_to_builder(*struct_declarations_builder, "Procedure_Capture_Data :: struct {\n");

    for proc_header : procs_to_capture_as_structs {
        if proc_header.body_or_null == null then continue;

        body := proc_header.body_or_null;
        proc_body_in_filename := body.block.location.enclosing_load.fully_pathed_filename;
        proc_body_file, success := read_entire_file(proc_body_in_filename);
        if !success {
            log("failed to open file % when generating struct for proc %", proc_body_in_filename, proc_header.name);
            continue;
        }
        
        Procedure_Lines_Collector :: struct {
            procedure_lines: [..]string;
            procedure_block: *Code_Block;
        }

        collect_procedure_lines :: (line: *string, line_index: s64, in_data: *void) {
            collector := in_data.(*Procedure_Lines_Collector);
            proc_body_line_begin := collector.procedure_block.location.l0;
            proc_body_line_end := collector.procedure_block.location.l1;
            if line_index >= proc_body_line_begin-1 && line_index <= proc_body_line_end {
                array_add(*collector.procedure_lines, line.*);
            }
        }
        collector := Procedure_Lines_Collector.{procedure_block=proc_header.body_or_null.block};
        process_per_line(proc_body_file, collect_procedure_lines, *collector);

        if collector.procedure_lines.count < 2 {
            log("failed to collect a valid line count when generating a struct for proc %", proc_header.name);
            continue;
        }
        proc_header_line := *collector.procedure_lines[0];
        if !begins_with(proc_header_line.*, proc_header.name) {
            log("when generating a struct for proc %, noticed that line % does not begin with the procedure's name. failed to generate the alternate proc", proc_header.name, proc_header_line.*);
        }

        for #v2 < *collector.procedure_lines {
            // replace the note with one noting that the procedure was generated by this process
            line_with_replaced_note, replaced_count := replace(it.*, "@capture_body_as_struct", "@struct_capture_duplicate");
            if replaced_count > 0 {
                it.* = line_with_replaced_note;
            }
            // delete declaration lines that aren't also assignments. their declarations would be in conflict with the existence of the same-named struct members.
            if it_index > 0
            && find_index_from_left(it.*, ":") != -1
            && (find_index_from_left(it.*, "=") == -1 || find_index_from_left(it.*, "---") != -1) {
                array_ordered_remove_by_index(*collector.procedure_lines, it_index);
                continue;
            }
            // turn combined declaration-assignment statements into just assignments (assigning to the struct field)
            line_with_replaced_combination_decl_expr:, replaced_count = replace(it.*, ":=", "=");
            if replaced_count > 0 {
                it.* = line_with_replaced_combination_decl_expr;
            }
        }

        // add the struct instance's 'using' line into the top of the body
        using_statement := tprint("\tusing procedure_capture_data.%;", proc_header.name);
        array_insert_at(*collector.procedure_lines, using_statement, 1);

        // statically declare an instance of the generated struct in the global scope (maybe change later)
        print_to_builder(*struct_declarations_builder, "\t%: Procedure_Capture_Type.%;\n", proc_header.name, proc_header.name);

        // declare the duplicate version of the procedure that, rather than just using local variables, stores all values into the struct instance.
        for collector.procedure_lines {
            print_to_builder(*procedures_builder, "\t%\n", it);
        }

        // declare the struct type
        print_to_builder(*struct_definitions_builder, "\t% :: struct {\n", proc_header.name);
        recursively_gather_declarations_from_block(body.block, *struct_definitions_builder);
        print_to_builder(*struct_definitions_builder, "\t}\n\n");
    }

    file_bytes := tprint(
        "procedure_capture_data: Procedure_Capture_Data;\n\n%}\n\n%}\n\n%}", 
        builder_to_string(*struct_definitions_builder),
        builder_to_string(*struct_declarations_builder),
        builder_to_string(*procedures_builder)
    );

    write_entire_file("src/generated/procedure_captures.jai", file_bytes);
    add_build_file("src/generated/procedure_captures.jai", w);
}

recursively_gather_declarations_from_block :: (block: *Code_Block, builder: *String_Builder, max_depth := 10, depth := 0) {
    if block == null then return;
    if depth > max_depth then return;

    for block.statements {
        if it.kind == .DECLARATION {
            decl := it.(*Code_Declaration);
            if decl.type_inst != null && decl.type_inst.type_valued_expression != null {
                type_ident := decl.type_inst.type_valued_expression.(*Code_Ident);
                print_to_builder(builder, "\t\t%: %;\n", decl.name, type_ident.name);
            } else if decl.expression {
                print_to_builder(builder, "\t\t%: %;\n", decl.name, (cast(*Type)*decl.expression.type).*);
            }
        } else if it.kind == .COMPOUND_DECLARATION {
            decl := it.(*Code_Compound_Declaration);
            if decl.declaration_properties != null {
                if decl.declaration_properties.expression != null {
                    proc_return_types: [..]string;
                    // todo: I really don't think this covers the bases
                    if decl.declaration_properties.expression.kind == .PROCEDURE_CALL {
                        proc_call := decl.declaration_properties.expression.(*Code_Procedure_Call);
                        proc_expression := proc_call.resolved_procedure_expression;
                        if proc_expression.kind == .PROCEDURE_HEADER {
                            proc_header := proc_expression.(*Code_Procedure_Header);
                            for proc_header.returns {
                                if it.type_inst != null && it.type_inst.type_valued_expression != null {
                                    type_ident := it.type_inst.type_valued_expression.(*Code_Ident);
                                    array_add(*proc_return_types, type_ident.name);
                                }
                            }
                        }
                    } 
                    expression_type := cast(*Type)*decl.declaration_properties.expression.type;
                    for decl.comma_separated_assignment.arguments {
                        arg_node := it.node;
                        if arg_node.kind == .IDENT {
                            ident := arg_node.(*Code_Ident);
                            if proc_return_types.count > it_index {
                                print_to_builder(builder, "\t\t%: %;\n", ident.name, proc_return_types[it_index]);
                            } else {
                                print_to_builder(builder, "\t\t%: %;\n", ident.name, expression_type.*);
                            }
                        }
                    }
                } else if decl.declaration_properties.type_inst != null
                && decl.declaration_properties.type_inst.type_valued_expression.kind == .IDENT {
                    type_ident := decl.declaration_properties.type_inst.type_valued_expression.(*Code_Ident);
                    for decl.comma_separated_assignment.arguments {
                        arg_node := it.node;
                        if arg_node.kind == .IDENT {
                            ident := arg_node.(*Code_Ident);
                            print_to_builder(builder, "\t\t%: %;\n", ident.name, type_ident.name);
                        }
                    }
                }
            }
        } else if it.kind == .IF {
            if_statement := it.(*Code_If);
            recursively_gather_declarations_from_block(if_statement.then_block, builder, depth=depth+1);
            recursively_gather_declarations_from_block(if_statement.else_block, builder, depth=depth+1);
        }
    }
}

// the counter used for scope timer id's
scope_timer_id_counter: u32;

GET_SCOPE_TIMER_ID_PROC_DEF_FMT_STRING :: #string HERE
#import "Atomics";
get_scope_timer_id :: () -> u32 {
    comptime_id_counter : *u32 = xx %;
    out_id := atomic_add(comptime_id_counter, 1);
    return out_id;
}
HERE;

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "xxHash";
Program_Print :: #import "Program_Print";

#load "src/prebuild/asset.jai";
#load "src/file.jai";
// #load "src/prebuild/entity_construction.jai";
