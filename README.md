# visualization

## 项目简介

`visualization` 是一个面向 ROS 2 场景的可视化工具组件，主要用于为机器人系统提供基础可视化能力，包括：

- 启动 RViz 进行导航、SLAM、RGBD、3D 激光雷达等场景展示
- 提供基于 WebSocket 的图像流转发节点，将 ROS 话题中的压缩图像发布到浏览器端
- 配合前端页面模板，实现轻量级网页端图像查看能力

该组件主要解决以下问题：

- 机器人调试过程中需要快速查看传感器、地图、导航等可视化信息
- 在无本地桌面环境或需要远程访问时，需要通过浏览器查看图像结果
- 为开发、联调、演示提供统一的可视化入口

## 功能特性

当前支持：

- 通过 launch 文件启动不同场景下的 RViz 可视化
  - `display_navigation.launch.py`
  - `display_slam.launch.py`
  - `display_rgbd.launch.py`
  - `display_rtab_3dlidar.launch.py`
- 启动 `websocket_cpp_node` 节点
- 从 ROS 2 压缩图像话题订阅图像数据并通过 WebSocket 推送到网页端
- 通过模板页面访问可视化结果
- 支持通过 launch 参数配置图像话题与 WebSocket 端口

当前不支持或需注意：

- Web 页面能力当前主要聚焦图像展示，不等同于完整的机器人运维/监控平台
- WebSocket 节点当前基于压缩图像数据做转发，默认场景不包含鉴权、加密、访问控制等生产级安全能力
- 不同 launch 文件中引用的资源目录和包名需要结合实际安装内容确认，例如 RViz 配置文件、上层可视化资源包是否完整可用

## 快速开始

### 环境准备

建议确认以下环境已经具备：

- 已安装并配置 ROS 2 运行环境
- 已完成当前工作区依赖安装与源码同步
- 已具备 `colcon`、`ament` 等基础构建工具
- 若使用网页图像流功能，需要网络可达，并可通过浏览器访问运行节点所在设备 IP

### 在 SDK 内编译

本仓库提供统一的 SDK 构建脚本，推荐优先使用 SDK 自带方式完成编译。标准流程如下：

1. 加载构建环境脚本
2. 通过 `lunch` 选择目标配置
3. 使用 `m`、`mm` 或 `build/build.sh` 执行构建

在仓库根目录执行：

```bash
source build/envsetup.sh
```

选择构建目标，例如：

```bash
lunch
# 或直接指定
lunch k3-com260-minimal
```

如果当前目标配置已经启用了 `visualization` 所在的 ROS 2 包，可以直接构建全部 ROS 2 组件：

```bash
m -R
```

或使用等价命令：

```bash
./build/build.sh ros2
```

如果只想单独编译本组件，推荐使用单包构建方式：

```bash
source build/envsetup.sh
lunch k3-com260-minimal

cd middleware/ros2/tools/visualization
mm
```

也可以在仓库根目录直接执行：

```bash
source build/envsetup.sh
lunch k3-com260-minimal

./build/build.sh package middleware/ros2/tools/visualization
```

构建产物默认输出到：

- `output/staging`：开发与调试使用的安装目录
- `output/rootfs`：部署使用的根文件系统目录

编译完成后，若需运行 ROS 2 节点，建议加载 SDK 提供的 ROS 2 运行环境：

```bash
source build/envsetup.sh
sros2_setup
```

补充说明：

- `m -R` / `./build/build.sh ros2` 会根据当前 `target/*.json` 配置编译已启用的 ROS 2 包
- `mm` 适合在单个组件目录下快速迭代开发
- 若当前目标配置未包含 `visualization`，则需要先检查并修改对应的 `target/*.json`


### 单独构建编译

进入工作区根目录后，建议先加载环境：

```bash
source /opt/ros/<ros2发行版>/setup.bash
```

在工作区根目录执行：

```bash
colcon build --packages-select visualization
```

编译完成后执行：

```bash
source install/setup.bash
```

### 运行示例

#### 1. 启动 WebSocket 图像流节点

```bash
ros2 launch visualization websocket_cpp.launch.py
```

如需指定图像话题和端口：

```bash
ros2 launch visualization websocket_cpp.launch.py image_topic:=/result_img port:=8080
```

启动后，可在浏览器访问设备 IP 与端口对应页面，例如：

```text
http://<设备IP>:8080
```

#### 2. 启动 RViz 可视化

例如启动导航场景：

```bash
ros2 launch visualization display_navigation.launch.py
```

其他场景可按需选择：

```bash
ros2 launch visualization display_slam.launch.py
ros2 launch visualization display_rgbd.launch.py
ros2 launch visualization display_rtab_3dlidar.launch.py
```

## 常见问题

### 1. 浏览器打不开页面怎么办？

建议依次检查：

- `websocket_cpp_node` 是否已正常启动
- 端口是否被占用
- 设备 IP 是否正确
- 主机防火墙是否放通对应端口
- 浏览器访问地址是否为 `http://<设备IP>:<port>`

### 2. 页面打开了，但没有图像怎么办？

建议检查：

- `image_topic` 参数是否与实际发布的压缩图像话题一致
- 上游节点是否正在发布 `sensor_msgs/msg/CompressedImage`
- 图像数据是否正常更新
- 浏览器与节点所在设备网络是否连通

### 3. RViz 启动失败或看不到预期内容怎么办？

建议检查：

- 对应 RViz 配置文件是否存在
- 相关话题、TF、地图或传感器数据是否正常发布
- launch 文件中引用的包名、资源目录是否与当前工作区实际内容一致
- 是否已经正确 `source install/setup.bash`

### 4. 编译失败怎么办？

建议检查：

- ROS 2 依赖是否完整安装
- OpenCV、Boost 等依赖是否已满足
- 当前工作区是否存在未编译通过的上游依赖包
- 是否使用了正确的编译环境和工具链


## 贡献方式

欢迎通过以下方式参与贡献：

- 提交 Issue 反馈问题与需求
- 提交 Pull Request 修复问题或补充功能
- 完善文档、示例与测试用例
- 补充不同机器人场景下的 RViz 配置与网页模板

提交代码前建议：

- 遵循仓库现有代码规范与目录结构
- 通过 C++ / Python lint 检查
- 补充必要的说明文档
- 确保新增功能不影响现有使用方式


## License

本组件源码文件头声明为 Apache-2.0，最终以本目录 `LICENSE` 文件为准。
