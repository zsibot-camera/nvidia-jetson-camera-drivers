// depth_sdk public types. See spec §4.
#pragma once

#include <cstdint>

namespace depth_sdk {

struct FrameSize {
    uint32_t width = 0, height = 0;
};

// 源分辨率 -> 目标分辨率的水平缩放因子（目标像素 / 源像素）。
// 约定「角点对齐」映射 src_x = dst_x * (src_w-1)/(dst_w-1)（与
// third_party/las2 的 preprocess 一致），故反向比例为 (dst_w-1)/(src_w-1)。
// 用途：把源分辨率下标定的 fx/cx 换算到模型输入分辨率；src_w==dst_w 时为 1。
constexpr double ScaleX(uint32_t src_w, uint32_t dst_w) {
    return (src_w > 1 && dst_w > 1)
               ? static_cast<double>(dst_w - 1) / static_cast<double>(src_w - 1)
               : 1.0;
}

enum class PixelFormat : uint8_t {
    RGB8, // 3 bytes/pixel，R,G,B 连续
    BGR8, // 3 bytes/pixel，B,G,R 连续
    NV12, // Y plane + 交错 UV（semi-planar）
    GRAY8,
    YUV420, // planar：Y 全平面，随后 U、V 各 1/4 平面
};

enum class DepthFormat : uint8_t {
    F32_METERS,      // float32，单位米
    U16_MILLIMETERS, // uint16，单位毫米（0=无效）
};

struct Timestamp {
    uint64_t ns = 0;
};

enum class StatusCode : uint8_t {
    Ok = 0,
    NotStarted,
    AlreadyRunning,
    Stopped,
    Timeout,
    NoFrameAvailable,
    SourceUnavailable,
    EngineUnavailable,
    BackendNotAvailable,
    Busy,
    InvalidArgument,
    Internal,
};

struct Status {
    StatusCode code = StatusCode::Ok;
    // 可空；不持有所有权。契约：message 必须指向生命周期不短于 Status 消费方的存储
    //（成员变量 / 静态串 / 字符串字面量），不得指向临时对象（如直接返回 e.what() 的
    // 临时异常缓冲）。跨模块转发（如 DepthStream::start 转发引擎的 load 错误）依赖本契约。
    const char* message = nullptr;
    explicit operator bool() const { return code == StatusCode::Ok; }
};

struct StereoIntrinsics {
    double fx = 0.0, fy = 0.0;
    double cx = 0.0, cy = 0.0;
    double baseline_m = 0.0; // 基线，米
    double k1 = 0.0, k2 = 0.0, p1 = 0.0, p2 = 0.0, k3 = 0.0;
};

} // namespace depth_sdk
