// Depth inference abstraction. See spec §7.
#pragma once

#include <string>

#include "depth_sdk/frame.hpp"
#include "depth_sdk/types.hpp"

namespace depth_sdk {

struct DepthEngineConfig {
    std::string model_path; // 骨架期未解释；TRT/onnx 路径由实现约定
    // LAS float32 output is the raw network disparity map. The legacy U16 path
    // still requests metric depth in millimeters.
    DepthFormat output_format = DepthFormat::F32_METERS;
    // 仅 StubDepthEngine 使用；真引擎忽略。
    int debug_infer_delay_ms = 0; // 每次 infer 模拟耗时
    int debug_failure_count = 0;  // 前 N 次 infer 返回 EngineUnavailable

    // 模型输入尺寸。0 = 由后端自报（TRT engine 内嵌形状）；非 0 = 校验后端自报值，
    // 不符则 load() 返回 InvalidArgument（早失败，胜过拿错尺寸静默跑）。
    int input_width = 0;
    int input_height = 0;

    // 视差→深度换算参数；语义 = 源分辨率下测得的值，引擎按 ScaleX 自动换算后使用。
    double fx = 305.471008;      // 水平焦距（像素）
    double baseline_m = 0.10054; // 双目基线（米，物理量，不换算）
};

class DepthEngine {
  public:
    virtual ~DepthEngine() = default;
    // 各实现返回的 Status::message 须遵循 types.hpp 的生命周期契约：
    // 指向成员 / 静态串 / 字面量，不得指向临时对象。
    virtual Status load(const DepthEngineConfig&) = 0;
    virtual Status unload() = 0;
    virtual Status infer(const ColorFrame& left, const ColorFrame& right, DepthFrame* out,
                         int timeout_ms = 0) = 0;
    // 可选：DepthStream 在 start() 成功后前推源的相机标定（仅当源 has_intrinsics()）。
    // 默认空实现，既有引擎不受影响。
    virtual void setIntrinsics(const StereoIntrinsics&) {}
};

// Optional extension for engines that can overlap preparation of a later frame
// with inference of an earlier frame. DepthStream keeps the ordinary synchronous
// DepthEngine path for implementations that do not provide this interface.
class PipelinedDepthEngine {
  public:
    virtual ~PipelinedDepthEngine() = default;
    // Non-blocking submission. Busy means the bounded pipeline has no free slot.
    virtual Status submit(const ColorFrame& left, const ColorFrame& right) = 0;
    // Wait for the oldest submitted result, preserving input order.
    virtual Status wait(FramePair* out, int timeout_ms) = 0;
};

// Deterministic stub for flow tests and demos. Sets format/size/data only;
// seq/ts are owned by the caller (DepthStream).
class StubDepthEngine final : public DepthEngine {
  public:
    Status load(const DepthEngineConfig&) override;
    Status unload() override;
    Status infer(const ColorFrame& left, const ColorFrame& right, DepthFrame* out,
                 int timeout_ms = 0) override;

  private:
    DepthEngineConfig cfg_{};
    bool loaded_ = false;
};

} // namespace depth_sdk
