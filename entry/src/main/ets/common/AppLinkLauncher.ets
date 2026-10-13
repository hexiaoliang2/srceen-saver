/**
 * =============================================================================
 * 应用间跳转（AppLinkLauncher.ets）——变更项 2
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把「按用户填写的链接打开目标应用/页面」这一件事收口成一个函数，
 * 供三条点击路径共用，避免各处各写一遍 openLink：
 *   1. 屏保展示态：单击「应用入口」卡片（由 ScreensaverPage 统一分发）；
 *   2. 编辑态：卡片内的「打开」按钮；
 *   3. 设置面板里的「测试打开」。
 *
 * 【为什么用 openLink】
 * 官方文档（应用间跳转 / 拉起指定应用）：`UIAbilityContext.openLink(link, options)`
 * 是 Deep Linking / App Linking 的标准入口；`appLinkingOnly: false` 表示允许系统
 * 按可用方式打开（找不到能处理的应用时抛错，由这里统一转成降级文案）。
 * 本项目**不预置**任何第三方 scheme/链接，因此也不调用 canOpenLink 预判
 * （canOpenLink 需要在 module.json5 里声明 querySchemes，见 docs/card-feasibility.md）。
 *
 * 【失败一律降级】
 * 未安装目标应用、链接不可用、scheme 未声明等情况统一返回可展示的原因文案，
 * 绝不静默失败。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

/** 跳转结果：ok=true 表示已成功发起跳转；否则 reason 是给用户看的降级文案。 */
export interface ScreenSaverLinkResult {
  ok: boolean;
  reason: string;
}

/**
 * 发起跳转。
 * @param context 宿主 UIAbilityContext（用 getUIContext().getHostContext() 获取）
 * @param link    用户填写的链接（http/https 或目标应用声明支持的链接）
 */
export async function screenSaverOpenLink(context: common.UIAbilityContext,
  link: string): Promise<ScreenSaverLinkResult> {
  const target = link.trim();
  if (target.length === 0) {
    const empty: ScreenSaverLinkResult = { ok: false, reason: '未配置链接：请先在卡片设置里填写' };
    return empty;
  }
  try {
    await context.openLink(target, { appLinkingOnly: false });
    ScreenSaverLogger.info(`entry link opened: ${target}`);
    const ok: ScreenSaverLinkResult = { ok: true, reason: '' };
    return ok;
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`entry link failed: code=${error.code}, link=${target}`);
    const failed: ScreenSaverLinkResult = { ok: false, reason: '无法打开：目标应用未安装或链接不可用' };
    return failed;
  }
}
