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
    color: vec4<f32>,
    normal: vec3<f32>
}

struct RaymarchOutput {
    color: vec4<f32>,
    min_distance: f32,
    total_distance: f32,
    end_position: vec3<f32>,
    normal: vec3<f32>,
    collided: bool
}

fn negate_sdf(sdf: SDFOutput) -> SDFOutput
{
    return SDFOutput(
        -sdf.distance,
        sdf.color,
        sdf.normal
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

fn sphere(pos: vec3<f32>, sphere_center: vec3<f32>, radius: f32) -> SDFOutput
{
    let sphere = SDFOutput(
        sdSphere(pos, sphere_center, radius),
        vec4<f32>(0.0, 1.0, 0.0, 1.0),
        vec3<f32>(0.0, 0.0, 0.0) // Normal should be set later
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
        floor_color,
        vec3<f32>(0.0, 0.0, 0.0) // Normal should be set later
    );

    return floor;
}

fn sdf(pos: vec3<f32>) -> SDFOutput
{
    let floor = sdfFloor(pos);
    // let sphere = sphere(pos, vec3<f32>(2.0 * cos(params.iTime), 2.0 * sin(params.iTime), 0.0), 2.0);
    // let sphere = sphere(vec3<f32>(pos.x % 10.0, pos.y % 10.0, pos.z), vec3<f32>(5.0, 5.0, 5.0), 1.0);
    let donut = SDFOutput(
        sdTorus(pos, vec2<f32>(3.0, 1.0)),
        vec4<f32>(0.0, 0.0, 1.0, 0.0),
        vec3<f32>(0.0, 0.0, 0.0) // Normal should be set later
    );

    return min_sdf(floor, donut);
}

fn get_normal(pos: vec3<f32>) -> vec3<f32>
{
    let epsilon = 0.0001;

    let v1 = vec3<f32>(
        sdf(pos + vec3<f32>(epsilon, 0.0,     0.0    )).distance,
        sdf(pos + vec3<f32>(0.0,     epsilon, 0.0    )).distance,
        sdf(pos + vec3<f32>(0.0,     0.0,     epsilon)).distance
    );
    let v2 = vec3<f32>(
        sdf(pos - vec3<f32>(epsilon, 0.0,     0.0    )).distance,
        sdf(pos - vec3<f32>(0.0,     epsilon, 0.0    )).distance,
        sdf(pos - vec3<f32>(0.0,     0.0,     epsilon)).distance
    );

    return normalize(v1 - v2);
}

fn map(pos: vec3<f32>) -> SDFOutput
{
    let out = sdf(pos);
    let normal = get_normal(pos);

    return SDFOutput(
        out.distance,
        out.color,
        normal
    );
}

fn lerp(a: vec4<f32>, b: vec4<f32>, t: f32) -> vec4<f32>
{
    return a + (b - a) * t;
}

fn raymarch(initial_position: vec3<f32>, direction: vec3<f32>, max_steps: i32, max_distance: f32) -> RaymarchOutput
{
    let epsilon = 0.001;
    let threshold = 0.001;

    var steps = 0;
    var total_distance = 0.0;
    var min_distance = 999999999.0; // arbitrarally large number
    var last_distance = -1.0;
    var left_threshold = false;

    var current_position = initial_position;

    while (steps < max_steps && total_distance < max_distance) {
        let sdf_output = map(current_position);
        total_distance += sdf_output.distance;

        if (steps > 0 && (sdf_output.distance < min_distance) && (last_distance - sdf_output.distance) > 0.0) {
            min_distance = sdf_output.distance;
        }

        if (steps == 0 && sdf_output.distance == 0.0) {
            current_position += epsilon * direction;
            last_distance = epsilon;
            steps += 1;
            continue;
        }

        if ((sdf_output.distance < threshold && sdf_output.distance >= -epsilon && left_threshold) || (!left_threshold && (last_distance - sdf_output.distance) > 0.0)) {
            return RaymarchOutput(
                sdf_output.color,
                min_distance,
                total_distance,
                current_position,
                sdf_output.normal,
                true
            );
        } else if (sdf_output.distance >= threshold) {
            left_threshold = true;
        } else if (sdf_output.distance < -epsilon) {
            return RaymarchOutput(
                vec4<f32>(1.0, 0.0, 0.0, 1.0),
                min_distance,
                total_distance,
                current_position,
                sdf_output.normal,
                true
            );
        }

        if (steps == 0) {
            last_distance = sdf_output.distance;
        }

        current_position += abs(sdf_output.distance) * direction;

        steps += 1;
    }
    
    return RaymarchOutput(
        vec4<f32>(0.0, 1.0, 0.0, 0.0),
        min_distance,
        total_distance,
        current_position,
        vec3<f32>(0.0, 0.0, 0.0),
        false
    );
}


@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_ix: vec3<u32>) {
    let frag_coord: vec2<f32> = (vec2<f32>(global_ix.xy) / vec2<f32>(f32(params.width), f32(params.height))
        - vec2<f32>(0.5, 0.5)) * vec2<f32>(f32(params.width) / f32(params.height), 1.0);

    var camera_position = vec3<f32>(params.x, params.y, params.z);
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

    var frag_color = vec4<f32>(0.0, 0.0, 0.0, 0.0);

    for (var i = 0; i < 5; i += 1)
    {
        var offset = vec2<f32>(0.0, 0.0);

        if (i == 1) {
            offset = vec2<f32>(-1.0/3.0 / f32(params.width), 1.0/3.0 / f32(params.height));
        } else if (i == 2) {
            offset = vec2<f32>(1.0/3.0 / f32(params.width), 1.0/3.0 / f32(params.height));
        } else if (i == 3) {
            offset = vec2<f32>(1.0/3.0 / f32(params.width), -1.0/3.0 / f32(params.height));
        } else if (i == 4) {
            offset = vec2<f32>(-1.0/3.0 / f32(params.width), -1.0/3.0 / f32(params.height));
        }

        let direction = normalize(vec3<f32>(frag_coord.x + offset.x, -frag_coord.y + offset.y, 0.5)) * x_rot_matrix * y_rot_matrix;
        
        let bg_color = vec4<f32>(0.1, 0.5, 0.9, 0.0);
        let light_direction = normalize(vec3<f32>(20.0, 40.0, 20.0));

        let march_output = raymarch(camera_position, direction, 500, 5000.0);
        var color = bg_color;

        if (march_output.collided) {
            color = lerp(march_output.color, bg_color, pow(total_distance / 5000.0, 2.0));
            
            // let light_direction = normalize(light - march_output.end_position);
            let ambient = 0.1;

            let shadow_march = raymarch(march_output.end_position, light_direction, 100, 1000.0);

            if (shadow_march.collided) {
                color *= (ambient);
            } else {
                let diffuse = max(dot(march_output.normal, light_direction), 0.0);
                // let soft_shadow = clamp(shadow_march.min_distance, 0.0, 0.1) * 10.0;

                color *= (ambient + diffuse);
                // color = vec4<f32>(clamp(shadow_march.min_distance, 0.0, 1.0), 0.0, 0.0, 1.0);
            }
        }

        frag_color += color * 0.2;
        // frag_color = color;
    }

    textureStore(outputTex, vec2<i32>(global_ix.xy), frag_color);
}