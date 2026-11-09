// Frame types: an immutable view over a Buffer plus its timestamp/seq. See spec §6.
#pragma once

#include <memory>

#include "depth_sdk/buffer.hpp"
#include "depth_sdk/types.hpp"

namespace depth_sdk {

struct ColorFrame {
    PixelFormat format = PixelFormat::RGB8;
    FrameSize size;
    std::shared_ptr<Buffer> data; // 只读；深拷贝由消费者决定
    Timestamp ts;
    uint64_t seq = 0; // 源侧单调序号
};

struct DepthFrame {
    DepthFormat format = DepthFormat::F32_METERS;
    FrameSize size;
    std::shared_ptr<Buffer> data;
    Timestamp ts;
    uint64_t seq = 0; // 与同源 ColorFrame 对应
};

struct FramePair {
    ColorFrame color;
    DepthFrame depth;
};

} // namespace depth_sdk
