import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { GlobalContext } from '../common/GlobalContext';
import { formInfo } from '@kit.FormKit';
import { PreferencesUtil } from '../mijia/PreferencesUtil';
import { MiDebug } from '../mi/MiDebug';

const DOMAIN = 0x0200;
const TAG = 'WidgetEditAbility';

export default class WidgetEditAbility extends UIAbility {
  private formId: string = '';
  private currentWindowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.extractFormId(want);
    GlobalContext.initContext(this.context);
    MiDebug.init(this.context);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.extractFormId(want);
    if (this.currentWindowStage !== null) {
      AppStorage.setOrCreate('formId', this.formId);
      const storage: LocalStorage = new LocalStorage();
      storage.setOrCreate('formId', this.formId);
      PreferencesUtil.init().then(() => {
        this.currentWindowStage!.loadContent('pages/WidgetEditPage', storage, (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'Failed to reload: %{public}s', JSON.stringify(err));
          }
        });
      });
    }
  }

  private extractFormId(want: Want): void {
    let id: string | Object | undefined | null = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    if (id === undefined || id === null) {
      const params: Record<string, Object> = want.parameters ?? {} as Record<string, Object>;
      id = params['formId'];
    }
    if (id !== undefined && id !== null) {
      this.formId = String(id);
      hilog.info(DOMAIN, TAG, 'extractFormId formId=%{public}s', this.formId);
    } else {
      hilog.warn(DOMAIN, TAG, 'extractFormId: no formId found in want parameters');
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate formId=%{public}s', this.formId);
    if (this.currentWindowStage === null) {
      this.currentWindowStage = windowStage;
    }
    AppStorage.setOrCreate('formId', this.formId);
    const storage: LocalStorage = new LocalStorage();
    storage.setOrCreate('formId', this.formId);
    PreferencesUtil.init().then(() => {
      windowStage.loadContent('pages/WidgetEditPage', storage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'Loaded: pages/WidgetEditPage');
      });
    }).catch(() => {
      hilog.error(DOMAIN, TAG, 'PreferencesUtil init failed');
      windowStage.loadContent('pages/WidgetEditPage', storage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load fallback: %{public}s', JSON.stringify(err));
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
