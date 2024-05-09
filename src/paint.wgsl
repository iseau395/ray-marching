struct Params {
    width: u32,
    height: u32,
    iTime: f32,
    x: f32,
    y: f32,
    z: f32,
    y_rot: f32,
    x_rot: f32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var outputTex: texture_storage_2d<rgba8unorm, write>;

struct SDFOutput {
    distance: f32,
    color: vec4<f32>
}

fn negate_sdf(sdf: SDFOutput) -> SDFOutput
{
    return SDFOutput(
        -sdf.distance,
        sdf.color
    );
}

fn min_sdf(a: SDFOutput, b: SDFOutput) -> SDFOutput
{
    if (a.distance < b.distance)
    {
        return a;
    }
    else
    {
        return b;
    }
}

fn max_sdf(a: SDFOutput, b: SDFOutput) -> SDFOutput
{
    if (a.distance > b.distance)
    {
        return a;
    }
    else
    {
        return b;
    }
}

fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32
{
  // n must be normalized
  return dot(p,n) + h;
}

fn sdSphere(pos: vec3<f32>, sphere_center: vec3<f32>, radius: f32) -> f32
{
    return length(pos - sphere_center) - radius;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32
{
  let q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

fn get_light_strength(normal: vec3<f32>) -> f32
{
    let light = normalize(vec3<f32>(1.0, -1.0, 1.0));

    return clamp(-dot(light, normal), 0.0, 1.0);
}

fn sphere(pos: vec3<f32>, sphere_center: vec3<f32>, radius: f32) -> SDFOutput
{
    let sphere_normal = normalize(pos - sphere_center);

    let light_strength = get_light_strength(sphere_normal);

    let sphere = SDFOutput(
        sdSphere(pos, sphere_center, radius),
        vec4<f32>(0.0, light_strength, 0.0, 1.0)
    );

    return sphere;
}

fn sdfFloor(pos: vec3<f32>) -> SDFOutput
{
    var floor_color: vec4<f32>;
    if ((ceil(pos.x * 1.0) % 2.0 == 0.0) != (ceil(pos.z * 1.0) % 2.0 == 0.0)) {
        floor_color = vec4<f32>(0.7, 0.7, 0.7, 1.0);
    } else {
        floor_color = vec4<f32>(0.5, 0.5, 0.5, 1.0);
    }

    let floor = SDFOutput(
        sdPlane(pos, vec3<f32>(0.0, 1.0, 0.0), 2.0),
        floor_color
    );

    return floor;
}

fn map(pos: vec3<f32>) -> SDFOutput
{
    let floor = sdfFloor(pos);
    // let sphere = sphere(pos, vec3<f32>(cos(params.iTime), sin(params.iTime), 3.0), 1.0);
    let sphere = sphere(vec3<f32>(pos.x % 10.0, pos.y, pos.z % 10.0), vec3<f32>(5.0, 5.0, 5.0), 1.0);

    return min_sdf(floor, sphere);
}

fn lerp(a: vec4<f32>, b: vec4<f32>, t: f32) -> vec4<f32>
{
    return a + (b - a) * t;
}


@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_ix: vec3<u32>) {
    let frag_coord: vec2<f32> = (vec2<f32>(global_ix.xy) / vec2<f32>(f32(params.width), f32(params.height))
        - vec2<f32>(0.5, 0.5)) * vec2<f32>(f32(params.width) / f32(params.height), 1.0);
        
    let epsilon = 0.0001;
    let threshold = 0.001;
    let max_steps = 500;
    let max_distance = 5000.0;

    var current_position = vec3<f32>(params.x, params.y, params.z);
    var total_distance = 0.0;
    
    let y_rot_matrix = mat3x3<f32>(
        cos(params.y_rot),  0.0,     sin(params.y_rot),
        0.0,                1.0,     0.0,
        -sin(params.y_rot), 0.0,    cos(params.y_rot)
    );
    let x_rot_matrix = mat3x3<f32>(
        1.0, 0.0,                0.0,               
        0.0, cos(params.x_rot),  -sin(params.x_rot),
        0.0, sin(params.x_rot),  cos(params.x_rot), 
    );

    let direction = normalize(vec3<f32>(frag_coord.x, -frag_coord.y, 0.5)) * x_rot_matrix * y_rot_matrix;
    
    var steps = 0;

    let bg_color =vec4<f32>(0.1, 0.5, 0.9, 0.0);
    var frag_color = bg_color;

    while (steps < max_steps && total_distance < max_distance) {
        let sdf_output = map(current_position);
        total_distance += sdf_output.distance;

        if (sdf_output.distance < threshold && sdf_output.distance >= -epsilon) {
            // frag_color = sdf_output.color;
            frag_color = lerp(sdf_output.color, bg_color, pow(total_distance / max_distance, 2.0));
            // frag_color = vec4<f32>(f32(5 - steps) / f32(5), 0.0, 0.0, 1.0);
            break;
        } else if (sdf_output.distance < -epsilon) {
            frag_color = vec4<f32>(1.0, 0.0, 0.0, 1.0);
            break;
        }

        current_position += sdf_output.distance * direction;

        steps += 1;
    }

    textureStore(outputTex, vec2<i32>(global_ix.xy), frag_color);
}