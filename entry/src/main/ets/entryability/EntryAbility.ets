import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { GlobalContext } from '../common/GlobalContext';
import { PreferencesUtil } from '../mijia/PreferencesUtil';
import { MiDebug } from '../mi/MiDebug';

const DOMAIN = 0x0200;
const TAG = 'MijiaControl';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    GlobalContext.initContext(this.context);
    MiDebug.init(this.context);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onNewWant');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    PreferencesUtil.init()
      .then(() => {
        windowStage.loadContent('pages/Index', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'Failed to load: %{public}s', JSON.stringify(err));
            return;
          }
          hilog.info(DOMAIN, TAG, 'Loaded: pages/Index');
        });
      })
      .catch(() => {
        hilog.error(DOMAIN, TAG, 'Initialization failed');
        windowStage.loadContent('pages/Index', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'Failed to load fallback: %{public}s', JSON.stringify(err));
          }
        });
      });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
