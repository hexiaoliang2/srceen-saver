import { ScreenSaverCardMeta, ScreenSaverCardType } from '../model/ConfigModels';

export const SCREEN_SAVER_CARD_CATALOG: ScreenSaverCardMeta[] = [
  {
    cardType: 'clock',
    displayName: '时钟',
    description: '数字时钟，可显示日期',
    defaultColSpan: 1,
    defaultRowSpan: 1
  },
  {
    cardType: 'photo',
    displayName: '相册',
    description: '照片轮播，可设间隔、顺序',
    defaultColSpan: 2,
    defaultRowSpan: 2
  }
];

export function screenSaverFindCardMeta(cardType: ScreenSaverCardType): ScreenSaverCardMeta | undefined {
  return SCREEN_SAVER_CARD_CATALOG.find((meta: ScreenSaverCardMeta): boolean => meta.cardType === cardType);
}
