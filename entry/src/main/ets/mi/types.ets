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
  statusText: string = '\u52A0\u8F7D\u4E2D...';
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

const DEVICE_PROFILES: Record<string, DeviceProfile> = {
  'yeelink.light.light': { icon: DeviceIcon.SpotLight, siid: 2, piid: 1, label: '\u5C04\u706F' } as DeviceProfile,
  'yeelink.light.': { icon: DeviceIcon.Bulb, siid: 2, piid: 1, label: '\u706F' } as DeviceProfile,
  'philips.light.': { icon: DeviceIcon.Bulb, siid: 2, piid: 1, label: '\u706F' } as DeviceProfile,
  'lumi.light.': { icon: DeviceIcon.Bulb, siid: 2, piid: 1, label: '\u706F' } as DeviceProfile,
  'zmowe.light.': { icon: DeviceIcon.Bulb, siid: 2, piid: 1, label: '\u706F' } as DeviceProfile,
  'zerone.switch.lykg1': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'zerone.switch.lykg2': {
    icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173',
    slots: [
      { siid: 2, piid: 1, label: '\u6309\u952E1' } as SwitchSlot,
      { siid: 3, piid: 1, label: '\u6309\u952E2' } as SwitchSlot,
    ]
  } as DeviceProfile,
  'zerone.switch.': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'lumi.switch.acn016': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'lumi.switch.acn017': {
    icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173',
    slots: [
      { siid: 2, piid: 1, label: '\u5DE6\u952E' } as SwitchSlot,
      { siid: 3, piid: 1, label: '\u53F3\u952E' } as SwitchSlot,
    ]
  } as DeviceProfile,
  'lumi.switch.acn018': {
    icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173',
    slots: [
      { siid: 2, piid: 1, label: '\u5DE6\u952E' } as SwitchSlot,
      { siid: 3, piid: 1, label: '\u4E2D\u952E' } as SwitchSlot,
      { siid: 4, piid: 1, label: '\u53F3\u952E' } as SwitchSlot,
    ]
  } as DeviceProfile,
  'zimi.switch.': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'cuco.switch.': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'lumi.switch.': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'zwave.switch.': { icon: DeviceIcon.Switch, siid: 2, piid: 1, label: '\u5F00\u5173' } as DeviceProfile,
  'zhimi.fan.': { icon: DeviceIcon.Fan, siid: 2, piid: 1, label: '\u98CE\u6247' } as DeviceProfile,
  'dmaker.fan.': { icon: DeviceIcon.Fan, siid: 2, piid: 1, label: '\u98CE\u6247' } as DeviceProfile,
  'zhimi.aircondition.': { icon: DeviceIcon.AirConditioner, siid: 2, piid: 1, label: '\u7A7A\u8C03' } as DeviceProfile,
  'zhimi.airpurifier.': { icon: DeviceIcon.AirConditioner, siid: 2, piid: 1, label: '\u51C0\u5316\u5668' } as DeviceProfile,
  'zhimi.humidifier.': { icon: DeviceIcon.Humidifier, siid: 2, piid: 1, label: '\u52A0\u6E7F\u5668' } as DeviceProfile,
  'deerma.humidifier.': { icon: DeviceIcon.Humidifier, siid: 2, piid: 1, label: '\u52A0\u6E7F\u5668' } as DeviceProfile,
  'chuangmi.camera.': { icon: DeviceIcon.Camera, siid: 2, piid: 1, label: '\u6444\u50CF\u5934' } as DeviceProfile,
  'mjsx.camera.': { icon: DeviceIcon.Camera, siid: 2, piid: 1, label: '\u6444\u50CF\u5934' } as DeviceProfile,
  'isa.camera.': { icon: DeviceIcon.Camera, siid: 2, piid: 1, label: '\u6444\u50CF\u5934' } as DeviceProfile,
  'zimi.powerstrip.': { icon: DeviceIcon.Plug, siid: 2, piid: 1, label: '\u63D2\u5EA7' } as DeviceProfile,
  'cuco.plug.': { icon: DeviceIcon.Plug, siid: 2, piid: 1, label: '\u63D2\u5EA7' } as DeviceProfile,
  'lumi.curtain.': { icon: DeviceIcon.Curtain, siid: 2, piid: 1, label: '\u7A97\u5E18' } as DeviceProfile,
  'dooya.curtain.': { icon: DeviceIcon.Curtain, siid: 2, piid: 1, label: '\u7A97\u5E18' } as DeviceProfile,
  'lumi.lock.': { icon: DeviceIcon.LockLight, siid: 2, piid: 1, label: '\u95E8\u9501' } as DeviceProfile,
  'lumi.sensor.': { icon: DeviceIcon.Sensor, siid: 2, piid: 1, label: '\u4F20\u611F\u5668' } as DeviceProfile,
  'lumi.weather.': { icon: DeviceIcon.Sensor, siid: 2, piid: 1, label: '\u4F20\u611F\u5668' } as DeviceProfile,
};

export function getDeviceProfile(model: string): DeviceProfile {
  if (model === undefined || model === null) {
    const defaultProfile = new DeviceProfile();
    defaultProfile.label = '\u8BBE\u5907';
    return defaultProfile;
  }
  const keys = Object.keys(DEVICE_PROFILES);
  for (let i = 0; i < keys.length; i++) {
    if (model.startsWith(keys[i])) {
      const profile = DEVICE_PROFILES[keys[i]];
      profile.known = true;
      return profile;
    }
  }
  const defaultProfile = new DeviceProfile();
  defaultProfile.label = '\u8BBE\u5907';
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
    return '\u23FB';
  }
  if (icon === DeviceIcon.SpotLight) {
    return '\uD83D\uDCA1';
  }
  if (icon === DeviceIcon.LockLight) {
    return '\uD83D\uDD12';
  }
  if (icon === DeviceIcon.Bulb) {
    return '\uD83D\uDD06';
  }
  if (icon === DeviceIcon.Fan) {
    return '\uD83D\uDD04';
  }
  if (icon === DeviceIcon.AirConditioner) {
    return '\u2744';
  }
  if (icon === DeviceIcon.Humidifier) {
    return '\uD83D\uDCA7';
  }
  if (icon === DeviceIcon.Camera) {
    return '\uD83D\uDCF7';
  }
  if (icon === DeviceIcon.Plug) {
    return '\uD83D\uDD0C';
  }
  if (icon === DeviceIcon.Curtain) {
    return '\uD83D\uDECB';
  }
  if (icon === DeviceIcon.Sensor) {
    return '\uD83D\uDD0D';
  }
  if (icon === DeviceIcon.Elevator) {
    return '\uD83D\uDED7';
  }
  if (icon === DeviceIcon.Door) {
    return '\uD83D\uDEAA';
  }
  if (icon === DeviceIcon.Tv) {
    return '\uD83D\uDCFA';
  }
  if (icon === DeviceIcon.Boiler) {
    return '\u2668';
  }
  if (icon === DeviceIcon.Router) {
    return '\uD83D\uDCE1';
  }
  if (icon === DeviceIcon.Alarm) {
    return '\uD83D\uDD14';
  }
  return '\u26A1';
}

export const WIDGET_ENABLED: boolean = true;

export function protectBigNumbers(json: string): string {
  return json.replace(/:\s*(\d{16,})\s*([,}\]])/g, ': "$1"$2');
}
