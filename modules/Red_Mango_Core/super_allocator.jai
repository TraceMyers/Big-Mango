// ---------------------------------------------------------------------------------------------------------------------
// Super Allocator
// it's super

super_allocator_proc ::(mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    MIN_SIZE :: 8;
    MAX_SIZE :: 131072;

    dummy_super_allocator := allocator_data.(*Super_Allocator);

    #insert -> string {
        builder: String_Builder;
        

        print(*builder, 
#string HERE
        if dummy_super_allocator.min_alloc_size == {
HERE
        );

        size := MIN_SIZE;
        while size <= MAX_SIZE {
            print(*builder,
#string HERE
        case %;   
            super_allocator := allocator_data.(*Super_Allocator(%));
            return super_allocator_proc_impl(mode, size, old_size, old_memory, super_allocator);
HERE,
                size, size
            );
            size <<= 1;
        }

        print(*builder,
#string HERE
        case;
            assert(false, "invalid super allocator min alloc size: % (must be >= % and <= %)", dummy_super_allocator.min_alloc_size, MIN_SIZE, MAX_SIZE);
        }
HERE,
            size, MIN_SIZE, MAX_SIZE
        );
        return builder_to_string(*builder);
    };
    return null;
}

super_allocator_proc_impl :: inline (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, super_allocator: *Super_Allocator($MIN_ALLOC_SIZE)) -> *void {
    if mode == {
    case .ALLOCATE;
        return super_alloc(super_allocator, size);
    case .RESIZE;
        if old_memory != null {
            super_free(super_allocator, old_memory);
        }
        return super_alloc(super_allocator, size);
    case .FREE;
        if old_memory != null {
            super_free(super_allocator, old_memory);
        }
    case .STARTUP;
    case .SHUTDOWN;
    case .THREAD_START;
    case .THREAD_STOP;
    case .CREATE_HEAP;
    case .DESTROY_HEAP;
    case .IS_THIS_YOURS;
    case .CAPS;
    }
    return null;
}

Super_Allocator :: struct ($MIN_ALLOCATION_SIZE := 16) {
    using #as super_base: Allocator;
    min_alloc_size := xx MIN_ALLOCATION_SIZE;
    parent_allocator: Allocator;
    chunk_lists: [..][]Super_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE);
    books: Super_Allocator_Books;
    books_allocated_size: s64;
    default_outer_chunk_count_per_list: s32 = 32;
    shrink_to_min_lists: s32 = 1;
    default_reserve_size: s32;
    old_list_count: s32;

    CHUNKS_PER_HEAP :: 64;
    CHUNK_SIZE :: size_of(Super_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE));
    #run assert(is_power_of_two(MIN_ALLOCATION_SIZE));
    #run assert(MIN_ALLOCATION_SIZE >= size_of(Super_Allocation_Header));
}

Super_Allocation_Header :: struct {
    using metadata: union {
        bin: enum u8 {
            STANDALONE;
            SMALL;
            MEDIUM;
            LARGE;
        }
        // when an allocation is valid, the upper 4 bits are stamped with a specific bit pattern.
        // this is intentionally placed at byte 0 of the struct because the lowest byte of data is the one most likely to change, and so (naively speaking) most likely to change when trashed.
        bit_pattern: u8 = ---;
    }
    inner_chunk: u8;
    inner_chunk_count: u16;
    outer_chunk: u16;
    list: s16;
}

Super_Allocator_Outer_Chunk :: struct ($MIN_ALLOCATION_SIZE: s64) {
    inner_chunks: [64][MIN_ALLOCATION_SIZE]u8;
}

Super_Allocator_Books :: struct {
    largest_gap_per_list: *u8;
    gap_list_of_lists: []*u8;
    flag_list_of_lists: []*u64;
}

initialize_super_allocator :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), in_parent_allocator: Allocator, in_default_chunk_list_size := 0, add_chunk_lists := 1) {
    assert(chunk_lists.count == 0 && chunk_lists.data == null);
    allocator.* = .{};
    allocator.super_base.data = allocator;
    allocator.super_base.proc = super_allocator_proc;
    parent_allocator = in_parent_allocator;
    if in_default_chunk_list_size > 0 {
        default_reserve_size = xx in_default_chunk_list_size;
    } else {
        default_reserve_size = xx (CHUNK_SIZE * 64);
    }
    if add_chunk_lists > 0 then for 0..add_chunk_lists - 1 {
        add_chunk_list(allocator, default_reserve_size, false);
    }
}

