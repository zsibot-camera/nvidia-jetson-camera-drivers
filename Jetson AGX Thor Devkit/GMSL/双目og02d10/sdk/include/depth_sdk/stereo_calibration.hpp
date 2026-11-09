#pragma once

#include <string>

#include <opencv2/core.hpp>

#include "depth_sdk/types.hpp"

namespace depth_sdk {

class StereoCalibration final {
  public:
    static Status loadJson(const std::string& path, StereoCalibration* out);

    bool valid() const;
    FrameSize imageSize() const;
    double rectifiedFx() const;
    double rectifiedFy() const;
    double rectifiedCx() const;
    double rectifiedCy() const;
    double baselineM() const;

    const cv::Mat& leftCameraMatrix() const;
    const cv::Mat& leftDistCoeffs() const;
    const cv::Mat& rightCameraMatrix() const;
    const cv::Mat& rightDistCoeffs() const;
    const cv::Mat& leftRectification() const;
    const cv::Mat& rightRectification() const;
    const cv::Mat& leftProjection() const;
    const cv::Mat& rightProjection() const;
    const cv::Mat& reprojectionMatrix() const;

  private:
    FrameSize image_size_{};
    double baseline_m_ = 0.0;
    bool valid_ = false;
    std::string error_;
    cv::Mat r_, t_;
    cv::Mat k_left_, d_left_, k_right_, d_right_;
    cv::Mat r1_, r2_, p1_, p2_, q_;
};

} // namespace depth_sdk
