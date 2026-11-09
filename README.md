# NVIDIA Jetson 相机驱动

智身科技（GENISOM AI）视觉传感器团队面向 NVIDIA Jetson 平台的相机驱动与 SDK 发布仓库。

## 内容

| 平台 | 接口 | 相机模组 | 说明 |
| --- | --- | --- | --- |
| Jetson AGX Thor Devkit | GMSL | 双目 OG02D10 | [深度相机交付包](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/) |

其他平台与模组目录（Jetson AGX Orin Devkit、RLINK、单目 ISX031 / OG02B10）暂未发布。

## 交付形式

以二进制交付为主：内核驱动（`.ko` / `.dtbo`）、安装脚本、预编译 SDK（头文件 + 动态库 + TensorRT engine）与 ROS2 节点，不包含算法与 C++ 源码。

## 相关仓库

- [d-robotics-camera-drivers](https://github.com/zsibot-camera/d-robotics-camera-drivers) — D-Robotics RDK S600 / S100P 平台
- [.github](https://github.com/zsibot-camera/.github) — 组织展示页
