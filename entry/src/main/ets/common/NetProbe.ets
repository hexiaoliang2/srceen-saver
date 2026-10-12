import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

class ScreenSaverNetProbeService {
  async isMetered(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      if (netHandle.netId === 0) {
        return true;
      }
      const caps = await connection.getNetCapabilities(netHandle);
      for (const bearer of caps.bearerTypes) {
        if (bearer === connection.NetBearType.BEARER_WIFI || bearer === connection.NetBearType.BEARER_ETHERNET) {
          return false;
        }
      }
      return true;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`net probe failed: code=${error.code}`);
      return true;
    }
  }

  async isOnline(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      return netHandle.netId !== 0;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`net online probe failed: code=${error.code}`);
      return false;
    }
  }
}

export const screenSaverNetProbe: ScreenSaverNetProbeService = new ScreenSaverNetProbeService();
