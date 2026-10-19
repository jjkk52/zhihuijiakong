import { hilog } from '@kit.PerformanceAnalysisKit';
import { MiAccount } from '../mi/MiAccount';
import { MiIOService } from '../mi/MiIOService';
import { MiTokenStore } from '../mi/MiTokenStore';
import { MiToken } from '../mi/types';
import { AssetTokenStore } from './AssetTokenStore';

const DOMAIN = 0x0200;
const TAG = 'MiAuthService';
const SID_IO = 'xiaomiio';

export class MiAuthService {
  private static instance: MiAuthService | null = null;
  private account: MiAccount;
  private ioService: MiIOService;
  private tokenStore: MiTokenStore;

  static getInstance(): MiAuthService {
    if (!MiAuthService.instance) {
      MiAuthService.instance = new MiAuthService();
    }
    return MiAuthService.instance;
  }

  constructor() {
    this.tokenStore = new AssetTokenStore();
    this.account = new MiAccount('', '', this.tokenStore);
    this.ioService = new MiIOService(this.account);
  }

  getIOService(): MiIOService {
    return this.ioService;
  }

  configure(username: string, password: string): void {
    if (this.account.isNeedOtp()) {
      this.account.updateCredentials(username, password);
    } else {
      this.account = new MiAccount(username, password, this.tokenStore);
      this.ioService = new MiIOService(this.account);
    }
  }

  async login(username: string, password: string): Promise<MiToken> {
    this.configure(username, password);
    const token = await this.account.login(SID_IO);
    return token;
  }

  async loginWithOtp(otp: string): Promise<MiToken> {
    const token = await this.account.loginWithOtp(otp);
    return token;
  }

  async checkLoginStatus(): Promise<boolean> {
    const loaded = await this.account.loadSavedToken();
    if (!loaded) {
      return false;
    }
    if (this.account.isServiceTokenStale()) {
      hilog.info(DOMAIN, TAG, 'serviceToken stale, silent refresh');
      const refreshed = await this.account.refreshToken(SID_IO);
      if (refreshed) {
        this.ioService = new MiIOService(this.account);
      }
    }
    return this.account.getToken() !== null;
  }

  async resendOtp(): Promise<void> {
    await this.account.resendOtp();
  }

  async logout(): Promise<void> {
    await this.account.logout();
  }

  async clearCache(): Promise<void> {
    this.ioService.clearCache();
  }

}
