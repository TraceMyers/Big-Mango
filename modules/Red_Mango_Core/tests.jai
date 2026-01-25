bit_array_test :: () -> bool, string {
    single_bits: Bit_Array(1);
    set_capacity(*single_bits, 97);

    test_condition(single_bits.items.count == 2);

    test_condition(find_first_set_bit(*single_bits) == -1);
    set_bit(*single_bits, 33);
    test_condition(find_first_set_bit(*single_bits) == 33);
    test_condition(find_last_set_bit(*single_bits) == 33);
    set_bit(*single_bits, 35);
    test_condition(find_last_set_bit(*single_bits) == 35);
    set_bit(*single_bits, 92);
    test_condition(find_first_set_bit(*single_bits) == 33);
    set_bit(*single_bits, 93);
    set_bit(*single_bits, 94);
    set_bit(*single_bits, 95);
    set_bit(*single_bits, 96);

    test_condition(bit_is_set(*single_bits, 33));
    test_condition(bit_is_set(*single_bits, 35));
    test_condition(bit_is_set(*single_bits, 92));
    test_condition(bit_is_set(*single_bits, 93));
    test_condition(bit_is_set(*single_bits, 94));
    test_condition(bit_is_set(*single_bits, 95));
    test_condition(bit_is_set(*single_bits, 96));

    test_condition(find_last_unset_bit(*single_bits) == 91);
    unset_bit(*single_bits, 92);
    test_condition(find_last_unset_bit(*single_bits) == 92);
    unset_bit(*single_bits, 35);
    unset_bit(*single_bits, 36);

    unset_bit(*single_bits, 33);
    test_condition(find_first_set_bit(*single_bits) == 93);
    set_bit(*single_bits, 33);

    test_condition(find_last_set_bit(*single_bits) == 96);
    unset_bit(*single_bits, 96);
    test_condition(find_last_set_bit(*single_bits) == 95);

    test_condition(bit_is_set(*single_bits, 33));
    test_condition(!bit_is_set(*single_bits, 35));
    test_condition(!bit_is_set(*single_bits, 36));
    test_condition(!bit_is_set(*single_bits, 92));

    for 0..20 {
        if it == 10 || it == 15 {
            continue;
        }
        set_bit_group(*single_bits, it);
    }
    test_condition(find_first_unset_bit(*single_bits) == 10);
    test_condition(find_first_unset_bit(*single_bits, -1, 11) == 15);
    test_condition(find_first_unset_bit(*single_bits, -1, 15) == 15);
    test_condition(find_first_unset_bit(*single_bits, -1, 16) == 21);

    MULTI_BIT_CT :: 16;
    multi_bit_capacity := 97;
    multi_bits: Bit_Array(MULTI_BIT_CT);

    set_capacity(*multi_bits, multi_bit_capacity);

    bit_ct := MULTI_BIT_CT * multi_bit_capacity;
    u64_ct := bit_ct / 64;
    u64_ct += ifx (u64_ct * 64 == bit_ct) then 0 else 1;
    test_condition(multi_bits.items.count == u64_ct);

    set_bit(*multi_bits, 33);
    test_condition(find_last_group_with_set_bits(*multi_bits) == 33);
    test_condition(find_first_group_with_set_bits(*multi_bits) == 33);
    set_bit(*multi_bits, 35, 3);
    test_condition(find_first_group_with_set_bits(*multi_bits) == 33);
    set_bit(*multi_bits, 92, 15);
    test_condition(find_last_group_with_set_bits(*multi_bits, 3) == 35);
    test_condition(find_last_group_with_set_bits(*multi_bits) == 92);
    set_bit_group(*multi_bits, 93);
    set_bit_group(*multi_bits, 91);

    set_bit_group(*multi_bits, 94);
    set_bit_group(*multi_bits, 95);
    set_bit_group(*multi_bits, 96);

    unset_bit(*multi_bits, 94, 1);
    test_condition(find_last_group_with_unset_bits(*multi_bits, 1) == 94);
    set_bit(*multi_bits, 94, 1);

    test_condition(find_last_group_with_unset_bits(*multi_bits) == 92);
    unset_bit_group(*multi_bits, 94);
    test_condition(find_last_group_with_unset_bits(*multi_bits) == 94);
    unset_bit_group(*multi_bits, 95);
    unset_bit_group(*multi_bits, 96);

    test_condition(bit_is_set(*multi_bits, 33));
    test_condition(bit_is_set(*multi_bits, 35, 3));
    test_condition(bit_is_set(*multi_bits, 92, 15));
    test_condition(all_bits_in_group_set(*multi_bits, 93));
    test_condition(all_bits_in_group_set(*multi_bits, 91));
    test_condition(!any_bits_in_group_set(*multi_bits, 94));

    unset_bit(*multi_bits, 35, 3);
    unset_bit(*multi_bits, 36, 5);
    unset_bit(*multi_bits, 33);
    test_condition(find_first_group_with_set_bits(*multi_bits) == 91);
    set_bit(*multi_bits, 33);
    unset_bit(*multi_bits, 92, 15);

    test_condition(bit_is_set(*multi_bits, 33));
    test_condition(!any_bits_in_group_set(*multi_bits, 35));
    test_condition(!any_bits_in_group_set(*multi_bits, 36));
    test_condition(!any_bits_in_group_set(*multi_bits, 92));

    unset_bit(*multi_bits, 33);

    for 0..13 {
        if it == 9 || it == 12 {
            continue;
        }
        set_bit_group(*multi_bits, it);
    }
    test_condition(find_first_group_with_unset_bits(*multi_bits) == 9);
    test_condition(find_first_group_with_unset_bits(*multi_bits, -1, 10) == 12);
    test_condition(find_first_group_with_unset_bits(*multi_bits, -1, 12) == 12);
    test_condition(find_first_group_with_unset_bits(*multi_bits, -1, 13) == 14);

    unset_bit(*multi_bits, 2, 0);
    test_condition(find_first_group_with_unset_bits(*multi_bits) == 2);

    set_bit_group(*multi_bits, 9);
    set_bit_group(*multi_bits, 12);
     for 0..11 {
        unset_bit(*multi_bits, it, it);
    }
    test_condition(find_first_group_with_unset_bits(*multi_bits, 9) == 9);

    reset(*single_bits);
    reset(*multi_bits);

    return_test_success();
}

