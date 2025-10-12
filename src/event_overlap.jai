
determine_if_gadget_volume_is_overlapped :: (volume: *Entity, gadget: *Entity) {
    any_overlappers_can_interact: bool;
    for *volume.event_volume.overlaps {
        overlapper := try_get_entity(*it.entity);
        if overlapper != null && is_set(*overlapper.flags, .CAN_INTERACT_WITH_GADGETS_IN_PROXIMITY) {
            any_overlappers_can_interact = true;
            break;
        }
    }
    if any_overlappers_can_interact {
        set(*gadget.flags, .GADGET_EVENT_VOLUME_IS_OVERLAPPED);
    } else {
        unset(*gadget.flags, .GADGET_EVENT_VOLUME_IS_OVERLAPPED);
    }
}

on_gadget_event_volume_begin_overlap :: (volume: *Entity, gadget: *Entity, trespasser: *Entity) {
    assert(gadget.gadget_type != 0);
    determine_if_gadget_volume_is_overlapped(volume, gadget);

    // handle gadget-specific on-begin-overlap logic
    if gadget.gadget_type == {
    case .DOOR;
    case .BUTTON;
    }
}

on_gadget_event_volume_end_overlap :: (volume: *Entity, gadget: *Entity, coward: *Entity) {
    assert(gadget.gadget_type != 0);
    determine_if_gadget_volume_is_overlapped(volume, gadget);

    // handle gadget-specific on-end-overlap logic
    if gadget.gadget_type == {
    case .DOOR;
    case .BUTTON;
    }
}