shutdown_super_allocator :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE)) {
    for list : *chunk_lists {
        array_reset(list);
    }
    array_reset(*chunk_lists);
    free(books.largest_gap_per_list);
    allocator.* = .{};
}

add_chunk_list :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), min_bytes: s64, remake_books := true) {
    scope_set_allocator(parent_allocator);
    chunk_list := array_add(*chunk_lists);
    alloc_chunk_count := max(div_ceil(min_bytes, CHUNK_SIZE), 2);
    // Super_Allocation_Header requirements
    assert(chunk_lists.count <= S16_MAX);
    assert(alloc_chunk_count <= U16_MAX);
    if alloc_chunk_count < 8 && !did_small_chunk_count_warning {
        rm_warning("min bytes % leads to only % chunks being allocated per super allocator heap. the number of chunks per heap should probably be somewhere between 8 and 128", min_bytes, alloc_chunk_count);
        did_small_chunk_count_warning = true;
    }
    chunk_list.* = array_alloc(Super_Allocator_Outer_Chunk(MIN_ALLOC_SIZE), alloc_chunk_count);
    grow_super_allocator_books(allocator);    
}

basic_validity_check :: inline (using header: Super_Allocation_Header) -> bool {
    return list >= 0 && (bit_pattern & 0xf0) == ALLOCATOR_VALIDATION_PATTERN;
}

super_alloc :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), size: s64) -> *void {
    allocation_size_with_header := size + HEADER_SPACE;
    ptr := try_super_alloc(allocator, allocation_size_with_header);
    // didn't find existing space, need to grow
    if ptr == null {
        add_chunk_list(allocator, max(allocation_size_with_header, default_reserve_size));
        ptr = try_super_alloc(allocator, allocation_size_with_header);
        assert(ptr != null);
    }
    return ptr.(*u8) + HEADER_SPACE;
}

super_free :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), ptr: *void) {
    byte_ptr := ptr.(*u8);
    header := (byte_ptr - HEADER_SPACE).(*Super_Allocation_Header);
    assert(basic_validity_check(header.*));

    list := header.list;
    outer_chunk := header.outer_chunk;
    inner_chunk := header.inner_chunk;
    inner_chunk_count := header.inner_chunk_count;

    if inner_chunk_count > 64 {
        outer_chunk_count := div_ceil(inner_chunk_count, 64);
        assert(outer_chunk_count <= U16_MAX);
        li := *chunk_lists[list];
        start_index := outer_chunk;
        end_index := start_index + outer_chunk_count - 1;
        assert(end_index < li.count);
        for i : start_index..end_index-1 {
            flag_set := *books.flag_list_of_lists[list][i];
            assert((flag_set.* & U64_MAX) == U64_MAX);
            flag_set.* = 0;
            gap := *books.gap_list_of_lists[list][i];
            gap.* = 64;
            inner_chunk_count -= 64;
        }
        outer_chunk = end_index;
        inner_chunk = 0;
    }

    mask: u64 = ---;
    if inner_chunk_count == 64 {
        mask = U64_MAX;
    } else {
        mask = (((1).(u64) << (inner_chunk_count)) - 1) << (inner_chunk);
    }

    flag_set := *books.flag_list_of_lists[list][outer_chunk];
    assert(flag_set.* & mask == mask);
    flag_set.* &= ~mask;

    gap := *books.gap_list_of_lists[list][outer_chunk];
    gap.* = xx largest_gap_in_bit_sequence_lsb(flag_set.*);

    largest_gap := *books.largest_gap_per_list[list];
    if inner_chunk_count > 64 {
        largest_gap.* = 64;
    } else if gap.* > largest_gap.* {
        max_gap: u8;
        for chunk : 0..chunk_lists[list].count-1 {
            gap = *books.gap_list_of_lists[list][outer_chunk];
            max_gap = max(max_gap, gap.*);
            if max_gap == CHUNKS_PER_HEAP then break;
        }
        largest_gap.* = max_gap;
    }

    header.* = .{};
}

