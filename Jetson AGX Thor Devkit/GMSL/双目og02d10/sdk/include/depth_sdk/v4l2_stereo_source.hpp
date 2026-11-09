// V4L2-backed synchronized-by-timestamp stereo source.
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "depth_sdk/stereo_source.hpp"

namespace depth_sdk {

class StereoCalibration;

// Captures two YUYV V4L2 devices and pairs frames by their monotonic kernel
// timestamps. This provides software pairing; true exposure synchronization
// still requires sensor/driver hardware triggering.
class V4L2StereoSource final : public StereoSource {
  public:
    V4L2StereoSource();
    ~V4L2StereoSource() override;

    Status open(const StereoSourceConfig&) override;
    Status close() override;
    Status grab(ColorFrame* left, ColorFrame* right) override;
    bool hasIndependentRaw() const override;
    Status grabRaw(ColorFrame* left, ColorFrame* right) override;
    void setRawEnabled(bool enabled) override;
    Status grabWithRaw(ColorFrame* raw_left, ColorFrame* raw_right,
                       ColorFrame* processed_left, ColorFrame* processed_right) override;
    void intrinsics(StereoIntrinsics*) const override;
    bool has_intrinsics() const override;

    // Enables the Jetson VPI path. The calibration must match the capture
    // resolution. Without DEPTH_SDK_HAS_VPI this returns BackendNotAvailable.
    Status setVpiRectification(const StereoCalibration& calibration);

  private:
    struct MappedBuffer {
        void* start = nullptr;
        size_t length = 0;
    };

    struct PendingFrame {
        std::vector<uint8_t> payload;
        uint64_t timestamp_ns = 0;
        uint32_t buffer_index = 0;
        bool is_yuyv = true;
        bool valid = false;
    };

    struct CaptureTiming {
        double poll_ms = 0.0;
        double dqbuf_ms = 0.0;
        double vic_transform_ms = 0.0;
        double map_ms = 0.0;
        double sync_for_cpu_ms = 0.0;
        double rgbx_to_rgb_ms = 0.0;
        double unmap_ms = 0.0;
        double qbuf_ms = 0.0;
        double payload_prepare_ms = 0.0;
    };

    struct FrameBuildTiming {
        double buffer_alloc_ms = 0.0;
        double yuyv_to_rgb_ms = 0.0;
        double rgb_copy_ms = 0.0;
    };

    // Per-capture-buffer VPI resources. A slot stays owned from DQBUF until
    // its VPI work is complete and the original DMABUF has been QBUF'ed.
    // Keeping outputs per slot is what permits several camera frames to be
    // in flight without one frame overwriting another's VIC/VPI result.
    struct VpiSlot {
        void* nvbuf_output = nullptr;
        void* nv12_output = nullptr;
        void* rectified_output = nullptr;
        void* nv12_image = nullptr;
        void* output_image = nullptr;
        void* stream = nullptr;
        uint32_t buffer_index = 0;
        uint64_t timestamp_ns = 0;
        bool in_flight = false;
    };

    struct Device {
        int fd = -1;
        std::string path;
        std::vector<MappedBuffer> buffers;
        std::vector<void*> nvbuf_surfaces;
        std::vector<int> dmabuf_fds;
        void* nvbuf_output = nullptr;
        std::vector<void*> vpi_input_images;
        std::vector<VpiSlot> vpi_slots;
        PendingFrame pending;
        PendingFrame raw_pending;
        bool streaming = false;
        // 采集线程诊断计数（只在 asyncCaptureLoop 里读写，无需原子）。
        uint64_t dbg_polls = 0;
        uint64_t dbg_ready = 0;
        uint64_t dbg_dqbuf = 0;
        uint64_t dbg_timeouts = 0;
        uint64_t dbg_submit_fail = 0;
    };

    struct AsyncPair {
        uint64_t sequence = 0;
        uint32_t left_index = 0;
        uint32_t right_index = 0;
        std::shared_ptr<PendingFrame> raw_left;
        std::shared_ptr<PendingFrame> raw_right;
        uint64_t left_timestamp_ns = 0;
        uint64_t right_timestamp_ns = 0;
    };

    struct AsyncResult {
        uint64_t sequence = 0;
        std::shared_ptr<PendingFrame> raw_left;
        std::shared_ptr<PendingFrame> raw_right;
        ColorFrame processed_left;
        ColorFrame processed_right;
    };

    struct AsyncRawResult {
        ColorFrame left;
        ColorFrame right;
    };

    struct VpiState;

