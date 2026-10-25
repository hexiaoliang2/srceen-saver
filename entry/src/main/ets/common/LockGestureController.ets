/**
 * 遮盖手势控制器（本轮新增）
 *
 * 目标：只在「屏保页可见 + 开关开启 + 展示态」时订阅传感器，用边沿触发
 * 在卡片锁屏与固定主题锁屏之间切换。
 *
 * 传感器优先级：
 *   1. 接近光（PROXIMITY，distance=0 表示贴近）；
 *   2. 设备没有接近光时回退环境光（AMBIENT_LIGHT），用相对基线判定：
 *      当前照度 < 基线 * 0.35 视为遮盖，禁止写死绝对照度。
 *
 * 触发语义（边沿）：
 *   - 未遮盖 → 遮盖，且连续采样持续 ≥300ms 才触发一次；
 *   - 遮住不放手只触发一次，必须经历一次「未遮盖」才会重新上膛；
 *   - 快速划过（<200ms，采样上只有 0~1 个点）不会满足持续时长；
 *   - 每次切换后 1.5s 冷却；横滑主题期间不响应。
 *
 * 本文件不申请任何权限：@ohos.sensor 的 PROXIMITY / AMBIENT_LIGHT
 * 订阅在 SDK d.ts 中没有 @permission 标注（已核实 API 20 的
 * @ohos.sensor.d.ts），因此不需要在 module.json5 新增权限。
 */

import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

/** 采样间隔 200ms（200,000,000ns）；落在规范要求的 200~500ms 区间。 */
export const SCREEN_SAVER_LOCK_SAMPLE_INTERVAL_NS: number = 200000000;
/** 连续遮盖持续时长：≥300ms（两次采样 + 一个完整间隔）。 */
export const SCREEN_SAVER_LOCK_COVER_HOLD_MS: number = 300;
/** 切换冷却：1.5s。 */
export const SCREEN_SAVER_LOCK_COOLDOWN_MS: number = 1500;
/** 环境光相对基线阈值：低于基线的 35% 视为遮盖。 */
export const SCREEN_SAVER_LOCK_LIGHT_RATIO: number = 0.35;
/** 环境光基线样本数：5 × 200ms = 1s。 */
export const SCREEN_SAVER_LOCK_LIGHT_BASELINE_SAMPLES: number = 5;
/**
 * 环境光最低可用基线（lux）与最小绝对跌落（lux）。
 * 暗室/模拟器常报 0 lux：若只按比例判定，0 < 1*0.35 会误触发；
 * 因此必须同时满足「基线足够亮」和「绝对跌落≥2lux」，否则不判定为遮盖。
 */
export const SCREEN_SAVER_LOCK_LIGHT_MIN_BASELINE: number = 3;
export const SCREEN_SAVER_LOCK_LIGHT_MIN_DROP: number = 2;
/** 接近光「贴近」距离上限（cm）；SDK 约定 0 = 贴近。 */
export const SCREEN_SAVER_LOCK_PROXIMITY_NEAR: number = 0.5;

export type ScreensaverLockSensorKind = 'proximity' | 'ambient' | 'none';

@ObservedV2
export class ScreensaverLockGestureController {
  /** 设备是否具备可用传感器（接近光或环境光）。 */
  @Trace supported: boolean = false;
  /** 实际使用的传感器种类。 */
  @Trace sensorKind: ScreensaverLockSensorKind = 'none';
  /** 当前是否已订阅（只在屏保展示态为 true）。 */
  @Trace running: boolean = false;
  /** 不可用/订阅失败的具体原因，设置页直接展示。 */
  @Trace errorText: string = '';

  private probed: boolean = false;
  private trigger: (() => void) | undefined = undefined;
  private proximityCallback: ((data: sensor.ProximityResponse) => void) | undefined = undefined;
  private lightCallback: ((data: sensor.LightResponse) => void) | undefined = undefined;

  /** 边沿状态机。 */
  private covered: boolean = false;
  private coverStartMs: number = 0;
  private coverSamples: number = 0;
  private armed: boolean = true;
  private lastSwitchMs: number = 0;
  private swipeActive: boolean = false;
  /** 接近光事件驱动的 300ms 确认定时器（仅接近光路径使用）。 */
  private proximityConfirmTimer: number = -1;

  /** 环境光相对基线。 */
  private lightBaseline: number = -1;
  private lightBaselineSum: number = 0;
  private lightBaselineSamples: number = 0;

