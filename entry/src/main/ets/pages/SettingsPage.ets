import { router, KeyboardAvoidMode } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { MiAuthService } from '../mijia/MiAuthService';
import { MiDeviceService } from '../mijia/MiDeviceService';
import { MiDevice, MiToken, UserDevice, DeviceIcon, getIconText, isMultiSlotProfile, getDeviceProfile, getDeviceHomeRoomText } from '../mi/types';
import { PreferencesUtil } from '../mijia/PreferencesUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0200;
const TAG = 'SettingsPage';

const LOGIN_PHONE_KEY = 'login_phone';

const ICON_OPTIONS: number[] = [
  DeviceIcon.Switch,
  DeviceIcon.SpotLight,
  DeviceIcon.LockLight,
  DeviceIcon.Bulb,
  DeviceIcon.Fan,
  DeviceIcon.AirConditioner,
  DeviceIcon.Humidifier,
  DeviceIcon.Camera,
  DeviceIcon.Plug,
  DeviceIcon.Curtain,
  DeviceIcon.Sensor,
  DeviceIcon.Elevator,
  DeviceIcon.Door,
  DeviceIcon.Tv,
  DeviceIcon.Boiler,
  DeviceIcon.Router,
  DeviceIcon.Alarm,
  DeviceIcon.Generic,
];

@CustomDialog
struct AddAliasDialog {
  controller: CustomDialogController;
  deviceName: string = '';
  homeRoom: string = '';
  alias: string = '';
  onConfirm: (alias: string) => void = (_alias: string) => {};