text_encoding_test :: () -> bool, string {
    utf8_real_world_file := tprint("%/test_supplemental/utf8_in.txt", #filepath);
    utf8_real_world, read_utf8_real_world_success := read_entire_file(utf8_real_world_file);
    test_condition(read_utf8_real_world_success);
    encode_success: bool;

    str_a := "abc";
    str_b := copy_string(str_a);
    // some test conditions are predicated on '==' operator working like strcmp rather than just comparing pointers and counts. keeping this here in case the compiler changes the way this works, because this language is in closed beta and the compiler is volatile. this almost certainly won't change but who knows.
    test_condition(str_a == str_b); 

    // starting with real world utf8 and moving it through all of the translation paths
    {
        // this uses utf16 <-> utf32 as a transition state for each code point, so that is also tested somewhat
        to_utf16:, encode_success = encode_temp_text(utf8_real_world, .UTF8, .UTF16);
        test_condition(encode_success);
        back_to_utf8:, encode_success = encode_temp_text(to_utf16, .UTF16, .UTF8);
        test_condition(encode_success);
        test_condition(utf8_real_world == back_to_utf8);

        loopback_utf16:, encode_success = encode_temp_text(to_utf16, .UTF16, .UTF16);
        test_condition(encode_success);
        loopback_utf8:, encode_success = encode_temp_text(back_to_utf8, .UTF8, .UTF8);
        test_condition(encode_success);

        test_condition(to_utf16 == loopback_utf16);
        test_condition(utf8_real_world == loopback_utf8);
    }
    {
        to_utf32:, encode_success = encode_temp_text(utf8_real_world, .UTF8, .UTF32);
        test_condition(encode_success);
        back_to_utf8:, encode_success = encode_temp_text(to_utf32, .UTF32, .UTF8);
        test_condition(encode_success);
        test_condition(utf8_real_world == back_to_utf8);

        loopback_utf32:, encode_success = encode_temp_text(to_utf32, .UTF32, .UTF32);
        test_condition(encode_success);

        test_condition(to_utf32 == loopback_utf32);
    }
    {
        to_ansi:, encode_success = encode_temp_text(utf8_real_world, .UTF8, .ANSI);
        test_condition(!encode_success);
    }

    ansi_val := "\xff";
    ansi_to_utf8:, encode_success = encode_temp_text(ansi_val, .ANSI, .UTF8);
    test_condition(encode_success);
    test_condition(ansi_to_utf8.count == 2);

    bad_utf8_1 := "\xf0\x02";
    bad_utf8_to_utf32_1:, encode_success = encode_temp_text(bad_utf8_1, .UTF8, .UTF32);
    test_condition(!encode_success);

    bad_utf8_2 := "\xe1\x81";
    bad_utf8_to_utf32_2:, encode_success = encode_temp_text(bad_utf8_2, .UTF8, .UTF32);
    test_condition(!encode_success);

    bad_utf32 := "\x01\x02\x03";
    bad_utf32_to_utf16:, encode_success = encode_temp_text(bad_utf32, .UTF32, .UTF16);
    test_condition(!encode_success);

    unaligned_utf16 := copy_string("\x00\x01\x02");
    addr_is_even := (unaligned_utf16.data.(u64) & 1) == 0;
    if addr_is_even {
        unaligned_utf16.data += 1;
    }
    else {
        unaligned_utf16[0] = unaligned_utf16[1];
        unaligned_utf16[1] = unaligned_utf16[2];
    }
    unaligned_utf16.count -= 1;
    unaligned_utf16_to_utf32:, encode_success = encode_temp_text(unaligned_utf16, .UTF16, .UTF32);
    test_condition(encode_success);
    test_condition(unaligned_utf16_to_utf32.count == 4);
    test_condition(unaligned_utf16_to_utf32 == "\x01\x02\x00\x00");

    return_test_success();
}

math_test :: () -> bool, string {
    // seems silly to test this but it's free so whatever
    test_condition(!is_power_of_two(65));
    test_condition(!is_power_of_two(-1));
    for i : 0..63 {
        pow2 : u64 = (1).(u64) << i.(u64);
        test_condition(is_power_of_two(pow2));
        if i > 1 {
            test_condition(!is_power_of_two(pow2-1));
        }
    }

    {
        val := 5;
        min := 2;
        max := 8;
        add_to_val := 20;
        result := add_wrap(val, add_to_val, min, max);
        test_condition(result == 4);
    }
    {
        val := 11;
        min := 2;
        max := 12;

        add_to_val := 2;
        result := add_wrap(val, add_to_val, min, max);
        test_condition(result == min);

        add_to_val = 2 + (max - min);
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == max);

        val = 3;
        add_to_val = max - val;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == max);

        add_to_val = -1;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == min);

        add_to_val = -2;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == max);

        add_to_val = -2 - (max-min);
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == min);

        add_to_val -= 1;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == max);

        val = 2;
        min = 2;
        max = 2;
        add_to_val = 20;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == 2);

        add_to_val = -20;
        result = add_wrap(val, add_to_val, min, max);
        test_condition(result == 2);
    }
    {
        int_val : u8 = 127;
        norm_val := alter_cast(int_val, float, true);
        test_condition(abs(norm_val-0.5) <= 0.005);

        int_val = 0;
        norm_val = alter_cast(int_val, float, true);
        test_condition(norm_val == 0.0);

        int_val = 255;
        norm_val = alter_cast(int_val, float, true);
        test_condition(norm_val == 1.0);

        float_val := 0.0;
        out_int := alter_cast(float_val, s8, false, false);
        test_condition(out_int == 0);

        float_val = 1.0;
        out_int = alter_cast(float_val, s8, true, false);
        test_condition(out_int == 127);

        float_val = 1.0;
        out_int = alter_cast(float_val, s8, true, true);
        test_condition(out_int == 127);

        float_val = xx S32_MAX;
        out_int2 := alter_cast(float_val, s32, false, false);
        // overflow on cast back to int
        test_condition(out_int2 == S32_MIN);

        out_int2 = alter_cast(float_val, s32, false, true);
        // round() clamps to stop the overflow
        test_condition(out_int2 == S32_MAX);

        have_to_assign_to_var_or_cast_doesnt_work_right : s32 = S32_MIN;
        float_val = have_to_assign_to_var_or_cast_doesnt_work_right.(float) - 128.0;
        out_int2 = alter_cast(float_val, s32, false, true);
        // round() clamps to stop the underflow
        test_condition(out_int2 == S32_MIN);
    }
    {
        a: s32 = 8;
        b := ceil_to_multiple(a, 8);
        c := floor_to_multiple(a, 8);
        test_condition(b == 8);
        test_condition(c == 8);

        a = 9;
        b = ceil_to_multiple(a, 8);
        c = floor_to_multiple(a, 8);
        test_condition(b == 16);
        test_condition(c == 8);

        a = 7;
        b = ceil_to_multiple(a, 8);
        c = floor_to_multiple(a, 8);
        test_condition(b == 8);
        test_condition(c == 0);
    }

    return_test_success();
}

