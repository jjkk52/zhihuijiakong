import { StatusTexts } from '../common/StatusTexts';

export interface MiToken {
  deviceId: string;
  userId: string;
  passToken: string;
  ssecurity: string;
  serviceToken: string;
  expireTime: number;
}

export interface MiDevice {
  did: string;
  name: string;
  model: string;
  token: string;
  online: boolean;
  homeName: string;
  roomName: string;
}

export function getDeviceHomeRoomText(homeName: string, roomName: string): string {
  const home = homeName === undefined || homeName === null ? '' : homeName;
  const room = roomName === undefined || roomName === null ? '' : roomName;
  if (home.length > 0 && room.length > 0) {
    return `${home} · ${room}`;
  }
  if (room.length > 0) {
    return room;
  }
  if (home.length > 0) {
    return home;
  }
  return '';
}

export enum MiOtpMethod {
  Phone,
  Email
}

export interface MiOtpState {
  notificationUrl: string;
  deviceId: string;
  sid: string;
  flag: number;
  method: MiOtpMethod;
  context: string;
}

export interface MiHttpResp {
  result: string;
  headers: Record<string, string>;
}

export enum DeviceIcon {
  Switch,
  SpotLight,
  LockLight,
  Bulb,
  Fan,
  AirConditioner,
  Humidifier,
  Camera,
  Plug,
  Curtain,
  Sensor,
  Generic,
  Elevator,
  Door,
  Tv,
  Boiler,
  Router,
  Alarm
}

export class SwitchSlot {
  siid: number = 2;
  piid: number = 1;
  label: string = '';
}

export class DeviceProfile {
  icon: DeviceIcon = DeviceIcon.Generic;
  siid: number = 2;
  piid: number = 1;
  label: string = '';
  slots: SwitchSlot[] = [];
  known: boolean = false;
}

export class HomeRoom {
  homeName: string = '';
  roomName: string = '';
}

export class UserDevice {
  did: string = '';
  name: string = '';
  alias: string = '';
  model: string = '';
  icon: DeviceIcon = DeviceIcon.Generic;
  siid: number = 2;
  piid: number = 1;
  slotKey: string = '';
  slotLabel: string = '';
  homeName: string = '';
  roomName: string = '';

  static makeSlotKey(did: string, siid: number, piid: number): string {
    return `${did}_${siid}_${piid}`;
  }

  static getSlotKey(ud: UserDevice): string {
    if (ud.slotKey !== undefined && ud.slotKey !== null && ud.slotKey.length > 0) {
      return ud.slotKey;
    }
    return ud.did;
  }

  static getSlotLabel(ud: UserDevice): string {
    if (ud.slotLabel !== undefined && ud.slotLabel !== null && ud.slotLabel.length > 0) {
      return ud.slotLabel;
    }
    return '';
  }

  static getDisplayName(ud: UserDevice): string {
    const alias = ud.alias === undefined || ud.alias === null ? '' : ud.alias;
    const name = ud.name === undefined || ud.name === null ? '' : ud.name;
    if (alias.length > 0) {
      return alias;
    }
    const profile = getDeviceProfile(ud.model);
    if (isMultiSlotProfile(profile)) {
      const label = UserDevice.getSlotLabel(ud);
      if (label.length > 0) {
        return `${name} ${label}`;
      }
    }
    return name;
  }

  static getSourceInfo(ud: UserDevice): string {
    const alias = ud.alias === undefined || ud.alias === null ? '' : ud.alias;
    if (alias.length === 0) {
      return '';
    }
    const profile = getDeviceProfile(ud.model);
    if (isMultiSlotProfile(profile)) {
      const label = UserDevice.getSlotLabel(ud);
      if (label.length > 0) {
        return `${ud.name} · ${label}`;
      }
    }
    return ud.name;
  }

