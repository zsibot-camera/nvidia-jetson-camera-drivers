// 文件型双目源：用磁盘上的左右目图片对模拟相机输入。See spec §7.
//
// 典型用途：无真实相机时驱动完整 SDK 管线（DepthStream + 深度引擎），并与离线
// 推理工具（las_infer）的输出逐像素对照，从而把「模型/引擎是否正确」与「SDK
// 集成是否正确」分开验证。
#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "depth_sdk/stereo_source.hpp"

namespace depth_sdk {

// 一对左右目图片的文件路径。
struct ImagePair {
    std::string left;
    std::string right;
};

// 从磁盘图片回放双目输入。
//
// 语义约定（与 SyntheticStereoSource 的差异是有意为之）：
//
//   1. **图片文件是尺寸与格式的唯一真值。** StereoSourceConfig::resolution 与
//      format 被忽略：resolution 的默认值 1280x720 对合成源意为「生成多大」，
//      对文件源没有意义；若拿它做校验，任何非 1280x720 的图都会失败。模型输入
//      尺寸的校验由 DepthEngineConfig::input_width/height 负责（那里 0 = 不校验
//      的语义是明确的）。本类只校验文件侧的真实错误：同一对左右目必须同尺寸、
//      同格式，且所有图片对尺寸一致。
//
//   2. **grab() 永不返回失败。** 已解码的图片对循环回放。这是必须的：
//      DepthStream::CaptureLoop 对 grab() 失败只做 `continue`（spec §10），若在
//      此处报告「图片放完了」，采集线程会 100% 忙等自旋。停止由调用方调用
//      DepthStream::stop() 决定。
//
//   3. 回放节奏由 StereoSourceConfig::debug_frame_interval_ms 控制。图片是静止
//      的，不设节奏会全速空转烧 CPU。
class ImageStereoSource final : public StereoSource {
  public:
    // 构造只存路径、不读盘：读文件失败必须以 Status 返回，而构造函数没有返回
    // 通道（核心库对外不抛异常，见 types.hpp 的 Status 生命周期契约）。
    explicit ImageStereoSource(std::vector<ImagePair> pairs);

    Status open(const StereoSourceConfig&) override;
    Status close() override;
    Status grab(ColorFrame* left, ColorFrame* right) override;
    void intrinsics(StereoIntrinsics*) const override;
    bool has_intrinsics() const override;

  private:
    // 一对已解码的图片。像素已压紧到 SDK 的格式约定：灰度 1 字节/像素、
    // 彩色 3 字节/像素（交错 RGB，alpha 已丢弃）。
    struct Loaded {
        FrameSize size{};
        PixelFormat format = PixelFormat::GRAY8;
        std::vector<uint8_t> left;
        std::vector<uint8_t> right;
    };

    std::vector<ImagePair> paths_;
    std::vector<Loaded> loaded_;
    StereoSourceConfig cfg_{};
    // 承接 open() 失败的文本，供 Status::message 引用。该指针不持有所有权，必须由
    // 生命周期长于 Status 消费方的对象承接（同 TrtLasRunner::load_error_ 的做法）。
    std::string open_error_;
    bool opened_ = false;
    size_t next_ = 0; // 下一对要回放的图片下标，到尾回绕
    uint64_t seq_ = 0;
};

} // namespace depth_sdk