array_utils_test :: () -> bool, string {
    {
        base_array := u32.[0, 1, 2, 3];
        bound := bound_array(base_array);
        first_changed_val : u32 = 4;
        bound_array_add(*bound, first_changed_val);
        bound_array_add(*bound, first_changed_val+1);
        bound_array_append(*bound, u32.[first_changed_val+2, first_changed_val+3]);
        overwrite_as_expected := true;
        for 0..3 {
            if base_array[it] != first_changed_val + it {
                overwrite_as_expected = false;
                break;
            }
        }
        test_condition(overwrite_as_expected);
        test_condition(bound.max == bound.array.count);
    }
    {
        arr := string.["hello", "yes", "fishy joe"];
        pointer_based_index := array_element_index(arr, *arr[1]);
        success, found_index := array_find(arr, "yes");
        test_condition(pointer_based_index == found_index);
    }
    {
        arr1 := s32.[1, 2, 3];
        arr2 := s32.[1, 2, 3, 4];
        test_condition(!arrays_equal(arr1, arr2));
        arr3 : []s32 = arr2;
        arr3.count -= 1;
        test_condition(arrays_equal(arr1, arr3));
    }
    {
        arr1 := temp_dynamic_array(s32, 2);
        arr2 := s32.[1, 2, 3, 4];
        array_append(*arr1, arr2);
        test_condition(arrays_equal(arr1, arr2));

        arr3 := concatenate(arr1, arr2);
        arr_compare := s32.[1,2,3,4,1,2,3,4];
        test_condition(arrays_equal(arr3, arr_compare));

        arr4 := duplicate(arr3);
        test_condition(arrays_equal(arr3, arr4));
    }

    return_test_success();
}

