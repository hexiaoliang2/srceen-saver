import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

export function screenSaverApplyFontScale(context: common.UIAbilityContext, followSystem: boolean): void {
  try {
    const appContext = context.getApplicationContext();
    if (followSystem) {
      const scale = context.config.fontSizeScale;
      const value = (scale !== undefined && scale > 0) ? scale : 1;
      appContext.setFontSizeScale(value);
      ScreenSaverLogger.info(`font scale apply follow system: ${value}`);
    } else {
      appContext.setFontSizeScale(1);
      ScreenSaverLogger.info('font scale apply locked at 1');
    }
  } catch (err) {
    const error = err as Error;
    ScreenSaverLogger.warn(`font scale apply failed: ${error.message}`);
  }
}
