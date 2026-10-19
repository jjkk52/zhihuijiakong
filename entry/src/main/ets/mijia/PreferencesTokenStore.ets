import { MiTokenStore } from '../mi/MiTokenStore';
import { MiToken } from '../mi/types';
import { PreferencesUtil } from './PreferencesUtil';

export class PreferencesTokenStore implements MiTokenStore {
  async saveToken(token: MiToken): Promise<boolean> {
    return await PreferencesUtil.saveToken(token);
  }

  async getToken(): Promise<MiToken | undefined> {
    return await PreferencesUtil.getToken();
  }

  async clearToken(): Promise<boolean> {
    return await PreferencesUtil.clearToken();
  }
}
