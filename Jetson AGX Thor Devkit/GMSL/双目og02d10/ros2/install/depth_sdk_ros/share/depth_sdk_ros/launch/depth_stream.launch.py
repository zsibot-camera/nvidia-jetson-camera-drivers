# 启动 depth_stream_node，参数统一来自 config/params.yaml。
#
# 注意：不要把参数内联写在 parameters=[{...}] 字典里 —— 那样 config/params.yaml
# 就形同虚设，改它不生效（这里以前就是这么写的，踩过一次）。参数只留一处来源，
# 改配置只改 yaml。
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    # config/ 由 CMakeLists.txt 的 install(DIRECTORY launch config ...) 装到
    # share/depth_sdk_ros/ 下，故运行时可按包名定位。
    params_file = os.path.join(
        get_package_share_directory('depth_sdk_ros'), 'config', 'params.yaml')

    # 交付包中 sdk/ 不在构建机的默认路径下：允许用 DEPTH_SDK_CONFIG 指向随包
    # 的运行时配置（start_depth_ros.sh 默认设置该变量），覆盖 params.yaml 里的
    # config_file。未设置时保持 yaml 默认值，行为与开发环境一致。
    parameters = [params_file]
    config_override = os.environ.get("DEPTH_SDK_CONFIG")
    if config_override:
        parameters.append({"config_file": config_override})

    return LaunchDescription([
        Node(
            package='depth_sdk_ros',
            executable='depth_stream_node',
            name='depth_stream_node',
            output='screen',
            parameters=parameters,
        )
    ])