try_super_alloc :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), size: s64) -> *void {
    header: *Super_Allocation_Header;
    alloc_inner_chunk_count := div_ceil(size, MIN_ALLOC_SIZE);
    if alloc_inner_chunk_count > 64 {
        header = try_super_alloc_large(allocator, alloc_inner_chunk_count);
    } else {
        header = try_super_alloc_small(allocator, alloc_inner_chunk_count);
    }
    if header != null {
        // (these two fields are unioned)
        header.bin = .STANDALONE;
        header.bit_pattern |= ALLOCATOR_VALIDATION_PATTERN;
    }
    return header;
}

try_super_alloc_small :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), alloc_inner_chunk_count: s64) -> *Super_Allocation_Header {
    alloc_mask: u64 = ---;
    if alloc_inner_chunk_count == 64 {
        alloc_mask = U64_MAX;
    } else {
        alloc_mask = ((1).(u64) << alloc_inner_chunk_count) - (1).(u64);
    }

    out_header: *Super_Allocation_Header;
    allocated_gap_is_max := false;

    if chunk_lists.count > 0 then for list : 0..chunk_lists.count-1 {
        largest_gap := *books.largest_gap_per_list[list];
        if largest_gap.* >= alloc_inner_chunk_count {
            max_gap: u8;
            for chunk : 0..chunk_lists[list].count-1 {
                gap := *books.gap_list_of_lists[list][chunk];
                // only need to go in here if we haven't found the allocation that must be in this list yet...
                if out_header == null && gap.* >= alloc_inner_chunk_count {
                    allocated_gap_is_max = gap.* == largest_gap.*;
                    flag_set := *books.flag_list_of_lists[list][chunk];
                    alloc_index := find_index_of_missing_bit_sequence_lsb(flag_set.*, alloc_mask, alloc_inner_chunk_count);
                    flag_set.* |= alloc_mask << alloc_index;
                    gap.* = xx largest_gap_in_bit_sequence_lsb(flag_set.*);
                    out_header = (*chunk_lists[list][chunk].inner_chunks[alloc_index]).(*Super_Allocation_Header);
                    out_header.list = xx list;
                    out_header.outer_chunk = xx chunk;
                    out_header.inner_chunk = xx alloc_index;
                    out_header.inner_chunk_count = xx alloc_inner_chunk_count;
                    if !allocated_gap_is_max {
                        max_gap = largest_gap.*;
                        break;
                    }
                }
                // ...otherwise, if we have found it, we're just doing bookkeeping
                max_gap = max(max_gap, gap.*);
                if max_gap == CHUNKS_PER_HEAP {
                    break;
                }
            }
            assert(out_header != null);
            largest_gap.* = max_gap;
            break;
        }
    }

    return out_header;
}

try_super_alloc_large :: (using allocator: *Super_Allocator($MIN_ALLOC_SIZE), alloc_inner_chunk_count: s64) -> *Super_Allocation_Header {
    assert(alloc_inner_chunk_count > 64);
    alloc_outer_chunk_count := div_ceil(alloc_inner_chunk_count, 64);
    assert(alloc_outer_chunk_count <= U16_MAX);

    out_header: *Super_Allocation_Header;

    if chunk_lists.count > 0 then for list_index : 0..chunk_lists.count-1 {
        largest_gap := books.largest_gap_per_list[list_index];
        if largest_gap < 64 {
            continue;
        }
        chunk_index := 0;
        consecutive_free_outer_chunk_ct := 0;
        list := *chunk_lists[list_index];
        while chunk_index + alloc_outer_chunk_count <= list.count {
            gap := books.gap_list_of_lists[list_index][chunk_index];
            if gap == 64 {
                consecutive_free_outer_chunk_ct += 1;
                if consecutive_free_outer_chunk_ct == alloc_outer_chunk_count {
                    first_chunk_index := chunk_index - (alloc_outer_chunk_count-1);
                    last_chunk_index := first_chunk_index + (alloc_outer_chunk_count-1);
                    remain_inner_chunks := alloc_inner_chunk_count;
                    for c : first_chunk_index..last_chunk_index {
                        if remain_inner_chunks >= 64 {
                            books.gap_list_of_lists[list_index][c] = 0;
                            books.flag_list_of_lists[list_index][c] = U64_MAX;
                        } else {
                            books.gap_list_of_lists[list_index][c] = xx (64 - remain_inner_chunks);
                            books.flag_list_of_lists[list_index][c] = ((1).(u64) << remain_inner_chunks) - 1;
                        }
                        remain_inner_chunks -= 64;
                    }
                    out_header = (*list.*[first_chunk_index].inner_chunks[0]).(*Super_Allocation_Header);
                    out_header.list = xx list_index;
                    out_header.outer_chunk = xx first_chunk_index;
                    out_header.inner_chunk = 0;
                    out_header.inner_chunk_count = xx alloc_inner_chunk_count;
                    break;
                }
            } else {
                consecutive_free_outer_chunk_ct = 0;
            }
            chunk_index += 1;
        }
        if out_header != null then break;
    }

    return out_header;
}

