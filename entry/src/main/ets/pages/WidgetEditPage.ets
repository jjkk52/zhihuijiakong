import { MiDeviceService } from '../mijia/MiDeviceService';
import { MiAuthService } from '../mijia/MiAuthService';
import { UserDevice, DeviceIcon, getIconText, WidgetFormData } from '../mi/types';
import { formBindingData, formProvider } from '@kit.FormKit';
import { PreferencesUtil } from '../mijia/PreferencesUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0200;
const TAG = 'WidgetEditPage';
const FORM_DEVICE_KEY = 'form_device_map';

@Entry
@Component
struct WidgetEditPage {
  @LocalStorageProp('formId') formId: string = '';
  @State userDevices: UserDevice[] = [];
  @State selectedSlotKey: string = '';
  @State hasDevices: boolean = false;
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    this.initPage();
  }

  async initPage(): Promise<void> {
    try {
      if (this.formId.length === 0) {
        this.formId = String(AppStorage.get<string>('formId') ?? '');
      }
      hilog.info(DOMAIN, TAG, 'initPage formId=%{public}s', this.formId);
      const loggedIn = await MiAuthService.getInstance().checkLoginStatus();
      if (loggedIn) {
        this.userDevices = await MiDeviceService.getInstance().getUserDevices();
        this.hasDevices = this.userDevices.length > 0;
        const mapJson = await PreferencesUtil.getStr(FORM_DEVICE_KEY, '');
        if (mapJson.length > 0) {
          const map: Record<string, string> = JSON.parse(mapJson) as Record<string, string>;
          const val = map[this.formId] ?? '';
          this.selectedSlotKey = val;
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'initPage error: %{public}s', String(e));
    }
    this.isLoading = false;
  }

  async selectDevice(slotKey: string): Promise<void> {
    this.selectedSlotKey = slotKey;
  }

  async saveAndClose(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'saveAndClose formId=%{public}s slotKey=%{public}s', this.formId, this.selectedSlotKey);
      if (this.formId.length === 0) {
        this.closePage();
        return;
      }
      const mapJson = await PreferencesUtil.getStr(FORM_DEVICE_KEY, '');
      const map: Record<string, string> = mapJson.length > 0 ?
        JSON.parse(mapJson) as Record<string, string> : {} as Record<string, string>;
      map[this.formId] = this.selectedSlotKey;
      await PreferencesUtil.saveStr(FORM_DEVICE_KEY, JSON.stringify(map));

      if (this.formId.length > 0 && this.selectedSlotKey.length > 0) {
        const ud = this.findDevice(this.selectedSlotKey);
        const formData = new WidgetFormData();
        formData.did = ud !== null ? ud.did : '';
        formData.siid = ud !== null ? ud.siid : 2;
        formData.piid = ud !== null ? ud.piid : 1;
        formData.deviceName = ud !== null ? (ud.alias.length > 0 ? ud.alias : ud.name) : '';
        formData.iconType = ud !== null ? ud.icon : DeviceIcon.Generic;
        formData.dimension = await this.getFormDimension(this.formId);
        formData.statusText = '\u52A0\u8F7D\u4E2D...';
        try {
          const state = await MiDeviceService.getInstance().getSwitchStateByDid(
            ud !== null ? ud.did : '',
            ud !== null ? ud.siid : 2, ud !== null ? ud.piid : 1);
          formData.isOn = state ?? false;
          formData.statusText = state !== undefined ? (state ? '\u5DF2\u5F00\u542F' : '\u5DF2\u5173\u95ED') : '\u72B6\u6001\u672A\u77E5';
        } catch (e) {
          formData.statusText = '\u83B7\u53D6\u5931\u8D25';
        }
        formProvider.updateForm(this.formId, formBindingData.createFormBindingData(formData));
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveAndClose error: %{public}s', String(e));
    }
    this.closePage();
  }

  private closePage(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'closePage error: %{public}s', String(e));
    }
  }

  private findDevice(slotKey: string): UserDevice | null {
    for (let i = 0; i < this.userDevices.length; i++) {
      const udKey = (this.userDevices[i].slotKey !== undefined && this.userDevices[i].slotKey !== null && this.userDevices[i].slotKey.length > 0) ? this.userDevices[i].slotKey : this.userDevices[i].did;
      if (udKey === slotKey) {
        return this.userDevices[i];
      }
    }
    return null;
  }

  private async getFormDimension(formId: string): Promise<string> {
    try {
      const info = await formProvider.getPublishedRunningFormInfoById(formId);
      return this.dimensionToString(info.dimension);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getFormDimension query fail formId=%{public}s err=%{public}s', formId, String(e));
    }
    return '2*2';
  }

  private dimensionToString(dim: number): string {
    if (dim === 1) {
      return '1*2';
    }
    if (dim === 2) {
      return '2*2';
    }
    if (dim === 3) {
      return '2*4';
    }
    if (dim === 4) {
      return '4*4';
    }
    return '2*2';
  }

  private getUdKey(ud: UserDevice): string {
    return UserDevice.getSlotKey(ud);
  }

  private getUdDisplayLabel(ud: UserDevice): string {
    return UserDevice.getDisplayName(ud);
  }

  build() {
    Column() {
      Row() {
        Text('\u5361\u7247\u8BBE\u7F6E')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(40)
      }
      .width('100%')
      .height(56)
      .backgroundColor('#1976D2')
      .padding({ left: 16, right: 16 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#1976D2')
          Text('\u52A0\u8F7D\u4E2D...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (!this.hasDevices) {
        Column() {
          Text('\u5C1A\u672A\u6DFB\u52A0\u8BBE\u5907')
            .fontSize(16)
            .fontColor('#757575')
            .margin({ bottom: 12 })
          Text('\u8BF7\u5148\u5728\u5E94\u7528\u4E2D\u6DFB\u52A0\u8BBE\u5907')
            .fontSize(13)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            Text('\u9009\u62E9\u7ED1\u5B9A\u8BBE\u5907')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.userDevices, (ud: UserDevice) => {
              Row() {
                Text(getIconText(ud.icon))
                  .fontSize(24)
                  .margin({ right: 12 })
                Column() {
                  Text(this.getUdDisplayLabel(ud))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ud.model)
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (this.selectedSlotKey === this.getUdKey(ud)) {
                  Text('\u2713')
                    .fontSize(22)
                    .fontColor('#1976D2')
                    .margin({ right: 8 })
                }
              }
              .width('100%')
              .height(60)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.selectedSlotKey === this.getUdKey(ud) ? '#E3F2FD' : Color.White)
              .borderRadius(8)
              .margin({ bottom: 8 })
              .onClick(() => {
                this.selectDevice(this.getUdKey(ud));
              })
            }, (ud: UserDevice) => this.getUdKey(ud))

            Button('\u4FDD\u5B58')
              .width('100%')
              .height(50)
              .type(ButtonType.Capsule)
              .backgroundColor('#1976D2')
              .fontColor(Color.White)
              .fontSize(16)
              .margin({ top: 20 })
              .enabled(this.selectedSlotKey.length > 0)
              .backgroundColor(this.selectedSlotKey.length > 0 ? '#1976D2' : '#BBBBBB')
              .onClick(() => {
                this.saveAndClose();
              })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
