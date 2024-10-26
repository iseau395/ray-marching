# Raymarching

![a lot of green spheres](https://github.com/iseau395/ray-marching/blob/main/screenshot.png?raw=true)
![a blue torus with a shadow](https://github.com/iseau395/ray-marching/blob/main/screenshot2.png?raw=true)
![a lot of blue toruses, all with shadows](https://github.com/iseau395/ray-marching/blob/main/screenshot3.png?raw=true)

A super simple realtime ray marching rendering engine using wgpu in rust

based off this:
https://iquilezles.org/articles/raymarchingdf/

A lot of of the rust code and some of the shader code in `copy.wgsl` is from a tutorial to setup shaders which I can't find anymore, but basically everything in `paint.wgsl` (where the important math actually happens) is written by me