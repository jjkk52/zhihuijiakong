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
  @State loadingDids: Record<string, boolean> = {} as Record<string, boolean>;  @State hasToken: boolean = false;
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
    const currentState = this.deviceStates[key];
    const expectedNewState = !(currentState ?? false);
    hilog.info(DOMAIN, TAG, 'onDeviceClick did=%{public}s siid=%{public}d piid=%{public}d', ud.did, ud.siid, ud.piid);

    try {
      const success = await this.deviceService.toggleSwitchByDid(ud.did, ud.siid, ud.piid);
      if (success) {
        this.deviceService.pollSwitchState(ud.did, ud.siid, ud.piid, expectedNewState, (state: boolean | undefined) => {
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
        this.showToast('\u63A7\u5236\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u8BBE\u5907\u5728\u7EBF\u72B6\u6001');
      }
    } catch (error) {
      this.loadingDids[key] = false;
      const msg = String(error);
      if (msg.includes('\u8BA4\u8BC1\u5931\u6548') || msg.includes('auth')) {
        this.showToast('\u767B\u5F55\u5DF2\u8FC7\u671F\uFF0C\u8BF7\u91CD\u65B0\u767B\u5F55');
      } else {
        this.showToast('\u63A7\u5236\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u8BBE\u5907\u5728\u7EBF\u72B6\u6001');
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

  private showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'showToast error: %{public}s', String(e));
    }
  }

  private getDeviceStatusText(ud: UserDevice): string {
    const key = this.deviceKey(ud);
    if (this.loadingDids[key]) {
      return '\u5207\u6362\u4E2D...';
    }
    if (this.isRefreshing) {
      return '\u540C\u6B65\u4E2D...';
    }
    const state = this.deviceStates[key];
    if (state === undefined) {
      if (!this.deviceService.isDeviceOnline(ud.did)) {
        return '\u5DF2\u79BB\u7EBF';
      }
      return '\u72B6\u6001\u672A\u77E5';
    }
    return state ? '\u5DF2\u5F00\u542F' : '\u5DF2\u5173\u95ED';
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

  private getCardBgColor(ud: UserDevice): string {
    const key = this.deviceKey(ud);
    if (this.loadingDids[key]) {
      return '#FFF3E0';
    }
    if (this.isDeviceOffline(ud)) {
      return '#FFEBEE';
    }
    return this.isDeviceOn(ud) ? '#C8E6C9' : '#EEEEEE';
  }

  private getIconColor(ud: UserDevice): string {
    if (this.isDeviceOffline(ud)) {
      return '#E57373';
    }
    return this.isDeviceOn(ud) ? '#2E7D32' : '#757575';
  }

  private getDisplayName(ud: UserDevice): string {
    return UserDevice.getDisplayName(ud);
  }

  build() {
    Column() {
      Row() {
        Text('\u7C73\u5BB6\u63A7\u5236')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Button(this.showDetail ? '\u8BE6\u60C5' : '\u8BE6\u60C5')
          .height(28)
          .type(ButtonType.Capsule)
          .backgroundColor(this.showDetail ? '#33FFFFFF' : Color.Transparent)
          .fontColor(this.showDetail ? Color.White : '#99FFFFFF')
          .fontSize(12)
          .margin({ right: 6 })
          .onClick(() => {
            this.showDetail = !this.showDetail;
          })
        Button({ type: ButtonType.Circle }) {
          Text('\u21BB')
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
          Text('\u2699')
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
      .backgroundColor('#1976D2')

      if (!this.hasToken) {
        Column() {
          Text('\u672A\u767B\u5F55')
            .fontSize(18)
            .fontColor('#757575')
            .margin({ bottom: 12 })
          Text('\u70B9\u51FB\u767B\u5F55\u7C73\u5BB6\u8D26\u53F7')
            .fontSize(14)
            .fontColor('#1976D2')
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
          Text('\u5C1A\u672A\u6DFB\u52A0\u8BBE\u5907')
            .fontSize(18)
            .fontColor('#757575')
            .margin({ bottom: 12 })
          Text('\u524D\u5F80\u8BBE\u7F6E\u6DFB\u52A0\u8BBE\u5907')
            .fontSize(14)
            .fontColor('#1976D2')
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
                Text(getIconText(ud.icon))
                  .fontSize(40)
                  .fontColor(this.getIconColor(ud))
                  .margin({ top: 12, bottom: 6 })

                Text(this.getDisplayName(ud))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('80%')
                  .textAlign(TextAlign.Center)

                if (this.showDetail && UserDevice.getSourceInfo(ud).length > 0) {
                  Text(UserDevice.getSourceInfo(ud))
                    .fontSize(12)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('85%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 2 })
                }

                Text(this.getDeviceStatusText(ud))
                  .fontSize(13)
                  .fontColor(this.isDeviceOffline(ud) ? '#E57373' : (this.isDeviceOn(ud) ? '#4CAF50' : '#9E9E9E'))
                  .margin({ top: 4 })

                if (this.showDetail && UserDevice.getHomeRoomText(ud).length > 0) {
                  Text(UserDevice.getHomeRoomText(ud))
                    .fontSize(11)
                    .fontColor('#AAAAAA')
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
    .backgroundColor('#FAFAFA')
  }
}
