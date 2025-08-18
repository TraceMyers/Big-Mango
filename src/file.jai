
// $todo: this stuff was brought over from the Curry Engine codebase, and some of it references irrevelevant / nonexistent stuff

file_name_in_path :: (path: string) -> string {
    if path.count == 0 then return "no file";
    success, _, filename := split_from_right(path, #char "\\");
    if success then return filename; else return path;
}

open_file_dialog :: ($FileType: Type) -> FileType, bool {
    #if OS == .WINDOWS {
        MAX_FILE_NAME_LENGTH :: 4096;
        filename_buffer : [MAX_FILE_NAME_LENGTH]u8;
        fna : OPENFILENAMEA;
        fna.lStructSize = size_of(OPENFILENAMEA);
        fna.hwndOwner = null; // can pass in window
        fna.lpstrFilter = 
            #ifx FileType == Image then "Image Files\0*.jpg;*.png;*.gif;*.bmp;*.tga;\0\0"
            else #ifx FileType == Sprite then "Curry Sprite\0*.cspr;\0\0"
            else #ifx FileType == *Library_Info then "Dynamic Link LIbrary\0*.dll;\0\0"
            else "Invalid File Type";
        fna.lpstrFile = *filename_buffer[0];
        fna.nMaxFile = MAX_FILE_NAME_LENGTH;
        fna.lpstrTitle = "It's a file picker, friendo";
        fna.lpstrInitialDir = temp_c_string(get_path_of_running_executable());
        // fna.Flags =
        got_file := GetOpenFileNameA(*fna);

        if got_file {
            path : string = .{c_style_strlen(*filename_buffer[0]), *filename_buffer[0]};
            #if FileType == Image {
                return image_create(path), true;
            } else #if FileType == Sprite {
                return sprite_load(path), true;
            } else #if FileType == *Library_Info {
                return os_load_library(.[""], path, false), true;
            }
        }
    } else {
        // TODO more OS!
    }

    INFO :: #run type_info(FileType);
    #if #run INFO.type == .POINTER {
        return null, false;
    } else {
        return .{}, false;
    }
}

save_file_dialog :: ($FileType : Type) -> string, bool {
    #if OS == .WINDOWS {
        MAX_FILE_NAME_LENGTH :: 4096;
        filename_buffer : [MAX_FILE_NAME_LENGTH]u8;
        fna : OPENFILENAMEA;
        fna.lStructSize = size_of(OPENFILENAMEA);
        fna.hwndOwner = null; // can pass in window
        fna.lpstrFilter = 
            #ifx FileType == Image then "Portable Network Graphics (.png)\0\0"
            else #ifx FileType == Sprite then "Curry Sprite (.cspr)\0\0"
            else "Invalid File Type";
        fna.lpstrFile = *filename_buffer[0];
        fna.nMaxFile = MAX_FILE_NAME_LENGTH;
        fna.lpstrTitle = "It's a file picker, friendo";
        fna.lpstrInitialDir = temp_c_string(get_path_of_running_executable());
        expected_extension := 
            #ifx FileType == Image then "png"
            else #ifx FileType == Sprite then "cspr"
            else "Invalid File Type";
        fna.lpstrDefExt = expected_extension.data;

        got_path := GetSaveFileNameA(*fna);
        if got_path {
            path := copy_temporary_string(string.{c_style_strlen(fna.lpstrFile), fna.lpstrFile});
            found_ext, _, extension := split_from_right(path, ".");
            if !found_ext {
                log("save_file_dialog: failed to find file extension");
                return .{}, false;
            }
            if compare(extension, expected_extension) != 0 {
                log("save_file_dialog: wrong extension. must be '%'", expected_extension);
                return .{}, false;
            }
            return path, true;
        }
        else {
            log("save_file_dialog: failed to get path");
        }
    } else {
        // TODO more OS!
    }
    return .{}, false;
}

find_all_files_with_extension :: (path: string, extension: string, recursive := true) -> []string {
    VisitData :: struct {
        file_extension: string;
        files: [..]string;
    }
    visitor :: (info: *File_Visit_Info, visit_data: *VisitData) {
        found_extension, _, extension := split_from_right(info.short_name, #char ".");
        if found_extension && compare(extension, visit_data.file_extension) == 0 {
            array_add(*visit_data.files, copy_temporary_string(info.full_name));
        }
    }

    visit_data: VisitData;
    visit_data.file_extension = extension;
    visit_data.files.allocator = temp;
    visit_files(path, recursive, *visit_data, visitor, true);
    return visit_data.files;
}