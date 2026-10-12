import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

class ScreenSaverVibrationService {
  private failed: boolean = false;

  longPressFeedback(): void {
    if (this.failed) {
      return;
    }
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 30
      }, {
        id: 0,
        usage: 'touch'
      }).catch((err: BusinessError): void => {
        this.failed = true;
        ScreenSaverLogger.warn(`vibration failed: code=${err.code}`);
      });
    } catch (err) {
      const error = err as BusinessError;
      this.failed = true;
      ScreenSaverLogger.warn(`vibration failed: code=${error.code}`);
    }
  }
}

export const screenSaverVibration: ScreenSaverVibrationService = new ScreenSaverVibrationService();