pool_test :: () -> bool, string {
    SomeStruct :: struct {
        a : s32 = -1;
        b := 1.0;
        c := "a string!";
    }

    init_item_proc :: (s: *SomeStruct) {
        assert(s.a == -1 && s.b == 1.0 && s.c == "a string!");
        s.a = 100;
        s.b = 100.0;
        s.c = "neh";
    }

    deinit_item_proc :: (s: *SomeStruct) {
        assert(s.a == 100 && s.b == 100.0 && s.c == "neh");
        s.* = .{};
    }

    p: Pool(SomeStruct);
    p.shrink_to_min = 0;
    set_capacity(*p, 32);

    i1 := request_item(*p, init_item_proc);
    s1 := *p[i1];
    test_condition(s1 == *p[0]);

    i2 := request_item(*p, init_item_proc);
    s2 := *p[i2];
    test_condition(s2 == *p[1]);

    i3 := request_item(*p, init_item_proc);
    s3 := *p[i3];
    test_condition(s3 == *p[2]);

    return_item(*p, i2, deinit_item_proc);
    test_condition(p.top == 2);
    test_condition(!is_item_in_use(*p, 1));

    i3b := get_item_index(*p, s3);
    test_condition(i3b == i3);

    i2 = request_item(*p, init_item_proc);
    s2 = *p[i2];
    test_condition(s2 == *p[1]);
    test_condition(is_item_in_use(*p, 1));

    compare_proc :: (a: *SomeStruct, b: *SomeStruct) -> bool {
        return a == b;
    }

    i3c := find_item(*p, s3, compare_proc);
    test_condition(i3c == i3);

    // --
    reset(*p, deinit_item_proc);
    // --

    i1 = request_item(*p, init_item_proc);
    s1 = *p[i1];
    test_condition(s1 == *p[0]);

    i2 = request_item(*p, init_item_proc);
    s2 = *p[i2];
    test_condition(s2 == *p[1]);

    i3 = request_item(*p, init_item_proc);
    s3 = *p[i3];
    test_condition(s3 == *p[2]);

    return_item(*p, i2, deinit_item_proc);
    test_condition(p.top == 2);
    test_condition(!is_item_in_use(*p, 1));

    i3b = get_item_index(*p, s3);
    test_condition(i3b == i3);

    i2 = request_item(*p, init_item_proc);
    s2 = *p[i2];
    test_condition(s2 == *p[1]);
    test_condition(is_item_in_use(*p, 1));

    i3c = find_item(*p, s3, compare_proc);
    test_condition(i3c == i3);
    
    // --
    reset(*p, deinit_item_proc);
    // --
    
    indices := temp_dynamic_array(s64, 100);
    for 0..99 {
        request_item(*p, init_item_proc);
        array_add(*indices, it);
    }

    shuffle_array :: (arr: []$T) {
        if arr.count == 0 then return;
        for i: 0..arr.count-1 {
            rand_val := random_get_zero_to_one_new();
            swap_index := round(respace(xx rand_val, Vector2.{0.0, 1.0}, Vector2.{0.0, xx (arr.count-1)}));
            arr[i], arr[swap_index] = arr[swap_index], arr[i];
        }
    }

    test_condition(find_last_set_bit(*p.in_use) == 99);
    shuffle_array(indices);

    for indices {
        return_item(*p, it, deinit_item_proc);
    }

    test_condition(p.top == -1);
    test_condition(p.items.count == 0);
    test_condition(find_first_set_bit(*p.in_use) == -1);

    p.shrink_to_min = 12;
    for 0..99 {
        request_item(*p, init_item_proc);
    }
    for indices {
        return_item(*p, it, deinit_item_proc);
    }

    test_condition(p.top == -1);
    test_condition(p.items.count >= 12);

    return_test_success();
}