  /** 探测设备能力；设置页与屏保页都可调用，结果缓存。 */
  probe(): void {
    let hasProximity = false;
    let hasAmbient = false;
    let listText = '';
    try {
      const list: sensor.Sensor[] = sensor.getSensorListSync();
      for (const item of list) {
        listText += `${item.sensorName}:${item.sensorId},`;
        if (item.sensorId === sensor.SensorId.PROXIMITY) {
          hasProximity = true;
        } else if (item.sensorId === sensor.SensorId.AMBIENT_LIGHT) {
          hasAmbient = true;
        }
      }
    } catch (error) {
      const err = error as BusinessError;
      this.errorText = `传感器列表读取失败（${err.code}）`;
      ScreenSaverLogger.warn(`lock gesture probe failed: ${err.code} ${err.message}`);
    }
    if (hasProximity) {
      this.sensorKind = 'proximity';
      this.supported = true;
      this.errorText = '';
    } else if (hasAmbient) {
      this.sensorKind = 'ambient';
      this.supported = true;
      this.errorText = '';
    } else {
      this.sensorKind = 'none';
      this.supported = false;
      if (this.errorText.length === 0) {
        this.errorText = '当前设备不支持接近光/环境光传感器';
      }
    }
    this.probed = true;
    ScreenSaverLogger.info(`lock gesture probe: supported=${this.supported} kind=${this.sensorKind} ` +
      `sensors=${listText.length > 0 ? listText : 'none'}`);
  }

  /** 开始订阅；失败时返回 false 并写入 errorText。 */
  start(onTrigger: () => void): boolean {
    if (!this.probed) {
      this.probe();
    }
    this.trigger = onTrigger;
    if (!this.supported) {
      if (this.errorText.length === 0) {
        this.errorText = '当前设备不支持接近光/环境光传感器';
      }
      return false;
    }
    if (this.running) {
      return true;
    }
    this.resetCoverage();
    try {
      if (this.sensorKind === 'proximity') {
        const callback = (data: sensor.ProximityResponse): void => {
          this.onProximity(data);
        };
        this.proximityCallback = callback;
        sensor.on(sensor.SensorId.PROXIMITY, callback, {
          interval: SCREEN_SAVER_LOCK_SAMPLE_INTERVAL_NS
        });
      } else {
        const callback = (data: sensor.LightResponse): void => {
          this.onLight(data);
        };
        this.lightCallback = callback;
        sensor.on(sensor.SensorId.AMBIENT_LIGHT, callback, {
          interval: SCREEN_SAVER_LOCK_SAMPLE_INTERVAL_NS
        });
      }
      this.running = true;
      this.errorText = '';
      ScreenSaverLogger.info(`lock gesture subscribe: kind=${this.sensorKind} intervalMs=200`);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      this.running = false;
      this.errorText = this.subscribeErrorText(err.code);
      this.trigger = undefined;
      ScreenSaverLogger.warn(`lock gesture subscribe failed: ${err.code} ${err.message}`);
      return false;
    }
  }

