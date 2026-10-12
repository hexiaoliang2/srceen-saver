import { i18n } from '@kit.LocalizationKit';
import { ScreenSaverLogger } from './Logger';
import { SCREEN_SAVER_WEEK_NAMES } from './ScreenSaverStyle';

const HEAVENLY_STEMS: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const EARTHLY_BRANCHES: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const LUNAR_MONTH_NAMES: string[] = ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
const LUNAR_DAY_NAMES: string[] = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
];

export interface ScreenSaverTimeParts {
  mainText: string;
  periodText: string;
}

export interface ScreenSaverLunarParts {
  lunarLine: string;
  solarLine: string;
}

export function screenSaverFormatTime(date: Date, use24Hour: boolean, showSeconds: boolean): ScreenSaverTimeParts {
  let hours = date.getHours();
  let period = '';
  if (!use24Hour) {
    period = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    if (hours === 0) {
      hours = 12;
    }
  }
  const minutes = date.getMinutes().toString().padStart(2, '0');
  let text = `${hours.toString().padStart(2, '0')}:${minutes}`;
  if (showSeconds) {
    text = `${text}:${date.getSeconds().toString().padStart(2, '0')}`;
  }
  return { mainText: text, periodText: period };
}

export function screenSaverFormatDate(date: Date, withWeekday: boolean): string {
  const base = `${date.getMonth() + 1}月${date.getDate()}日`;
  if (!withWeekday) {
    return base;
  }
  return `${base} 星期${SCREEN_SAVER_WEEK_NAMES[date.getDay()]}`;
}

export function screenSaverFormatLunarShort(date: Date): string {
  try {
    const calendar: i18n.Calendar = i18n.getCalendar('zh-Hans', 'chinese');
    calendar.setTime(date);
    const lunarMonth = calendar.get('month');
    const lunarDay = calendar.get('date');
    return `农历${screenSaverLunarMonthName(lunarMonth)}${screenSaverLunarDayName(lunarDay)}`;
  } catch (err) {
    const error = err as Error;
    ScreenSaverLogger.warn(`lunar short failed: ${error.message}`);
    return '';
  }
}

export function screenSaverFormatDateFull(date: Date): string {
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

export function screenSaverFormatWeekdayFull(date: Date): string {
  return `星期${SCREEN_SAVER_WEEK_NAMES[date.getDay()]}`;
}

export function screenSaverFormatLunar(date: Date): ScreenSaverLunarParts {
  const solarLine = `对应公历 ${date.getMonth() + 1}月${date.getDate()}日 · 星期${SCREEN_SAVER_WEEK_NAMES[date.getDay()]}`;
  try {
    const calendar: i18n.Calendar = i18n.getCalendar('zh-Hans', 'chinese');
    calendar.setTime(date);
    const cycledYear = calendar.get('year');
    const lunarMonth = calendar.get('month');
    const lunarDay = calendar.get('date');
    const stem = HEAVENLY_STEMS[(cycledYear - 1) % 10];
    const branch = EARTHLY_BRANCHES[(cycledYear - 1) % 12];
    const monthName = screenSaverLunarMonthName(lunarMonth);
    const dayName = screenSaverLunarDayName(lunarDay);
    return { lunarLine: `${stem}${branch}年 · ${monthName}${dayName}`, solarLine: solarLine };
  } catch (err) {
    const error = err as Error;
    ScreenSaverLogger.warn(`lunar calendar failed: ${error.message}`);
    return { lunarLine: '农历不可用', solarLine: solarLine };
  }
}

function screenSaverLunarMonthName(monthIndex: number): string {
  if (monthIndex >= 0 && monthIndex < LUNAR_MONTH_NAMES.length) {
    return LUNAR_MONTH_NAMES[monthIndex];
  }
  return `${monthIndex + 1}月`;
}

function screenSaverLunarDayName(day: number): string {
  if (day >= 1 && day <= LUNAR_DAY_NAMES.length) {
    return LUNAR_DAY_NAMES[day - 1];
  }
  return `${day}日`;
}

export function screenSaverRelativeTime(fromMs: number, nowMs: number): string {
  if (fromMs <= 0) {
    return '尚未更新';
  }
  const diffMs = nowMs - fromMs;
  if (diffMs < 0) {
    return '刚刚更新';
  }
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) {
    return '刚刚更新';
  }
  if (diffMin < 60) {
    return `${diffMin} 分钟前更新`;
  }
  const diffHour = Math.floor(diffMin / 60);
  if (diffHour < 24) {
    return `更新于 ${fromMsToClock(fromMs)}`;
  }
  const diffDay = Math.floor(diffHour / 24);
  return `${diffDay} 天前更新`;
}

function fromMsToClock(ms: number): string {
  const date = new Date(ms);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}