grow_super_allocator_books :: (using allocator: *Super_Allocator($MIN_ALLOCATION_SIZE)) {
    scope_set_allocator(parent_allocator);
    auto_release_temp();
    assert(chunk_lists.count > 0);

    reader: Serializer(.STATIC, .PRIMITIVE);
    writer: Serializer(.DYNAMIC, .PRIMITIVE);

    reader.memory.data = books.largest_gap_per_list;
    reader.memory.count = books_allocated_size;

    writer.memory = talloc_string(max(reader.memory.count * 2, 1024));
    writer.allocator = temp;

    set_rw_mode(*reader, .READ, false);
    set_rw_mode(*writer, .WRITE, false);

    do_copy := old_list_count > 0;
    if do_copy {
        assert(books.largest_gap_per_list != null);
    }

    // the writer needs to move its head forward however many bytes were read into it. so, capture the head delta
    // from the reader and return it, so the writer can move its head forward by that much.
    capture_head_delta :: ($reader_call: Code) -> s32 #expand {
        cur_head := reader.head;
        #insert reader_call;
        new_head := reader.head;
        return new_head - cur_head;
    }

    // ----- gap super list -----

    if do_copy {
        // copy the old super list
        writer.head += capture_head_delta(read_bytes(*reader, writer.memory.data, xx old_list_count));
    }
    // add a new final entry indicating 64 inner chunks is the largest available allocation in the new list
    free_count : u8 = 64;
    write(*writer, *free_count);

    // ----- gap array datas -----

    gap_array_datas_offset := writer.head;
    if do_copy {
        // copy over each array of gaps
        for 0..chunk_lists.count-2 {
            writer.head += capture_head_delta(read_bytes(*reader, writer.memory.data + writer.head, xx chunk_lists[it].count));
        }
    }
    // create new array of gaps
    final_list := *chunk_lists[chunk_lists.count-1];
    for 0..final_list.count-1 {
        write(*writer, *free_count);
    }

    // all reads and writes going forward are 8-byte aligned, this only needs to be done once.
    // in normal serialization this happens automatically, but this isn't normal serialization
    align_head_up(*reader, 8);
    check_new_head(*writer, writer.head+8);
    align_head_up(*writer, 8);

    // ----- flag array datas -----

    flag_array_datas_offset := writer.head;
    if do_copy {
        // copy over each array of flags
        for 0..chunk_lists.count-2 {
            writer.head += capture_head_delta(read_bytes(*reader, writer.memory.data + writer.head, xx (chunk_lists[it].count * 8)));
        }
    }
    // create new array of flags
    zero_u64 : u64 = 0;
    for 0..final_list.count-1 {
        write(*writer, *zero_u64);
    }

    // ----- gap array pointers -----

    pointers_to_gap_arrays_offset := writer.head;
    running_gap_array_offset : u64 = xx gap_array_datas_offset;
    if do_copy {
        // write offsets to gap array datas. will add base address later
        for 0..chunk_lists.count-2 {
            write(*writer, *running_gap_array_offset);
            running_gap_array_offset += xx chunk_lists[it].count;
        }
    }
    // create new offset/pointer to gap array datas
    write(*writer, *running_gap_array_offset);

    // ----- flag array pointers -----

    pointers_to_flag_arrays_offset := writer.head;
    running_flag_array_offset : u64 = xx flag_array_datas_offset;
    if do_copy {
        // write offsets to flag array datas. will add base address later
        for 0..chunk_lists.count-2 {
            write(*writer, *running_flag_array_offset);
            running_flag_array_offset += xx (chunk_lists[it].count * 8);
        }
    }
    // create new offset/pointer to flag array datas
    write(*writer, *running_flag_array_offset);

    old_allocation: *u8 = books.largest_gap_per_list;
    new_books_data_allocation: *u8;
    new_books_data_size: s64;

    if writer.head > books_allocated_size {
        new_books_data_size = ceil_to_pow2_multiple(max(writer.head, 1024), 2);
        new_books_data_allocation = array_alloc(u8, new_books_data_size,, parent_allocator).data;
        if old_allocation != null {
            free(old_allocation);
        }
    } else {
        new_books_data_size = books_allocated_size;
        new_books_data_allocation = old_allocation;
    }

    memset(new_books_data_allocation, 0, new_books_data_size);
    memcpy(new_books_data_allocation, writer.memory.data, writer.head);

    // tell the books struct where its data is
    books.largest_gap_per_list = new_books_data_allocation;
    books.gap_list_of_lists.data = xx (new_books_data_allocation + pointers_to_gap_arrays_offset);
    books.gap_list_of_lists.count = chunk_lists.count;
    books.flag_list_of_lists.data = xx (new_books_data_allocation + pointers_to_flag_arrays_offset);
    books.flag_list_of_lists.count = chunk_lists.count;

    // previously, because we didn't know what the address of the allocation would be, when we created arrays of pointers,
    // we had to store offsets rather than actual addresses. now that we know the allocation address, we can add that
    // so the pointer points to the right place.
    for 0..chunk_lists.count-1 {
        gap_array_offset_from_allocation_head := books.gap_list_of_lists[it].(u64);
        books.gap_list_of_lists[it] = (new_books_data_allocation + gap_array_offset_from_allocation_head).(*u8);
        flag_array_offset_from_allocation_head := books.flag_list_of_lists[it].(u64);
        books.flag_list_of_lists[it] = (new_books_data_allocation.(u64) + flag_array_offset_from_allocation_head).(*u64);
    }

    books_allocated_size = new_books_data_size;
    old_list_count = xx chunk_lists.count;
}

