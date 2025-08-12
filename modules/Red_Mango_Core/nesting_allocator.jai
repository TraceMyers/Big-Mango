// This allocator can't be an Allocator type because it is meant to free data, but it doesn't have the proper context
// to free without extra info... which you can't get with a 'free' proc.

// TODO: make it so initialize only allocates books once

// NOTE: never use a variable named 'data' in a scope that is 'using' an allocator..

VALIDATION_PATTERN : u8 : 0xa0;

Nested_Allocation_Ref :: struct {
    data: *void;
    info: Nested_Allocation_Info;
}

Nested_Allocation :: struct {
    ref: Nested_Allocation_Ref;
    count: s32;
}

Nested_Dynamic_Allocation :: struct {
    ref: Nested_Allocation_Ref;
    count: s32;
    allocated: s32;
}

Nesting_Allocator_Collection :: struct {
    small_allocator: Nesting_Allocator(16);
    medium_allocator: Nesting_Allocator(1024);
    large_allocator: Nesting_Allocator(1024*256);
}

Nested_Allocation_Info :: struct {
    list: s16;
    outer_chunk: u16;
    inner_chunk_count: u16;
    inner_chunk: u8;
    using metadata: union {
        bin: enum u8 {
            STANDALONE;
            SMALL;
            MEDIUM;
            LARGE;
        }
        bit_pattern: u8 = ---;
    }
}

Nested_Array :: struct($T: Type, $NESTING_ALLOCATOR_BLOCK_SIZE: s64) {
    FIELD_TYPE :: #run -> Type { if T == string then return string; else return []T; };
    field: FIELD_TYPE;
    allocation: Nested_Allocation;
}

array_unordered_remove_by_index :: (array: *Nested_Array($T, $B), allocator: *Nesting_Allocator(B), i: s32, allow_shrink := true) {
    new_count := array.field.count - 1;
    assert(new_count >= 0);
    if allow_shrink && array.allocation.count > 8 && array.allocation.count > new_count / 4 {
        assert(basic_validity_check(array.allocation.ref));
        new_allocated_count := new_count / 2;
        array_resize(array, allocator, xx new_allocated_count);
    }
    if i != array.field.count - 1 {
        array.field[i] = array.field[array.field.count-1];
    }
    array.field.count = new_count;
}

array_add :: (array: *Nested_Array($T, $B), allocator: *Nesting_Allocator(B), item: T) 
#modify {
    return T != string;
} {
    new_count := array.field.count + 1;
    if array.allocation.count < new_count {
        new_allocated_count := ceil_to_pow2(new_count);
        array_resize(array, allocator, xx new_allocated_count);
    }
    array.field.count = new_count;
    array.field[array.field.count-1] = item;
}

array_append :: (array: *Nested_Array($T, $B), allocator: *Nesting_Allocator(B), items: array.FIELD_TYPE) {
    new_count := array.field.count + field.count;
    if array.allocation.count < new_count {
        new_allocated_count := ceil_to_pow2(new_count);
        array_resize(array, allocator, xx new_allocated_count);
    }
    old_count := array.field.count;
    array.field.count = new_count;
    for 0..items.count-1 {
        array.field[it+old_count] = items[it];
    }
}

array_set :: (array: *Nested_Array($T, $B), allocator: *Nesting_Allocator(B), items: array.FIELD_TYPE) {
    array_resize(array, allocator, xx items.count);
    array.field.count = items.count;
    for 0..items.count-1 {
        array.field[it] = items[it];
    }
}

array_resize :: (array: *Nested_Array($T, $B), allocator: *Nesting_Allocator(B), new_count: s32) {
    assert(new_count >= 0);
    new_ref := ifx new_count > 0 then na_alloc(allocator, new_count * size_of(T)) else .{};
    if basic_validity_check(array.allocation.ref) {
        copy_count := min(array.field.count, new_count);
        if copy_count > 0 {
            memcpy(new_ref.data, array.allocation.ref.data, copy_count * size_of(T));
        }
        na_free(allocator, *array.allocation.ref);
    }
    array.allocation.ref = new_ref;
    array.allocation.count = xx new_count;
    array.field.data = array.allocation.ref.data;
    array.field.count = new_count;
}

nack_initialize :: (using allocator: *Nesting_Allocator_Collection, parent_allocator: Allocator, small_list_count := 16, medium_list_count := 4, large_list_count := 0) {
    initialize_nesting_allocator(*small_allocator, parent_allocator, 4096 * small_allocator.MIN_ALLOCATION_SIZE, small_list_count);
    initialize_nesting_allocator(*medium_allocator, parent_allocator, 4096 * medium_allocator.MIN_ALLOCATION_SIZE, medium_list_count);
    initialize_nesting_allocator(*large_allocator, parent_allocator, 1024 * large_allocator.MIN_ALLOCATION_SIZE, large_list_count);
}

