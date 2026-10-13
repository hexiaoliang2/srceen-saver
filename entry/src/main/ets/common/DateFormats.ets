/**
 * =============================================================================
 * 日期/时间格式化工具（DateFormats.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 集中放所有「把 Date 对象变成屏幕上那串文字」的函数：
 * 时钟卡片的时分秒、日期、星期、农历、Git 卡片的「x 分钟前更新」等。
 *
 * 【为什么要集中】
 * 格式化规则容易重复散落（时钟卡片和 Git 卡片都可能要显示时间），
 * 集中后改一处即可，且保证全应用的时间显示风格一致。
 *
 * 【农历怎么来的】
 * 鸿蒙系统自带多语言日历能力（i18n.Calendar，'chinese' 即农历），
 * 不需要自己实现天干地支换算，直接问系统要农历的「月、日」数值，
 * 再映射成「正月初一」这样的中文说法。
 * =============================================================================
 */

import { i18n } from '@kit.LocalizationKit';
import { ScreenSaverLogger } from './Logger';
// 星期几的中文名（getDay() 返回 0~6，0 是周日）放在 ScreenSaverStyle 里统一维护。
import { SCREEN_SAVER_WEEK_NAMES } from './ScreenSaverStyle';

// 天干：用于农历年的「甲子」纪年（10 个循环）。
const HEAVENLY_STEMS: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
// 地支：12 个循环。
const EARTHLY_BRANCHES: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
// 农历月份的中文名（系统返回的月份是 0~11 的下标）。
const LUNAR_MONTH_NAMES: string[] = ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
// 农历「日」的中文名（初一~三十，系统返回 1~30）。
const LUNAR_DAY_NAMES: string[] = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
];

/** 时钟文本：主内容（如 09:41）和上下午标记（如 AM/PM）。 */
export interface ScreenSaverTimeParts {
  mainText: string;
  periodText: string;
}

/** 农历详情：农历一行 + 对应公历一行。 */
export interface ScreenSaverLunarParts {
  lunarLine: string;
  solarLine: string;
}

/**
 * 格式化时间。
 * - use24Hour：24 小时制则不带 AM/PM；12 小时制把 0 点折算成 12（12:xx AM）。
 * - showSeconds：是否带秒（开了「显示秒」后由秒级心跳驱动刷新）。
 * - padStart(2, '0')：把 9 补成 09，保证时间始终两位数对齐。
 */
export function screenSaverFormatTime(date: Date, use24Hour: boolean, showSeconds: boolean): ScreenSaverTimeParts {
  let hours = date.getHours();
  let period = '';
  if (!use24Hour) {
    period = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    if (hours === 0) {
      hours = 12; // 12 小时制没有「0 点」，0 点叫 12 AM
    }
  }
  const minutes = date.getMinutes().toString().padStart(2, '0');
  let text = `${hours.toString().padStart(2, '0')}:${minutes}`;
  if (showSeconds) {
    text = `${text}:${date.getSeconds().toString().padStart(2, '0')}`;
  }
  return { mainText: text, periodText: period };
}

/** 格式化日期：如「10月13日」，可选带星期。getMonth() 从 0 开始所以要 +1。 */
export function screenSaverFormatDate(date: Date, withWeekday: boolean): string {
  const base = `${date.getMonth() + 1}月${date.getDate()}日`;
  if (!withWeekday) {
    return base;
  }
  return `${base} 星期${SCREEN_SAVER_WEEK_NAMES[date.getDay()]}`;
}

/**
 * 农历短格式：如「农历正月初一」。
 * 出错时返回空字符串而不是抛异常——农历只是辅助信息，绝不能让它把时钟卡片搞崩。
 */
export function screenSaverFormatLunarShort(date: Date): string {
  try {
    // 'chinese' 表示农历日历；系统会自动完成公历→农历的换算。
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

/** 完整日期：如「2026年10月13日」。 */
export function screenSaverFormatDateFull(date: Date): string {
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

/** 星期全称：如「星期二」。 */
export function screenSaverFormatWeekdayFull(date: Date): string {
  return `星期${SCREEN_SAVER_WEEK_NAMES[date.getDay()]}`;
}

/**
 * 农历完整格式：农历行（甲子年 · 正月初一）+ 公历对照行。
 * 天干地支：系统返回的农历年是从甲子年开始数的序号（60 年一轮回），
 * 天干按序号对 10 取模、地支对 12 取模，即可拼出「丙午」这样的年份。
 * 出错时降级成「农历不可用」，公历行照常显示——保证信息不缺失。
 */
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

/** 农历月份下标 → 中文名；越界时退回数字写法，保证永不崩溃。 */
function screenSaverLunarMonthName(monthIndex: number): string {
  if (monthIndex >= 0 && monthIndex < LUNAR_MONTH_NAMES.length) {
    return LUNAR_MONTH_NAMES[monthIndex];
  }
  return `${monthIndex + 1}月`;
}

/** 农历日（1~30）→ 中文名；越界时退回数字写法。 */
function screenSaverLunarDayName(day: number): string {
  if (day >= 1 && day <= LUNAR_DAY_NAMES.length) {
    return LUNAR_DAY_NAMES[day - 1];
  }
  return `${day}日`;
}

/**
 * 相对时间文案（Git 卡片用）：如「刚刚更新」「5 分钟前更新」「3 天前更新」。
 * 规则从近到远依次判断：
 *   <1 分钟 → 刚刚；<1 小时 → x 分钟前；<24 小时 → 显示时刻（09:41）；
 *   ≥24 小时 → x 天前。
 * fromMs<=0 表示从未成功更新过（如没网时的初始状态）。
 */
export function screenSaverRelativeTime(fromMs: number, nowMs: number): string {
  if (fromMs <= 0) {
    return '尚未更新';
  }
  const diffMs = nowMs - fromMs;
  // 系统时间被改回过去（diff<0）时按「刚刚」处理，避免出现「-3 分钟前」。
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
    // 一天内不显示「x 小时前」（数字会很大不好读），改为直接显示更新时刻。
    return `更新于 ${fromMsToClock(fromMs)}`;
  }
  const diffDay = Math.floor(diffHour / 24);
  return `${diffDay} 天前更新`;
}

/** 毫秒时间戳 → HH:mm（补零），仅供上面的相对时间使用。 */
function fromMsToClock(ms: number): string {
  const date = new Date(ms);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}