bump_allocator_test :: no_inline () -> bool, string {
    // b: Bump_Allocator;
    // bump_allocator_initialize(*b);
    // defer bump_allocator_reset(*b);

    // test_condition(b.heaps.count == 1 || b.heaps[1].bytes.count == 0);
    // test_condition(b.heaps[0].bytes.count == BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
    // test_condition(b.heaps[0].end == 0);
    // {
    //     scope_mark_and_recede_allocations(*b);
    //     alloc1 := bump_allocator_allocate(*b, 1024);     
    //     test_condition(b.heaps[0].end == 1024);
    //     alloc2 := bump_allocator_allocate(*b, 1025);
    //     test_condition(b.heaps[0].end == 1024 + 1025 + 7);
    //     alloc3 := bump_allocator_allocate(*b, 1023);
    //     test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
    //     {
    //         scope_mark_and_recede_allocations(*b);
    //         data_prev: *u8 = null;
    //         prev_alloc_size: s32 = -1;
    //         for 0..100 {
    //             data: *u8 = bump_allocator_allocate(*b, it);
    //             if prev_alloc_size >= 1 {
    //                 diff := data.(u64) - data_prev.(u64);
    //                 should_be_diff := ceil_to_multiple(prev_alloc_size, 8);
    //                 test_condition(diff == xx should_be_diff);
    //             } else if prev_alloc_size == 0 {
    //                 // alloc(0) == no diff;
    //                 diff := data.(u64) - data_prev.(u64);
    //                 test_condition(diff == 0);
    //             }
    //             prev_alloc_size = xx it;
    //             data_prev = data;
    //         }
    //     }
    //     test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
    // }
    // test_condition(b.heaps[0].end == 0);

    // {
    //     scope_set_allocator(b);
    //     {
    //         scope_mark_and_recede_allocations(*b);
    //         alloc1 := alloc(1024);     
    //         test_condition(b.heaps[0].end == 1024);
    //         alloc2 := alloc(1025);
    //         test_condition(b.heaps[0].end == 1024 + 1025 + 7);
    //         alloc3 := alloc(1023);
    //         test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
    //         {
    //             scope_mark_and_recede_allocations(*b);
    //             for 0..100 {
    //                 alloc(it);
    //             }
    //         }
    //         test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
    //     }
    // }
    // test_condition(b.heaps[0].end == 0);

    // {
    //     scope_set_allocator(b);
    //     scope_mark_and_recede_allocations(*b);
    //     alloc_sz := BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE / 3 - 8;
    //     for 0..5 {
    //         data: *u8 = alloc(alloc_sz);
    //         if it <= 2 {
    //             test_condition(b.heaps[1].bytes.count == 0);
    //             test_condition(b.heaps[1].end == 0);
    //         } else if it <= 5 {
    //             test_condition(b.heaps[0].end < BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
    //             test_condition(b.heaps[1].bytes.count == BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
    //             test_condition(b.heaps[2].bytes.count == 0);
    //             test_condition(b.heaps[2].end == 0);
    //         }
    //     }
    // }
    // test_condition(b.heaps[0].end == 0);


    return_test_success();
}

