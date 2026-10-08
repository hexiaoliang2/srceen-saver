import { hilog } from '@kit.PerformanceAnalysisKit';

const SCREEN_SAVER_LOG_DOMAIN: number = 0x0000;
const SCREEN_SAVER_LOG_TAG: string = 'ScreenSaver';

export class ScreenSaverLogger {
  static info(message: string): void {
    hilog.info(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s', message);
  }

  static errorWithCause(message: string, cause: Object): void {
    hilog.error(SCREEN_SAVER_LOG_DOMAIN, SCREEN_SAVER_LOG_TAG, '%{public}s: %{public}s', message,
      JSON.stringify(cause));
  }
}
