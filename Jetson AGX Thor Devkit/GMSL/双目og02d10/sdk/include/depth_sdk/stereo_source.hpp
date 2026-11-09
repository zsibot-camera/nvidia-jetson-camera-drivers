// Stereo capture abstraction. See spec §7.
#pragma once

#include <string>

#include "depth_sdk/frame.hpp"
#include "depth_sdk/types.hpp"

namespace depth_sdk {

struct StereoSourceConfig {
    // v4l2:///dev/video0,/dev/video1 或 v4l2:///dev/v4l/by-path/<left>,/dev/v4l/by-path/<right>；
    // 空值使用默认源。
    std::string uri;
    FrameSize resolution{1280, 720};
    // Optional processing/rectification output size. Zero means the capture
    // resolution. VPI sources may use this to produce model-sized frames.
    FrameSize processed_resolution{};
    PixelFormat format = PixelFormat::RGB8;
    // 仅 SyntheticStereoSource / ImageStereoSource 使用；真实相机忽略。
    int debug_frame_interval_ms = 0;
    // V4L2 左右帧的软件配对上限；硬件 FSIN 未启用时不能保证曝光同步。
    uint64_t max_pair_skew_ns = 5000000;
    int capture_timeout_ms = 1000;
};

class StereoSource {
  public:
    virtual ~StereoSource() = default;
    // 各实现返回的 Status::message 须遵循 types.hpp 的生命周期契约：
    // 指向成员 / 静态串 / 字面量，不得指向临时对象。
    virtual Status open(const StereoSourceConfig&) = 0;
    virtual Status close() = 0;
    virtual Status grab(ColorFrame* left, ColorFrame* right) = 0;
    // Optional independent raw stream. Sources without a separate raw queue
    // retain the legacy behavior and report false.
    virtual bool hasIndependentRaw() const { return false; }
    virtual Status grabRaw(ColorFrame* left, ColorFrame* right) {
        return grab(left, right);
    }
    // Optional raw-stream control. Producers that maintain a separate raw queue
    // can skip capturing/converting raw frames when nobody consumes them.
    virtual void setRawEnabled(bool enabled) { (void)enabled; }
    // Optional dual-output hook. Legacy sources return the same frames for both paths.
    virtual Status grabWithRaw(ColorFrame* raw_left, ColorFrame* raw_right,
                               ColorFrame* processed_left, ColorFrame* processed_right) {
        if (!raw_left || !raw_right || !processed_left || !processed_right) {
            return {StatusCode::InvalidArgument, "null frame output"};
        }
        Status st = grab(processed_left, processed_right);
        if (st) {
            *raw_left = *processed_left;
            *raw_right = *processed_right;
        }
        return st;
    }
    virtual void intrinsics(StereoIntrinsics*) const = 0;
    virtual bool has_intrinsics() const = 0;
};

// Deterministic synthetic source (gradient pattern, optional frame pacing).
class SyntheticStereoSource final : public StereoSource {
  public:
    Status open(const StereoSourceConfig&) override;
    Status close() override;
    Status grab(ColorFrame* left, ColorFrame* right) override;
    void intrinsics(StereoIntrinsics* out) const override;
    bool has_intrinsics() const override;

  private:
    StereoSourceConfig cfg_{};
    bool opened_ = false;
    uint64_t seq_ = 0;
    size_t bytes_per_pixel_ = 0;
};

} // namespace depth_sdk
