#!/usr/bin/env bash
# Builds the neural rendering engine into target/engine/ (or $1): upscale-engine.so, nr/ beside it (the shaders, the
# default engine.ini and the model tools) and the harness. Needs g++ (C++20), the Vulkan loader and headers 1.4.357
# or later (VULKAN_INCLUDE: another include folder), glslang and python3. Install: target/engine/ but the harness,
# copied into the data folder.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
nr=$here/vendor/dlssnr-rdna3
out=$(mkdir -p -- "${1:-$here/../target/engine}" && cd -- "${1:-$here/../target/engine}" && pwd)
glslang=$(command -v glslang || command -v glslangValidator) || { echo "glslang is required" >&2; exit 1; }
export NR_GLSLANG=$glslang

cd -- "$nr"
source linux/build/arch/rdna3.sh
rm -rf -- "$out/nr/dlssnr-amd/shaders" "$out/nr/model-tools"
mkdir -p -- "$out/nr/dlssnr-amd"
python3 linux/build/build_network.py rdna3 --out "$out/nr/dlssnr-amd/shaders" > /dev/null
for s in prep compose; do "$glslang" -V --target-env vulkan1.3 -o "$out/nr/$s.spv" "$here/src/$s.comp" > /dev/null; done
inc=(-Ilinux/src/core ${VULKAN_INCLUDE:+-I$VULKAN_INCLUDE})
g++ -std=c++20 -O2 -w -fPIC -shared -fvisibility=hidden "${inc[@]}" "${NR_PRODUCT_DEFINES[@]}" \
    "$here/src/engine.cpp" linux/src/core/nr_runtime.cpp linux/src/core/nr_native_plan.cpp \
    -o "$out/upscale-engine.so" -lvulkan -lpthread
g++ -std=c++20 -O1 -w "${inc[@]}" "${NR_PRODUCT_DEFINES[@]}" "$here/tools/harness.cpp" -o "$out/harness" -lvulkan -ldl
cp -f -- "$here/engine.ini" "$out/nr/engine.ini.default"
cp -r -- linux/package/model-tools "$out/nr/model-tools"
echo "$out"
