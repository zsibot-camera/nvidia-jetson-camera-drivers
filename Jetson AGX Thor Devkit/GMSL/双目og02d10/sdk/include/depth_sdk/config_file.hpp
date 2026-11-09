// 极简 key=value 配置文件。See spec §7.
//
// 存在的理由：把**相机参数与标定**从代码里挪到运行时文件，使换相机、改分辨率、
// 换标定**不需要重新编译**。这对「PC 交叉编译 -> 部署到板子」的工作流尤其重要 ——
// 板上只需改一个文本文件。
//
// 格式（受 INI 启发，但刻意更简单）：
//
//     # 整行注释
//     camera.width = 1920          # 行尾注释（# 前须有空白）
//     calib.fx     = 1068.63
//
//     stream.drop_while_busy = true
//
//   - 每行 `key = value`，`=` 两侧空白忽略；行首尾空白忽略
//   - 空行忽略；`#` 为注释（行首，或前面有空白时视为行尾注释）
//   - key 里的点号（如 `calib.fx`）只是命名约定，解析时不建树、不展开
//   - **值不做引号解析**：整行右侧（去掉注释与首尾空白）即为值，因此值里可以
//     直接写含空格或等号的路径
//
// 设计取舍：**不做类型推断**。取值时显式声明类型（getDouble/getInt/...），
// 类型不合法时回退到调用方给的默认值 —— 配置文件写错不应让程序崩，只应退回默认。
#pragma once

#include <cstddef>
#include <map>
#include <string>

#include "depth_sdk/types.hpp"

namespace depth_sdk {

class ConfigFile {
  public:
    // 路径为空或文件打不开 -> SourceUnavailable；语法错误（缺 `=`）-> InvalidArgument。
    // 注意：**调用方可忽略返回值**（用内建默认值继续跑）；返回值只用于诊断。
    Status load(const std::string& path);

    size_t size() const { return kv_.size(); }
    bool has(const std::string& key) const { return kv_.find(key) != kv_.end(); }

    // 以下 get* 在 key 缺失、值非法、或类型不适配时一律返回 def。
    // 布尔接受 true/false/1/0/yes/no/on/off（大小写不敏感）。
    double getDouble(const std::string& key, double def) const;
    int getInt(const std::string& key, int def) const;
    bool getBool(const std::string& key, bool def) const;
    std::string getString(const std::string& key, const std::string& def) const;

  private:
    std::map<std::string, std::string> kv_;
    // 承接 load 失败的文本，供 Status::message 引用（该指针不持有所有权，
    // 必须由生命周期更长的成员承接，见 types.hpp 的契约）。
    std::string error_;
};

} // namespace depth_sdk
