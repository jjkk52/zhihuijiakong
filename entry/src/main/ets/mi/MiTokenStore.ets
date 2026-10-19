import { MiToken } from './types';

export interface MiTokenStore {
  saveToken(token: MiToken): Promise<boolean>;
  getToken(): Promise<MiToken | undefined>;
  clearToken(): Promise<boolean>;
}
