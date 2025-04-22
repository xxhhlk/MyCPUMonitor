//#import <UIKit/UIKit.h>
//#import <libhooker/libhooker.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <string.h>
#include <sys/sysctl.h>
#include <objc/runtime.h>
#include <libproc.h>
#include <sys/proc_info.h>

/*// 定义滑动窗口大小
#define WINDOW_SIZE 5
// 定义每个进程的 CPU 使用率历史记录
typedef struct {
    float values[WINDOW_SIZE];
    int currentIndex;
    int filledCount;
} CPUHistory;

// 修改字典声明，使用 NSValue 来包装 void* 指针
NSMutableDictionary<NSNumber *, NSValue *> *cpuHistories = nil;
*/
// 添加全局变量
static BOOL isDeviceLocked = YES; // 默认锁定状态为 YES
static const int UNLOCKED_CHECK_INTERVAL = 2;    // 解锁状态下检查间隔（秒）
static const int LOCKED_CHECK_INTERVAL = 6;     // 锁定状态下检查间隔（秒）
// 添加全局变量
static NSMutableDictionary *prevCPUInfo = nil;
// 全局时间基转换因子
static mach_timebase_info_data_t timebase_info;

// 这个判断不准确，仅仅下拉出锁屏界面也会触发
/*@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end

*/
//这个能判断是否真正锁定了
@interface SBLockStateAggregator : NSObject
+ (instancetype)sharedInstance;
- (unsigned long long)lockState;
@end

// 函数声明
//float getSmoothedCPUUsage(pid_t pid);
void getProcessName(pid_t pid, char *processName, size_t size);
float getProcessCPUUsage(pid_t pid);
static void deviceDidLockStateChange(void);  // 修改锁屏状态检测函数声明

// 观察者代码
static void addLockStateObserver() {
    static BOOL isObserverAdded = NO;
    if (isObserverAdded) {
        return;
    }
    isObserverAdded = YES;

    // 监听锁屏状态变化
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                  NULL,
                                  (CFNotificationCallback)deviceDidLockStateChange,
                                  CFSTR("com.apple.springboard.lockstate"),
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);

    // 监听屏幕熄灭事件
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                  NULL,
                                  (CFNotificationCallback)deviceDidLockStateChange,
                                  CFSTR("com.apple.springboard.hasBlankedScreen"),
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);

    //NSLog(@"[CPUMonitor] Lock state and screen off observers added.");
}
// 修改锁屏状态检测代码
static void deviceDidLockStateChange() {
    // 最安全方式，无需访问私有变量
    SBLockStateAggregator* aggregator = [objc_getClass("SBLockStateAggregator") sharedInstance];
    unsigned long long lockState = [aggregator lockState];
    //NSLog(@"[CPUMonitor] lock state code：0x%llx", lockState);
    // 0 表示解锁，3 表示锁定
    // 判断锁定状态
    BOOL newLockState = (lockState == 3); // 3 表示设备锁定
    if (newLockState != isDeviceLocked) {
        isDeviceLocked = newLockState;
        //NSLog(@"[CPUMonitor] Device Lock State Changed: %@ (%llu)", isDeviceLocked ? @"Locked" : @"Unlocked", lockState);
    }
}

// 获取进程名称
void getProcessName(pid_t pid, char *processName, size_t size) {
    struct kinfo_proc procInfo;
    size_t procInfoSize = sizeof(procInfo);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};

    if (sysctl(mib, 4, &procInfo, &procInfoSize, NULL, 0) == 0 && procInfoSize > 0) {
        strncpy(processName, procInfo.kp_proc.p_comm, size);
    } else {
        strncpy(processName, "Unknown", size);
    }
}

// 使用 libnotifications 推送通知
void showNotification(NSString *title, NSString *message) {
    void *handle = dlopen("/usr/lib/libnotifications.dylib", RTLD_LAZY);
    if (handle != NULL) {
        Class CPNotification = objc_getClass("CPNotification");
        if (CPNotification) {
            SEL showAlertSelector = @selector(showAlertWithTitle:message:userInfo:badgeCount:soundName:delay:repeats:bundleId:uuid:silent:);
            if ([CPNotification respondsToSelector:showAlertSelector]) {
                NSString *uid = [[NSUUID UUID] UUIDString];
                NSDictionary *userInfo = @{};
                NSMethodSignature *signature = [CPNotification methodSignatureForSelector:showAlertSelector];
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                invocation.target = CPNotification;
                invocation.selector = showAlertSelector;

                // 设置参数
                [invocation setArgument:&title atIndex:2];
                [invocation setArgument:&message atIndex:3];
                [invocation setArgument:&userInfo atIndex:4];
                int badgeCount = 0;
                [invocation setArgument:&badgeCount atIndex:5];
                NSString *soundName = nil;
                [invocation setArgument:&soundName atIndex:6];
                double delay = 1.0;
                [invocation setArgument:&delay atIndex:7];
                BOOL repeats = NO;
                [invocation setArgument:&repeats atIndex:8];
                NSString *bundleId = @"ru.domo.cocoatop64";
                [invocation setArgument:&bundleId atIndex:9];
                [invocation setArgument:&uid atIndex:10];
                BOOL silent = NO;
                [invocation setArgument:&silent atIndex:11];

                // 调用方法
                [invocation invoke];
            }
        }
        dlclose(handle);
    }
}