  static getHomeRoomText(ud: UserDevice): string {
    const homeName = ud.homeName === undefined || ud.homeName === null ? '' : ud.homeName;
    const roomName = ud.roomName === undefined || ud.roomName === null ? '' : ud.roomName;
    return getDeviceHomeRoomText(homeName, roomName);
  }
}

export class WidgetFormData {
  isOn: boolean = false;
  isOffline: boolean = false;
  statusText: string = StatusTexts.loading;
  did: string = '';
  siid: number = 2;
  piid: number = 1;
  deviceName: string = '';
  iconType: number = DeviceIcon.Generic;
  dimension: string = '2*2';
}

export class WidgetToggleMessage {
  method: string = '';
  did: string = '';
  siid: number = 2;
  piid: number = 1;
}

export interface MiioPropParam {
  did: string;
  siid: number;
  piid: number;
  value?: number | boolean | string;
}

export interface MiioResultItem {
  did: string;
  siid: number;
  piid: number;
  code: number;
  value: Object | null;
}

export interface MiioResponse {
  code: number;
  message: string;
  result: Object | null;
}

function createSlot(siid: number, piid: number, label: string): SwitchSlot {
  const slot = new SwitchSlot();
  slot.siid = siid;
  slot.piid = piid;
  slot.label = label;
  return slot;
}

function createProfile(icon: DeviceIcon, siid: number, piid: number, label: string, slots?: SwitchSlot[]): DeviceProfile {
  const profile = new DeviceProfile();
  profile.icon = icon;
  profile.siid = siid;
  profile.piid = piid;
  profile.label = label;
  if (slots !== undefined) {
    profile.slots = slots;
  }
  return profile;
}

const DEVICE_PROFILES: Record<string, DeviceProfile> = {
  'yeelink.light.light': createProfile(DeviceIcon.SpotLight, 2, 1, '射灯'),
  'yeelink.light.': createProfile(DeviceIcon.Bulb, 2, 1, '灯'),
  'philips.light.': createProfile(DeviceIcon.Bulb, 2, 1, '灯'),
  'lumi.light.': createProfile(DeviceIcon.Bulb, 2, 1, '灯'),
  'zmowe.light.': createProfile(DeviceIcon.Bulb, 2, 1, '灯'),
  'zerone.switch.lykg1': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'zerone.switch.lykg2': createProfile(DeviceIcon.Switch, 2, 1, '开关', [
    createSlot(2, 1, '按键1'),
    createSlot(3, 1, '按键2')
  ]),
  'zerone.switch.': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'lumi.switch.acn016': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'lumi.switch.acn017': createProfile(DeviceIcon.Switch, 2, 1, '开关', [
    createSlot(2, 1, '左键'),
    createSlot(3, 1, '右键')
  ]),
  'lumi.switch.acn018': createProfile(DeviceIcon.Switch, 2, 1, '开关', [
    createSlot(2, 1, '左键'),
    createSlot(3, 1, '中键'),
    createSlot(4, 1, '右键')
  ]),
  'zimi.switch.': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'cuco.switch.': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'lumi.switch.': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'zwave.switch.': createProfile(DeviceIcon.Switch, 2, 1, '开关'),
  'zhimi.fan.': createProfile(DeviceIcon.Fan, 2, 1, '风扇'),
  'dmaker.fan.': createProfile(DeviceIcon.Fan, 2, 1, '风扇'),
  'zhimi.aircondition.': createProfile(DeviceIcon.AirConditioner, 2, 1, '空调'),
  'zhimi.airpurifier.': createProfile(DeviceIcon.AirConditioner, 2, 1, '净化器'),
  'zhimi.humidifier.': createProfile(DeviceIcon.Humidifier, 2, 1, '加湿器'),
  'deerma.humidifier.': createProfile(DeviceIcon.Humidifier, 2, 1, '加湿器'),
  'chuangmi.camera.': createProfile(DeviceIcon.Camera, 2, 1, '摄像头'),
  'mjsx.camera.': createProfile(DeviceIcon.Camera, 2, 1, '摄像头'),
  'isa.camera.': createProfile(DeviceIcon.Camera, 2, 1, '摄像头'),
  'zimi.powerstrip.': createProfile(DeviceIcon.Plug, 2, 1, '插座'),
  'cuco.plug.': createProfile(DeviceIcon.Plug, 2, 1, '插座'),
  'lumi.curtain.': createProfile(DeviceIcon.Curtain, 2, 1, '窗帘'),
  'dooya.curtain.': createProfile(DeviceIcon.Curtain, 2, 1, '窗帘'),
  'lumi.lock.': createProfile(DeviceIcon.LockLight, 2, 1, '门锁'),
  'lumi.sensor.': createProfile(DeviceIcon.Sensor, 2, 1, '传感器'),
  'lumi.weather.': createProfile(DeviceIcon.Sensor, 2, 1, '传感器')
};

