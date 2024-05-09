#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::f32::consts::PI;

use wgpu::util::DeviceExt;
use wgpu::{BufferUsages, Extent3d, SamplerBindingType};

use winit::dpi::{LogicalPosition, LogicalSize};
use winit::event::{DeviceEvent, ElementState, KeyboardInput, VirtualKeyCode};
use winit::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::Window,
};

const WIDTH: f32 = 800.0;
const HEIGHT: f32 = 600.0;

async fn run(event_loop: EventLoop<()>, window: Window) {
    window.set_cursor_grab(winit::window::CursorGrabMode::Confined).unwrap();
    window.set_cursor_visible(false);
    window.set_cursor_position(LogicalPosition { x: WIDTH / 2.0, y: HEIGHT / 2.0 } ).unwrap();

    let instance = wgpu::Instance::new(wgpu::Backends::PRIMARY);
    let surface = unsafe { instance.create_surface(&window) };
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: Default::default(),
            force_fallback_adapter: false,
            compatible_surface: Some(&surface),
        })
        .await
        .expect("error finding adapter");

    let (device, queue) = adapter
        .request_device(&Default::default(), None)
        .await
        .expect("error creating device");
    let size = window.inner_size();
    let format = surface.get_supported_formats(&adapter)[0];
    let sc = wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format: format,
        width: size.width,
        height: size.height,
        present_mode: wgpu::PresentMode::Fifo,
        alpha_mode: surface.get_supported_alpha_modes(&adapter)[0],
    };
    surface.configure(&device, &sc);

    // We use a render pipeline just to copy the output buffer of the compute shader to the
    // swapchain. It would be nice if we could skip this, but swapchains with storage usage
    // are not fully portable.
    let copy_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(include_str!("copy.wgsl").into()),
    });
    let copy_bind_group_layout =
        device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        // Should filterable be false if we want nearest-neighbor?
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(SamplerBindingType::NonFiltering),
                    count: None,
                },
            ],
        });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[&copy_bind_group_layout],
        push_constant_ranges: &[],
    });
    let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &copy_shader,
            entry_point: "vs_main",
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: &copy_shader,
            entry_point: "fs_main",
            targets: &[Some(format.into())],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
    });

    let img = device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: Extent3d {
            width: size.width,
            height: size.height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::TEXTURE_BINDING,
    });
    let img_view = img.create_view(&Default::default());

    const CONFIG_SIZE: u64 = 32;

    let config_dev = device.create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size: CONFIG_SIZE,
        usage: BufferUsages::COPY_DST | BufferUsages::STORAGE | BufferUsages::UNIFORM,
        mapped_at_creation: false,
    });
    let config_resource = config_dev.as_entire_binding();

    let cs_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(include_str!("paint.wgsl").into()),
    });
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: None,
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::StorageTexture {
                    access: wgpu::StorageTextureAccess::WriteOnly,
                    format: wgpu::TextureFormat::Rgba8Unorm,
                    view_dimension: wgpu::TextureViewDimension::D2,
                },
                count: None,
            },
        ],
    });
    let compute_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: None,
        layout: Some(&compute_pipeline_layout),
        module: &cs_module,
        entry_point: "main",
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: config_resource,
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::TextureView(&img_view),
            },
        ],
    });
    let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        address_mode_u: wgpu::AddressMode::ClampToEdge,
        address_mode_v: wgpu::AddressMode::ClampToEdge,
        address_mode_w: wgpu::AddressMode::ClampToEdge,
        mag_filter: wgpu::FilterMode::Nearest,
        min_filter: wgpu::FilterMode::Nearest,
        mipmap_filter: wgpu::FilterMode::Nearest,
        ..Default::default()
    });
    let copy_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &copy_bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(&img_view),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::Sampler(&sampler),
            },
        ],
    });
    let start_time = std::time::Instant::now();

    let mut last_time = start_time;
    let mut tick = 0;

    let mut x_pos: f32 = 0.0;
    let mut y_pos: f32 = 0.0;
    let mut z_pos: f32 = 0.0;

    let mut y_rot: f32 = 0.0;
    let mut x_rot: f32 = 0.0;

    let mut w_pressed = false;
    let mut a_pressed = false;
    let mut s_pressed = false;
    let mut d_pressed = false;
    let mut space_pressed = false;
    let mut shift_pressed = false;

    let mut speed = 5.0;
    let mouse_speed = 0.002;

    event_loop.run(move |event, _, control_flow| {
        let current_time = std::time::Instant::now();
        let delta_time = (current_time - last_time).as_secs_f32();

        if tick % 100 == 0 {
            tick = 1;
            
            if !(current_time - last_time).is_zero() {
                // println!("{}", 1.0 / delta_time);
            }
            
        }
        tick += 1;
        
        last_time = current_time;

        // TODO: this may be excessive polling. It really should be synchronized with
        // swapchain presentation, but that's currently underbaked in wgpu.
        *control_flow = ControlFlow::Poll;
        match event {
            Event::DeviceEvent { event: DeviceEvent::Key(KeyboardInput{ virtual_keycode: Some(VirtualKeyCode::Escape), state: ElementState::Pressed, .. }), .. } => *control_flow = ControlFlow::Exit,
            Event::DeviceEvent { event: DeviceEvent::Key(KeyboardInput{ virtual_keycode, state, .. }), .. } => {
                match virtual_keycode.unwrap() {
                    VirtualKeyCode::W => {
                        w_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::A => {
                        a_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::S => {
                        s_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::D => {
                        d_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::Space => {
                        space_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::LShift => {
                        shift_pressed = if state == ElementState::Pressed { true } else { false };
                    }
                    VirtualKeyCode::LControl => {
                        if state == ElementState::Pressed {
                            speed = 40.0;
                        } else {
                            speed = 5.0;
                        } 
                    }
                    _ => {}
                }
            }
            Event::DeviceEvent { event: DeviceEvent::MouseMotion { delta }, .. } => {
                y_rot += delta.0 as f32 * mouse_speed;
                x_rot += delta.1 as f32 * mouse_speed;
            }
            Event::RedrawRequested(_) => {
                let frame = surface
                    .get_current_texture()
                    .expect("error getting texture from swap chain");

                let i_time: f32 = 0.5 + start_time.elapsed().as_micros() as f32 * 1e-6;
                let config_data = [size.width, size.height, i_time.to_bits(), x_pos.to_bits(), y_pos.to_bits(), z_pos.to_bits(), y_rot.to_bits(), x_rot.to_bits()];

                let config_host = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: None,
                    contents: bytemuck::bytes_of(&config_data),
                    usage: BufferUsages::COPY_SRC,
                });

                let mut encoder = device.create_command_encoder(&Default::default());
                encoder.copy_buffer_to_buffer(&config_host, 0, &config_dev, 0, CONFIG_SIZE);
                {
                    let mut cpass = encoder.begin_compute_pass(&Default::default());
                    cpass.set_pipeline(&pipeline);
                    cpass.set_bind_group(0, &bind_group, &[]);
                    cpass.dispatch_workgroups(size.width / 16, size.height / 16, 1);
                }
                {
                    let view = frame
                        .texture
                        .create_view(&wgpu::TextureViewDescriptor::default());
                    let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                        label: None,
                        color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                            view: &view,
                            resolve_target: None,
                            ops: wgpu::Operations {
                                load: wgpu::LoadOp::Clear(wgpu::Color::GREEN),
                                store: true,
                            },
                        })],
                        depth_stencil_attachment: None,
                    });
                    rpass.set_pipeline(&render_pipeline);
                    rpass.set_bind_group(0, &copy_bind_group, &[]);
                    rpass.draw(0..3, 0..2);
                }
                queue.submit(Some(encoder.finish()));
                frame.present();
            }
            Event::MainEventsCleared => {
                window.request_redraw();
            }
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => *control_flow = ControlFlow::Exit,
            _ => (),
        }

        if w_pressed {
            z_pos += y_rot.cos() * speed * delta_time;
            x_pos += y_rot.sin() * speed * delta_time;
        }
        if a_pressed {
            z_pos -= (y_rot + PI / 2.0).cos() * speed * delta_time;
            x_pos -= (y_rot + PI / 2.0).sin() * speed * delta_time;
        }
        if s_pressed {
            z_pos -= y_rot.cos() * speed * delta_time;
            x_pos -= y_rot.sin() * speed * delta_time;
        }
        if d_pressed {
            z_pos += (y_rot + PI / 2.0).cos() * speed * delta_time;
            x_pos += (y_rot + PI / 2.0).sin() * speed * delta_time;
        }
        if space_pressed {
            y_pos += speed * delta_time;
        }
        if shift_pressed {
            y_pos -= speed * delta_time;
        }

        x_rot = x_rot.clamp(-PI / 2.0, PI / 2.0);
    });
}

fn main() {
    let event_loop = EventLoop::new();
    let window = Window::new(&event_loop).unwrap();
    window.set_resizable(false);

    window.set_inner_size(LogicalSize { width: WIDTH, height: HEIGHT });
    pollster::block_on(run(event_loop, window));
}