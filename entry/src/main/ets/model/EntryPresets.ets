/**
 * =============================================================================
 * 应用入口预设清单（EntryPresets.ets）
 * =============================================================================
 *
 * 只收录产品需求里明确的 11 个目标：
 *   · 第三方应用 6 个：用官方 Deep Linking scheme 拉起；
 *   · 系统应用 5 个：用显式 Want（bundleName + abilityName）拉起。
 *
 * 约束：
 *   1. 设置页不允许用户手输 scheme / 包名，目标只能从本清单选择；
 *   2. 第三方可用性只用 bundleManager.canOpenLink(清单内 scheme) 判断，
 *      **不读取、不枚举已安装应用列表**，也不上传任何数据；
 *   3. 系统应用按产品确认「不做预检测」：清单始终展示，拉起失败时由卡片
 *      进入失效态并提示重选。
 * =============================================================================
 */

import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { ScreensaverEntryTargetType } from './ConfigModels';

/** 预设应用条目（静态数据，不含任何用户数据）。 */
export interface ScreensaverPresetApp {
  id: string;
  kind: ScreensaverEntryTargetType;
  name: string;
  subtitle: string;
  /** 第三方应用 Deep Linking scheme；系统应用为空串。 */
  scheme: string;
  /** 系统应用显式 Want 参数；第三方应用为空串。 */
  bundleName: string;
  abilityName: string;
}

const THIRD_PARTY_PRESETS: ScreensaverPresetApp[] = [
  {
    id: 'bilibili',
    kind: 'thirdparty',
    name: '哔哩哔哩',
    subtitle: '第三方应用',
    scheme: 'bilibili://root',
    // 显式唤起主 Ability：不导航到固定页面，由 B 站恢复上次停留页面。
    bundleName: 'yylx.danmaku.bili',
    abilityName: 'EntryAbility'
  },
  {
    id: 'jd',
    kind: 'thirdparty',
    name: '京东',
    subtitle: '第三方应用',
    scheme: 'openApp.jdMobile://',
    bundleName: '',
    abilityName: ''
  },
  {
    id: 'taobao',
    kind: 'thirdparty',
    name: '淘宝',
    subtitle: '第三方应用',
    scheme: 'taobao://',
    bundleName: '',
    abilityName: ''
  },
  {
    id: 'weixin',
    kind: 'thirdparty',
    name: '微信',
    subtitle: '第三方应用',
    scheme: 'weixin://',
    bundleName: '',
    abilityName: ''
  },
  {
    id: 'alipay',
    kind: 'thirdparty',
    name: '支付宝',
    subtitle: '第三方应用',
    scheme: 'alipays://',
    bundleName: '',
    abilityName: ''
  },
  {
    id: 'hexin',
    kind: 'thirdparty',
    name: '同花顺',
    subtitle: '第三方应用',
    scheme: 'amihexin://',
    bundleName: '',
    abilityName: ''
  }
];

const SYSTEM_PRESETS: ScreensaverPresetApp[] = [
  {
    id: 'calendar',
    kind: 'system',
    name: '日历',
    subtitle: '系统应用',
    scheme: '',
    bundleName: 'com.huawei.hmos.calendar',
    abilityName: 'MainAbility'
  },
  {
    id: 'photos',
    kind: 'system',
    name: '图库',
    subtitle: '系统应用',
    scheme: '',
    bundleName: 'com.huawei.hmos.photos',
    abilityName: 'com.huawei.hmos.photos.MainAbility'
  },
  {
    id: 'clock',
    kind: 'system',
    name: '时钟',
    subtitle: '系统应用',
    scheme: '',
    bundleName: 'com.huawei.hmos.clock',
    abilityName: 'com.huawei.hmos.clock.phone'
  },
  {
    id: 'weather',
    kind: 'system',
    name: '天气',
    subtitle: '系统应用',
    scheme: '',
    bundleName: 'com.huawei.hmsapp.totemweather',
    abilityName: 'com.huawei.hmsapp.totemweather.MainAbility'
  },
  {
    id: 'notepad',
    kind: 'system',
    name: '备忘录',
    subtitle: '系统应用',
    scheme: '',
    bundleName: 'com.huawei.hmos.notepad',
    abilityName: 'MainAbility'
  }
];

/** 按目标类型取预设清单（url 返回空数组）。 */
export function screenSaverPresetApps(kind: ScreensaverEntryTargetType): ScreensaverPresetApp[] {
  if (kind === 'thirdparty') {
    return THIRD_PARTY_PRESETS;
  }
  if (kind === 'system') {
    return SYSTEM_PRESETS;
  }
  return [];
}

/** 按 id 取预设（找不到返回 undefined；磁盘数据不可信，必须判空）。 */
export function screenSaverPresetAppById(id: string): ScreensaverPresetApp | undefined {
  if (id.length === 0) {
    return undefined;
  }
  for (const app of THIRD_PARTY_PRESETS) {
    if (app.id === id) {
      return app;
    }
  }
  for (const app of SYSTEM_PRESETS) {
    if (app.id === id) {
      return app;
    }
  }
  return undefined;
}

/**
 * 预设是否可选：
 *   · 系统应用：产品确认不做预检测 → 始终可选；
 *   · 第三方应用：canOpenLink(清单内 scheme)，需要在 module.json5 声明 querySchemes。
 * canOpenLink 只回答「系统里是否有组件能处理这个 scheme」，不枚举应用列表。
 */
export function screenSaverPresetAppSelectable(app: ScreensaverPresetApp): boolean {
  if (app.kind === 'system') {
    return true;
  }
  if (app.scheme.length === 0) {
    return false;
  }
  try {
    return bundleManager.canOpenLink(app.scheme);
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`canOpenLink failed: scheme=${app.scheme} code=${error.code}`);
    return false;
  }
}
