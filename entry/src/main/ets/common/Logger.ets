/**
 * =============================================================================
 * 日志工具（Logger.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 全应用统一的日志出口。把鸿蒙系统自带的 hilog（HiLog 日志系统）薄薄包一层，
 * 业务代码只需要调用 ScreenSaverLogger.info('xxx')，不用每次都写
 * domain、tag、'%{public}s' 这些重复的样板参数。
 *
 * 【为什么要单独包一层，而不直接调 hilog】
 * 1. 统一标识：所有日志共用同一个 TAG（ScreenSaver），在 DevEco Studio 的
 *    Log 窗口按 tag 过滤，就能只看本应用的日志，排查问题很快。
 * 2. 便于替换：以后如果想接文件日志 / 上报后台，只改这一个文件即可，
 *    全应用的调用点一行都不用动。这叫「收口」——公共能力只暴露一个入口。
 *
 * 【小白知识点】
 * - hilog 是鸿蒙官方的高性能日志方案，比 console.log 快，真机/模拟器上都能看。
 * - '%{public}s' 是格式占位符：{public} 表示该字段在系统日志中「明文可见」。
 *   不加 {public} 时日志可能被脱敏成 <private>，开发时反而看不到内容。
 *   注意：正式发布的产品里不要用 {public} 打印敏感信息（token、隐私数据）。
 * =============================================================================
 */

// hilog 来自 PerformanceAnalysisKit（性能分析工具包）
import { hilog } from '@kit.PerformanceAnalysisKit';

// 日志域（domain）：0x0000~0xFFFF 之间的整数，用于给日志分类。
// 这里用 0x0000 即可，同一个应用内不需要再细分。
const SCREEN_SAVER_LOG_DOMAIN: number = 0x0000;
// 日志标签：日志窗口里按这个字符串过滤，只看本应用日志。
const SCREEN_SAVER_LOG_TAG: string = 'ScreenSaver';

/**
 * 静态工具类：不需要 new，直接 ScreenSaverLogger.info(...) 调用。
 * 方法全部是 static，因为日志工具没有状态，没必要持有实例。
 */
export class ScreenSaverLogger {
  /** 普通信息日志：记录流程走到了哪里（如「进入编辑模式」）。 */
  static info(message: string): void {
    hilog.info(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  /** 警告日志：不影响运行、但值得注意的异常分支（如 toast 失败）。 */
  static warn(message: string): void {
    hilog.warn(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  /** 错误日志：功能失败（如持久化写入失败）。 */
  static error(message: string): void {
    hilog.error(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  /**
   * 带附加原因的错误日志。
   * 为什么单独加这个方法：错误对象（如系统抛出的 BusinessError）转成 JSON
   * 字符串后信息最全（code + message 都在里面），直接拼进日志方便定位。
   */
  static errorWithCause(message: string, cause: Object): void {
    hilog.error(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s: %{public}s', message,
      JSON.stringify(cause));
  }
}
