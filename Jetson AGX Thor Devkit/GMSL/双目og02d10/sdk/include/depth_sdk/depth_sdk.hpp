// depth_sdk public header.
// The library is agnostic about where the depth comes from; an inference
// backend (CUDA/TensorRT) plugs in later behind the same API.
#pragma once

namespace depth_sdk {

// SDK semantic version.
constexpr const char* version() { return "0.1.0"; }

// Returns the architecture this library was compiled for, as a C string,
// so you can tell at runtime that you really ran the aarch64 build.
// e.g. "aarch64 (L4T/Jetson)" on the board, "x86_64 (host)" on the PC.
const char* arch_name();

} // namespace depth_sdk
