import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { GlobalContext } from '../common/GlobalContext';
import { MiToken, UserDevice, protectBigNumbers } from '../mi/types';

const PREFERENCE_NAME = 'MiJiaElevatorPrefs';
const TOKEN_KEY = 'mi_token';
const USER_DEVICES_KEY = 'user_devices';

export class PreferencesUtil {
  private static pref: preferences.Preferences | null = null;

  private static getAppContext(): common.Context {
    const ctx = GlobalContext.getContext();
    const appCtx = ctx.getApplicationContext();
    if (appCtx === undefined || appCtx === null) {
      throw new Error('ApplicationContext not available');
    }
    return appCtx;
  }

  private static async getPref(): Promise<preferences.Preferences> {
    // 主应用与卡片是两个独立进程，内存缓存不共享。
    // 每次先移出缓存强制重读持久化文件，确保跨进程读取到最新数据。
    const appCtx = PreferencesUtil.getAppContext();
    preferences.removePreferencesFromCacheSync(appCtx, PREFERENCE_NAME);
    PreferencesUtil.pref = await preferences.getPreferences(appCtx, PREFERENCE_NAME);
    if (!PreferencesUtil.pref) {
      throw new Error('Preferences not initialized');
    }
    return PreferencesUtil.pref;
  }

  static async init(): Promise<boolean> {
    try {
      await PreferencesUtil.getPref();
      return true;
    } catch (error) {
      console.error('初始化Preferences失败:', error);
      return false;
    }
  }

  static async saveToken(token: MiToken): Promise<boolean> {
    try {
      const pref = await PreferencesUtil.getPref();
      await pref.put(TOKEN_KEY, JSON.stringify(token));
      await pref.flush();
      return true;
    } catch (error) {
      console.error('保存Token失败:', error);
      return false;
    }
  }

  static async getToken(): Promise<MiToken | undefined> {
    try {
      const pref = await PreferencesUtil.getPref();
      const tokenStr = await pref.get(TOKEN_KEY, '');
      if (tokenStr === '') {
        return undefined;
      }
      const safeStr = protectBigNumbers(tokenStr as string);
      return JSON.parse(safeStr) as MiToken;
    } catch (error) {
      console.error('获取Token失败:', error);
      return undefined;
    }
  }

  static async clearToken(): Promise<boolean> {
    try {
      const pref = await PreferencesUtil.getPref();
      await pref.delete(TOKEN_KEY);
      await pref.flush();
      return true;
    } catch (error) {
      console.error('清除Token失败:', error);
      return false;
    }
  }

  static async saveUserDevices(devices: UserDevice[]): Promise<boolean> {
    try {
      const pref = await PreferencesUtil.getPref();
      await pref.put(USER_DEVICES_KEY, JSON.stringify(devices));
      await pref.flush();
      return true;
    } catch (error) {
      console.error('保存设备列表失败:', error);
      return false;
    }
  }

  static async getUserDevices(): Promise<UserDevice[]> {
    try {
      const pref = await PreferencesUtil.getPref();
      const jsonStr = await pref.get(USER_DEVICES_KEY, '');
      if (jsonStr === '') {
        return [];
      }
      const safeStr = protectBigNumbers(jsonStr as string);
      return JSON.parse(safeStr) as UserDevice[];
    } catch (error) {
      console.error('获取设备列表失败:', error);
      return [];
    }
  }

  static async saveStr(key: string, value: string): Promise<boolean> {
    try {
      const pref = await PreferencesUtil.getPref();
      await pref.put(key, value);
      await pref.flush();
      return true;
    } catch (error) {
      console.error('保存字符串失败:', error);
      return false;
    }
  }

  static async getStr(key: string, defaultValue: string = ''): Promise<string> {
    try {
      const pref = await PreferencesUtil.getPref();
      const value = await pref.get(key, defaultValue);
      return String(value);
    } catch (error) {
      console.error('获取字符串失败:', error);
      return defaultValue;
    }
  }

  static async saveJsonArray(key: string, value: string[]): Promise<boolean> {
    return await PreferencesUtil.saveStr(key, JSON.stringify(value));
  }

  static async getJsonArray(key: string): Promise<string[] | undefined> {
    const raw = await PreferencesUtil.getStr(key, '');
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed instanceof Array) {
        const result: string[] = [];
        for (let i = 0; i < parsed.length; i++) {
          result.push(String(parsed[i]));
        }
        return result;
      }
      return undefined;
    } catch (error) {
      return undefined;
    }
  }
}
