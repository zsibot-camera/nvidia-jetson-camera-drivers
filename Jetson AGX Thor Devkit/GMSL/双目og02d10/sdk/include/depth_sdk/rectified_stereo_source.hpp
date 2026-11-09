#pragma once

#include <memory>
#include <string>

#include <opencv2/core.hpp>

#include "depth_sdk/stereo_calibration.hpp"
#include "depth_sdk/stereo_source.hpp"

namespace depth_sdk {

class RectifiedStereoSource final : public StereoSource {
  public:
    RectifiedStereoSource(std::unique_ptr<StereoSource> source, StereoCalibration calibration);

    Status open(const StereoSourceConfig&) override;
    Status close() override;
    Status grab(ColorFrame* left, ColorFrame* right) override;
    void intrinsics(StereoIntrinsics*) const override;
    bool has_intrinsics() const override;

  private:
    std::unique_ptr<StereoSource> source_;
    StereoCalibration calibration_;
    cv::Mat left_map_x_, left_map_y_, right_map_x_, right_map_y_;
    StereoIntrinsics intrinsics_{};
    std::string error_;
    bool opened_ = false;
};

} // namespace depth_sdk