nack_alloc :: (using allocator: *Nesting_Allocator_Collection, size: s64) -> Nested_Allocation_Ref {
    ref: Nested_Allocation_Ref = ---;
    Bin_Type :: type_of(ref.info.bin);
    if size < medium_allocator.MIN_ALLOCATION_SIZE {
        ref = na_alloc(*small_allocator, size);
        ref.info.bin = .SMALL;
    } else if size < large_allocator.MIN_ALLOCATION_SIZE {
        ref = na_alloc(*medium_allocator, size);
        ref.info.bin = .MEDIUM;
    } else {
        ref = na_alloc(*large_allocator, size);
        ref.info.bin = .LARGE;
    }
    // needs to be re-set because it's unioned with 'bin'. (setting 'bin' clears the validation pattern.)
    ref.info.bit_pattern |= VALIDATION_PATTERN;
    return ref;
}

nack_free :: (using allocator: *Nesting_Allocator_Collection, ref: *Nested_Allocation_Ref) {
    assert((ref.info.bit_pattern & 0xf0) == VALIDATION_PATTERN);
    // clearing the bit pattern allows for a clean read of the bin
    ref.info.bit_pattern &= 0x0f;
    if #complete ref.info.bin == {
    case .SMALL;
        na_free(*small_allocator, ref);
    case .MEDIUM;
        na_free(*medium_allocator, ref);
    case .LARGE;
        na_free(*large_allocator, ref);
    case .STANDALONE;
        assert(false, "standalone ref either came from a standalone Nesting_Allocator, or the ref was corrupted");
    }
}

basic_validity_check :: inline (using ref: Nested_Allocation_Ref) -> bool {
    return data != null && info.list >= 0 && (info.bit_pattern & 0xf0) == VALIDATION_PATTERN;
}


Nesting_Allocator_Outer_Chunk :: struct ($MIN_ALLOCATION_SIZE: s64) {
    inner_chunks: [64][MIN_ALLOCATION_SIZE]u8;
}

Nesting_Allocator :: struct ($MIN_ALLOCATION_SIZE := 16) {
    parent_allocator: Allocator;
    chunk_lists: [..][]Nesting_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE);
    books: Nesting_Allocator_Books;
    books_allocated_size: s64;
    default_outer_chunk_count_per_list: s32 = 32;
    shrink_to_min_lists: s32 = 1;
    default_reserve_size: s32;
    old_list_count: s32;

    CHUNKS_PER_HEAP :: 64;
    CHUNK_SIZE :: size_of(Nesting_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE));
    #run assert(is_power_of_two(MIN_ALLOCATION_SIZE));
}

Nesting_Allocator_Books :: struct {
    largest_gap_per_list: *u8;
    gap_list_of_lists: []*u8;
    flag_list_of_lists: []*u64;
}

initialize_nesting_allocator :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), in_parent_allocator: Allocator, in_default_chunk_list_size := 0, add_chunk_lists := 1) {
    assert(chunk_lists.count == 0 && chunk_lists.data == null);
    allocator.* = .{};
    parent_allocator = in_parent_allocator;
    if in_default_chunk_list_size > 0 {
        default_reserve_size = xx in_default_chunk_list_size;
    } else {
        default_reserve_size = xx (CHUNK_SIZE * 64);
    }
    if add_chunk_lists > 0 then for 0..add_chunk_lists - 1 {
        add_chunk_list(allocator, default_reserve_size, false);
    }
    // grow_nesting_allocator_books(allocator);
}

// remake_books is optional so initialize_nesting_allocator can call it only after adding all of the chunk lists.
add_chunk_list :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), min_bytes: s64, remake_books := true) {
    scope_set_allocator(parent_allocator);
    chunk_list := array_add(*chunk_lists);
    alloc_chunk_count := max(div_ceil(min_bytes, CHUNK_SIZE), 2);
    // Nested_Allocation_Info requirements
    assert(chunk_lists.count <= S16_MAX);
    assert(alloc_chunk_count <= U16_MAX);
    if alloc_chunk_count < 8 && !did_small_chunk_count_warning {
        rm_warning("min bytes % leads to only % chunks being allocated per nesting allocator heap. the number of chunks per heap should probably be somewhere between 8 and 128", min_bytes, alloc_chunk_count);
        did_small_chunk_count_warning = true;
    }
    chunk_list.* = alloc_array(Nesting_Allocator_Outer_Chunk(MIN_ALLOC_SIZE), alloc_chunk_count);
    // if remake_books {
        grow_nesting_allocator_books(allocator);    
    // }
}

na_alloc :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), size: s64) -> Nested_Allocation_Ref {
    success, ref := na_try_alloc(allocator, size);
    if success then return ref;
    // didn't find existing space, need to grow
    add_chunk_list(allocator, max(size, default_reserve_size));
    success, ref = na_try_alloc(allocator, size);
    assert(success);
    return ref;
}

