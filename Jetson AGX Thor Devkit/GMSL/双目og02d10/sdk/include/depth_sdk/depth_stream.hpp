// Public facade wiring capture + inference into aligned frame pairs. See spec §8.
#pragma once

#include <functional>
#include <memory>

#include "depth_sdk/depth_engine.hpp"
#include "depth_sdk/frame.hpp"
#include "depth_sdk/stereo_source.hpp"
#include "depth_sdk/types.hpp"

namespace depth_sdk {

struct DepthStreamConfig {
    StereoSourceConfig source;
    DepthEngineConfig engine;
    // 与 engine.output_format 必须一致，否则 start() 返回 InvalidArgument。
    DepthFormat depth_format = DepthFormat::F32_METERS;
    int capture_threads = 1; // 骨架期固定 1
    int infer_threads = 1;   // 骨架期固定 1
    bool drop_while_busy = true;
    int frame_queue_depth = 2; // 采集→引擎之间缓冲上限
    // 深度推理最大帧率；<=0 表示不限速（引擎尽力跑，GPU 占空比可能接近 100%）。
    // 限速只跳过送推理的帧，不影响彩色输出。
    double max_infer_fps = 0.0;
};

class DepthStream {
  public:
    struct Stats {
        uint64_t frames_produced = 0;
        uint64_t frames_dropped = 0;
        double average_fps = 0.0;
    };

    DepthStream();
    ~DepthStream(); // 未 stop 则隐式 stop（幂等）
    DepthStream(const DepthStream&) = delete;
    DepthStream& operator=(const DepthStream&) = delete;

    // start()/stop() 不得在 setFrameCallback / setColorFrameCallback 的回调内调用
    // （回调运行于内部工作线程，stop 会自 join）。
    Status start(const DepthStreamConfig&);
    Status stop();

    // 可选注入（须在 start() 前调用）；未设置则用内置 SyntheticStereoSource + StubDepthEngine。
    void setEngine(std::unique_ptr<DepthEngine> engine);
    void setSource(std::unique_ptr<StereoSource> source);

    // 阻塞至多 timeout_ms 取最新一对。
    Status waitNextFrame(FramePair* out, int timeout_ms);
    // 非阻塞取当前最新快照；尚无帧→NoFrameAvailable。
    Status getLatestFrame(FramePair* out);

    // 注册后由独立分发线程回调最新的成功推理帧。回调慢时旧帧会被覆盖，
    // 不会阻塞 inference 线程。clearFrameCallback 关闭。
    // 注意：回调运行在内部工作线程上，请勿在其中调用 stop()/start()——stop() 会 join 该线程，
    // 造成自 join（std::system_error → std::terminate）；如需停机请从其他线程调度。
    void setFrameCallback(std::function<void(const FramePair&)> fn);
    // 注册后由独立 color 分发线程回调最新的成功采集帧。支持独立 raw 队列的源
    // （当前为 V4L2+VPI）不会等待校正/推理路径，回调慢时旧帧会被覆盖。
    void setColorFrameCallback(std::function<void(const ColorFrame&)> fn);
    void setStereoColorFrameCallback(
        std::function<void(const ColorFrame&, const ColorFrame&)> fn);
    // Optional callback for the rectified color frame used by depth inference.
    void setRectifiedColorFrameCallback(std::function<void(const ColorFrame&)> fn);
    void setStereoRectifiedColorFrameCallback(
        std::function<void(const ColorFrame&, const ColorFrame&)> fn);
    void clearFrameCallback();
    void clearColorFrameCallback();
    void clearStereoColorFrameCallback();
    void clearRectifiedColorFrameCallback();
    void clearStereoRectifiedColorFrameCallback();

    Status getStats(Stats*) const;

  private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace depth_sdk
