# The neural rendering engine

`upscale-engine.so`: Settings > Upscaling > Neural Rendering (config `neural`). It runs NVIDIA's DLSS 5 neural
rendering network on the render-size colour before the upscale, through the `vana_nr_dispatch` export of the engine
ABI (`docs/upscaler-engine.md`). Linux, Vulkan backend. Built for RDNA3 (Radeon RX 7000) and tested on a 7900 XTX.

The network is [DLSSNR-RDNA3](https://github.com/mauri870/DLSSNR-RDNA3)'s runtime (mauri870, MIT), built on
DLSSNR-AMD (mochizuki0323, MIT), vendored in `vendor/dlssnr-rdna3/`. The colour handover in `src/compose.comp`
follows RenoDX's DLSS 5 resolve.

## Build

```sh
engine/build.sh            # into target/engine/
```

Needs g++ (C++20), the Vulkan headers and loader, glslang and python3.

## Install

Copy `target/engine/upscale-engine.so` and `target/engine/nr/` into the data folder (`~/.local/share/vana-client`),
or point `VANA_UPSCALE_ENGINE` at the library. The engine reads everything from `nr/` beside the library
(`VANA_NR_ROOT` overrides it):

| Path | |
|---|---|
| `nr/dlssnr-amd/shaders/` | The network's shaders. |
| `nr/dlssnr-amd/dlssnr-small.bin`, `dlssnr.bin` | The model. Not shipped: made from the user's NVIDIA DLL, below. |
| `nr/prep.spv`, `nr/compose.spv` | The passes either side of the network. |
| `nr/engine.ini` | The settings, re-read while the game runs. The first run writes it from `engine.ini.default`. |
| `nr/engine.log` | Settings and GPU time. |
| `nr/model-tools/` | The model extraction. |

## The model

The weights are NVIDIA's and are not in this repository or in a release. They come from the user's own copy of
`nvngx_dlssnr.dll`, version 310.9.16 (both models) or 310.8.0 (`dlssnr.bin` only):

```sh
mkdir -p ~/.local/share/vana-client/nr/dlssnr-amd
bash ~/.local/share/vana-client/nr/model-tools/extract_model.sh nvngx_dlssnr.dll ~/.local/share/vana-client/nr/dlssnr-amd
```

It takes the DLL or a zip holding it, reads only the weight data (the DLL is never loaded or run) and writes a file
only when it matches the tested model byte for byte. It needs python3 only.

## Settings

`engine.ini` (`engine.ini` here is the default):

- `model`: `small` (310.9.16, faster) or `original` (310.8.0's, stronger, about twice the cost).
- `scale`: the network's size as a fraction of the render size, 0.25..1.
- `reuse_every`: run the network every Nth frame and carry its edit along the motion between.
- `style`, `intensity`, `local_tone`, `local_structure`, `skin_structure`, `exposure_ev`, `strength`, `color`,
  `chroma_clamp`, `vivid_guard`, `history`, `log_every`: see the comments in `engine.ini`.

`model`, `scale` and `reuse_every` rebuild the network when changed (a short hitch); the rest apply at once.

GPU time per frame on a 7900 XTX, 1280 x 720: the original model 15.0 ms, small 8.1, small at scale 0.5 4.1,
small with reuse 2 (the default) 4.3.

## Tools

- `tools/harness.cpp` (built as `target/engine/harness`): `harness <engine.so> <capture> <frames> <out>` calls
  `vana_nr_dispatch` the way the client does on an `/upcapture` capture and writes each frame's output as linear f32.
- `tools/experiment.py <capture> <out> name:key=value,...`: runs the harness under several `engine.ini` settings and
  prints the GPU time of each.
