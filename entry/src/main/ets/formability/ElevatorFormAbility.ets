import { FormExtensionAbility, formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlobalContext } from '../common/GlobalContext';
import { PreferencesUtil } from '../mijia/PreferencesUtil';
import { MiAuthService } from '../mijia/MiAuthService';
import { MiDeviceService } from '../mijia/MiDeviceService';
import { WidgetFormData, WidgetToggleMessage, UserDevice, DeviceIcon } from '../mi/types';
import { StatusTexts } from '../common/StatusTexts';

const DOMAIN = 0x0200;
const TAG = 'SwitchForm';
const FORM_DEVICE_KEY = 'form_device_map';
const REFRESH_DELAY_MINUTES = 5;

export default class SwitchFormAbility extends FormExtensionAbility {
  private switchingDevices: Record<string, boolean> = {} as Record<string, boolean>;
  private deviceStates: Record<string, boolean | undefined> = {} as Record<string, boolean | undefined>;

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.ensureContext();
    const formId = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const formDim = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 3);
    const dimensionStr = this.dimensionToString(formDim);
    hilog.info(DOMAIN, TAG, 'onAddForm formId=%{public}s dim=%{public}s', String(formId), dimensionStr);

    if (formId.length > 0) {
      this.ensureFormBinding(formId);
      this.saveFormDimension(formId, dimensionStr);
      this.scheduleNextRefresh(formId);
    }

    const data = new WidgetFormData();
    data.dimension = dimensionStr;
    return formBindingData.createFormBindingData(data);
  }

  onCastToNormalForm(formId: string): void {
    this.ensureContext();
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm formId=%{public}s', formId);
    this.onUpdateForm(formId);
  }

  async onVisibilityChange(formId: string, isVisible: boolean): Promise<void> {
    this.ensureContext();
    hilog.info(DOMAIN, TAG, 'onVisibilityChange formId=%{public}s visible=%{public}s', formId, String(isVisible));
    if (isVisible) {
      await this.onUpdateForm(formId);
    }
  }

  async onUpdateForm(formId: string): Promise<void> {
    this.ensureContext();
    hilog.info(DOMAIN, TAG, 'onUpdateForm formId=%{public}s', formId);
    try {
      const data = await this.getWidgetFormData(formId);
      if (data.did.length > 0 && this.switchingDevices[data.did]) {
        data.statusText = StatusTexts.switching;
      }
      hilog.info(DOMAIN, TAG, 'onUpdateForm push did=%{public}s name=%{public}s dim=%{public}s status=%{public}s', data.did, data.deviceName, data.dimension, data.statusText);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
      this.scheduleNextRefresh(formId);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onUpdateForm error: %{public}s', String(e));
    }
  }

  async onFormEvent(formId: string, message: string): Promise<void> {
    this.ensureContext();
    hilog.info(DOMAIN, TAG, 'onFormEvent formId=%{public}s msg=%{public}s', formId, message.substring(0, 200));
    try {
      const msgObj = JSON.parse(message) as WidgetToggleMessage;
      if (msgObj.method === 'toggle') {
        this.scheduleNextRefresh(formId);
        await MiAuthService.getInstance().checkLoginStatus();
        const deviceService = MiDeviceService.getInstance();
        const dim = await this.getFormDimension(formId);

        let did = msgObj.did;
        let siid = msgObj.siid;
        let piid = msgObj.piid;
        let deviceName = '';
        let iconType = DeviceIcon.Generic;

        if (did.length === 0) {
          const slotKey = await this.getFormDevice(formId);
          if (slotKey.length === 0) {
            const errData = new WidgetFormData();
            errData.statusText = StatusTexts.noDevice;
            errData.dimension = dim;
            formProvider.updateForm(formId, formBindingData.createFormBindingData(errData));
            return;
          }
          const userDevices = await deviceService.getUserDevices();
          for (let i = 0; i < userDevices.length; i++) {
            if (UserDevice.getSlotKey(userDevices[i]) === slotKey) {
              did = userDevices[i].did;
              siid = userDevices[i].siid;
              piid = userDevices[i].piid;
              deviceName = UserDevice.getDisplayName(userDevices[i]);
              iconType = userDevices[i].icon;
              break;
            }
          }
        } else {
          const userDevices = await deviceService.getUserDevices();
          for (let i = 0; i < userDevices.length; i++) {
            if (userDevices[i].did === did) {
              deviceName = UserDevice.getDisplayName(userDevices[i]);
              iconType = userDevices[i].icon;
              break;
            }
          }
        }

        if (did.length === 0) {
          const errData = new WidgetFormData();
          errData.statusText = StatusTexts.noDevice;
          errData.dimension = dim;
          formProvider.updateForm(formId, formBindingData.createFormBindingData(errData));
          return;
        }

        if (this.switchingDevices[did]) {
          return;
        }

        this.switchingDevices[did] = true;
        let currentOn = this.deviceStates[did];
        if (currentOn === undefined) {
          currentOn = await deviceService.getSwitchStateByDid(did, siid, piid);
        }
        const switchingData = new WidgetFormData();
        switchingData.statusText = StatusTexts.switching;
        switchingData.isOn = currentOn ?? false;
        switchingData.isOffline = deviceService.isDeviceOnline(did) === false;
        switchingData.did = did;
        switchingData.siid = siid;
        switchingData.piid = piid;
        switchingData.deviceName = deviceName;
        switchingData.iconType = iconType;
        switchingData.dimension = dim;
        this.pushSwitchingToAllForms(did, switchingData);

        try {
          const newState = await deviceService.toggleSwitchByDid(did, siid, piid);
          hilog.info(DOMAIN, TAG, 'toggle did=%{public}s result=%{public}s', did, String(newState));
          if (newState !== undefined) {
            this.startSwitchPolling(did, siid, piid, newState);
          } else {
            this.switchingDevices[did] = false;
            this.pushStateToAllForms(did, undefined, StatusTexts.controlFailed);
          }
        } catch (toggleError) {
          this.switchingDevices[did] = false;
          hilog.error(DOMAIN, TAG, 'toggle error: %{public}s', String(toggleError));
          this.pushStateToAllForms(did, undefined, StatusTexts.controlFailed);
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onFormEvent error: %{public}s', String(e));
    }
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm formId=%{public}s', formId);
    this.unbindFormDevice(formId);
  }

  private startSwitchPolling(did: string, siid: number, piid: number, expectedValue: boolean): void {
    const maxPolls = 20;
    const intervalMs = 200;
    let pollCount = 0;
    const poll = async (): Promise<void> => {
      pollCount++;
      try {
        const deviceService = MiDeviceService.getInstance();
        const state = await deviceService.getSwitchStateByDid(did, siid, piid);
        if (state !== undefined) {
          this.deviceStates[did] = state;
        }
        const statusText = state !== undefined ? (state ? StatusTexts.on : StatusTexts.off) : StatusTexts.unknown;
        this.pushStateToAllForms(did, state, statusText);
        if (state !== undefined && state === expectedValue) {
          hilog.info(DOMAIN, TAG, 'switchPoll reached expected did=%{public}s status=%{public}s count=%{public}d', did, statusText, pollCount);
          this.switchingDevices[did] = false;
          return;
        }
        hilog.info(DOMAIN, TAG, 'switchPoll did=%{public}s status=%{public}s count=%{public}d', did, statusText, pollCount);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'switchPoll error: %{public}s', String(e));
      }
      if (pollCount < maxPolls) {
        setTimeout(poll, intervalMs);
      } else {
        this.switchingDevices[did] = false;
      }
    };
    setTimeout(poll, intervalMs);
  }

  private ensureContext(): void {
    try {
      GlobalContext.getContext();
    } catch (e) {
      GlobalContext.initContext(this.context);
    }
    PreferencesUtil.setForceReload(true);
  }

  private async saveFormDimension(formId: string, dimension: string): Promise<void> {
    const map = await this.loadFormDimensionMap();
    map[formId] = dimension;
    await this.saveFormDimensionMap(map);
  }

  private scheduleNextRefresh(formId: string): void {
    try {
      formProvider.setFormNextRefreshTime(formId, REFRESH_DELAY_MINUTES, (err: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'setFormNextRefreshTime FAIL formId=%{public}s code=%{public}s', formId, String(err.code));
        } else {
          hilog.info(DOMAIN, TAG, 'setFormNextRefreshTime OK formId=%{public}s', formId);
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setFormNextRefreshTime error: %{public}s', String(e));
    }
  }

  private async getWidgetFormData(formId: string): Promise<WidgetFormData> {
    try {
      await MiAuthService.getInstance().checkLoginStatus();
      const deviceService = MiDeviceService.getInstance();
      await deviceService.refreshOnlineStatus();
      const slotKey = await this.getFormDevice(formId);
      const dim = await this.getFormDimension(formId);
      if (slotKey.length === 0) {
        const data = new WidgetFormData();
        data.statusText = StatusTexts.noDevice;
        data.dimension = dim;
        return data;
      }

      const userDevices = await deviceService.getUserDevices();
      let ud: UserDevice | null = null;
      for (let i = 0; i < userDevices.length; i++) {
        if (UserDevice.getSlotKey(userDevices[i]) === slotKey) {
          ud = userDevices[i];
          break;
        }
      }

      const did = ud !== null ? ud.did : '';
      const siid = ud !== null ? ud.siid : 2;
      const piid = ud !== null ? ud.piid : 1;
      const state = await deviceService.getSwitchStateByDid(did, siid, piid);
      if (state !== undefined) {
        this.deviceStates[did] = state;
      }
      const data = new WidgetFormData();
      data.isOn = state ?? false;
      data.isOffline = did.length === 0 || (deviceService.isDeviceOnline(did) === false);
      data.statusText = data.isOffline ? StatusTexts.offline : (state !== undefined ? (state ? StatusTexts.on : StatusTexts.off) : StatusTexts.unknown);
      data.did = did;
      data.siid = siid;
      data.piid = piid;
      data.deviceName = ud !== null ? UserDevice.getDisplayName(ud) : '';
      data.iconType = ud !== null ? ud.icon : DeviceIcon.Generic;
      data.dimension = dim;
      return data;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getWidgetFormData error: %{public}s', String(e));
      const data = new WidgetFormData();
      data.statusText = StatusTexts.loadFailed;
      return data;
    }
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

  private async getFormDimension(formId: string): Promise<string> {
    try {
      const info = await formProvider.getPublishedRunningFormInfoById(formId);
      const dim = this.dimensionToString(info.dimension);
      this.saveFormDimension(formId, dim);
      return dim;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getFormDimension query fail formId=%{public}s err=%{public}s', formId, String(e));
    }
    const map = await this.loadFormDimensionMap();
    return map[formId] ?? '2*2';
  }

  private async bindFormToDevice(formId: string, did: string): Promise<void> {
    const map = await this.loadFormDeviceMap();
    map[formId] = did;
    await this.saveFormDeviceMap(map);
  }

  private async ensureFormBinding(formId: string): Promise<void> {
    const map = await this.loadFormDeviceMap();
    if (map[formId] === undefined) {
      map[formId] = '';
      await this.saveFormDeviceMap(map);
    }
  }

  private async unbindFormDevice(formId: string): Promise<void> {
    const map = await this.loadFormDeviceMap();
    const newMap: Record<string, string> = {} as Record<string, string>;
    const keys = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== formId) {
        newMap[keys[i]] = map[keys[i]];
      }
    }
    await this.saveFormDeviceMap(newMap);

    const dimMap = await this.loadFormDimensionMap();
    const newDimMap: Record<string, string> = {} as Record<string, string>;
    const dimKeys = Object.keys(dimMap);
    for (let i = 0; i < dimKeys.length; i++) {
      if (dimKeys[i] !== formId) {
        newDimMap[dimKeys[i]] = dimMap[dimKeys[i]];
      }
    }
    await this.saveFormDimensionMap(newDimMap);
  }

  private async getFormDevice(formId: string): Promise<string> {
    const map = await this.loadFormDeviceMap();
    return map[formId] ?? '';
  }

  private async pushSwitchingToAllForms(did: string, switchingData: WidgetFormData): Promise<void> {
    try {
      const deviceService = MiDeviceService.getInstance();
      const userDevices = await deviceService.getUserDevices();
      const map = await this.loadFormDeviceMap();
      const formIds = Object.keys(map);
      for (let i = 0; i < formIds.length; i++) {
        const fid = formIds[i];
        const slotKey = map[fid] ?? '';
        if (slotKey.length === 0) {
          continue;
        }
        let sameDevice = false;
        for (let j = 0; j < userDevices.length; j++) {
          if (UserDevice.getSlotKey(userDevices[j]) === slotKey && userDevices[j].did === did) {
            sameDevice = true;
            break;
          }
        }
        if (!sameDevice) {
          continue;
        }
        const data = new WidgetFormData();
        data.statusText = switchingData.statusText;
        data.isOn = switchingData.isOn;
        data.isOffline = switchingData.isOffline;
        data.did = did;
        data.siid = switchingData.siid;
        data.piid = switchingData.piid;
        data.deviceName = switchingData.deviceName;
        data.iconType = switchingData.iconType;
        data.dimension = await this.getFormDimension(fid);
        hilog.info(DOMAIN, TAG, 'pushSwitching -> %{public}s dim=%{public}s', fid, data.dimension);
        formProvider.updateForm(fid, formBindingData.createFormBindingData(data)).then(() => {
          hilog.info(DOMAIN, TAG, 'pushSwitching updateForm OK formId=%{public}s', fid);
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'pushSwitching updateForm FAIL formId=%{public}s code=%{public}s', fid, String((err as BusinessError).code));
        });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pushSwitchingToAllForms error: %{public}s', String(e));
    }
  }

  private async pushStateToAllForms(did: string, state: boolean | undefined, statusText: string): Promise<void> {
    try {
      const deviceService = MiDeviceService.getInstance();
      const userDevices = await deviceService.getUserDevices();
      let deviceName = '';
      let iconType = DeviceIcon.Generic;
      let siid = 2;
      let piid = 1;
      for (let i = 0; i < userDevices.length; i++) {
        if (userDevices[i].did === did) {
          deviceName = UserDevice.getDisplayName(userDevices[i]);
          iconType = userDevices[i].icon;
          siid = userDevices[i].siid;
          piid = userDevices[i].piid;
          break;
        }
      }
      const isOffline = deviceService.isDeviceOnline(did) === false;
      const map = await this.loadFormDeviceMap();
      const formIds = Object.keys(map);
      hilog.info(DOMAIN, TAG, 'pushStateToAllForms did=%{public}s forms=%{public}s', did, formIds.join(','));
      for (let i = 0; i < formIds.length; i++) {
        const fid = formIds[i];
        const slotKey = map[fid] ?? '';
        if (slotKey.length === 0) {
          continue;
        }
        let sameDevice = false;
        for (let j = 0; j < userDevices.length; j++) {
          if (UserDevice.getSlotKey(userDevices[j]) === slotKey && userDevices[j].did === did) {
            sameDevice = true;
            break;
          }
        }
        if (!sameDevice) {
          continue;
        }
        const data = new WidgetFormData();
        data.isOn = state ?? false;
        data.isOffline = isOffline;
        data.statusText = statusText;
        data.did = did;
        data.siid = siid;
        data.piid = piid;
        data.deviceName = deviceName;
        data.iconType = iconType;
        data.dimension = await this.getFormDimension(fid);
        hilog.info(DOMAIN, TAG, 'pushStateToAllForms -> %{public}s dim=%{public}s status=%{public}s', fid, data.dimension, statusText);
        formProvider.updateForm(fid, formBindingData.createFormBindingData(data)).then(() => {
          hilog.info(DOMAIN, TAG, 'pushState updateForm OK formId=%{public}s', fid);
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'pushState updateForm FAIL formId=%{public}s code=%{public}s', fid, String((err as BusinessError).code));
        });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pushStateToAllForms error: %{public}s', String(e));
    }
  }

  private async loadFormDeviceMap(): Promise<Record<string, string>> {
    const json = await PreferencesUtil.getStr(FORM_DEVICE_KEY, '');
    if (json.length === 0) {
      return {} as Record<string, string>;
    }
    const map = JSON.parse(json) as Record<string, string>;
    const keys = Object.keys(map);
    const cleanMap: Record<string, string> = {} as Record<string, string>;
    for (let i = 0; i < keys.length; i++) {
      const fid = keys[i];
      const val = map[fid] ?? '';
      if (fid.length > 0 && val.length > 0 && val.indexOf('_') >= 0) {
        cleanMap[fid] = val;
      }
    }
    if (keys.length !== Object.keys(cleanMap).length) {
      await this.saveFormDeviceMap(cleanMap);
    }
    return cleanMap;
  }

  private async saveFormDeviceMap(map: Record<string, string>): Promise<void> {
    await PreferencesUtil.saveStr(FORM_DEVICE_KEY, JSON.stringify(map));
  }

  private async loadFormDimensionMap(): Promise<Record<string, string>> {
    const json = await PreferencesUtil.getStr('form_dimension_map', '');
    if (json.length === 0) {
      return {} as Record<string, string>;
    }
    return JSON.parse(json) as Record<string, string>;
  }

  private async saveFormDimensionMap(map: Record<string, string>): Promise<void> {
    await PreferencesUtil.saveStr('form_dimension_map', JSON.stringify(map));
  }
}
