// Frame data carrier. CUDA is the first-class path (CudaBuffer later); the
// host view keeps the flow testable on a GPU-less PC. See spec §5.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "depth_sdk/types.hpp"

namespace depth_sdk {

enum class DeviceKind : uint8_t { Host, Cuda };

class Buffer {
  public:
    virtual ~Buffer() = default;
    virtual DeviceKind device() const = 0;
    virtual size_t bytes() const = 0;
    virtual void* cuda_ptr(Status* out_status = nullptr) = 0;
    virtual void* host_ptr(Status* out_status = nullptr) = 0;
};

// Host-resident buffer used by the synthetic source and by GPU-less testing.
class HostBuffer final : public Buffer {
  public:
    explicit HostBuffer(size_t bytes) : data_(bytes, 0) {}

    DeviceKind device() const override { return DeviceKind::Host; }
    size_t bytes() const override { return data_.size(); }

    void* cuda_ptr(Status* out_status = nullptr) override {
        if (out_status) {
            out_status->code = StatusCode::BackendNotAvailable;
            out_status->message = "no CUDA backend on this build";
        }
        return nullptr;
    }

    void* host_ptr(Status* out_status = nullptr) override {
        if (out_status) {
            out_status->code = StatusCode::Ok;
            out_status->message = nullptr;
        }
        return data_.data();
    }

  private:
    std::vector<uint8_t> data_;
};

} // namespace depth_sdk