  /** 解除订阅；离开屏保/切后台/进设置/关开关都必须调用。 */
  stop(reason: string): void {
    this.trigger = undefined;
    if (this.proximityCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.PROXIMITY, this.proximityCallback);
      } catch (error) {
        const err = error as BusinessError;
        ScreenSaverLogger.warn(`lock gesture off proximity failed: ${err.code}`);
      }
      this.proximityCallback = undefined;
    }
    if (this.lightCallback !== undefined) {
      try {
        sensor.off(sensor.SensorId.AMBIENT_LIGHT, this.lightCallback);
      } catch (error) {
        const err = error as BusinessError;
        ScreenSaverLogger.warn(`lock gesture off ambient failed: ${err.code}`);
      }
      this.lightCallback = undefined;
    }
    if (this.running) {
      ScreenSaverLogger.info(`lock gesture unsubscribe: ${reason}`);
    }
    this.running = false;
    this.resetCoverage();
    this.lightBaseline = -1;
    this.lightBaselineSum = 0;
    this.lightBaselineSamples = 0;
  }

  /** 主题横滑开始/结束：期间丢弃遮盖触发，且本次遮盖不再上膛。 */
  setSwipeActive(active: boolean): void {
    this.swipeActive = active;
    if (active) {
      this.clearProximityConfirm();
      this.armed = false;
      this.coverStartMs = 0;
      this.coverSamples = 0;
    }
  }

  /** 诊断用：当前是否已订阅。 */
  isRunning(): boolean {
    return this.running;
  }

  private subscribeErrorText(code: number): string {
    if (code === 201) {
      return '订阅传感器失败：权限被拒绝';
    }
    if (code === 14500101) {
      return '订阅传感器失败：服务异常（可能被占用）';
    }
    return `订阅传感器失败（${code}）`;
  }

  private resetCoverage(): void {
    this.clearProximityConfirm();
    this.covered = false;
    this.coverStartMs = 0;
    this.coverSamples = 0;
    this.armed = true;
    this.swipeActive = false;
  }

  private onProximity(data: sensor.ProximityResponse): void {
    const nowMs = Date.now();
    const covered = data.distance <= SCREEN_SAVER_LOCK_PROXIMITY_NEAR;
    if (!covered) {
      this.clearProximityConfirm();
      this.processCoverage(false, nowMs);
      return;
    }
    if (this.covered) {
      this.coverSamples++;
      return;
    }
    // 接近光是事件驱动（只在状态变化时回调），不能等待第二次采样；
    // 首个“贴近”事件后启动 300ms 确认定时器，期间收到“远离”即取消。
    this.covered = true;
    this.coverStartMs = nowMs;
    this.coverSamples = 1;
    this.armed = (nowMs - this.lastSwitchMs) >= SCREEN_SAVER_LOCK_COOLDOWN_MS;
    if (!this.armed || this.swipeActive) {
      return;
    }
    this.scheduleProximityConfirm(SCREEN_SAVER_LOCK_COVER_HOLD_MS);
  }

  /** 安排接近光确认；定时器到期时仍处于遮盖且未滑动才触发。 */
  private scheduleProximityConfirm(delayMs: number): void {
    this.clearProximityConfirm();
    this.proximityConfirmTimer = setTimeout((): void => {
      this.proximityConfirmTimer = -1;
      if (!this.covered || !this.armed || this.swipeActive) {
        return;
      }
      const heldMs = Date.now() - this.coverStartMs;
      if (heldMs < SCREEN_SAVER_LOCK_COVER_HOLD_MS) {
        this.scheduleProximityConfirm(SCREEN_SAVER_LOCK_COVER_HOLD_MS - heldMs);
        return;
      }
      this.fireTrigger(Date.now());
    }, delayMs);
  }

  private clearProximityConfirm(): void {
    if (this.proximityConfirmTimer >= 0) {
      clearTimeout(this.proximityConfirmTimer);
      this.proximityConfirmTimer = -1;
    }
  }

  private onLight(data: sensor.LightResponse): void {
    const intensity = data.intensity;
    if (this.lightBaseline < 0) {
      this.lightBaselineSum += intensity;
      this.lightBaselineSamples++;
      if (this.lightBaselineSamples >= SCREEN_SAVER_LOCK_LIGHT_BASELINE_SAMPLES) {
        this.lightBaseline = Math.max(this.lightBaselineSum / this.lightBaselineSamples, 1);
        ScreenSaverLogger.info(`lock gesture ambient baseline=${this.lightBaseline.toFixed(1)} lux`);
      }
      return;
    }
    if (this.lightBaseline < SCREEN_SAVER_LOCK_LIGHT_MIN_BASELINE) {
      // 暗室/模拟器：基线太低时比例判定不可靠，只允许基线向上适应，不触发。
      this.lightBaseline = Math.max(this.lightBaseline, intensity);
      this.processCoverage(false, Date.now());
      return;
    }
    if (!this.covered) {
      // 未遮盖时缓慢跟踪环境变化，避免白天/夜晚切换导致基线漂移。
      this.lightBaseline = this.lightBaseline * 0.8 + intensity * 0.2;
    }
    const covered = intensity < this.lightBaseline * SCREEN_SAVER_LOCK_LIGHT_RATIO &&
      (this.lightBaseline - intensity) >= SCREEN_SAVER_LOCK_LIGHT_MIN_DROP;
    this.processCoverage(covered, Date.now());
  }

  /**
   * 上升沿 + 持续判定 + 冷却。
   * 注意：触发后 armed=false；必须收到一次未遮盖采样才会重新上膛，
   * 因此「遮住不放手」不会反复切换。
   */
  private processCoverage(covered: boolean, nowMs: number): void {
    if (!covered) {
      this.covered = false;
      this.coverStartMs = 0;
      this.coverSamples = 0;
      this.armed = true;
      return;
    }
    if (!this.covered) {
      this.covered = true;
      this.coverStartMs = nowMs;
      this.coverSamples = 1;
      // 冷却期内的新遮盖直接失效，必须抬手后再来一次。
      this.armed = (nowMs - this.lastSwitchMs) >= SCREEN_SAVER_LOCK_COOLDOWN_MS;
      return;
    }
    this.coverSamples++;
    if (!this.armed || this.swipeActive) {
      return;
    }
    const heldMs = nowMs - this.coverStartMs;
    if (this.coverSamples < 2 || heldMs < SCREEN_SAVER_LOCK_COVER_HOLD_MS) {
      return;
    }
    this.fireTrigger(nowMs);
  }

  /** 触发一次模式切换；调用方必须已通过持续/上膛/滑动互斥检查。 */
  private fireTrigger(nowMs: number): void {
    this.armed = false;
    this.lastSwitchMs = nowMs;
    ScreenSaverLogger.info(`lock gesture triggered: kind=${this.sensorKind} ` +
      `heldMs=${nowMs - this.coverStartMs} samples=${this.coverSamples}`);
    const callback = this.trigger;
    if (callback !== undefined) {
      callback();
    }
  }
}

/** 全局唯一实例。 */
export const screenSaverLockGestureController: ScreensaverLockGestureController =
  new ScreensaverLockGestureController();
