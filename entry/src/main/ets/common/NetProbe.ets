/**
 * =============================================================================
 * 网络探测工具（NetProbe.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 探测当前网络状态，回答两个问题：
 *   1. 有没有网？（isOnline）—— 没网时 Git 卡片直接显示离线提示，不去请求。
 *   2. 是不是「计费网络」？（isMetered）—— 蜂窝流量按字节计费，
 *      Git 卡片默认不在计费网络上自动拉取数据，避免偷跑用户流量。
 *
 * 【怎么判断是否计费】
 * 鸿蒙把网络按「承载类型」分类（WiFi、蜂窝、以太网…）。拿默认网络的
 * 能力信息（NetCapabilities），只要承载是 WiFi 或以太网，就视为不计费；
 * 其它情况（蜂窝、拿不到信息、查询失败）一律按计费处理。
 *
 * 【为什么失败时偏向「保守」】
 * isMetered 失败返回 true（当作计费）、isOnline 失败返回 false（当作没网）。
 * 原则：拿不准时按「不自动消耗流量」处理，宁可少刷新一次数据，
 * 也不能悄悄用掉用户的蜂窝流量。
 * =============================================================================
 */

import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

class ScreenSaverNetProbeService {
  /**
   * 当前默认网络是否计费（蜂窝流量）。
   * netId 为 0 表示「当前没有默认网络」，按计费/不可用处理。
   */
  async isMetered(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      if (netHandle.netId === 0) {
        return true;
      }
      const caps = await connection.getNetCapabilities(netHandle);
      for (const bearer of caps.bearerTypes) {
        // WiFi 或以太网 → 不计费，直接返回 false。
        if (bearer === connection.NetBearType.BEARER_WIFI || bearer === connection.NetBearType.BEARER_ETHERNET) {
          return false;
        }
      }
      // 蜂窝等其它承载 → 计费。
      return true;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`net probe failed: code=${error.code}`);
      return true; // 查询失败按计费处理（保守策略，避免偷跑流量）
    }
  }

  /** 当前是否有可用网络。 */
  async isOnline(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      return netHandle.netId !== 0;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`net online probe failed: code=${error.code}`);
      return false; // 查询失败按无网处理（Git 卡片会显示离线提示）
    }
  }
}

// 导出全局唯一实例（单例），全应用共享同一份探测服务。
export const screenSaverNetProbe: ScreenSaverNetProbeService = new ScreenSaverNetProbeService();
