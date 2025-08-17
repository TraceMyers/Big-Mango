
Program_Meta_Data :: struct {
    world_id_counter: u64;
}

program_meta_data: Program_Meta_Data;

_program :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_meta_data = .{};
        loaded_data, success := read_entire_file("meta.bin");
        if success {
            // account for things being added / removed and just be careful not to add/remove s.t. shit gets fucked up?
            // or I guess propertly serialize...
            min_copy_size := min(size_of(Program_Meta_Data), loaded_data.count);
            memcpy(*program_meta_data, loaded_data.data, min_copy_size);
        }
    } else {
        save_program_meta_data();
    }
    return true;
}

save_program_meta_data :: () {
    meta_data: string;
    meta_data.data = xx *program_meta_data;
    meta_data.count = size_of(Program_Meta_Data);
    write_entire_file("meta.bin", meta_data);
}

get_new_world_id :: () -> u64 {
    program_meta_data.world_id_counter += 1;
    new_id := program_meta_data.world_id_counter;
    save_program_meta_data();
    return new_id;
}