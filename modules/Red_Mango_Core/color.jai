
COLOR4F_WHITE       :: Color4f.{1,1,1,1};
COLOR4F_RED         :: Color4f.{1,0,0,1};
COLOR4F_GREEN       :: Color4f.{0,1,0,1};
COLOR4F_BLUE        :: Color4f.{0,0,1,1};
COLOR4F_BLACK       :: Color4f.{0,0,0,1};

// COLOR4B_WHITE       :: #run to_color4b(COLOR4F_WHITE);
// COLOR4B_RED         :: #run to_color4b(COLOR4F_RED);
// COLOR4B_GREEN       :: #run to_color4b(COLOR4B_GREEN);
// COLOR4B_BLUE        :: #run to_color4b(COLOR4B_BLUE);
// COLOR4B_BLACK       :: #run to_color4b(COLOR4B_BLACK);

Color2f :: struct {
    r: float32;
    g: float32;

#overlay(r) vec2: Vector2 = ---;

#overlay(r) component: [2]float = ---;
}

Color3f :: struct {
    r: float32;
    g: float32;
    b: float32;

#overlay(r) rg: Color2f = ---;
#overlay(g) gb: Color2f = ---;

#overlay(r) using vec3: Vector3 = ---;

// #overlay r;
//     component: [3]float = ---;
}

Color4f :: struct {
    r: float32;
    g: float32;
    b: float32;
    a: float32 = 1.0;

#overlay(r) rgb: Color3f = ---;
#overlay(r) rg: Color2f = ---;
#overlay(g) gb: Color2f = ---;
#overlay(b) ba: Color2f = ---;

#overlay(r) using #as vec4: Vector4 = ---;
// #overlay r;
    // vec3: Vector3 = ---;

// #overlay r;
    // component: [4]float = ---;
}

Color4b :: struct {
    r: u8 #align 4; // should align to 4 bytes so this struct can be read as a u32;
    g: u8;
    b: u8;
    a: u8 = 255;

#overlay(r) bytes: [4]u8 = ---;
#overlay(r) _u32: u32 = ---;
}

operator * :: inline (color: Color4f, scalar: float) -> Color4f #symmetric {
    c := Color4f.{color.r * scalar, color.g * scalar, color.b * scalar, color.a};
    c.r = clamp(c.r, 0, 1);
    c.g = clamp(c.g, 0, 1);
    c.b = clamp(c.b, 0, 1);
    return c;
}

to_color4f :: inline (color3f: Color3f, alpha := 1.0) -> Color4f {
    float_color: Color4f = ---;
    float_color.r = color3f.r;
    float_color.g = color3f.g;
    float_color.b = color3f.b;
    float_color.a = alpha;
    return float_color;
}

to_color4f :: inline (color3f: Color3f, alpha : u8 = 255) -> Color4f {
    float_color: Color4f = ---;
    float_color.r = color3f.r;
    float_color.g = color3f.g;
    float_color.b = color3f.b;
    float_color.a = alter_cast(alpha, float, true);
    return float_color;
}

to_color4b :: inline (color4f: Color4f) -> Color4b {
    byte_color: Color4b = ---;
    byte_color.r = alter_cast(color4f.r, u8, true);
    byte_color.b = alter_cast(color4f.b, u8, true);
    byte_color.g = alter_cast(color4f.g, u8, true);
    byte_color.a = alter_cast(color4f.a, u8, true);
    return byte_color;
}

to_color4f :: inline (color4b: Color4b) -> Color4f {
    float_color: Color4f = ---;
    float_color.r = alter_cast(color4b.r, float, true);
    float_color.g = alter_cast(color4b.g, float, true);
    float_color.b = alter_cast(color4b.b, float, true);
    float_color.a = alter_cast(color4b.a, float, true);
    return float_color;
}

to_color4b :: inline (hex_color_code: u32) -> Color4b {
    byte_color: Color4b = ---;
    byte_color.r = ((hex_color_code & 0xff0000) >> 16).(u8);
    byte_color.g = ((hex_color_code & 0x00ff00) >>  8).(u8);
    byte_color.b = ((hex_color_code & 0x0000ff) >>  0).(u8);
    byte_color.a = 255;
    return byte_color;   
}

to_color4f :: inline (hex_color_code: u32) -> Color4f {
    color_4b := to_color4b(hex_color_code);
    return to_color4f(color_4b);
}

random_color4f :: inline (r_bounds := Vector2.{0.2, 0.8}, g_bounds := Vector2.{0.2, 0.8}, b_bounds := Vector2.{0.2, 0.8}, a := 1.0, random_state : *Random_State = null) -> Color4f {
    if random_state == null {
        random_state = *context.random_state;
    }
    float_color: Color4f = ---;
    float_color.r = r_bounds.x + random_get_zero_to_one(random_state) * (r_bounds.y - r_bounds.x);
    float_color.g = g_bounds.x + random_get_zero_to_one(random_state) * (g_bounds.y - g_bounds.x);
    float_color.b = b_bounds.x + random_get_zero_to_one(random_state) * (b_bounds.y - b_bounds.x);
    float_color.a = a;
    return float_color;
}

uniform_brighten :: (color: Color3f, alpha := 0.2) -> Color3f {
    assert(alpha >= 0 && alpha <= 1);
    out_color: Color3f = ---;
    out_color.r = min(color.r + (1.0 - color.r) * alpha, 1.0);
    out_color.g = min(color.g + (1.0 - color.g) * alpha, 1.0);
    out_color.b = min(color.b + (1.0 - color.b) * alpha, 1.0);
    return out_color;
}