  build() {
    Column() {
      Text('\u6DFB\u52A0\u8BBE\u5907')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })
      Text('\u8BBE\u5907: ' + this.deviceName)
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 4 })
      if (this.homeRoom.length > 0) {
        Text('\u4F4D\u7F6E: ' + this.homeRoom)
          .fontSize(13)
          .fontColor('#999999')
          .margin({ bottom: 12 })
      } else {
        Blank()
          .height(12)
      }
      TextInput({ placeholder: '\u8F93\u5165\u5907\u6CE8\u540D\uFF08\u53EF\u7559\u7A7A\uFF09', text: this.alias })
        .width('100%')
        .height(50)
        .onChange((value: string) => {
          this.alias = value;
        })
        .margin({ bottom: 20 })
      Row() {
        Button('\u53D6\u6D88')
          .width('45%')
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .onClick(() => {
            this.controller.close();
          })
        Button('\u786E\u8BA4')
          .width('45%')
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor('#1976D2')
          .fontColor(Color.White)
          .onClick(() => {
            this.onConfirm(this.alias);
            this.controller.close();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

@Entry
@Component
struct SettingsPage {
  @State phone: string = '';
  @State password: string = '';
  @State otp: string = '';
  @State needOtp: boolean = false;
  @State isLoggingIn: boolean = false;
  @State loginError: string = '';

  @State allDevices: MiDevice[] = [];
  @State isLoadingDevices: boolean = false;
  @State showDeviceList: boolean = false;
  @State searchText: string = '';

  @State isLoggedIn: boolean = false;
  @State loginPhone: string = '';

  @State userDevices: UserDevice[] = [];
  @State devicesVersion: number = 0;
  @State otpCountDown: number = 0;

  @State editingSlotKey: string = '';
  @State editingAlias: string = '';
  @State editingIcon: number = DeviceIcon.Generic;
  @State appVersion: string = '';
  private editingAliasController: TextInputController = new TextInputController();

  private authService: MiAuthService = MiAuthService.getInstance();
  private deviceService: MiDeviceService = MiDeviceService.getInstance();
  private countDownTimer: number = -1;
  private pendingAddDevice: MiDevice | null = null;
  private addDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.appVersion = this.loadAppVersion();
    this.initPage();
  }

  private loadAppVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      hilog.info(DOMAIN, TAG, 'appVersion=%{public}s', info.versionName);
      return info.versionName;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadAppVersion error: %{public}s', String(error));
      return '';
    }
  }

  async initPage(): Promise<void> {
    try {
      this.isLoggedIn = await this.authService.checkLoginStatus();
      if (this.isLoggedIn) {
        this.loginPhone = await PreferencesUtil.getStr(LOGIN_PHONE_KEY, '');
        this.userDevices = await this.deviceService.getUserDevices();
        this.userDevices = await this.deviceService.enrichHomeRooms(this.userDevices);
        this.devicesVersion++;
        this.preloadDevices();
      }
      hilog.info(DOMAIN, TAG, 'initPage isLoggedIn=%{public}s', String(this.isLoggedIn));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'initPage error: %{public}s', String(error));
    }
  }

  preloadDevices(): void {
    if (this.deviceService.isDeviceListLoaded()) {
      return;
    }
    this.loadDevices().then(() => {
      hilog.info(DOMAIN, TAG, 'preloadDevices done count=%{public}d', this.allDevices.length);
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'preloadDevices error: %{public}s', String(e));
    });
  }

  async login(): Promise<void> {
    if (!this.phone || !this.password) {
      this.loginError = '\u8BF7\u8F93\u5165\u624B\u673A\u53F7\u548C\u5BC6\u7801';
      return;
    }
    this.isLoggingIn = true;
    this.loginError = '';

    try {
      let token: MiToken;
      if (this.needOtp && this.otp.length > 0) {
        token = await this.authService.loginWithOtp(this.otp);
      } else {
        token = await this.authService.login(this.phone, this.password);
      }
      this.isLoggedIn = true;
      this.needOtp = false;
      this.otp = '';
      this.loginPhone = this.phone;
      await PreferencesUtil.saveStr(LOGIN_PHONE_KEY, this.phone);
      this.loginError = '';
      this.userDevices = await this.deviceService.getUserDevices();
      this.devicesVersion++;
      hilog.info(DOMAIN, TAG, 'login success');
    } catch (error) {
      const errorMsg = String(error);
      hilog.error(DOMAIN, TAG, 'login error: %{public}s', errorMsg);
      if (errorMsg.includes('\u9700\u8981\u77ED\u4FE1\u9A8C\u8BC1\u7801')) {
        this.needOtp = true;
        this.loginError = '\u8BF7\u8F93\u5165\u77ED\u4FE1\u9A8C\u8BC1\u7801';
        this.startOtpCountDown();
      } else {
        this.loginError = errorMsg;
      }
    } finally {
      this.isLoggingIn = false;
    }
  }

  async logout(): Promise<void> {
    await this.authService.logout();
    this.deviceService.clearCache();
    this.isLoggedIn = false;
    this.loginPhone = '';
    this.phone = '';
    this.password = '';
    this.otp = '';
    this.needOtp = false;
    this.otpCountDown = 0;
    if (this.countDownTimer >= 0) {
      clearInterval(this.countDownTimer);
      this.countDownTimer = -1;
    }
    this.allDevices = [];
    this.showDeviceList = false;
    this.searchText = '';
    this.editingSlotKey = '';
  }

  async loadDevices(): Promise<void> {
    this.isLoadingDevices = true;
    try {
      this.allDevices = await this.deviceService.getAllDevices();
      hilog.info(DOMAIN, TAG, 'loadDevices count=%{public}d', this.allDevices.length);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadDevices error: %{public}s', String(error));
      this.loginError = '\u83B7\u53D6\u8BBE\u5907\u5217\u8868\u5931\u8D25: ' + String(error);
    } finally {
      this.isLoadingDevices = false;
    }
  }

  toggleDeviceList(): void {
    if (this.showDeviceList) {
      this.showDeviceList = false;
    } else {
      this.loadDevices().then(() => {
        this.showDeviceList = true;
      }).catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'toggleDeviceList error: %{public}s', String(e));
      });
    }
  }

  getFilteredDevices(): MiDevice[] {
    if (this.searchText.length === 0) {
      return this.allDevices;
    }
    const keyword = this.searchText.toLowerCase();
    return this.allDevices.filter((d: MiDevice) => {
      return d.name.toLowerCase().includes(keyword) || d.model.toLowerCase().includes(keyword);
    });
  }

  showAddDialog(device: MiDevice): void {
    this.pendingAddDevice = device;
    this.addDialogController = new CustomDialogController({
      builder: AddAliasDialog({
        deviceName: device.name,
        homeRoom: getDeviceHomeRoomText(device.homeName, device.roomName),
        alias: '',
        onConfirm: (alias: string) => {
          this.confirmAddDevice(alias);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.addDialogController.open();
  }

  async confirmAddDevice(alias: string): Promise<void> {
    if (!this.pendingAddDevice) {
      return;
    }
    const saved = await this.deviceService.addUserDevice(this.pendingAddDevice, alias);
    if (saved) {
      this.userDevices = await this.deviceService.getUserDevices();
      this.devicesVersion++;
      hilog.info(DOMAIN, TAG, 'addDevice: %{public}s did=%{public}s alias=%{public}s', this.pendingAddDevice.name, this.pendingAddDevice.did, alias);
    }
    this.pendingAddDevice = null;
  }

  startEdit(ud: UserDevice): void {
    this.editingSlotKey = UserDevice.getSlotKey(ud);
    this.editingAlias = ud.alias;
    this.editingIcon = ud.icon;
    this.editingAliasController = new TextInputController();
  }

  cancelEdit(): void {
    this.editingSlotKey = '';
    this.editingAlias = '';
    this.editingIcon = DeviceIcon.Generic;
  }

  async saveEdit(): Promise<void> {
    if (this.editingSlotKey.length === 0) {
      return;
    }
    await this.deviceService.updateUserDevice(this.editingSlotKey, this.editingAlias, this.editingIcon);
    this.userDevices = await this.deviceService.getUserDevices();
    this.devicesVersion++;
    hilog.info(DOMAIN, TAG, 'saveEdit slotKey=%{public}s alias=%{public}s icon=%{public}d', this.editingSlotKey, this.editingAlias, this.editingIcon);
    this.editingSlotKey = '';
    this.editingAlias = '';
    this.editingIcon = DeviceIcon.Generic;
  }

  async removeDevice(slotKey: string): Promise<void> {
    if (this.editingSlotKey === slotKey) {
      this.editingSlotKey = '';
    }
    await this.deviceService.removeUserDevice(slotKey);
    this.userDevices = await this.deviceService.getUserDevices();
    this.devicesVersion++;
    hilog.info(DOMAIN, TAG, 'removeDevice slotKey=%{public}s', slotKey);
  }

  confirmRemove(slotKey: string, name: string): void {
    this.getUIContext().showAlertDialog({
      title: '\u5220\u9664\u8BBE\u5907',
      message: '\u786E\u5B9A\u5220\u9664\u300C' + name + '\u300D\u5417\uFF1F',
      primaryButton: {
        value: '\u5220\u9664',
        fontColor: '#F44336',
        action: () => {
          this.removeDevice(slotKey);
        }
      },
      secondaryButton: {
        value: '\u53D6\u6D88',
        action: () => {}
      }
    });
  }

  goBack(): void {
    router.back();
  }

  startOtpCountDown(): void {
    this.otpCountDown = 60;
    if (this.countDownTimer >= 0) {
      clearInterval(this.countDownTimer);
    }
    this.countDownTimer = setInterval(() => {
      if (this.otpCountDown > 0) {
        this.otpCountDown--;
      } else {
        clearInterval(this.countDownTimer);
        this.countDownTimer = -1;
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.countDownTimer >= 0) {
      clearInterval(this.countDownTimer);
      this.countDownTimer = -1;
    }
  }

  async resendOtp(): Promise<void> {
    try {
      await this.authService.resendOtp();
      this.startOtpCountDown();
      this.loginError = '\u9A8C\u8BC1\u7801\u5DF2\u91CD\u65B0\u53D1\u9001';
    } catch (error) {
      this.loginError = '\u91CD\u53D1\u9A8C\u8BC1\u7801\u5931\u8D25: ' + String(error);
    }
  }

  isDeviceAdded(device: MiDevice): boolean {
    let addedCount = 0;
    for (let i = 0; i < this.userDevices.length; i++) {
      if (this.userDevices[i].did === device.did) {
        addedCount++;
      }
    }
    const profile = getDeviceProfile(device.model);
    let totalCount = 1;
    if (isMultiSlotProfile(profile)) {
      totalCount = profile.slots.length;
    }
    return addedCount >= totalCount;
  }

  getDeviceDisplayName(ud: UserDevice): string {
    return UserDevice.getDisplayName(ud);
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('\u2190')
            .fontSize(24)
            .fontColor(Color.White)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.goBack();
        })
        Text('\u8BBE\u7F6E')
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        if (this.isLoggedIn) {
          Button('\u9000\u51FA\u767B\u5F55')
            .height(32)
            .type(ButtonType.Capsule)
            .backgroundColor('#33FFFFFF')
            .fontColor(Color.White)
            .fontSize(13)
            .onClick(() => {
              this.logout();
            })
        } else {
          Blank()
            .width(40)
        }
      }
      .width('100%')
      .height(56)
      .backgroundColor('#1976D2')
      .padding({ left: 16, right: 16 })

      if (this.isLoggedIn) {
        Column() {
          Row() {
            Text('\u5DF2\u767B\u5F55')
              .fontSize(15)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
            Blank()
            if (this.loginPhone.length > 0) {
              Text(this.loginPhone)
                .fontSize(13)
                .fontColor('#999999')
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Color.White)
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .margin({ left: 16, right: 16 })
      }

      Scroll() {
        Column() {
          if (!this.isLoggedIn) {
            Column() {
              Text('\u7C73\u5BB6\u8D26\u53F7\u767B\u5F55')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 24 })

              TextInput({ placeholder: '\u624B\u673A\u53F7', text: this.phone })
                .width('100%')
                .height(50)
                .type(InputType.Number)
                .maxLength(11)
                .onChange((value: string) => {
                  this.phone = value;
                })
                .margin({ bottom: 12 })

              TextInput({ placeholder: '\u5BC6\u7801', text: this.password })
                .width('100%')
                .height(50)
                .type(InputType.Password)
                .onChange((value: string) => {
                  this.password = value;
                })
                .margin({ bottom: 12 })

              if (this.needOtp) {
                Row() {
                  TextInput({ placeholder: '\u77ED\u4FE1\u9A8C\u8BC1\u7801', text: this.otp })
                    .type(InputType.Number)
                    .maxLength(6)
                    .layoutWeight(1)
                    .height(50)
                    .onChange((value: string) => {
                      this.otp = value;
                    })
                  Button(this.otpCountDown > 0 ? `${this.otpCountDown}s` : '\u83B7\u53D6\u9A8C\u8BC1\u7801')
                    .width(110)
                    .height(50)
                    .fontSize(14)
                    .type(ButtonType.Capsule)
                    .backgroundColor(this.otpCountDown > 0 ? '#BBBBBB' : '#1976D2')
                    .fontColor(Color.White)
                    .enabled(this.otpCountDown <= 0)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.resendOtp();
                    })
                }
                .width('100%')
                .margin({ bottom: 12 })
              }

              if (this.loginError.length > 0) {
                Text(this.loginError)
                  .fontSize(14)
                  .fontColor('#F44336')
                  .width('100%')
                  .margin({ bottom: 12 })
              }

              Button(this.isLoggingIn ? '\u767B\u5F55\u4E2D...' : '\u767B\u5F55')
                .width('100%')
                .height(50)
                .type(ButtonType.Capsule)
                .backgroundColor('#1976D2')
                .fontColor(Color.White)
                .enabled(!this.isLoggingIn)
                .onClick(() => {
                  this.login();
                })
            }
            .width('100%')
            .padding(20)
            .backgroundColor(Color.White)
            .borderRadius(12)
            .margin({ top: 20, left: 16, right: 16 })
          } else {
            Column() {
              Row() {
                Text('\u6211\u7684\u8BBE\u5907')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .layoutWeight(1)
                Button(this.isLoadingDevices ? '\u52A0\u8F7D\u4E2D...' : '+ \u6DFB\u52A0')
                  .height(32)
                  .type(ButtonType.Capsule)
                  .backgroundColor('#1976D2')
                  .fontColor(Color.White)
                  .fontSize(13)
                  .enabled(!this.isLoadingDevices)
                  .onClick(() => {
                    this.toggleDeviceList();
                  })
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.userDevices.length === 0) {
                Text('\u5C1A\u672A\u6DFB\u52A0\u8BBE\u5907')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 })
              } else {
                ForEach(this.userDevices, (ud: UserDevice) => {
                  Column() {
                    Row() {
                      Text(getIconText(ud.icon))
                        .fontSize(24)
                        .margin({ right: 12 })
                      Column() {
                        if (ud.alias.length > 0) {
                          Text(this.getDeviceDisplayName(ud))
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text(ud.name)
                            .fontSize(12)
                            .fontColor('#999999')
                            .margin({ top: 1 })
                        } else {
                          Text(this.getDeviceDisplayName(ud))
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        Row() {
                          Text(ud.model)
                            .fontSize(11)
                            .fontColor('#BBBBBB')
                          if (UserDevice.getHomeRoomText(ud).length > 0) {
                            Text(' · ' + UserDevice.getHomeRoomText(ud))
                              .fontSize(11)
                              .fontColor('#BBBBBB')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: 180 })
                          }
                        }
                        .margin({ top: 1 })
                        .alignItems(VerticalAlign.Center)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                       if (this.editingSlotKey === UserDevice.getSlotKey(ud)) {
                         Button('\u53D6\u6D88')
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor('#999999')
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.cancelEdit();
                           })
                         Button('\u4FDD\u5B58')
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor('#4CAF50')
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.saveEdit();
                           })
                       } else {
                         Button('\u7F16\u8F91')
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor('#1976D2')
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.startEdit(ud);
                           })
                       }
                        Button('\u5220\u9664')
                          .height(28)
                          .type(ButtonType.Capsule)
                          .backgroundColor('#F44336')
                          .fontColor(Color.White)
                          .fontSize(12)
                          .onClick(() => {
                            this.confirmRemove(UserDevice.getSlotKey(ud), UserDevice.getDisplayName(ud));
                          })
                    }
                    .width('100%')
                    .height(64)
                    .padding({ left: 16, right: 16 })

                    if (this.editingSlotKey === UserDevice.getSlotKey(ud)) {
                      Column() {
                        Text('\u9009\u62E9\u56FE\u6807')
                          .fontSize(14)
                          .fontColor('#666666')
                          .width('100%')
                          .margin({ bottom: 8 })
                        Grid() {
                          ForEach(ICON_OPTIONS, (icon: number) => {
                            GridItem() {
                              Column() {
                                Text(getIconText(icon))
                                  .fontSize(30)
                              }
                              .width('100%')
                              .height('100%')
                              .aspectRatio(1)
                              .borderRadius(8)
                              .border(this.editingIcon === icon ? { width: 2, color: '#1976D2' } : { width: 1, color: '#DDDDDD' })
                              .backgroundColor(this.editingIcon === icon ? '#E3F2FD' : '#F5F5F5')
                              .justifyContent(FlexAlign.Center)
                              .alignItems(HorizontalAlign.Center)
                              .onClick(() => {
                                this.editingIcon = icon;
                              })
                            }
                          }, (icon: number) => String(icon))
                        }
                        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
                        .rowsGap(8)
                        .columnsGap(8)
                        .width('100%')
                        .height(236)
                        .margin({ bottom: 12 })
                        TextInput({ placeholder: '\u8F93\u5165\u5907\u6CE8\u540D\uFF08\u53EF\u7559\u7A7A\uFF09', text: this.editingAlias, controller: this.editingAliasController })
                          .width('100%')
                          .height(44)
                          .onChange((value: string) => {
                            this.editingAlias = value;
                          })
                      }
                      .width('100%')
                      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
                      .backgroundColor('#F8F8F8')
                    }
                  }
                  .width('100%')
                  }, (ud: UserDevice) => `${UserDevice.getSlotKey(ud)}_${this.devicesVersion}`)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(12)
            .margin({ top: 12, left: 16, right: 16 })

            if (this.showDeviceList) {
              Column() {
                TextInput({ placeholder: '\u641C\u7D22\u8BBE\u5907\u540D\u79F0\u6216\u578B\u53F7...', text: this.searchText })
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .margin({ bottom: 8 })
                  .onChange((value: string) => {
                    this.searchText = value;
                  })

                Text(`\u5171 ${this.getFilteredDevices().length} \u4E2A\u8BBE\u5907`)
                  .fontSize(12)
                  .fontColor('#999999')
                  .width('100%')
                  .margin({ bottom: 6 })

                Column() {
                  ForEach(this.getFilteredDevices(), (device: MiDevice) => {
                    Row() {
                      Column() {
                        Text(device.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row() {
                          Text(device.model)
                            .fontSize(12)
                            .fontColor('#999999')
                          if (getDeviceHomeRoomText(device.homeName, device.roomName).length > 0) {
                            Text(' · ' + getDeviceHomeRoomText(device.homeName, device.roomName))
                              .fontSize(12)
                              .fontColor('#BBBBBB')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: 200 })
                          }
                        }
                        .margin({ top: 2 })
                        .alignItems(VerticalAlign.Center)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      if (this.isDeviceAdded(device)) {
                        Text('\u5DF2\u6DFB\u52A0')
                          .fontSize(13)
                          .fontColor('#4CAF50')
                          .margin({ right: 8 })
                      } else {
                        Button('\u6DFB\u52A0')
                          .height(32)
                          .type(ButtonType.Capsule)
                          .backgroundColor('#1976D2')
                          .fontColor(Color.White)
                          .fontSize(12)
                          .onClick(() => {
                            this.showAddDialog(device);
                          })
                      }
                    }
                    .width('100%')
                    .height(56)
                    .padding({ left: 16, right: 16 })
                  }, (device: MiDevice) => device.did)
                }
                .width('100%')
                .backgroundColor(Color.White)
                .borderRadius(8)
              }
              .width('100%')
              .padding(16)
              .backgroundColor(Color.White)
              .borderRadius(12)
              .margin({ top: 12, left: 16, right: 16, bottom: 24 })
            }
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      Row() {
        Text('\u667a\u6167\u5bb6\u63a7 v' + (this.appVersion.length > 0 ? this.appVersion : '--'))
          .fontSize(12)
          .fontColor('#AAAAAA')
      }
      .width('100%')
      .height(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
