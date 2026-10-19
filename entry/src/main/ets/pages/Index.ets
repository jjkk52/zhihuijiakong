import { MiDeviceService } from '../mijia/MiDeviceService';
import { MiAuthService } from '../mijia/MiAuthService';
import { UserDevice, getIconText } from '../mi/types';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0200;
const TAG = 'IndexPage';
const REFRESH_INTERVAL_MS = 5000;

@Entry
@Component
struct Index {
  @State userDevices: UserDevice[] = [];
  @State devicesVersion: number = 0;
  @State deviceStates: Record<string, boolean | undefined> = {} as Record<string, boolean | undefined>;
  @State loadingDids: Record<string, boolean> = {} as Record<string, boolean>;
  @State hasToken: boolean = false;
  @State isRefreshing: boolean = false;
  @State showDetail: boolean = false;
  private deviceService: MiDeviceService = MiDeviceService.getInstance();
  private authService: MiAuthService = MiAuthService.getInstance();
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.initPage();
  }

  onPageShow(): void {
    this.initPage();
  }

  aboutToDisappear(): void {
    this.stopAutoRefresh();
  }

  async initPage(): Promise<void> {
    try {
      this.hasToken = await this.authService.checkLoginStatus();
      this.userDevices = await this.deviceService.getUserDevices();
      this.userDevices = await this.deviceService.enrichHomeRooms(this.userDevices);
      this.devicesVersion++;
      if (this.hasToken && this.userDevices.length > 0) {
        await this.refreshStates(true);
        this.startAutoRefresh();
      } else {
        this.stopAutoRefresh();
      }
      hilog.info(DOMAIN, TAG, 'initPage devices=%{public}d hasToken=%{public}s', this.userDevices.length, String(this.hasToken));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'initPage error: %{public}s', String(error));
      this.isRefreshing = false;
    }
  }

  async refreshStates(showRefreshing: boolean = false): Promise<void> {
    if (this.userDevices.length === 0) {
      return;
    }
    if (showRefreshing) {
      this.isRefreshing = true;
    }
    try {
      this.deviceStates = await this.deviceService.refreshDeviceStates(this.userDevices);
      hilog.info(DOMAIN, TAG, 'refreshStates done');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'refreshStates error: %{public}s', String(error));
    }
    if (showRefreshing) {
      this.isRefreshing = false;
    }
  }

  startAutoRefresh(): void {
    this.stopAutoRefresh();
    this.refreshTimer = setInterval(() => {
      this.refreshStates();
    }, REFRESH_INTERVAL_MS);
  }

  stopAutoRefresh(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private deviceKey(ud: UserDevice): string {
    return UserDevice.getSlotKey(ud);
  }

  async onDeviceClick(ud: UserDevice): Promise<void> {
    if (!this.hasToken) {
      this.goSettings();
      return;
    }
    const key = this.deviceKey(ud);
    if (this.loadingDids[key]) {
      return;
    }
    this.loadingDids[key] = true;
    hilog.info(DOMAIN, TAG, 'onDeviceClick did=%{public}s siid=%{public}d piid=%{public}d', ud.did, ud.siid, ud.piid);

    try {
      const newState = await this.deviceService.toggleSwitchByDid(ud.did, ud.siid, ud.piid);
      if (newState !== undefined) {
        this.deviceService.pollSwitchState(ud.did, ud.siid, ud.piid, newState, (state: boolean | undefined) => {
          this.loadingDids[key] = false;
          const newStates: Record<string, boolean | undefined> = {} as Record<string, boolean | undefined>;
          const keys = Object.keys(this.deviceStates);
          for (let i = 0; i < keys.length; i++) {
            newStates[keys[i]] = this.deviceStates[keys[i]];
          }
          newStates[key] = state;
          this.deviceStates = newStates;
        });
      } else {
        this.loadingDids[key] = false;
        this.showToast($r('app.string.toast_control_failed'));
      }
    } catch (error) {
      this.loadingDids[key] = false;
      const msg = String(error);
      if (msg.includes('认证失效') || msg.includes('auth')) {
        this.showToast($r('app.string.toast_login_expired'));
      } else {
        this.showToast($r('app.string.toast_control_failed'));
      }
    }
  }

  private goSettings(): void {
    try {
      router.pushUrl({ url: 'pages/SettingsPage' });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'goSettings error: %{public}s', String(e));
    }
  }

  private showToast(msg: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'showToast error: %{public}s', String(e));
    }
  }

  private getDeviceStatusText(ud: UserDevice): ResourceStr {
    const key = this.deviceKey(ud);
    if (this.loadingDids[key]) {
      return $r('app.string.status_switching');
    }
    if (this.isRefreshing) {
      return $r('app.string.status_syncing');
    }
    const state = this.deviceStates[key];
    if (state === undefined) {
      if (!this.deviceService.isDeviceOnline(ud.did)) {
        return $r('app.string.status_offline');
      }
      return $r('app.string.status_unknown');
    }
    return state ? $r('app.string.status_on') : $r('app.string.status_off');
  }

  private isDeviceOn(ud: UserDevice): boolean {
    return this.deviceStates[this.deviceKey(ud)] ?? false;
  }

  private isDeviceOffline(ud: UserDevice): boolean {
    const state = this.deviceStates[this.deviceKey(ud)];
    if (state === undefined) {
      return !this.deviceService.isDeviceOnline(ud.did);
    }
    return false;
  }

  private getCardBgColor(ud: UserDevice): ResourceColor {
    const key = this.deviceKey(ud);
    if (this.loadingDids[key]) {
      return $r('app.color.switching_bg');
    }
    if (this.isDeviceOffline(ud)) {
      return $r('app.color.card_offline_bg');
    }
    return this.isDeviceOn(ud) ? $r('app.color.card_on_bg') : $r('app.color.card_off_bg');
  }

  private getIconColor(ud: UserDevice): ResourceColor {
    if (this.isDeviceOffline(ud)) {
      return $r('app.color.offline_red');
    }
    return this.isDeviceOn(ud) ? $r('app.color.icon_on') : $r('app.color.icon_off');
  }

  private getDisplayName(ud: UserDevice): string {
    return UserDevice.getDisplayName(ud);
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.index_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Button(this.showDetail ? $r('app.string.btn_simple') : $r('app.string.btn_detail'))
          .height(28)
          .type(ButtonType.Capsule)
          .backgroundColor(this.showDetail ? $r('app.color.header_btn_bg') : Color.Transparent)
          .fontColor(this.showDetail ? Color.White : $r('app.color.header_btn_text_dim'))
          .fontSize(12)
          .margin({ right: 6 })
          .onClick(() => {
            this.showDetail = !this.showDetail;
          })
        Button({ type: ButtonType.Circle }) {
          Text('↻')
            .fontSize(22)
            .fontColor(Color.White)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.refreshStates(true);
        })
        Button({ type: ButtonType.Circle }) {
          Text('⚙')
            .fontSize(22)
            .fontColor(Color.White)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.goSettings();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 10 })
      .backgroundColor($r('app.color.brand_primary'))

      if (!this.hasToken) {
        Column() {
          Text($r('app.string.not_logged_in'))
            .fontSize(18)
            .fontColor($r('app.color.icon_off'))
            .margin({ bottom: 12 })
          Text($r('app.string.login_prompt'))
            .fontSize(14)
            .fontColor($r('app.color.brand_primary'))
            .onClick(() => {
              this.goSettings();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 40 })
      } else if (this.userDevices.length === 0) {
        Column() {
          Text($r('app.string.no_device_added'))
            .fontSize(18)
            .fontColor($r('app.color.icon_off'))
            .margin({ bottom: 12 })
          Text($r('app.string.go_settings_add'))
            .fontSize(14)
            .fontColor($r('app.color.brand_primary'))
            .onClick(() => {
              this.goSettings();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 40 })
      } else {
        Scroll() {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
            ForEach(this.userDevices, (ud: UserDevice) => {
              Column() {
                Column() {
                  Text(getIconText(ud.icon))
                    .fontSize(40)
                    .fontColor(this.getIconColor(ud))
                }
                .height(60)
                .justifyContent(FlexAlign.Center)
                .margin({ top: 12, bottom: 6 })

                Text(this.getDisplayName(ud))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('80%')
                  .textAlign(TextAlign.Center)

                if (this.showDetail && UserDevice.getSourceInfo(ud).length > 0) {
                  Text(UserDevice.getSourceInfo(ud))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('85%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 2 })
                }

                Text(this.getDeviceStatusText(ud))
                  .fontSize(13)
                  .fontColor(this.isDeviceOffline(ud) ? $r('app.color.offline_red') :
                    (this.isDeviceOn(ud) ? $r('app.color.status_on') : $r('app.color.status_off')))
                  .margin({ top: 4 })

                if (this.showDetail && UserDevice.getHomeRoomText(ud).length > 0) {
                  Text(UserDevice.getHomeRoomText(ud))
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('85%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 2, bottom: 10 })
                } else if (this.showDetail) {
                  Blank()
                    .height(10)
                }
              }
              .width('46%')
              .height(this.showDetail ? 172 : 150)
              .margin({ left: '2.5%', top: 12 })
              .borderRadius(16)
              .backgroundColor(this.getCardBgColor(ud))
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.onDeviceClick(ud);
              })
            }, (ud: UserDevice) => `${this.deviceKey(ud)}_${this.devicesVersion}`)
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
