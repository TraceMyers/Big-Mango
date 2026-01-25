
// general purpose allocator
// culmination of ~3 years of practice making allocators with a focus on speed and it works pretty great imo. w/ -release, tested ~53ns for small allocations and ~300-500ns for medium to large.

GP_Allocator :: struct {
    MIN_BIN_ITEM_SIZE :: 16;
    ITEMS_PER_LIST :: 128;
    INITIAL_LIST_COUNT_PER_BIN :: 50;
    using #as base: Allocator;
    bins: [8]GP_Bin;
    med_allocator: Super_Allocator(4096);
    lrg_allocator: Super_Allocator(131072);
    parent_allocator: Allocator;
}

GP_Bin :: struct {
    first_available : s32 = -1;
    lists: [..][]u8;
}

gp_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator: *void) -> *void {
    gp_allocator := allocator.(*GP_Allocator);
    if mode == {
    case .ALLOCATE;
        return gp_alloc(gp_allocator, size);
    case .RESIZE;
        new_allocation := gp_alloc(gp_allocator, size);
        if old_memory != null {
            memcpy(new_allocation, old_memory, min(size, old_size));
            gp_free(gp_allocator, xx old_memory);
        }
        return new_allocation;
    case .FREE;
        if old_memory != null {
            gp_free(gp_allocator, old_memory);
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

initialize_gp_allocator :: (using allocator: *GP_Allocator, in_parent_allocator: Allocator) {
    allocator.* = .{parent_allocator=in_parent_allocator};
    base.data = allocator;
    base.proc = gp_allocator_proc;
    for *bin : bins {
        bin_index := it_index;
        for 1..INITIAL_LIST_COUNT_PER_BIN {
            add_list(allocator, bin_index);
        }
    }
    initialize_super_allocator(*med_allocator, parent_allocator);
    initialize_super_allocator(*lrg_allocator, parent_allocator);
}

add_list :: (using allocator: *GP_Allocator, bin_index: s64) {
    assert(bin_index >= 0 && bin_index < bins.count);
    item_size := MIN_BIN_ITEM_SIZE << bin_index;
    list_size := item_size * ITEMS_PER_LIST;
    bin := *bins[bin_index];
    list := array_add(*bin.lists);
    list.data = alloc(item_size * ITEMS_PER_LIST,,parent_allocator);
    list.count = ITEMS_PER_LIST;

    item_index_begin : s32 = xx ((bin.lists.count - 1) * ITEMS_PER_LIST);
    for < 0..ITEMS_PER_LIST-2 {
        item_slot : *s32 = xx (list.data + item_size * it);
        item_slot.* = item_index_begin + (it.(s32) + 1);
    }

    final_slot : *s32 = xx (list.data + item_size * (ITEMS_PER_LIST - 1));
    if bin.first_available == -1 {
        final_slot.* = -1;
    } else {
        final_slot.* = bin.first_available;        
    }
    bin.first_available = item_index_begin;
}

gp_alloc :: (using allocator: *GP_Allocator, alloc_size: s64) -> *void {
    if alloc_size <= 0 {
        return null;
    } else if alloc_size <= (2048 - size_of(Allocation_Header)) {
        // small allocations, fast track
        alloc_size += size_of(Allocation_Header);
        bin_index := max(bit_scan_reverse((alloc_size-1) >> 3) - 1, 0);
        bin := *bins[bin_index];
        if bin.first_available == -1 {
            add_list(allocator, bin_index);
        }
        assert(bin.first_available != -1);
        item_size := MIN_BIN_ITEM_SIZE << bin_index;
        list_index := bin.first_available / ITEMS_PER_LIST;
        item_index := bin.first_available - list_index * ITEMS_PER_LIST;
        allocation := bin.lists[list_index].data + item_index * item_size;

        bin.first_available = allocation.(*s32).*;

        allocation.(*Allocation_Header).id = xx ((Allocator_Identifier.GP_ALLOCATOR_16.(s32) + bin_index) | ALLOCATOR_VALIDATION_PATTERN);
        allocation.(*Allocation_Header).gp.list = xx list_index;

        return allocation + size_of(Allocation_Header);
    } else if alloc_size < (131072 - size_of(Allocation_Header)) {
        // medium allocations ~(2-130KB)
        allocation := super_alloc(*med_allocator, alloc_size);
        header := (allocation.(*u8) - size_of(Allocation_Header)).(*Allocation_Header);
        // overwrite the id so the allocator can be identified on free
        header.id = xx (Allocator_Identifier.GP_ALLOCATOR_SUPER_MED.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        return allocation;
    } else {
        // large allocations (130KB+)
        allocation := super_alloc(*lrg_allocator, alloc_size);
        header := (allocation.(*u8) - size_of(Allocation_Header)).(*Allocation_Header);
        // overwrite the id so the allocator can be identified on free
        header.id = xx (Allocator_Identifier.GP_ALLOCATOR_SUPER_LRG.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        return allocation;
    }
}

gp_free :: (using allocator: *GP_Allocator, addr: *u8) {
    header := (addr - size_of(Allocation_Header)).(*Allocation_Header);
    // log("free header address: %", header.(u64));
    identifier := (header.bit_pattern & 0x0f).(Allocator_Identifier);
    if identifier >= .GP_ALLOCATOR_16 && identifier <= .GP_ALLOCATOR_2048 {
        assert((header.bit_pattern & 0xf0) == ALLOCATOR_VALIDATION_PATTERN, "bad validation bits %", (header.bit_pattern & 0xf0));
        bin_index := (identifier - .GP_ALLOCATOR_16).(s64);
        item_size := MIN_BIN_ITEM_SIZE << bin_index;
        bin := *bins[bin_index];
        list_index := header.gp.list;
        list_data_begin := bin.lists[list_index].data;
        list_data_end   := list_data_begin + item_size * ITEMS_PER_LIST;
        assert(header.(*u8) >= list_data_begin && header.(*u8) < list_data_end);
        header.(*s32).* = bin.first_available;
        item_index := (header.(*u8) - list_data_begin) / item_size;
        bin.first_available = xx (list_index * ITEMS_PER_LIST + item_index);
    } else if identifier == {
    case .GP_ALLOCATOR_SUPER_MED;
        // this id was overwritten so it could be directed to the medium allocator. need to fix it so the super allocator can validate
        header.id = xx (Allocator_Identifier.SUPER_ALLOCATOR.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        super_free(*med_allocator, addr);
    case .GP_ALLOCATOR_SUPER_LRG;
        // this id was overwritten so it could be directed to the large allocator. need to fix it so the super allocator can validate
        header.id = xx (Allocator_Identifier.SUPER_ALLOCATOR.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        super_free(*lrg_allocator, addr);
    case;
        assert(false, "invalid id for allocation %", identifier);
    }
}
