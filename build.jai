
compile_shaders := true;
#run {
    if compile_shaders {
        scope_set_working_directory("shaders");
        log("compiling shaders...");
        run_command("compile.bat");
    }
    // make sure environment is set up
    make_directory_if_it_does_not_exist("bin");
    make_directory_if_it_does_not_exist("modules");

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

    if build_release {
        build_options.backend = .LLVM;
        set_optimization(*build_options, .VERY_OPTIMIZED);
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

    add_build_file("src/game.jai", w);

    command_line_proc_names: [..]string;
    added_command_line_procedures: bool;

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
                if it.expression.type.type != .PROCEDURE then continue;
                for note : it.expression.notes {
                    if note.text == "command_line" {
                        log("found command line proc: %", it.expression.name);
                        array_add(*command_line_proc_names, it.expression.name);
                    }
                }
            }
        }
        if m.kind == .PHASE {
            m_phase := cast(*Message_Phase)m;
            if m_phase.phase == .TYPECHECKED_ALL_WE_CAN && !added_command_line_procedures {
                builder: String_Builder;
                print_to_builder(*builder, "COMMAND_LINE_PROCEDURES :: Command_Line_Procedure.[\n");
                for command_line_proc_names {
                    print_to_builder(*builder, "\t.{name=\"%\", proc=%},\n", it, it);
                }
                print_to_builder(*builder, "];\n");

                // add command line proc stuff to the build
                add_build_string(builder_to_string(*builder), w);
                added_command_line_procedures = true;
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

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

scope_set_working_directory :: (dir: string) #expand {
    cwd := get_working_directory();
    set_working_directory(dir);
    `defer set_working_directory(cwd);   
}