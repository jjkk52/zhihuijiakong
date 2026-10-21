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
      Text($r('app.string.dialog_add_device'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })
      Text($r('app.string.dialog_device_label', this.deviceName))
        .fontSize(14)
        .fontColor($r('app.color.text_hint'))
        .margin({ bottom: 4 })
      if (this.homeRoom.length > 0) {
        Text($r('app.string.dialog_location_label', this.homeRoom))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 12 })
      } else {
        Blank()
          .height(12)
      }
      TextInput({ placeholder: $r('app.string.alias_hint'), text: this.alias })
        .width('100%')
        .height(50)
        .onChange((value: string) => {
          this.alias = value;
        })
        .margin({ bottom: 20 })
      Row() {
        Button($r('app.string.btn_cancel'))
          .width('45%')
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.card_off_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.controller.close();
          })
        Button($r('app.string.btn_confirm'))
          .width('45%')
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand_primary'))
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
  @State loginError: ResourceStr = '';

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
  @State editingMomentary: boolean = false;
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
      this.loginError = $r('app.string.login_error_empty');
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
      if (errorMsg.includes('需要短信验证码')) {
        this.needOtp = true;
        this.loginError = $r('app.string.login_error_need_otp');
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
      this.loginError = $r('app.string.load_devices_failed', String(error));
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
    this.editingMomentary = ud.momentary === true;
    this.editingAliasController = new TextInputController();
  }

  cancelEdit(): void {
    this.editingSlotKey = '';
    this.editingAlias = '';
    this.editingIcon = DeviceIcon.Generic;
    this.editingMomentary = false;
  }

  async saveEdit(): Promise<void> {
    if (this.editingSlotKey.length === 0) {
      return;
    }
    await this.deviceService.updateUserDevice(this.editingSlotKey, this.editingAlias, this.editingIcon, this.editingMomentary);
    this.userDevices = await this.deviceService.getUserDevices();
    this.devicesVersion++;
    hilog.info(DOMAIN, TAG, 'saveEdit slotKey=%{public}s alias=%{public}s icon=%{public}d momentary=%{public}s',
      this.editingSlotKey, this.editingAlias, this.editingIcon, String(this.editingMomentary));
    this.editingSlotKey = '';
    this.editingAlias = '';
    this.editingIcon = DeviceIcon.Generic;
    this.editingMomentary = false;
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
      title: $r('app.string.remove_device_title'),
      message: $r('app.string.remove_device_confirm', name),
      primaryButton: {
        value: $r('app.string.btn_delete'),
        fontColor: $r('app.color.danger_red'),
        action: () => {
          this.removeDevice(slotKey);
        }
      },
      secondaryButton: {
        value: $r('app.string.btn_cancel'),
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
      this.loginError = $r('app.string.otp_resent');
    } catch (error) {
      this.loginError = $r('app.string.otp_resend_failed', String(error));
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
          Text('←')
            .fontSize(24)
            .fontColor(Color.White)
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.goBack();
        })
        Text($r('app.string.settings_title'))
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        if (this.isLoggedIn) {
          Button($r('app.string.settings_logout'))
            .height(32)
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.header_btn_bg'))
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
      .backgroundColor($r('app.color.brand_primary'))
      .padding({ left: 16, right: 16 })

      if (this.isLoggedIn) {
        Column() {
          Row() {
            Text($r('app.string.logged_in_label'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
            Blank()
            if (this.loginPhone.length > 0) {
              Text(this.loginPhone)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
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
              Text($r('app.string.login_title'))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 24 })

              TextInput({ placeholder: $r('app.string.phone_hint'), text: this.phone })
                .width('100%')
                .height(50)
                .type(InputType.Number)
                .maxLength(11)
                .onChange((value: string) => {
                  this.phone = value;
                })
                .margin({ bottom: 12 })

              TextInput({ placeholder: $r('app.string.password_hint'), text: this.password })
                .width('100%')
                .height(50)
                .type(InputType.Password)
                .onChange((value: string) => {
                  this.password = value;
                })
                .margin({ bottom: 12 })

              if (this.needOtp) {
                Row() {
                  TextInput({ placeholder: $r('app.string.otp_hint'), text: this.otp })
                    .type(InputType.Number)
                    .maxLength(6)
                    .layoutWeight(1)
                    .height(50)
                    .onChange((value: string) => {
                      this.otp = value;
                    })
                  Button(this.otpCountDown > 0 ? `${this.otpCountDown}s` : $r('app.string.get_otp'))
                    .width(110)
                    .height(50)
                    .fontSize(14)
                    .type(ButtonType.Capsule)
                    .backgroundColor(this.otpCountDown > 0 ? $r('app.color.text_disabled') : $r('app.color.brand_primary'))
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

              if (this.loginError !== '') {
                Text(this.loginError)
                  .fontSize(14)
                  .fontColor($r('app.color.danger_red'))
                  .width('100%')
                  .margin({ bottom: 12 })
              }

              Button(this.isLoggingIn ? $r('app.string.logging_in') : $r('app.string.login_button'))
                .width('100%')
                .height(50)
                .type(ButtonType.Capsule)
                .backgroundColor($r('app.color.brand_primary'))
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
                Text($r('app.string.my_devices'))
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .layoutWeight(1)
                Button(this.isLoadingDevices ? $r('app.string.loading') : $r('app.string.btn_add'))
                  .height(32)
                  .type(ButtonType.Capsule)
                  .backgroundColor($r('app.color.brand_primary'))
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
                Text($r('app.string.no_device_added'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
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
                          Flex({ alignItems: ItemAlign.Center }) {
                            Text(this.getDeviceDisplayName(ud))
                              .fontSize(15)
                              .fontWeight(FontWeight.Medium)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .flexShrink(1)
                            if (ud.momentary === true) {
                              Text($r('app.string.momentary_tag'))
                                .fontSize(10)
                                .fontColor($r('app.color.brand_primary'))
                                .border({ width: 1, color: $r('app.color.brand_primary') })
                                .borderRadius(4)
                                .padding({ left: 4, right: 4 })
                                .margin({ left: 6 })
                                .flexShrink(0)
                            }
                          }
                          .width('100%')
                          Text(ud.name)
                            .fontSize(12)
                            .fontColor($r('app.color.text_secondary'))
                            .margin({ top: 1 })
                        } else {
                          Flex({ alignItems: ItemAlign.Center }) {
                            Text(this.getDeviceDisplayName(ud))
                              .fontSize(15)
                              .fontWeight(FontWeight.Medium)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .flexShrink(1)
                            if (ud.momentary === true) {
                              Text($r('app.string.momentary_tag'))
                                .fontSize(10)
                                .fontColor($r('app.color.brand_primary'))
                                .border({ width: 1, color: $r('app.color.brand_primary') })
                                .borderRadius(4)
                                .padding({ left: 4, right: 4 })
                                .margin({ left: 6 })
                                .flexShrink(0)
                            }
                          }
                          .width('100%')
                        }
                        Row() {
                          Text(ud.model)
                            .fontSize(11)
                            .fontColor($r('app.color.text_disabled'))
                          if (UserDevice.getHomeRoomText(ud).length > 0) {
                            Text(' · ' + UserDevice.getHomeRoomText(ud))
                              .fontSize(11)
                              .fontColor($r('app.color.text_disabled'))
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
                         Button($r('app.string.btn_cancel'))
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor($r('app.color.text_secondary'))
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.cancelEdit();
                           })
                         Button($r('app.string.btn_save'))
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor($r('app.color.status_on'))
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.saveEdit();
                           })
                       } else {
                         Button($r('app.string.btn_edit'))
                           .height(28)
                           .type(ButtonType.Capsule)
                           .backgroundColor($r('app.color.brand_primary'))
                           .fontColor(Color.White)
                           .fontSize(12)
                           .margin({ right: 6 })
                           .onClick(() => {
                             this.startEdit(ud);
                           })
                       }
                        Button($r('app.string.btn_delete'))
                          .height(28)
                          .type(ButtonType.Capsule)
                          .backgroundColor($r('app.color.danger_red'))
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
                        Text($r('app.string.choose_icon'))
                          .fontSize(14)
                          .fontColor($r('app.color.text_hint'))
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
                              .border(this.editingIcon === icon ?
                                { width: 2, color: $r('app.color.brand_primary') } :
                                { width: 1, color: $r('app.color.border_light') })
                              .backgroundColor(this.editingIcon === icon ?
                                $r('app.color.selected_bg') : $r('app.color.unbound_bg'))
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
                        TextInput({ placeholder: $r('app.string.alias_hint'), text: this.editingAlias, controller: this.editingAliasController })
                          .width('100%')
                          .height(44)
                          .onChange((value: string) => {
                            this.editingAlias = value;
                          })
                        Row() {
                          Column() {
                            Text($r('app.string.momentary_mode'))
                              .fontSize(14)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.text_primary'))
                              .width('100%')
                            Text($r('app.string.momentary_mode_desc'))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .width('100%')
                              .margin({ top: 2 })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)

                          Toggle({ type: ToggleType.Switch, isOn: this.editingMomentary })
                            .onChange((isOn: boolean) => {
                              this.editingMomentary = isOn;
                            })
                        }
                        .width('100%')
                        .margin({ top: 12 })
                        .alignItems(VerticalAlign.Center)
                      }
                      .width('100%')
                      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
                      .backgroundColor($r('app.color.edit_panel_bg'))
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
                TextInput({ placeholder: $r('app.string.search_hint'), text: this.searchText })
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .margin({ bottom: 8 })
                  .onChange((value: string) => {
                    this.searchText = value;
                  })

                Text($r('app.string.device_count', this.getFilteredDevices().length))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
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
                            .fontColor($r('app.color.text_secondary'))
                          if (getDeviceHomeRoomText(device.homeName, device.roomName).length > 0) {
                            Text(' · ' + getDeviceHomeRoomText(device.homeName, device.roomName))
                              .fontSize(12)
                              .fontColor($r('app.color.text_disabled'))
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
                        Text($r('app.string.already_added'))
                          .fontSize(13)
                          .fontColor($r('app.color.status_on'))
                          .margin({ right: 8 })
                      } else {
                        Button($r('app.string.btn_add'))
                          .height(32)
                          .type(ButtonType.Capsule)
                          .backgroundColor($r('app.color.brand_primary'))
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
        Text($r('app.string.version_footer', this.appVersion.length > 0 ? this.appVersion : '--'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg_alt'))
  }
}