function cloneProfile(profile: DeviceProfile, known: boolean): DeviceProfile {
  const cloned = new DeviceProfile();
  cloned.icon = profile.icon;
  cloned.siid = profile.siid;
  cloned.piid = profile.piid;
  cloned.label = profile.label;
  cloned.known = known;
  const slots: SwitchSlot[] = [];
  for (let i = 0; i < profile.slots.length; i++) {
    slots.push(createSlot(profile.slots[i].siid, profile.slots[i].piid, profile.slots[i].label));
  }
  cloned.slots = slots;
  return cloned;
}

export function getDeviceProfile(model: string): DeviceProfile {
  if (model === undefined || model === null) {
    const defaultProfile = new DeviceProfile();
    defaultProfile.label = '设备';
    return defaultProfile;
  }
  const keys = Object.keys(DEVICE_PROFILES);
  for (let i = 0; i < keys.length; i++) {
    if (model.startsWith(keys[i])) {
      return cloneProfile(DEVICE_PROFILES[keys[i]], true);
    }
  }
  const defaultProfile = new DeviceProfile();
  defaultProfile.label = '设备';
  return defaultProfile;
}

export function isMultiSlotProfile(profile: DeviceProfile): boolean {
  const slots = profile.slots;
  if (slots === undefined || slots === null) {
    return false;
  }
  return slots.length > 1;
}

export function getIconText(icon: DeviceIcon): string {
  if (icon === DeviceIcon.Switch) {
    return '⏻';
  }
  if (icon === DeviceIcon.SpotLight) {
    return '💡';
  }
  if (icon === DeviceIcon.LockLight) {
    return '🔒';
  }
  if (icon === DeviceIcon.Bulb) {
    return '🔆';
  }
  if (icon === DeviceIcon.Fan) {
    return '🔄';
  }
  if (icon === DeviceIcon.AirConditioner) {
    return '❄';
  }
  if (icon === DeviceIcon.Humidifier) {
    return '💧';
  }
  if (icon === DeviceIcon.Camera) {
    return '📷';
  }
  if (icon === DeviceIcon.Plug) {
    return '🔌';
  }
  if (icon === DeviceIcon.Curtain) {
    return '🛋';
  }
  if (icon === DeviceIcon.Sensor) {
    return '🔍';
  }
  if (icon === DeviceIcon.Elevator) {
    return '🛗';
  }
  if (icon === DeviceIcon.Door) {
    return '🚪';
  }
  if (icon === DeviceIcon.Tv) {
    return '📺';
  }
  if (icon === DeviceIcon.Boiler) {
    return '♨';
  }
  if (icon === DeviceIcon.Router) {
    return '📶';
  }
  if (icon === DeviceIcon.Alarm) {
    return '🔔';
  }
  return '⚡';
}

export const WIDGET_ENABLED: boolean = true;

export function protectBigNumbers(json: string): string {
  return json.replace(/:\s*(\d{16,})\s*([,}\]])/g, ': "$1"$2');
}
