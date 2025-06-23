
Capsule_Collider :: struct {
    height: float;
    radius: float;
}

Box_Collider :: struct {
    height: float;
    width: float;
    length: float;
}

Entity_Collider :: struct {
    type: enum u8 {
        CAPSULE;
        BOX;
    };
    using data: union {
        capsule: Capsule_Collider = ---;
        box: Box_Collider = ---;
    };
}

