struct VertexOutput {
    @location(0) tex_coord: vec2<f32>,
    @builtin(position) position: vec4<f32>,
};

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
    @builtin(instance_index) in_instance_index: u32
) -> VertexOutput {
    var out: VertexOutput;
    let x = f32((in_vertex_index & 1u) ^ in_instance_index);
    let y = f32((in_vertex_index >> 1u) ^ in_instance_index);
    out.position = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    out.tex_coord = vec2<f32>(x, y);
    return out;
}

@group(0) @binding(0)
var r_color: texture_2d<f32>;
@group(0) @binding(1)
var r_sampler: sampler;

fn anti_alising(tex_coord: vec2<f32>) -> vec4<f32>
{
    let main = textureSample(r_color, r_sampler, tex_coord);
    let direct_neighbors = array<vec4<f32>, 4>(
        textureSample(r_color, r_sampler, tex_coord + vec2<f32>(1.0, 0.0) * 0.003),
        textureSample(r_color, r_sampler, tex_coord + vec2<f32>(-1.0, 0.0) * 0.003),
        textureSample(r_color, r_sampler, tex_coord + vec2<f32>(0.0, 1.0) * 0.003),
        textureSample(r_color, r_sampler, tex_coord + vec2<f32>(0.0, -1.0) * 0.003)
    );

    var color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    color += main * 0.6;
    color += direct_neighbors[0] * 0.1;
    color += direct_neighbors[1] * 0.1;
    color += direct_neighbors[2] * 0.1;
    color += direct_neighbors[3] * 0.1;
    
    // color += main * 0.2;
    // color += direct_neighbors[0] * 0.2;
    // color += direct_neighbors[1] * 0.2;
    // color += direct_neighbors[2] * 0.2;
    // color += direct_neighbors[3] * 0.2;

    return color;
    // return vec4<f32>(tex_coord.x, 0.0, tex_coord.y, 1.0);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // return anti_alising(in.tex_coord);
    return textureSample(r_color, r_sampler, in.tex_coord);
}