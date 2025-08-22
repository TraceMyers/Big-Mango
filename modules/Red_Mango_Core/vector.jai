
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

operator - :: (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x - scalar, a.y - scalar};
}

operator + :: (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator + :: (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Int_Vector2 :: struct {
    x: s32;
    y: s32;
}

operator + :: inline (a: Int_Vector2, b: Int_Vector2) -> Int_Vector2 {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: Int_Vector2, b: Int_Vector2) -> Int_Vector2 {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: Int_Vector2, b: Int_Vector2) -> Int_Vector2 {
    return .{a.x * b.x, a.y * b.y};
}

operator / :: inline (a: Int_Vector2, b: Int_Vector2) -> Int_Vector2 {
    return .{a.x / b.x, a.y / b.y};
}

operator + :: inline (a: Int_Vector2, scalar: s32) -> Int_Vector2 #symmetric {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Int_Vector2, scalar: s32) -> Int_Vector2 {
    return .{a.x - scalar, a.y - scalar};
}

operator - :: inline (scalar: s32, a: Int_Vector2) -> Int_Vector2 {
    return .{scalar - a.x, scalar - a.y};
}

operator * :: inline (a: Int_Vector2, scalar: s32) -> Int_Vector2 #symmetric {
    return .{a.x * scalar, a.y * scalar};
}

operator / :: inline (a: Int_Vector2, scalar: s32) -> Int_Vector2 {
    return .{a.x / scalar, a.y / scalar};
}

operator / :: inline (scalar: s32, a: Int_Vector2) -> Int_Vector2 {
    return .{scalar / a.x, scalar / a.y};
}

operator == :: inline (a: Int_Vector2, b: Int_Vector2) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}

to_vector2 :: inline (v: Int_Vector2) -> Vector2 {
    return .{xx v.x, xx v.y};
}

to_int_vector2 :: inline (v: Vector2) -> Int_Vector2 {
    return .{xx v.x, xx v.y};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Int_Vector3 :: struct {
    x: s32;
    y: s32;
    z: s32;

#place x;
    xy: Int_Vector2 = ---;
#place y;
    yz: Int_Vector2 = ---;
}

operator + :: inline (a: Int_Vector3, b: Int_Vector3) -> Int_Vector3 {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator - :: inline (a: Int_Vector3, b: Int_Vector3) -> Int_Vector3 {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator * :: inline (a: Int_Vector3, b: Int_Vector3) -> Int_Vector3 {
    return .{a.x * b.x, a.y * b.y, a.z * b.z};
}

operator / :: inline (a: Int_Vector3, b: Int_Vector3) -> Int_Vector3 {
    return .{a.x / b.x, a.y / b.y, a.z / b.z};
}

operator + :: inline (a: Int_Vector3, scalar: s32) -> Int_Vector3 #symmetric {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

operator - :: inline (a: Int_Vector3, scalar: s32) -> Int_Vector3 {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator - :: inline (scalar: s32, a: Int_Vector3) -> Int_Vector3 {
    return .{scalar - a.x, scalar - a.y, scalar - a.z};
}

operator * :: inline (a: Int_Vector3, scalar: s32) -> Int_Vector3 #symmetric {
    return .{a.x * scalar, a.y * scalar, a.z * scalar};
}

operator / :: inline (a: Int_Vector3, scalar: s32) -> Int_Vector3 {
    return .{a.x / scalar, a.y / scalar, a.z / scalar};
}

operator / :: inline (scalar: s32, a: Int_Vector3) -> Int_Vector3 {
    return .{scalar / a.x, scalar / a.y, scalar / a.z};
}

operator == :: inline (a: Int_Vector3, b: Int_Vector3) -> bool {
    return (a.x == b.x) && (a.y == b.y) && (a.z == b.z);
}

to_vector3 :: inline (v: Int_Vector3) -> Vector3 {
    return .{xx v.x, xx v.y, xx v.z};
}

to_int_vector3 :: inline (v: Vector3) -> Int_Vector3 {
    return .{xx v.x, xx v.y, xx v.z};
}

abs :: inline (a: Int_Vector3) -> Int_Vector3 {
    return .{abs(a.x), abs(a.y), abs(a.z)};
}

sum :: inline (a: Int_Vector3) -> s32 {
    return a.x + a.y + a.z;
}