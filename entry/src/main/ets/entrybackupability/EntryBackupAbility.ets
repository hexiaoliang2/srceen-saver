/**
 * =============================================================================
 * 备份扩展 Ability（EntryBackupAbility.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 系统备份/恢复框架的扩展点（BackupExtensionAbility）。
 * 用户换机或恢复出厂后，系统可以通过它备份/恢复应用沙箱数据
 * （包括屏保布局偏好存储）。
 *
 * 【当前实现】
 * 只打日志占位：框架默认会处理应用沙箱内的文件，无需额外逻辑。
 * 保留此文件是因为 module.json5 里注册了备份扩展，
 * 缺了它备份配置会指向不存在的类。
 * =============================================================================
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;

export default class EntryBackupAbility extends BackupExtensionAbility {
  /** 系统发起备份时回调。 */
  async onBackup() {
    hilog.info(DOMAIN, 'testTag', 'onBackup ok');
    await Promise.resolve();
  }

  /** 系统发起恢复时回调（bundleVersion 携带备份来源的版本信息）。 */
  async onRestore(bundleVersion: BundleVersion) {
    hilog.info(DOMAIN, 'testTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
