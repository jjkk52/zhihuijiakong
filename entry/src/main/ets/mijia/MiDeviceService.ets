import { MiAuthService } from './MiAuthService';
import { MiIOService } from '../mi/MiIOService';
import { MiDevice, UserDevice, SwitchSlot, HomeRoom, DeviceProfile, getDeviceProfile, isMultiSlotProfile } from '../mi/types';
import { PreferencesUtil } from './PreferencesUtil';

export class MiDeviceService {
  private static instance: MiDeviceService | null = null;
  private authService: MiAuthService = MiAuthService.getInstance();
  private onlineMap: Record<string, boolean> = {};
  private allDevicesCache: MiDevice[] = [];
  private allDevicesCacheTime: number = 0;
  private allDevicesLoading: Promise<MiDevice[]> | null = null;

  static getInstance(): MiDeviceService {
    if (!MiDeviceService.instance) {
      MiDeviceService.instance = new MiDeviceService();
    }
    return MiDeviceService.instance;
  }

  private getIOService(): MiIOService {
    return this.authService.getIOService();
  }

  isDeviceListLoaded(): boolean {
    return this.allDevicesCache.length > 0;
  }

  clearCache(): void {
    this.allDevicesCache = [];
    this.allDevicesCacheTime = 0;
    this.allDevicesLoading = null;
    this.onlineMap = {};
    this.getIOService().clearCache();
  }

  async getAllDevices(force: boolean = false): Promise<MiDevice[]> {
    if (this.allDevicesLoading !== null) {
      return this.allDevicesLoading;
    }
    if (!force && this.allDevicesCache.length > 0 && (Date.now() - this.allDevicesCacheTime) < 60000) {
      return this.allDevicesCache;
    }
    const loading = this.doLoadAllDevices();
    this.allDevicesLoading = loading;
    try {
      return await loading;
    } finally {
      this.allDevicesLoading = null;
    }
  }

  private async doLoadAllDevices(): Promise<MiDevice[]> {
    try {
      const io = this.getIOService();
      const devices = await io.getDeviceList();
      try {
        const roomMap = await io.getHomeRooms();
        for (let i = 0; i < devices.length; i++) {
          const hr = roomMap[devices[i].did];
          if (hr !== undefined) {
            devices[i].homeName = hr.homeName;
            devices[i].roomName = hr.roomName;
          }
        }
      } catch (e) {
      }
      this.allDevicesCache = devices;
      this.allDevicesCacheTime = Date.now();
      return devices;
    } catch (error) {
      return [];
    }
  }

  async refreshOnlineStatus(): Promise<void> {
    try {
      const devices = await this.getIOService().getDeviceList();
      const map: Record<string, boolean> = {};
      for (let i = 0; i < devices.length; i++) {
        map[devices[i].did] = devices[i].online;
      }
      this.onlineMap = map;
    } catch (e) {
    }
  }

  isDeviceOnline(did: string): boolean {
    return this.onlineMap[did] !== false;
  }

