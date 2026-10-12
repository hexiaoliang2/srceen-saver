import { ScreensaverClockCard } from './ClockCardView';
import { ScreensaverPhotoCard } from './PhotoCardView';
import { ScreensaverVideoCard } from './VideoCardView';
import { ScreensaverGitCard } from './GitCardView';
import { ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverCardHost {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Event onRequestConfig: () => void = (): void => {};

  build() {
    if (this.card.cardType === 'photo') {
      ScreensaverPhotoCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive
      })
    } else if (this.card.cardType === 'video') {
      ScreensaverVideoCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        onRequestConfig: (): void => {
          this.onRequestConfig();
        }
      })
    } else if (this.card.cardType === 'git') {
      ScreensaverGitCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        onRequestConfig: (): void => {
          this.onRequestConfig();
        }
      })
    } else {
      ScreensaverClockCard({
        card: this.card,
        cardMode: this.cardMode
      })
    }
  }
}
