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
  private processingForms: Record<string, boolean> = {} as Record<string, boolean>;
  private switchingDevices: Record<string, boolean> = {} as Record<string, boolean>;
  private deviceStates: Record<string, boolean | undefined> = {} as Record<string, boolean | undefined>;
  private dimensionCache: Record<string, string> = {} as Record<string, string>;

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.ensureContext();
    const formId = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const formDim = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 3);
    const dimensionStr = this.dimensionToString(formDim);
    hilog.info(DOMAIN, TAG, 'onAddForm formId=%{public}s dim=%{public}s', String(formId), dimensionStr);

    if (formId.length > 0) {
      this.ensureFormBinding(formId);
      this.saveFormDimension(formId, dimensionStr);
      this.dimensionCache[formId] = dimensionStr;
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
    if (this.processingForms[formId] === true) {
      hilog.info(DOMAIN, TAG, 'onUpdateForm skipped, form busy formId=%{public}s', formId);
      return;
    }
    hilog.info(DOMAIN, TAG, 'onUpdateForm formId=%{public}s', formId);
    try {
      const data = await this.getWidgetFormData(formId);
      const key = UserDevice.makeSlotKey(data.did, data.siid, data.piid);
      if (data.did.length > 0 && this.switchingDevices[key] === true) {
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
    if (this.processingForms[formId] === true) {
      hilog.info(DOMAIN, TAG, 'onFormEvent ignored, form busy formId=%{public}s', formId);
      return;
    }
    this.processingForms[formId] = true;
    let activeKey = '';
    hilog.info(DOMAIN, TAG, 'onFormEvent formId=%{public}s msg=%{public}s', formId, message.substring(0, 200));
    try {
      this.scheduleNextRefresh(formId);
      const msgObj = JSON.parse(message) as WidgetToggleMessage;
      if (msgObj.method !== 'toggle') {
        return;
      }

      await MiAuthService.getInstance().checkLoginStatus();
      const deviceService = MiDeviceService.getInstance();

      const slotKey = await this.getFormDevice(formId);
      if (slotKey.length === 0) {
        await this.pushNoDevice(formId);
        return;
      }

      const userDevices = await deviceService.getUserDevices();
      let ud = this.findBySlotKey(userDevices, slotKey);
      if (ud === null && msgObj.did.length > 0) {
        ud = this.findByTriple(userDevices, msgObj.did, msgObj.siid, msgObj.piid);
      }
      if (ud === null) {
        await this.pushNoDevice(formId);
        return;
      }

      const key = UserDevice.getSlotKey(ud);
      if (this.switchingDevices[key] === true) {
        hilog.info(DOMAIN, TAG, 'onFormEvent ignored, device busy key=%{public}s', key);
        return;
      }
      this.switchingDevices[key] = true;
      activeKey = key;

      if (UserDevice.isMomentary(ud)) {
        await this.runPulse(ud, key);
      } else {
        await this.runToggle(ud, key);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onFormEvent error: %{public}s', String(e));
      if (activeKey.length > 0) {
        this.switchingDevices[activeKey] = false;
      }
    } finally {
      this.processingForms[formId] = false;
    }
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm formId=%{public}s', formId);
    this.unbindFormDevice(formId);
  }

  private async runToggle(ud: UserDevice, key: string): Promise<void> {
    const deviceService = MiDeviceService.getInstance();
    let currentOn = this.deviceStates[key];
    if (currentOn === undefined) {
      currentOn = await deviceService.getSwitchStateByDid(ud.did, ud.siid, ud.piid);
    }
    await this.pushStateToAllForms(ud, currentOn ?? false, StatusTexts.switching);

    try {
      const newState = await deviceService.toggleSwitchByDid(ud.did, ud.siid, ud.piid);
      hilog.info(DOMAIN, TAG, 'toggle did=%{public}s result=%{public}s', ud.did, String(newState));
      if (newState !== undefined) {
        this.startSwitchPolling(ud, key, newState);
      } else {
        this.switchingDevices[key] = false;
        await this.pushStateToAllForms(ud, currentOn ?? false, StatusTexts.controlFailed);
      }
    } catch (toggleError) {
      this.switchingDevices[key] = false;
      hilog.error(DOMAIN, TAG, 'toggle error: %{public}s', String(toggleError));
      await this.pushStateToAllForms(ud, currentOn ?? false, StatusTexts.controlFailed);
    }
  }

  private async runPulse(ud: UserDevice, key: string): Promise<void> {
    const deviceService = MiDeviceService.getInstance();
    const startOn = this.deviceStates[key] ?? false;
    await this.pushStateToAllForms(ud, startOn, StatusTexts.switching);

    let lastKnown: boolean | undefined = startOn;
    const ok = await deviceService.pulseSwitchByDid(
      ud.did,
      ud.siid,
      ud.piid,
      (state: boolean | undefined) => {
        if (state === true) {
          lastKnown = true;
          this.deviceStates[key] = true;
          this.pushStateToAllForms(ud, true, StatusTexts.on);
        } else if (state === false) {
          lastKnown = false;
          this.deviceStates[key] = false;
          this.pushStateToAllForms(ud, false, StatusTexts.off);
        }
      }
    );

    hilog.info(DOMAIN, TAG, 'pulse done did=%{public}s ok=%{public}s last=%{public}s', ud.did, String(ok), String(lastKnown));
    if (!ok) {
      await this.pushStateToAllForms(ud, lastKnown ?? false, StatusTexts.controlFailed);
    }
    this.switchingDevices[key] = false;
  }

  private startSwitchPolling(ud: UserDevice, key: string, expectedValue: boolean): void {
    const maxPolls = 20;
    const intervalMs = 200;
    let pollCount = 0;
    let lastState: boolean | undefined = undefined;
    const poll = async (): Promise<void> => {
      pollCount++;
      try {
        const deviceService = MiDeviceService.getInstance();
        const state = await deviceService.getSwitchStateByDid(ud.did, ud.siid, ud.piid);
        lastState = state;
        if (state !== undefined) {
          this.deviceStates[key] = state;
        }
        const statusText = state !== undefined ? (state ? StatusTexts.on : StatusTexts.off) : StatusTexts.unknown;
        this.pushStateToAllForms(ud, state, statusText);
        if (state !== undefined && state === expectedValue) {
          hilog.info(DOMAIN, TAG, 'switchPoll reached expected did=%{public}s status=%{public}s count=%{public}d', ud.did, statusText, pollCount);
          this.switchingDevices[key] = false;
          return;
        }
        hilog.info(DOMAIN, TAG, 'switchPoll did=%{public}s status=%{public}s count=%{public}d', ud.did, statusText, pollCount);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'switchPoll error: %{public}s', String(e));
      }
      if (pollCount < maxPolls) {
        setTimeout(poll, intervalMs);
      } else {
        this.switchingDevices[key] = false;
        const fallback = lastState !== undefined ? lastState : this.deviceStates[key];
        this.pushStateToAllForms(ud, fallback, StatusTexts.controlFailed);
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
      const dim = await this.getCachedDimension(formId);
      if (slotKey.length === 0) {
        const data = new WidgetFormData();
        data.statusText = StatusTexts.noDevice;
        data.dimension = dim;
        return data;
      }

      const userDevices = await deviceService.getUserDevices();
      const ud = this.findBySlotKey(userDevices, slotKey);

      const did = ud !== null ? ud.did : '';
      const siid = ud !== null ? ud.siid : 2;
      const piid = ud !== null ? ud.piid : 1;
      let state: boolean | undefined = undefined;
      if (did.length > 0) {
        state = await deviceService.getSwitchStateByDid(did, siid, piid);
        if (state !== undefined) {
          this.deviceStates[UserDevice.makeSlotKey(did, siid, piid)] = state;
        }
      }
      const data = new WidgetFormData();
      data.isOn = state ?? false;
      data.isOffline = did.length === 0 || (deviceService.isDeviceOnline(did) === false);
      if (data.isOffline) {
        data.statusText = StatusTexts.offline;
      } else if (state === undefined) {
        data.statusText = StatusTexts.unknown;
      } else {
        data.statusText = state ? StatusTexts.on : StatusTexts.off;
      }
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
      this.dimensionCache[formId] = dim;
      this.saveFormDimension(formId, dim);
      return dim;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getFormDimension query fail formId=%{public}s err=%{public}s', formId, String(e));
    }
    const map = await this.loadFormDimensionMap();
    const dim = map[formId] ?? '2*2';
    this.dimensionCache[formId] = dim;
    return dim;
  }

  private async getCachedDimension(formId: string): Promise<string> {
    const cached = this.dimensionCache[formId];
    if (cached !== undefined) {
      return cached;
    }
    return await this.getFormDimension(formId);
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
    this.dimensionCache = {} as Record<string, string>;
  }

  private async getFormDevice(formId: string): Promise<string> {
    const map = await this.loadFormDeviceMap();
    return map[formId] ?? '';
  }

  private findBySlotKey(devices: UserDevice[], slotKey: string): UserDevice | null {
    for (let i = 0; i < devices.length; i++) {
      if (UserDevice.getSlotKey(devices[i]) === slotKey) {
        return devices[i];
      }
    }
    return null;
  }

  private findByTriple(devices: UserDevice[], did: string, siid: number, piid: number): UserDevice | null {
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].did === did && devices[i].siid === siid && devices[i].piid === piid) {
        return devices[i];
      }
    }
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].did === did) {
        return devices[i];
      }
    }
    return null;
  }

  private async pushNoDevice(formId: string): Promise<void> {
    const data = new WidgetFormData();
    data.statusText = StatusTexts.noDevice;
    data.dimension = await this.getCachedDimension(formId);
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pushNoDevice error: %{public}s', String(e));
    }
  }

  private async pushStateToAllForms(ud: UserDevice, state: boolean | undefined, statusText: string): Promise<void> {
    try {
      const slotKey = UserDevice.getSlotKey(ud);
      const isOffline = MiDeviceService.getInstance().isDeviceOnline(ud.did) === false;
      const map = await this.loadFormDeviceMap();
      const formIds = Object.keys(map);
      for (let i = 0; i < formIds.length; i++) {
        const fid = formIds[i];
        if (map[fid] !== slotKey) {
          continue;
        }
        const data = new WidgetFormData();
        data.isOn = state ?? false;
        data.isOffline = isOffline;
        data.statusText = statusText;
        data.did = ud.did;
        data.siid = ud.siid;
        data.piid = ud.piid;
        data.deviceName = UserDevice.getDisplayName(ud);
        data.iconType = ud.icon;
        data.dimension = await this.getCachedDimension(fid);
        hilog.info(DOMAIN, TAG, 'pushState -> %{public}s dim=%{public}s status=%{public}s isOn=%{public}s', fid, data.dimension, statusText, String(data.isOn));
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