  async getUserDevices(): Promise<UserDevice[]> {
    let devices = await PreferencesUtil.getUserDevices();
    let needMigrate = false;
    const migratedDevices: UserDevice[] = [];
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].slotKey === undefined || devices[i].slotKey === null || devices[i].slotKey.length === 0) {
        needMigrate = true;
        const profile = getDeviceProfile(devices[i].model);
        if (isMultiSlotProfile(profile)) {
          for (let j = 0; j < profile.slots.length; j++) {
            const slot: SwitchSlot = profile.slots[j];
            const ud: UserDevice = {
              did: devices[i].did,
              name: devices[i].name,
              alias: devices[i].alias,
              model: devices[i].model,
              icon: profile.icon,
              siid: slot.siid,
              piid: slot.piid,
              slotKey: UserDevice.makeSlotKey(devices[i].did, slot.siid, slot.piid),
              slotLabel: slot.label,
              homeName: devices[i].homeName ?? '',
              roomName: devices[i].roomName ?? '',
            };
            migratedDevices.push(ud);
          }
        } else {
          devices[i].slotKey = UserDevice.makeSlotKey(devices[i].did, devices[i].siid, devices[i].piid);
          devices[i].slotLabel = profile.label;
          migratedDevices.push(devices[i]);
        }
      } else {
        migratedDevices.push(devices[i]);
      }
    }
    if (needMigrate) {
      devices = migratedDevices;
      await PreferencesUtil.saveUserDevices(devices);
    }
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].homeName === undefined || devices[i].homeName === null) {
        devices[i].homeName = '';
      }
      if (devices[i].roomName === undefined || devices[i].roomName === null) {
        devices[i].roomName = '';
      }
    }
    const cleaned: UserDevice[] = [];
    let needClean = false;
    for (let i = 0; i < devices.length; i++) {
      const profile = getDeviceProfile(devices[i].model);
      if (!isMultiSlotProfile(profile)) {
        if (devices[i].siid === profile.siid) {
          devices[i].slotLabel = profile.label;
          cleaned.push(devices[i]);
        } else {
          needClean = true;
        }
      } else {
        cleaned.push(devices[i]);
      }
    }
    if (needClean) {
      devices = cleaned;
      await PreferencesUtil.saveUserDevices(devices);
    }
    return devices;
  }

  async getMergedUserDevices(): Promise<UserDevice[]> {
    const local = await this.getUserDevices();
    const localDids: Record<string, boolean> = {} as Record<string, boolean>;
    for (let i = 0; i < local.length; i++) {
      localDids[local[i].did] = true;
    }
    let cloudDevices: MiDevice[] = [];
    try {
      cloudDevices = await this.getIOService().getDeviceList();
    } catch (e) {
      cloudDevices = [];
    }
    let roomMap: Record<string, HomeRoom> = {} as Record<string, HomeRoom>;
    try {
      roomMap = await this.getIOService().getHomeRooms();
    } catch (e) {
      roomMap = {} as Record<string, HomeRoom>;
    }
    const result: UserDevice[] = local.slice();
    for (let i = 0; i < cloudDevices.length; i++) {
      const cd = cloudDevices[i];
      if (localDids[cd.did]) {
        continue;
      }
      const profile = getDeviceProfile(cd.model);
      const hr = roomMap[cd.did];
      const ud: UserDevice = {
        did: cd.did,
        name: cd.name,
        alias: '',
        model: cd.model,
        icon: profile.icon,
        siid: profile.siid,
        piid: profile.piid,
        slotKey: UserDevice.makeSlotKey(cd.did, profile.siid, profile.piid),
        slotLabel: profile.label,
        homeName: hr !== undefined ? hr.homeName : '',
        roomName: hr !== undefined ? hr.roomName : ''
      };
      result.push(ud);
    }
    return result;
  }

  async addUserDevice(device: MiDevice, alias: string): Promise<boolean> {
    const devices = await PreferencesUtil.getUserDevices();
    const profile = getDeviceProfile(device.model);
    let homeName = device.homeName === undefined || device.homeName === null ? '' : device.homeName;
    let roomName = device.roomName === undefined || device.roomName === null ? '' : device.roomName;
    if (homeName.length === 0) {
      try {
        const roomMap = await this.getIOService().getHomeRooms();
        const hr = roomMap[device.did];
        if (hr !== undefined) {
          homeName = hr.homeName;
          roomName = hr.roomName;
        }
      } catch (e) {
      }
    }

    let dynamicSiids: number[] = [];
    if (!profile.known) {
      dynamicSiids = await this.getIOService().getDeviceSwitchSiids(device.model);
    }
    const slots: SwitchSlot[] = this.resolveSlots(profile, dynamicSiids);

    let added = false;
    for (let i = 0; i < slots.length; i++) {
      const slot: SwitchSlot = slots[i];
      const slotKey = UserDevice.makeSlotKey(device.did, slot.siid, slot.piid);
      let exists = false;
      for (let j = 0; j < devices.length; j++) {
        const existingKey = UserDevice.getSlotKey(devices[j]);
        if (existingKey === slotKey || (slots.length === 1 && devices[j].did === device.did)) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        const ud: UserDevice = {
          did: device.did,
          name: device.name,
          alias: alias,
          model: device.model,
          icon: profile.icon,
          siid: slot.siid,
          piid: slot.piid,
          slotKey: slotKey,
          slotLabel: slot.label,
          homeName: homeName,
          roomName: roomName,
        };
        devices.push(ud);
        added = true;
      }
    }
    if (added) {
      return await PreferencesUtil.saveUserDevices(devices);
    }
    return false;
  }

  private resolveSlots(profile: DeviceProfile, dynamicSiids: number[]): SwitchSlot[] {
    const slots: SwitchSlot[] = [];
    if (dynamicSiids.length > 0) {
      for (let i = 0; i < dynamicSiids.length; i++) {
        const slot = new SwitchSlot();
        slot.siid = dynamicSiids[i];
        slot.piid = 1;
        let label = '';
        for (let k = 0; k < profile.slots.length; k++) {
          if (profile.slots[k].siid === dynamicSiids[i]) {
            label = profile.slots[k].label;
            break;
          }
        }
        if (label.length === 0) {
          label = dynamicSiids.length > 1 ? ('\u6309\u952E' + (i + 1)) : profile.label;
        }
        slot.label = label;
        slots.push(slot);
      }
    } else if (isMultiSlotProfile(profile)) {
      for (let i = 0; i < profile.slots.length; i++) {
        slots.push(profile.slots[i]);
      }
    } else {
      const single = new SwitchSlot();
      single.siid = profile.siid;
      single.piid = profile.piid;
      single.label = profile.label;
      slots.push(single);
    }
    return slots;
  }

  async enrichHomeRooms(userDevices: UserDevice[]): Promise<UserDevice[]> {
    let needEnrich = false;
    for (let i = 0; i < userDevices.length; i++) {
      if (userDevices[i].homeName === undefined || userDevices[i].homeName === null || userDevices[i].homeName.length === 0) {
        needEnrich = true;
        break;
      }
    }
    if (!needEnrich) {
      return userDevices;
    }
    try {
      const roomMap = await this.getIOService().getHomeRooms();
      for (let i = 0; i < userDevices.length; i++) {
        const hr = roomMap[userDevices[i].did];
        if (hr !== undefined) {
          userDevices[i].homeName = hr.homeName;
          userDevices[i].roomName = hr.roomName;
        }
      }
      await PreferencesUtil.saveUserDevices(userDevices);
    } catch (e) {
    }
    return userDevices;
  }

  async updateUserDevice(slotKey: string, alias: string, icon: number): Promise<boolean> {
    const devices = await PreferencesUtil.getUserDevices();
    for (let i = 0; i < devices.length; i++) {
      if (UserDevice.getSlotKey(devices[i]) === slotKey) {
        devices[i].alias = alias;
        devices[i].icon = icon;
        return await PreferencesUtil.saveUserDevices(devices);
      }
    }
    return false;
  }

  async removeUserDevice(slotKey: string): Promise<boolean> {
    const devices = await PreferencesUtil.getUserDevices();
    const newDevices: UserDevice[] = [];
    for (let i = 0; i < devices.length; i++) {
      if (UserDevice.getSlotKey(devices[i]) !== slotKey) {
        newDevices.push(devices[i]);
      }
    }
    return await PreferencesUtil.saveUserDevices(newDevices);
  }

  async refreshDeviceStates(userDevices: UserDevice[]): Promise<Record<string, boolean | undefined>> {
    await this.refreshOnlineStatus();
    const states: Record<string, boolean | undefined> = {} as Record<string, boolean | undefined>;
    const promises: Promise<void>[] = [];
    for (let i = 0; i < userDevices.length; i++) {
      const ud = userDevices[i];
      const key = UserDevice.getSlotKey(ud);
      if (this.onlineMap[ud.did] === false) {
        states[key] = undefined;
        continue;
      }
      promises.push(this.getSwitchStateByDid(ud.did, ud.siid, ud.piid).then((state: boolean | undefined) => {
        states[key] = state;
      }));
    }
    await Promise.all(promises);
    return states;
  }

  async getSwitchStateByDid(did: string, siid: number, piid: number): Promise<boolean | undefined> {
    if (this.onlineMap[did] === false) {
      return undefined;
    }
    try {
      const value = await this.getIOService().getProperty(did, siid, piid);
      if (value === null) {
        return undefined;
      }
      return value === true || value === 1;
    } catch (error) {
      return undefined;
    }
  }

  async toggleSwitchByDid(did: string, siid: number, piid: number): Promise<boolean> {
    try {
      return await this.getIOService().toggleSwitch(did, siid, piid);
    } catch (error) {
      return false;
    }
  }

  pollSwitchState(
    did: string,
    siid: number,
    piid: number,
    expectedValue: boolean,
    onResult: (state: boolean | undefined) => void,
    maxPolls: number = 25,
    intervalMs: number = 200
  ): void {
    let pollCount = 0;
    let lastState: boolean | undefined = undefined;
    const poll = async (): Promise<void> => {
      pollCount++;
      try {
        const state = await this.getSwitchStateByDid(did, siid, piid);
        if (pollCount >= maxPolls || (state !== undefined && state === expectedValue)) {
          onResult(state);
          return;
        }
        lastState = state;
      } catch (e) {
        if (pollCount >= maxPolls) {
          onResult(undefined);
          return;
        }
      }
      if (pollCount < maxPolls) {
        setTimeout(poll, intervalMs);
      } else {
        onResult(lastState);
      }
    };
    setTimeout(poll, intervalMs);
  }
}
