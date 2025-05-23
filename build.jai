
// TODO: this build script depends on git, which is silly
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
    clone_vulkan := !is_directory("modules/vulkan-jai");
    if clone_vulkan {
        scope_set_working_directory("modules");
        run_command("git", "clone", "https://github.com/rytc/vulkan-jai");
    }

    set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    build_options := get_build_options(w);

    // react to arguments
    args : []string = build_options.compile_time_command_line;
    for args {
        if it == "update-red-mango-core" {
            if !update_red_mango_core() {
                return;
            }
        }
    }

    build_options.output_type = .EXECUTABLE;
    build_options.output_executable_name = "game";
    build_options.output_path = "bin";
    set_build_options(build_options, w);
    // build
    add_build_file("src/game.jai", w);
}

// pull this repository when the argument to do so is passed.
update_red_mango_core :: () -> bool {
    log("\nupdating red mango core\n ");
    if !is_directory("modules/Red_Mango_Core") {
        log("failed to update because ($project dir)/modules/Red_Mango_Core does not exist");
        return false;
    }
    scope_set_working_directory("modules/Red_Mango_Core");
    run_command("git", "fetch", "--all");
    run_command("git", "reset", "--hard", "origin/master");
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