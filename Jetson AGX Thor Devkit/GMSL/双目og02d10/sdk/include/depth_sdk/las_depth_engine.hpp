// LAS2-M depth engine adapter. Wraps the LAS2-M disparity backend (TensorRT in
// production) behind the DepthEngine interface. See spec §7 and the T3 brief.
#pragma once

#include <memory>

#include "depth_sdk/depth_engine.hpp"

namespace depth_sdk {

// Abstract view of the LAS2-M inference backend. Production uses a TensorRT
// implementation (T4); tests inject a fake. Kept abstract so the core library
// never includes TensorRT/CUDA headers.
class LasRunner {
  public:
    virtual ~LasRunner() = default;
    // 模型输入尺寸，由后端自报（TrtLasRunner 从 engine 读出）。全 SDK 的尺寸以
    // 此为准，不得硬编码；换模型/换 engine 后尺寸自动跟随。
    virtual int inputHeight() const = 0;
    virtual int inputWidth() const = 0;
    virtual void infer(const float* left, const float* right, float* disp) = 0;
    // 让 runner 加载模型（model_path = engine 文件路径，语义见 DepthEngineConfig）。
    // 默认无操作并返回 Ok：测试注入的 FakeRunner 无需加载。TrtLasRunner 覆写为反
    // 序列化 TensorRT engine，并把构造/反序列化的异常转成 Status（核心库对外不抛
    // 异常）。LasDepthEngine::load 会先调它、再按自报尺寸做校验。
    virtual Status load(const std::string& model_path) { return {}; }
};

class LasDepthEngine final : public DepthEngine, public PipelinedDepthEngine {
  public:
    LasDepthEngine();                                    // 生产：由 TRT 分支创建 runner
    explicit LasDepthEngine(std::unique_ptr<LasRunner>); // 测试注入
    ~LasDepthEngine() override;
    Status load(const DepthEngineConfig&) override; // model_path = engine 文件路径
    Status unload() override;
    Status infer(const ColorFrame& left, const ColorFrame& right, DepthFrame* out,
                 int timeout_ms) override;
    Status submit(const ColorFrame& left, const ColorFrame& right) override;
    Status wait(FramePair* out, int timeout_ms) override;
    void setIntrinsics(const StereoIntrinsics&) override;

  private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace depth_sdk
