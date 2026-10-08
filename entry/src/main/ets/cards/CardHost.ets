import { ScreenSaverClockCard } from './ClockCardView';
import { ScreenSaverPhotoCard } from './PhotoCardView';
import { ScreenSaverCardInstance, ScreenSaverCardMode } from '../model/ConfigModels';

@ComponentV2
export struct ScreenSaverCardHost {
  @Param card: ScreenSaverCardInstance = new ScreenSaverCardInstance();
  @Param cardMode: ScreenSaverCardMode = 'play';
  @Param pageIndex: number = 0;
  @Param cardActive: boolean = true;

  build() {
    if (this.card.cardType === 'photo') {
      ScreenSaverPhotoCard({
        card: this.card,
        cardMode: this.cardMode,
        pageIndex: this.pageIndex,
        cardActive: this.cardActive
      })
    } else {
      ScreenSaverClockCard({
        card: this.card,
        cardMode: this.cardMode
      })
    }
  }
}