    Status openDevice(Device*, const FrameSize&, const FrameSize&);
    void closeDevice(Device*);
    Status captureOne(Device*, int timeout_ms, bool* captured, CaptureTiming* timing);
    Status grabInternal(ColorFrame* raw_left, ColorFrame* raw_right,
                        ColorFrame* processed_left, ColorFrame* processed_right);
#if defined(DEPTH_SDK_HAS_VPI)
    Status finishVpi(Device*, uint32_t buffer_index, PendingFrame* output,
                     CaptureTiming* timing);
    void startAsyncVpi();
    void stopAsyncVpi();
    void asyncCaptureLoop();
    void asyncProcessLoop();
    void asyncRawLoop();
    Status grabAsync(ColorFrame* raw_left, ColorFrame* raw_right,
                     ColorFrame* processed_left, ColorFrame* processed_right);
    Status grabRawAsync(ColorFrame* left, ColorFrame* right);
#endif
    static bool parseUri(const std::string&, std::string*, std::string*);
    static size_t outputBytes(FrameSize, PixelFormat);
    static void yuyvToPixels(const std::vector<uint8_t>&, FrameSize, PixelFormat, void*);
    static ColorFrame makeFrame(const PendingFrame&, FrameSize, PixelFormat, uint64_t,
                                FrameBuildTiming* timing);

    Device left_;
    Device right_;
    StereoSourceConfig cfg_{};
    FrameSize size_{};
    FrameSize processed_size_{};
    PixelFormat output_format_ = PixelFormat::RGB8;
    uint64_t max_pair_skew_ns_ = 5000000; // 5 ms software pairing bound
    int capture_timeout_ms_ = 1000;
    uint64_t seq_ = 0;
    bool opened_ = false;
    std::string open_error_;
    std::unique_ptr<VpiState> vpi_;
#if defined(DEPTH_SDK_HAS_VPI)
    std::mutex async_mutex_;
    std::condition_variable async_cv_;
    // Raw frames are only a preview side-channel: never let them accumulate
    // when the consumer is slower than capture (each pair holds ~10 MB of YUYV).
    static constexpr size_t kMaxRawQueue = 4;
    std::deque<AsyncPair> async_pairs_;
    std::deque<AsyncPair> async_raw_pairs_;
    std::deque<AsyncResult> async_results_;
    std::deque<AsyncRawResult> async_raw_results_;
    std::atomic<bool> raw_enabled_{true};
    std::thread async_capture_thread_;
    std::thread async_process_thread_;
    std::thread async_raw_thread_;
    bool async_stop_ = false;
    uint64_t async_sequence_ = 0;
#endif
    uint64_t timing_pairs_ = 0;
    double timing_frame_build_ms_ = 0.0;
    double timing_frame_buffer_alloc_ms_ = 0.0;
    double timing_frame_yuyv_to_rgb_ms_ = 0.0;
    double timing_frame_rgb_copy_ms_ = 0.0;
    double timing_pair_total_ms_ = 0.0;
    double timing_left_poll_ms_ = 0.0;
    double timing_right_poll_ms_ = 0.0;
    double timing_left_payload_prepare_ms_ = 0.0;
    double timing_right_payload_prepare_ms_ = 0.0;
    double timing_left_dqbuf_ms_ = 0.0;
    double timing_right_dqbuf_ms_ = 0.0;
    double timing_left_vic_transform_ms_ = 0.0;
    double timing_right_vic_transform_ms_ = 0.0;
    double timing_left_map_ms_ = 0.0;
    double timing_right_map_ms_ = 0.0;
    double timing_left_sync_for_cpu_ms_ = 0.0;
    double timing_right_sync_for_cpu_ms_ = 0.0;
    double timing_left_rgbx_to_rgb_ms_ = 0.0;
    double timing_right_rgbx_to_rgb_ms_ = 0.0;
    double timing_left_unmap_ms_ = 0.0;
    double timing_right_unmap_ms_ = 0.0;
    double timing_left_qbuf_ms_ = 0.0;
    double timing_right_qbuf_ms_ = 0.0;
    double timing_pair_skew_ms_ = 0.0;
    double timing_max_pair_skew_ms_ = 0.0;
    uint64_t timing_skew_drops_ = 0;
    uint64_t timing_capture_timeouts_ = 0;
    uint64_t timing_grab_timeouts_ = 0;

    // These are reset after each timing log, so they describe the most recent
    // 100 successfully matched pairs rather than the entire process lifetime.
    std::chrono::steady_clock::time_point timing_last_pair_done_{};
    double timing_window_output_period_ms_ = 0.0;
    double timing_window_max_output_period_ms_ = 0.0;
    uint64_t timing_window_output_periods_ = 0;
    uint64_t timing_window_skew_drops_ = 0;
    uint64_t timing_window_capture_timeouts_ = 0;
    uint64_t timing_window_grab_timeouts_ = 0;
};

} // namespace depth_sdk
