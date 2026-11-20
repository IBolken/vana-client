# Upscaling: the inputs, the debug views, captures and the external engine

Settings > Graphics > Upscaling (config `upscaler`, `upscale_quality`, `upscale_sharpness`; off by default) draws the
3D world at a render size below the Background size and upscales it before the menus are drawn. The upscaler
runs in the world only, never in 3D LCD Mode, and needs a GPU with read-write storage textures in the formats
below (any desktop Vulkan or DX12 GPU). Code: `crates/vana-client/src/render/upscale/`.

## The per-frame inputs

All at the render size unless noted.

| Input | Format | Notes |
|---|---|---|
| Colour | `Rgba16Float` | Linear: the scene's gamma 2.2 undone, before grading and the gamma ramp (the scaling pass applies those after the upscale). |
| Depth | `Depth32Float` | Standard 0..1 (near 0, far 1), not reversed. Near 0.1, far 20000; vertical FOV per frame. |
| Motion | `Rg16Float` | Previous minus current position, in render pixels (FSR's convention), jitter taken out. The camera's from the depth; skinned actors' from this and last frame's bones; door and lift parts and a voyage's world from this and last frame's part clock and voyage matrix. |
| Reactive | `R8Unorm` | Where the effects (particles, spells, fire, faded actors) changed the picture: the largest channel change between the scene before and after them. |
| Composition | `R8Unorm` | Where blended scenery (water, glass, foliage cards) covers the opaque scenery: the change those passes made. |

Per frame also: the jitter in render pixels (Halton(2, 3), sequence length 8 x (output / render)² as FSR's), a reset
flag (zone change, size change, a camera cut: the eye moves over 8 units or turns over 30° in a frame), the frame time,
1 world unit = 1 metre, exposure 1.

The upscaled output is `Rgba16Float`, linear, at the Background size.

## Debug views and captures

- `/updebug [0..4]` shows an input in place of the scene: 1 motion (direction as colour around grey), 2 depth (log
  scale), 3 reactive (red), 4 composition (green); 0 the scene; without a number it steps to the next. Config
  `upscale_debug` keeps it.
- `/upcapture [frames] [label]` writes the inputs of the next 1..240 frames to the data folder (Linux
  `~/.local/share/vana-client`, Windows `%APPDATA%\vana-client`): `captures/<unix time>[-label]/frame_NNN/` holds
  `color.f32` (4 channels), `depth.f32` (1), `motion.f32` (2), `reactive.f32` (1), `composition.f32` (1) as raw
  little-endian f32, row-major with the top row first, and `inputs.json` with the sizes, the jitter, the reset flag
  and the scalars. The upscaler must be on (any mode).

## The external engine (Upscaling: External)

A native library is given the inputs as Vulkan handles and records its work into a command buffer of its own. It is
loaded from `VANA_UPSCALE_ENGINE`, else `upscale-engine.so` (Linux) / `upscale-engine.dll` (Windows) in the data
folder, and needs the Vulkan backend. It exports one function:

```c
int vana_upscale_dispatch(const VanaUpscaleFrame* frame); /* 0 = done; anything else: the frame is scaled plainly */
```

```c
typedef struct {
    uint64_t image;      /* VkImage */
    uint64_t view;       /* VkImageView */
    uint32_t format;     /* VkFormat */
    uint32_t layout;     /* VkImageLayout it is in, and must be left in */
    uint32_t width, height;
} VanaUpscaleImage;

typedef struct {
    uint32_t version;              /* 1 */
    uint32_t queue_family;
    uint64_t instance, physical_device, device, queue;
    uint64_t command_buffer;       /* recording: record into it; do not begin, end or submit it */
    VanaUpscaleImage color, depth, motion, reactive, composition;
    VanaUpscaleImage output;       /* write the upscaled linear colour here (output size) */
    uint32_t render_size[2], output_size[2];
    float jitter[2];               /* render pixels */
    uint32_t reset, reversed_z;
    float frame_time_ms, near_plane, far_plane, fov_y, meters_per_unit, exposure, sharpness;
} VanaUpscaleFrame;
```

- Layouts at the handover: colour, motion, reactive and composition `SHADER_READ_ONLY_OPTIMAL`, depth
  `DEPTH_STENCIL_READ_ONLY_OPTIMAL`, the output `GENERAL`. Leave each in the layout it came in.
- wgpu may not mix its own recording with raw commands in one encoder, so the frame's work up to here is submitted
  first and the engine's command buffer right after it on the same queue: its first commands must wait on that work
  with a barrier (source: all commands, memory writes), and its last must make the output's writes visible to
  fragment shader reads.
- The handles belong to the client: do not destroy them or keep them past the call.