// mostly for sanity testing before a commit. tests in here likely aren't precious.
misc_test :: () -> bool, string {
    {
        k: [9]u64;
        k[2] = 20;
        array_zero(k);
        test_condition(k[2] == 0);
    }
    {
        b: Bound_Local_Array(s32, 8);
        bound_local_array_init(*b);
        bound_local_array_add(*b, 1);
        bound_local_array_add(*b, 2);
        bound_local_array_add(*b, S32_MAX);
        bound_local_array_add(*b, S32_MIN);
        bound_local_array_add(*b, 1);
        bound_local_array_add(*b, 2);
        bound_local_array_add(*b, S32_MAX);
        bound_local_array_add(*b, S32_MIN);
        test_condition(arrays_equal(b.array, s32.[1, 2, S32_MAX, S32_MIN, 1, 2, S32_MAX, S32_MIN]));
        test_condition(b.array.count == b.array_data.count);
    }


    return_test_success();
}

Test_Struct :: struct {
    a: s32;
    b: u8;
    c: float64;
    d: string;
}

operator == :: (t1: Test_Struct, t2: Test_Struct) -> bool {
    return t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d;
}

serializer_test :: () -> bool, string {
    // checksum: [4]u32;
    // {
    //     ser: Serializer(.STATIC, .BYTE);
    //     ser.memory = alloc_string(1024);
    //     ser.read_array_allocator = context.allocator;
    //     serializer_test_body(*checksum, true);
    // }
    // {
    //     ser: Serializer(.STATIC, .PRIMITIVE);
    //     ser.memory = alloc_string(1024);
    //     ser.read_array_allocator = context.allocator;
    //     serializer_test_body();
    // }
    // {
    //     ser: Serializer(.STATIC, .PARAMETER);
    //     ser.memory = alloc_string(1024);
    //     ser.read_array_allocator = context.allocator;
    //     ser.parameter_align = 1;
    //     serializer_test_body();
    //     ser.parameter_align = 2;
    //     serializer_test_body();
    //     ser.parameter_align = 4;
    //     serializer_test_body();
    //     ser.parameter_align = 8;
    //     serializer_test_body();
    // }
    // {
    //     ser: Serializer(.DYNAMIC, .BYTE);
    //     ser.allocator = context.allocator;
    //     ser.read_array_allocator = context.allocator;
    //     serializer_test_body(*checksum);
    // }
    return_test_success();
}

gp_allocator_test :: () -> bool, string {
    a: GP_Allocator;
    initialize_gp_allocator(*a, context.default_allocator);

    ITER_CT :: 10_000;

    // total_time: float64;
    max_time: float64;
    allocations: [..]*u8;

    allocation_sizes: [ITER_CT]s64;
    for 0..ITER_CT-1 {
        alloc_sz := random_get_within_range(1, 2048-size_of(Allocation_Header)).(s64);
        allocation_sizes[it] = alloc_sz;
    }

    t1 := seconds_since_init();
    for 0..ITER_CT-1 {
        // t1 := seconds_since_init();
        allocation := alloc(allocation_sizes[it],,a).(*u8);
        // t2 := seconds_since_init();
        // time_taken := t2 - t1;
        // max_time = max(time_taken, max_time);
        // total_time += time_taken;
        // array_add(*allocations, allocation);
    }
    t2 := seconds_since_init();
    total_time := t2 - t1;

    avg_time := total_time / ITER_CT.(float64);

    log("gp allocator (small) avg alloc time:                        %us", avg_time * 1000 * 1000);
    // log("gp allocator (small) avg alloc time (last 100 allocations): %us", last_100_us_per_alloc);
    log("gp allocator (small) max time:                              %us", max_time * 1000 * 1000);

    // for allocations {
    //     free(it,,a);
    // }

    return_test_success();
}