na_free :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), ref: *Nested_Allocation_Ref) {
    list := ref.info.list;
    outer_chunk := ref.info.outer_chunk;
    inner_chunk := ref.info.inner_chunk;
    inner_chunk_count := ref.info.inner_chunk_count;

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

    ref.* = .{};
}

// will not reallocate
na_try_alloc :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), size: s64) -> bool, Nested_Allocation_Ref {
    success: bool = ---;
    ref: Nested_Allocation_Ref = ---;
    alloc_inner_chunk_count := div_ceil(size, MIN_ALLOC_SIZE);
    if alloc_inner_chunk_count > 64 {
        success, ref = na_try_alloc_large(allocator, alloc_inner_chunk_count);
    } else {
        success, ref = na_try_alloc_small(allocator, alloc_inner_chunk_count);
    }
    // (these two fields are unioned)
    ref.info.bin = .STANDALONE;
    ref.info.bit_pattern |= VALIDATION_PATTERN;
    return success, ref;
}

na_try_alloc_small :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), alloc_inner_chunk_count: s64) -> bool, Nested_Allocation_Ref {
    alloc_mask: u64 = ((1).(u64) << alloc_inner_chunk_count) - (1).(u64);

    out_ref: Nested_Allocation_Ref;
    allocated_gap_is_max := false;

    if chunk_lists.count > 0 then for list : 0..chunk_lists.count-1 {
        largest_gap := *books.largest_gap_per_list[list];
        if largest_gap.* >= alloc_inner_chunk_count {
            max_gap: u8;
            for chunk : 0..chunk_lists[list].count-1 {
                gap := *books.gap_list_of_lists[list][chunk];
                // only need to go in here if we haven't found the allocation that must be in this list yet...
                if out_ref.data == null && gap.* >= alloc_inner_chunk_count {
                    allocated_gap_is_max = gap.* == largest_gap.*;
                    flag_set := *books.flag_list_of_lists[list][chunk];
                    alloc_index := find_index_of_missing_bit_sequence_lsb(flag_set.*, alloc_mask, alloc_inner_chunk_count);
                    flag_set.* |= alloc_mask << alloc_index;
                    gap.* = xx largest_gap_in_bit_sequence_lsb(flag_set.*);
                    out_ref.data = *chunk_lists[list][chunk].inner_chunks[alloc_index];
                    out_ref.info.list = xx list;
                    out_ref.info.outer_chunk = xx chunk;
                    out_ref.info.inner_chunk = xx alloc_index;
                    out_ref.info.inner_chunk_count = xx alloc_inner_chunk_count;
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
            assert(out_ref.data != null);
            largest_gap.* = max_gap;
            break;
        }
    }

    return out_ref.data != null, out_ref;
}

na_try_alloc_large :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE), alloc_inner_chunk_count: s64) -> bool, Nested_Allocation_Ref {
    assert(alloc_inner_chunk_count > 64);
    alloc_outer_chunk_count := div_ceil(alloc_inner_chunk_count, 64);
    assert(alloc_outer_chunk_count <= U16_MAX);

    out_ref: Nested_Allocation_Ref;

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
                    out_ref.data = *list.*[first_chunk_index].inner_chunks[0];
                    out_ref.info.list = xx list_index;
                    out_ref.info.outer_chunk = xx first_chunk_index;
                    out_ref.info.inner_chunk = 0;
                    out_ref.info.inner_chunk_count = xx alloc_inner_chunk_count;
                    break;
                }
            } else {
                consecutive_free_outer_chunk_ct = 0;
            }
            chunk_index += 1;
        }
        if out_ref.data != null then break;
    }

    return out_ref.data != null, out_ref;
}

nesting_allocator_shutdown :: (using allocator: *Nesting_Allocator($MIN_ALLOC_SIZE)) {
    for list : *chunk_lists {
        array_reset(list);
    }
    array_reset(*chunk_lists);
    free(books.largest_gap_per_list);
    allocator.* = .{};
}

grow_nesting_allocator_books :: (using allocator: *Nesting_Allocator($MIN_ALLOCATION_SIZE)) {
    scope_set_allocator(parent_allocator);
    auto_release_temp();
    assert(chunk_lists.count > 0);

    reader: Serializer(.STATIC, .PRIMITIVE);
    writer: Serializer(.DYNAMIC, .PRIMITIVE);

    reader.memory.data = books.largest_gap_per_list;
    reader.memory.count = books_allocated_size;

    writer.memory = talloc_string(max(reader.memory.count * 2, 1024));
    writer.allocator = temp;

    set_rw_mode(*reader, .READ);
    set_rw_mode(*writer, .WRITE);

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

    super_list_offst := 0;
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
        new_books_data_allocation = alloc_array(u8, new_books_data_size, parent_allocator).data;
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

repr :: (using allocator: *Nesting_Allocator($MIN_ALLOCATION_SIZE)) -> string {
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
Nesting_Allocator {
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

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

did_small_chunk_count_warning := false;
