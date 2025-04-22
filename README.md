# CPUMonitorTweak

CPUMonitorTweak 是一个 iOS 越狱插件，用于监控设备上运行的进程的 CPU 使用率，并在检测到某些进程的 CPU 使用率过高时发送通知。在iPhone SE (2020) iOS13.4.1 成功运行
**本项目由 AI 生成。**
在 iPhone SE (2020) iOS13.4.1 上运行成功。

## 功能

- **实时监控**：后台持续监控所有进程的 CPU 使用率。
- **锁屏优化**：根据设备的锁屏状态调整监控频率，减少资源消耗。
- **高 CPU 使用率通知**：当某个进程的 CPU 使用率持续超过阈值时，发送通知提醒用户。

## 安装

1. 确保您的设备已越狱，并安装了 Theos 环境。
2. 克隆此项目到本地：
   ```bash
   git clone <repository-url>
   cd CPUMonitorTweak
   ```
3. 编译并安装：
   ```bash
   make package install
   ```
	或者仅生成deb，手动安装 (make package)
## 文件结构

- `Tweak.x`：插件的主要逻辑代码。
- `Makefile`：Theos 构建配置文件。
- `control`：Debian 包的控制文件。

## 配置

### Makefile 配置

- **目标设备架构**：
  默认支持 `arm64e` 架构。如果需要支持其他架构，可以修改 `Makefile` 中的 `ARCHS` 参数：
  ```makefile
  ARCHS = arm64
  ```

  如果需要添加其他框架，可以在 `Makefile` 中的 `mycpumonitor_FRAMEWORKS` 参数中添加。

### 代码配置

- **CPU 使用率阈值**：
  默认阈值为 80%（单核心）。您可以在 `monitorCPUUsage` 函数中修改以下代码：
  ```objectivec
  if (cpuUsage > 80.0) {
      // 修改阈值
  }
  ```

- **检测间隔**：
  根据设备的锁屏状态，检测间隔默认为：
  - 解锁状态：2 秒
  - 锁屏状态：6 秒

  您可以修改以下全局变量调整间隔：
  ```objectivec
  static const int UNLOCKED_CHECK_INTERVAL = 2;
  static const int LOCKED_CHECK_INTERVAL = 6;
  ```

## 使用说明

1. 安装插件后，插件会自动启动，无设置。
2. 插件会在后台监控所有进程的 CPU 使用率。
3. 当某个进程的 CPU 使用率持续超过阈值时，设备会收到通知，提示高 CPU 使用率的进程名称。

## 注意事项

- 本插件依赖私有框架 `SpringBoardServices`，仅适用于越狱设备。
- 插件可能会对设备性能产生一定影响，请根据需要调整检测间隔。A13 实测占用 CPU 非常低（单核心的3%以下）

## 许可

- 本项目仅供教育和个人使用。不适用于在 BigBoss 或 Havoc 等公共软件源上重新分发。
- 本项目遵循 MIT 许可证。详情请参阅 [LICENSE](LICENSE) 文件。
```