// 平滑 CPU 使用率计算函数。之前获取 CPU 使用率的方法不对（获取的瞬时占用），现在已经不需要了
/*float getSmoothedCPUUsage(pid_t pid) {
    // 初始化 CPU 历史记录字典
    if (!cpuHistories) {
        cpuHistories = [NSMutableDictionary dictionary];
    }
    
    // 获取或创建进程的 CPU 历史记录
    NSNumber *pidKey = @(pid);
    CPUHistory *history = NULL;
    NSValue *value = cpuHistories[pidKey];
    
    if (value) {
        history = (CPUHistory *)[value pointerValue];
    } else {
        history = (CPUHistory *)malloc(sizeof(CPUHistory));
        memset(history, 0, sizeof(CPUHistory));
        cpuHistories[pidKey] = [NSValue valueWithPointer:history];
    }
    
    // 获取当前 CPU 使用率
    float currentUsage = getProcessCPUUsage(pid);
    
    // 更新历史记录
    history->values[history->currentIndex] = currentUsage;
    history->currentIndex = (history->currentIndex + 1) % WINDOW_SIZE;
    if (history->filledCount < WINDOW_SIZE) {
        history->filledCount++;
    }
    
    // 计算加权移动平均值
    float sum = 0.0;
    float weightSum = 0.0;
    int count = history->filledCount;
    
    // 使用指数衰减权重
    for (int i = 0; i < count; i++) {
        // 计算索引，从最新的值开始
        int index = (history->currentIndex - 1 - i + WINDOW_SIZE) % WINDOW_SIZE;
        // 权重随时间指数衰减
        float weight = exp(-0.3f * i); // 可以调整 -0.5 这个衰减因子
        sum += history->values[index] * weight;
        weightSum += weight;
    }
    
    return weightSum > 0 ? sum / weightSum : 0.0;
}*/


// 修改 getProcessCPUUsage 函数
float getProcessCPUUsage(pid_t pid) {
    static NSMutableDictionary *prevCPUInfo;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prevCPUInfo = [NSMutableDictionary dictionary];
        mach_timebase_info(&timebase_info);
    });
    struct proc_taskinfo taskInfo;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo)) <= 0) {
        return 0.0;
    }
    NSNumber *pidKey = @(pid);
    NSDictionary *previous = prevCPUInfo[pidKey];
    
    // 获取当前时间（滴答数）
    const uint64_t currentTicks = mach_absolute_time();
    // 总CPU时间（滴答数）
    const uint64_t totalTicks = taskInfo.pti_total_user + taskInfo.pti_total_system;
    
    if (!previous) {
        prevCPUInfo[pidKey] = @{
            @"totalTicks": @(totalTicks),
            @"timestamp": @(currentTicks)
        };
        return 0.0;
    }
    // 获取前次数据
    const uint64_t lastTotalTicks = [previous[@"totalTicks"] unsignedLongLongValue];
    const uint64_t lastTimestamp = [previous[@"timestamp"] unsignedLongLongValue];
    
    // 计算增量
    const uint64_t ticksDiff = totalTicks - lastTotalTicks;
    const uint64_t timeDiff = ticksDiff * timebase_info.numer / timebase_info.denom; // 转换为纳秒
    const uint64_t timeInterval = (currentTicks - lastTimestamp) * timebase_info.numer / timebase_info.denom;
    
    // 更新存储数据
    prevCPUInfo[pidKey] = @{
        @"totalTicks": @(totalTicks),
        @"timestamp": @(currentTicks)
    };
    if (timeInterval == 0) return 0.0;
    // 转换为秒
    const double timeDiffSec = (double)timeDiff / 1e9;
    const double intervalSec = (double)timeInterval / 1e9;
    
    // 单核等效使用率计算
    const double singleCoreUsage = (timeDiffSec / intervalSec) * 100.0;
    
    return MAX(singleCoreUsage, 0.0);
}

// 获取所有进程的 CPU 使用率
NSMutableDictionary<NSNumber *, NSNumber *> *overThresholdDurations = nil;

void monitorCPUUsage() {
    if (!overThresholdDurations) {
        overThresholdDurations = [NSMutableDictionary dictionary];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (true) {
            int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
            size_t size;
            sysctl(mib, 4, NULL, &size, NULL, 0);

            struct kinfo_proc *processes = malloc(size);
            sysctl(mib, 4, processes, &size, NULL, 0);

            int processCount = (int)(size / sizeof(struct kinfo_proc));
            for (int i = 0; i < processCount; i++) {
                pid_t pid = processes[i].kp_proc.p_pid;
                char processName[256];
                getProcessName(pid, processName, sizeof(processName));

                float cpuUsage = getProcessCPUUsage(pid); // 使用平滑后的 CPU 使用率
                //NSLog(@"[CPUMonitor] Process: %s, PID: %d, Smoothed CPU Usage: %.2f%%", processName, pid, cpuUsage);
                if (cpuUsage > 80.0) {
                    NSNumber *pidKey = @(pid);
                    NSNumber *duration = overThresholdDurations[pidKey] ?: @(0);
                    int newDuration = duration.intValue + 1;
                    overThresholdDurations[pidKey] = @(newDuration);

                    if (newDuration >= 14) {
                        NSString *title = @"CPU 使用率通知";
                        NSString *message = [NSString stringWithFormat:@"进程 %s 占用 CPU 较高", processName];
                        showNotification(title, message);
                        overThresholdDurations[pidKey] = @(0); // 重置计时器
                    }
                } else {
                    overThresholdDurations[@(pid)] = @(0); // 重置计时器
                }
            }

            free(processes);
            // 根据锁屏状态调整检测间隔
            if (isDeviceLocked) {
                sleep(LOCKED_CHECK_INTERVAL);
            } else {
                sleep(UNLOCKED_CHECK_INTERVAL);
            }
        }
    });
}

// 主屏幕加载后推送测试通知
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // 添加锁屏状态观察者
    addLockStateObserver();
    // 启动 CPU 监控
    monitorCPUUsage();
}
%end