repr :: (using allocator: *Super_Allocator($MIN_ALLOCATION_SIZE)) -> string {
    builder: String_Builder;
    builder.allocator = temp;
    for list : 0..chunk_lists.count-1 {
        print_to_builder(*builder, "list %:\n", FormatInt.{value=list, minimum_digits=2});
        for chunk : 0..chunk_lists[list].count-1 {
            print_to_builder(*builder, "\tchunk %: [%|%]\n", 
                FormatInt.{value=chunk, minimum_digits=3}, 
                FormatInt.{value=books.gap_list_of_lists[list][chunk], minimum_digits=2},
                FormatInt.{value=books.flag_list_of_lists[list][chunk], base=2, minimum_digits=64},
            );
        }
    }
    return builder_to_string(*builder);
}

// 0: one byte gap per chunk list
// 1: array of gap bytes per chunk list, laid out one after another
// 2: align to 8 bytes
// 3: array of flag u64s per chunk list, laid out one after another
// 4. one slice per chunk list, each pointing into [1]
// 5. one slice per chunk list, each pointing into [3]

// books "array data offset" offsets to [4]

/*
Super_Allocator {
    books pointers:

    ----------- largest_gap_array_ptr    
    |     ----- lists_of_gaps_array_ptr 
    |     |     flag_set_array_ptr ---------------------------------------
    |     |                                                               |
    |     ------------------------------------------                      |
    v                                              V                      v
    [gaps data | lists_of_gaps data | flags data | [lists_of_gaps_ptrs] | [flags_ptrs]
                  ^    ^   ^   ^                    |  |   |   |           |   |  |  |
                  |    |   |   |--------------------   |   |   |           (point into the flags data. omitted arrows because diagram would get confusing)
                  |    |   |---------------------------|   |   |
                  |    |------------------------------------   |
                  |--------------------------------------------|

*/

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

did_small_chunk_count_warning := false;

HEADER_SPACE :: #run ceil_to_pow2_multiple(size_of(Super_Allocation_Header), 8);
