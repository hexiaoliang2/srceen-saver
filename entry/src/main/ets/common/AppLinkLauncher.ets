/**
 * =============================================================================
 * 应用间跳转（AppLinkLauncher.ets）
 * =============================================================================
 *
 * 把「打开入口卡目标」收口成 screenSaverOpenEntry，三种目标类型：
 *   · url：沿用 openLink(link, { appLinkingOnly: false })；
 *   · thirdparty：只能打开预设清单内的 scheme（先 canOpenLink 再 openLink）；
 *   · system：显式 Want（bundleName + abilityName）拉起；失败时若有备用链接
 *     再尝试 openLink。
 *
 * 供三条点击路径共用：
 *   1. 屏保展示态：单击「应用入口」卡片（ScreensaverPage 统一分发）；
 *   2. 编辑态：设置面板；
 *   3. 设置面板里的「测试打开」。
 *
 * 失败一律返回可展示的原因文案，绝不静默失败。
 * =============================================================================
 */

import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';
import { screenSaverPresetAppById } from '../model/EntryPresets';
import { ScreensaverEntryConfig } from '../model/ConfigModels';

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

/** 按入口配置的目标类型发起跳转。 */
export async function screenSaverOpenEntry(context: common.UIAbilityContext,
  entry: ScreensaverEntryConfig): Promise<ScreenSaverLinkResult> {
  if (entry.targetType === 'thirdparty') {
    return screenSaverOpenThirdParty(context, entry);
  }
  if (entry.targetType === 'system') {
    return screenSaverOpenSystem(context, entry);
  }
  return screenSaverOpenLink(context, entry.link);
}

/** 取第三方目标 scheme：配置优先，缺失时按 presetId 从静态清单补齐。 */
function screenSaverEntryScheme(entry: ScreensaverEntryConfig): string {
  const stored = entry.scheme.trim();
  if (stored.length > 0) {
    return stored;
  }
  const preset = screenSaverPresetAppById(entry.presetId);
  return preset === undefined ? '' : preset.scheme;
}

/** 第三方应用：只允许清单内 scheme；先 canOpenLink 再 openLink。 */
async function screenSaverOpenThirdParty(context: common.UIAbilityContext,
  entry: ScreensaverEntryConfig): Promise<ScreenSaverLinkResult> {
  const scheme = screenSaverEntryScheme(entry);
  if (scheme.length === 0) {
    const empty: ScreenSaverLinkResult = { ok: false, reason: '未选择目标应用：请在设置里重新选择' };
    return empty;
  }
  let available = false;
  try {
    available = bundleManager.canOpenLink(scheme);
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`canOpenLink failed: scheme=${scheme} code=${error.code}`);
    available = false;
  }
  if (!available) {
    ScreenSaverLogger.warn(`entry target unavailable: scheme=${scheme}`);
    const missing: ScreenSaverLinkResult = { ok: false, reason: '目标应用未安装或不可用：请在设置里重新选择' };
    return missing;
  }
  try {
    await context.openLink(scheme, { appLinkingOnly: false });
    ScreenSaverLogger.info(`entry third-party opened: scheme=${scheme}`);
    const ok: ScreenSaverLinkResult = { ok: true, reason: '' };
    return ok;
  } catch (openError) {
    const openBusinessError = openError as BusinessError;
    ScreenSaverLogger.warn(
      `entry third-party openLink failed: scheme=${scheme} code=${openBusinessError.code}`);
    // 部分机型/应用只响应隐式 Want（action=viewData + uri），openLink 失败后再试一次。
    const want: Want = { action: 'ohos.want.action.viewData', uri: scheme };
    try {
      await context.startAbility(want);
      ScreenSaverLogger.info(`entry third-party opened by want: scheme=${scheme}`);
      const ok: ScreenSaverLinkResult = { ok: true, reason: '' };
      return ok;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`entry third-party failed: scheme=${scheme} code=${error.code}`);
      const failed: ScreenSaverLinkResult = { ok: false, reason: '目标应用拉起失败：请在设置里重新选择' };
      return failed;
    }
  }
}

/** 系统应用：显式 Want；失败时若有备用链接再尝试一次 openLink。 */
async function screenSaverOpenSystem(context: common.UIAbilityContext,
  entry: ScreensaverEntryConfig): Promise<ScreenSaverLinkResult> {
  const preset = screenSaverPresetAppById(entry.presetId);
  const bundleName = entry.bundleName.trim().length > 0 ? entry.bundleName.trim() :
    (preset === undefined ? '' : preset.bundleName);
  const abilityName = entry.abilityName.trim().length > 0 ? entry.abilityName.trim() :
    (preset === undefined ? '' : preset.abilityName);
  if (bundleName.length === 0 || abilityName.length === 0) {
    const empty: ScreenSaverLinkResult = { ok: false, reason: '未选择目标系统应用：请在设置里重新选择' };
    return empty;
  }
  const want: Want = { bundleName: bundleName, abilityName: abilityName };
  try {
    await context.startAbility(want);
    ScreenSaverLogger.info(`entry system app opened: ${bundleName}/${abilityName}`);
    const ok: ScreenSaverLinkResult = { ok: true, reason: '' };
    return ok;
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`entry system app failed: ${bundleName}/${abilityName} code=${error.code}`);
    const fallback = entry.link.trim();
    if (fallback.length > 0) {
      ScreenSaverLogger.info(`entry system fallback link: ${fallback}`);
      return screenSaverOpenLink(context, fallback);
    }
    const failed: ScreenSaverLinkResult = { ok: false, reason: '无法打开该系统应用：可能未安装或版本不支持' };
    return failed;
  }
}
