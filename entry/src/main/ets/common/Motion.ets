import { screenSaverAppModel } from '../model/AppModel';

export const SCREEN_SAVER_MOTION_PAGE_TRANSITION_MS: number = 300;
export const SCREEN_SAVER_MOTION_ENTER_MS: number = 300;
export const SCREEN_SAVER_MOTION_EXIT_MS: number = 250;
export const SCREEN_SAVER_MOTION_EDIT_ENTER_MS: number = 250;
export const SCREEN_SAVER_MOTION_CAPSULE_MS: number = 200;
export const SCREEN_SAVER_MOTION_SHEET_MS: number = 300;
export const SCREEN_SAVER_MOTION_SNAP_MS: number = 150;
export const SCREEN_SAVER_MOTION_BOUNCE_MS: number = 200;
export const SCREEN_SAVER_MOTION_PHOTO_FADE_MS: number = 250;
export const SCREEN_SAVER_MOTION_PREVIEW_MS: number = 150;
export const SCREEN_SAVER_MOTION_TOAST_MS: number = 200;
export const SCREEN_SAVER_MOTION_GIT_SPIN_MS: number = 600;
export const SCREEN_SAVER_MOTION_AMBIENT_MS: number = 800;
export const SCREEN_SAVER_REDUCED_MOTION_MAX_MS: number = 100;

export function screenSaverMotionOff(): boolean {
  return screenSaverAppModel.layout.settings.motionDisabled;
}

export function screenSaverMotionDuration(baseMs: number): number {
  if (!screenSaverMotionOff()) {
    return baseMs;
  }
  if (baseMs <= 0) {
    return 0;
  }
  return Math.min(baseMs, SCREEN_SAVER_REDUCED_MOTION_MAX_MS);
}

export function screenSaverFadeDuration(baseMs: number): number {
  if (!screenSaverMotionOff()) {
    return baseMs;
  }
  return 0;
}

export function screenSaverSnapDuration(): number {
  if (screenSaverMotionOff()) {
    return 0;
  }
  return SCREEN_SAVER_MOTION_SNAP_MS;
}

export function screenSaverBounceDuration(): number {
  if (screenSaverMotionOff()) {
    return 0;
  }
  return SCREEN_SAVER_MOTION_BOUNCE_MS;
}