super_allocator_test :: () -> bool, string {
    MIN_CHUNK_SZ :: 8;
    HEADER_SPACE :: #run ceil_to_pow2_multiple(size_of(Super_Allocation_Header), 8);

    a: Super_Allocator(MIN_CHUNK_SZ);
    initialize_super_allocator(*a, context.default_allocator/*, MIN_CHUNK_SZ*/);
    // scope_set_allocator(a);

    data_1_sz := 129;
    allocated_chunk_ct := div_ceil(data_1_sz, MIN_CHUNK_SZ) + 1; // + 1 for header
    data_1 := alloc(data_1_sz,,a);
    test_condition(data_1 == xx ((*a.chunk_lists[0][0]).(*u8)+HEADER_SPACE));

    data_2_sz := 880;
    allocated_chunk_ct += div_ceil(data_2_sz, MIN_CHUNK_SZ) + 1;
    data_2 := alloc(880,,a);

    free(data_1,,a);
    free(data_2,,a);

    POINTER_COUNT :: 10000;
    pointers: [..]*void;
    pointers.allocator = temp;
    array_resize(*pointers, POINTER_COUNT);

    total_alloc_seconds: float64;
    total_alloc_seconds_last_100: float64;
    max_time: float64;

    for 0..pointers.count-1 {
        bin_ct := random_get_within_range(1, 64).(s64);
        alloc_sz := bin_ct * /*a.min_allocation_size*/ MIN_CHUNK_SZ;
        t1 := seconds_since_init();
        pointers[it] = alloc(alloc_sz,,a);
        t2 := seconds_since_init();
        total_alloc_seconds += t2 - t1;
        max_time = max(max_time, t2-t1);
        if it >= POINTER_COUNT-100 {
            total_alloc_seconds_last_100 += t2 - t1;
        }
    }
    for 0..pointers.count-1 {
        index := ifx pointers.count > 1 then round(random_get_within_range(0, (pointers.count-1).(float))) else 0;
        if index < 0 {
            index = 0;
        }
        ptr := pointers[index];
        array_ordered_remove_by_index(*pointers, index);
        free(ptr,,a);
    }

    // log("small allocator data");
    // log("%", repr(*a.small_allocator));

    // not real world but whatever
    total_alloc_ms := total_alloc_seconds * 1000.0;
    ms_per_alloc := total_alloc_ms / POINTER_COUNT.(float64);
    us_per_alloc := ms_per_alloc * 1000.0;

    last_100_total_ms := total_alloc_seconds_last_100 * 1000.0;
    last_100_ms_per_alloc := last_100_total_ms / 100.0;
    last_100_us_per_alloc := last_100_ms_per_alloc * 1000.0;

    log("super allocator avg alloc time:                        %us", us_per_alloc);
    log("super allocator avg alloc time (last 100 allocations): %us", last_100_us_per_alloc);
    log("super allocator max time:                              %us", max_time * 1000.0 * 1000.0);

    // total_alloc_seconds = 0;
    // total_alloc_seconds_last_100 = 0;
    // max_time = 0;
    // array_resize(*pointers, POINTER_COUNT);

    // for 0..POINTER_COUNT-1 {
    //     bin_ct: s64;
    //     if random_get_zero_to_one() <= 0.2 {
    //         bin_ct = random_get_within_range(32, 384).(s64);
    //     } else {
    //         bin_ct = random_get_within_range(1, 64).(s64);
    //     }
    //     alloc_sz := bin_ct * a.small_allocator.MIN_ALLOCATION_SIZE;
    //     t1 := seconds_since_init();
    //     refs[it] = nack_alloc(*a, alloc_sz);
    //     t2 := seconds_since_init();
    //     total_alloc_seconds += t2 - t1;
    //     max_time = max(max_time, t2-t1);
    //     if it >= POINTER_COUNT-100 {
    //         total_alloc_seconds_last_100 += t2 - t1;
    //     }
    // }
    // for 0..POINTER_COUNT-1 {
    //     index := ifx refs.count > 1 then round(random_get_within_range(0, (refs.count-1).(float))) else 0;
    //     if index < 0 {
    //         index = 0;
    //     }
    //     ref := refs[index];
    //     array_ordered_remove_by_index(*refs, index);
    //     nack_free(*a, *ref);
    // }

    // // not real world but whatever
    // total_alloc_ms = total_alloc_seconds * 1000.0;
    // ms_per_alloc = total_alloc_ms / POINTER_COUNT.(float64);
    // us_per_alloc = ms_per_alloc * 1000.0;

    // last_100_total_ms = total_alloc_seconds_last_100 * 1000.0;
    // last_100_ms_per_alloc = last_100_total_ms / 100.0;
    // last_100_us_per_alloc = last_100_ms_per_alloc * 1000.0;

    // log("mixed allocations avg alloc time:                        %us", us_per_alloc);
    // log("mixed allocations avg alloc time (last 100 allocations): %us", last_100_us_per_alloc);
    // log("mixed allocations max time:                              %us", max_time * 1000.0 * 1000.0);

    return_test_success();
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

serializer_test_body :: (checksum: *[4]u32 = null, load_checksum := false) #expand {
    // s := `ser;
    // if checksum {
    //     s.pad_for_checksum = true;
    // }
    // reset(*s);

    // t: Test_Struct;
    // memset(*t, 0, size_of(Test_Struct));
    // t = Test_Struct.{
    //     a = 100,
    //     b = 255,
    //     c = 0.1,
    //     d = "hello"
    // };
    // str := "whatever";
    // array := u16.[1, 2, 3, 4, 5, 6, 7];
    // array_for_copy : []u16 = array;

    // serialize(*s, *t.a);
    // head_1 := s.head;
    // serialize(*s, *t.b);
    // head_2 := s.head;
    // serialize(*s, *t.c);
    // head_3 := s.head;
    // serialize(*s, *t.d);
    // head_4 := s.head;
    // serialize(*s, *t);
    // head_5 := s.head;
    // serialize(*s, *str);
    // head_6 := s.head;
    // serialize(*s, *array_for_copy);
    // head_7 := s.head;
    // serialize(*s, *t);
    // head_8 := s.head;
    // serialize(*s, *t.a);
    // head_9 := s.head;
    // serialize(*s, *t.b);
    // head_10 := s.head;
    // serialize(*s, *t.c);
    // head_11 := s.head;
    // serialize(*s, *t.d);
    // head_12 := s.head;

    // if checksum {
    //     // if load_checksum {
    //     //     imprint_checksum(*s);
    //     //     memcpy(checksum.data, s.memory.data, size_of([4]u32));
    //     // } else {
    //     //     memcpy(s.memory.data, checksum.data, size_of([4]u32));
    //     //     test_condition(validate_checksum(*s));
    //     // }
    // }

    // rt1, rt2, rt3, rt4: Test_Struct;
    // memset(*rt1, 0, size_of(Test_Struct));
    // rstr: string;
    // rarray: []u16;

    // set_rw_mode(*s, .READ);

    // serialize(*s, *rt1.a);
    // test_condition(head_1 == s.head);
    // serialize(*s, *rt1.b);
    // test_condition(head_2 == s.head);
    // serialize(*s, *rt1.c);
    // test_condition(head_3 == s.head);
    // serialize(*s, *rt1.d);
    // test_condition(head_4 == s.head);
    // serialize(*s, *rt2);
    // test_condition(head_5 == s.head);
    // serialize(*s, *rstr);
    // test_condition(head_6 == s.head);
    // serialize(*s, *rarray);
    // test_condition(head_7 == s.head);
    // serialize(*s, *rt3);
    // test_condition(head_8 == s.head);
    // serialize(*s, *rt4.a);
    // test_condition(head_9 == s.head);
    // serialize(*s, *rt4.b);
    // test_condition(head_10 == s.head);
    // serialize(*s, *rt4.c);
    // test_condition(head_11 == s.head);
    // serialize(*s, *rt4.d);
    // test_condition(head_12 == s.head);

    // test_condition(rt1 == t);
    // test_condition(rt2 == t);
    // test_condition(rt3 == t);
    // test_condition(rt4 == t);
    // test_condition(rstr == str);
    // test_condition(arrays_equal(rarray, array));
}

