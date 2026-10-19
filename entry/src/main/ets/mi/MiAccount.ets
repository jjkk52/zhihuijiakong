import { hilog } from '@kit.PerformanceAnalysisKit';
import { CryptoUtil } from './CryptoUtil';
import { MiHttpTransport } from './MiHttpTransport';
import { MiTokenStore } from './MiTokenStore';
import { MiToken, MiOtpState, MiOtpMethod, MiHttpResp, protectBigNumbers } from './types';
import { MiDebug } from './MiDebug';
import { LoginCooldown } from './LoginCooldown';

const DOMAIN = 0x0200;
const TAG = 'MiAccount';

const ACCOUNT_BASE = 'https://account.xiaomi.com';
const SID = 'xiaomiio';
const JSON_PREFIX = '&&&START&&&';
const SERVICE_TOKEN_TTL_MS = 6 * 60 * 60 * 1000;
const RATE_LIMIT_CODE = 70022;
const LOGIN_RETRY_MAX = 5;
const LOGIN_COOLDOWN_MS = 2 * 60 * 60 * 1000;
const UA_LOGIN = 'APP/com.xiaomi.mihome APPV/11.3.203 iosPassportSDK/4.2.50 iOS/26.3.1 MK/aVBob25lMTcsMg== DEVT/aVBob25l DEVS/aU9T BRA/QXBwbGU= L/zh_CN';
const UA_OTP_TEMPLATE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 iOS/26.3.1 MiHome/11.3.203 iPhone/iPhone17,2 DeviceId/%DEVICEID% APP/com.xiaomi.mihome APPV/11.3.203 Platform/iPhone Region/CN /xiaomi/miuibrowser/4.3/smartHome/ios/iPhone17,2/11.3.203 APP/com.xiaomi.mihome APPV/11.3.203 iosPassportSDK/4.2.50 iOS/26.3.1 MK/aVBob25lMTcsMg== DEVT/aVBob25l DEVS/aU9T BRA/QXBwbGU= L/zh_CN';

class ServiceLoginData {
  _json: string = '';
  qs: string = '';
  sid: string = '';
  _sign: string = '';
  callback: string = '';
  user: string = '';
  hash: string = '';
}

export class MiAccount {
  private username: string;
  private password: string;
  private tokenStore: MiTokenStore;
  private transport: MiHttpTransport = new MiHttpTransport();
  private token: MiToken | null = null;
  private pendingOtp: MiOtpState | null = null;
  private deviceId: string = '';
  private loginCooldown: LoginCooldown = new LoginCooldown(LOGIN_RETRY_MAX, LOGIN_COOLDOWN_MS);

  constructor(username: string, password: string, tokenStore: MiTokenStore) {
    this.username = username;
    this.password = password;
    this.tokenStore = tokenStore;
  }

  getToken(): MiToken | null {
    return this.token;
  }

  isNeedOtp(): boolean {
    return this.pendingOtp !== null;
  }

  invalidateToken(): void {
    this.token = null;
    hilog.info(DOMAIN, TAG, 'invalidateToken');
  }

  importToken(token: MiToken): void {
    this.token = token;
    hilog.info(DOMAIN, TAG, 'importToken userId=%{public}s', token.userId);
  }

  updateCredentials(username: string, password: string): void {
    this.username = username;
    this.password = password;
    hilog.info(DOMAIN, TAG, 'updateCredentials');
  }

  async loadSavedToken(): Promise<boolean> {
    const saved = await this.tokenStore.getToken();
    if (saved !== undefined && this.hasUsableSession(saved)) {
      this.token = saved;
      this.deviceId = saved.deviceId;
      hilog.info(DOMAIN, TAG, 'loadSavedToken userId=%{public}s', saved.userId);
      MiDebug.log('Account', 'loadSavedToken userId=' + saved.userId);
      return true;
    }
    this.token = null;
    hilog.info(DOMAIN, TAG, 'loadSavedToken no usable token');
    return false;
  }

  private hasUsableSession(token: MiToken): boolean {
    try {
      return token.serviceToken.length > 0 && token.passToken.length > 0
        && token.userId.length > 0 && token.deviceId.length > 0;
    } catch (e) {
      return false;
    }
  }

  isServiceTokenStale(): boolean {
    if (this.token === null) {
      return false;
    }
    const expireTime = this.token.expireTime;
    if (typeof expireTime !== 'number' || expireTime <= 0) {
      return true;
    }
    return Date.now() >= expireTime;
  }

  private recordRateLimitFailure(tips: string): void {
    this.loginCooldown.recordFailure(Date.now());
    hilog.warn(DOMAIN, TAG, 'rate limited failures=%{public}d cooldownHours=%{public}d tips=%{public}s',
      this.loginCooldown.getFailures(), this.loginCooldown.remainingHours(Date.now()), tips);
    MiDebug.log('Account', 'rate limited failures=' + String(this.loginCooldown.getFailures()) + ' tips=' + tips);
    throw new Error('\u767B\u5F55\u8BF7\u6C42\u88AB\u9650\u6D41: ' + tips);
  }

  async refreshToken(sid: string): Promise<boolean> {
    if (this.token === null) {
      return false;
    }
    const old = this.token;
    this.deviceId = old.deviceId;
    hilog.info(DOMAIN, TAG, 'refreshToken start userId=%{public}s', old.userId);
    MiDebug.log('Account', 'refreshToken start userId=' + old.userId);
    this.transport.clearCookies();
    try {
      this.loginCooldown.check(Date.now());
      const resp = await this.serviceLogin('serviceLogin?sid=' + sid + '&_json=true', null);
      if (resp['code'] !== 0) {
        const code = Number(resp['code']);
        if (code === RATE_LIMIT_CODE) {
          this.recordRateLimitFailure(String(resp['tips'] ?? ''));
        }
        hilog.warn(DOMAIN, TAG, 'refreshToken rejected, require relogin code=%{public}s', String(resp['code']));
        MiDebug.log('Account', 'refreshToken rejected code=' + String(resp['code']));
        this.token = null;
        this.transport.clearCookies();
        await this.tokenStore.clearToken();
        return false;
      }
      const newUserId = String(resp['userId'] ?? old.userId);
      const respPassToken = String(resp['passToken'] ?? '');
      const newPassToken = respPassToken.length > 0 && respPassToken !== 'undefined' ? respPassToken : old.passToken;
      const location = String(resp['location'] ?? '');
      const nonce = String(resp['nonce'] ?? '');
      const ssecurity = String(resp['ssecurity'] ?? '');
      if (location.length === 0 || nonce.length === 0 || ssecurity.length === 0) {
        hilog.warn(DOMAIN, TAG, 'refreshToken missing sign fields');
        return false;
      }
      const serviceToken = await this.securityTokenService(location, nonce, ssecurity);
      const tk: MiToken = {
        deviceId: this.deviceId,
        userId: newUserId,
        passToken: newPassToken,
        ssecurity: ssecurity,
        serviceToken: serviceToken,
        expireTime: Date.now() + SERVICE_TOKEN_TTL_MS
      };
      this.token = tk;
      await this.tokenStore.saveToken(tk);
      hilog.info(DOMAIN, TAG, 'refreshToken success userId=%{public}s', newUserId);
      MiDebug.log('Account', 'refreshToken OK userId=' + newUserId);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'refreshToken error: %{public}s', String(e));
      MiDebug.log('Account', 'refreshToken error=' + String(e));
      return false;
    }
  }

  async login(sid: string): Promise<MiToken> {
    this.loginCooldown.check(Date.now());
    hilog.info(DOMAIN, TAG, 'login start');
    MiDebug.log('Account', 'login start');
    this.deviceId = CryptoUtil.randomAlphanumeric(16).toUpperCase();
    MiDebug.log('Account', 'deviceId=' + this.deviceId);
    let resp = await this.serviceLogin('serviceLogin?sid=' + sid + '&_json=true', null);
    if (resp['code'] !== 0) {
      if (Number(resp['code']) === RATE_LIMIT_CODE) {
        this.recordRateLimitFailure(String(resp['tips'] ?? ''));
      }
      const hash = await CryptoUtil.md5HexUpper(this.password);
      const data = new ServiceLoginData();
      data._json = 'true';
      data.qs = String(resp['qs']);
      data.sid = String(resp['sid']);
      data._sign = String(resp['_sign']);
      data.callback = String(resp['callback']);
      data.user = this.username;
      data.hash = hash;
      resp = await this.serviceLogin('serviceLoginAuth2', data);
      hilog.info(DOMAIN, TAG, 'serviceLoginAuth2 code=%{public}s location=%{public}s notificationUrl=%{public}s desc=%{public}s',
        String(resp['code']), String(resp['location'] ?? '').substring(0, 100),
        String(resp['notificationUrl'] ?? '').substring(0, 80),
        String(resp['desc'] ?? resp['description'] ?? ''));
      if (resp['notificationUrl']) {
        hilog.info(DOMAIN, TAG, 'OTP required, notificationUrl=%{public}s', String(resp['notificationUrl']).substring(0, 80));
        const ntfUrl = String(resp['notificationUrl']);
        const fullNtfUrl = ntfUrl.startsWith('http') ? ntfUrl : ACCOUNT_BASE + ntfUrl;
        await this.transport.request(fullNtfUrl, 'GET', null, { 'User-Agent': this.buildOtpUa() }, { 'deviceId': this.deviceId });
        const ntfParams = this.parseUrlQuery(fullNtfUrl);
        const ctx = ntfParams['context'] ?? '';
        const idataUrl = ACCOUNT_BASE + '/identity/list?sid=' + sid + '&supportedMask=0&_locale=zh_CN&context=' + encodeURIComponent(ctx);
        const idataResp = await this.transport.request(idataUrl, 'GET', null, { 'User-Agent': this.buildOtpUa() }, { 'deviceId': this.deviceId });
        const idata = this.parseLoginResp(idataResp);
        const flag = (idata['flag'] as number) ?? 4;
        const otpMethod = flag === 8 ? MiOtpMethod.Email : MiOtpMethod.Phone;
        hilog.info(DOMAIN, TAG, 'OTP method=%{public}s flag=%{public}d', String(otpMethod), flag);
        const triggerUrl = ACCOUNT_BASE + '/identity/auth/verify' + (otpMethod === MiOtpMethod.Email ? 'Email' : 'Phone') + '?_flag=' + flag + '&_json=true';
        await this.transport.request(triggerUrl, 'GET', null, { 'User-Agent': this.buildOtpUa() }, { 'deviceId': this.deviceId });
        if (otpMethod === MiOtpMethod.Phone) {
          const sendUrl = ACCOUNT_BASE + '/identity/auth/sendPhoneTicket';
          const sendData = 'retry=0&icode=&_json=true';
          const sendResp = await this.transport.request(sendUrl, 'POST', sendData, { 'User-Agent': this.buildOtpUa(), 'Content-Type': 'application/x-www-form-urlencoded' }, { 'deviceId': this.deviceId });
          const sendJson = this.parseLoginResp(sendResp);
          const sendCode = (sendJson['code'] as number) ?? -1;
          if (sendCode !== 0 && sendCode !== null) {
            const tips = String(sendJson['tips'] ?? sendJson['desc'] ?? '');
            hilog.error(DOMAIN, TAG, 'sendPhoneTicket failed code=%{public}d tips=%{public}s', sendCode, tips);
            throw new Error('\u53D1\u9001\u9A8C\u8BC1\u7801\u5931\u8D25(code=' + String(sendCode) + '): ' + tips);
          }
          hilog.info(DOMAIN, TAG, 'OTP SMS sent successfully');
        }
        const otp: MiOtpState = {
          notificationUrl: String(resp['notificationUrl']),
          deviceId: this.deviceId,
          sid: sid,
          flag: flag,
          method: otpMethod,
          context: ctx
        };
        this.pendingOtp = otp;
        throw new Error('\u9700\u8981\u77ED\u4FE1\u9A8C\u8BC1\u7801');
      }
      if (resp['code'] !== 0) {
        throw new Error('\u767B\u5F55\u5931\u8D25: ' + (String(resp['desc'] ?? JSON.stringify(resp))));
      }
    }
    const userId = String(resp['userId']);
    const passToken = String(resp['passToken']);
    const location = String(resp['location']);
    const nonce = String(resp['nonce']);
    const ssecurity = String(resp['ssecurity']);
    const serviceToken = await this.securityTokenService(location, nonce, ssecurity);
    const tk: MiToken = {
      deviceId: this.deviceId,
      userId: userId,
      passToken: passToken,
      ssecurity: ssecurity,
      serviceToken: serviceToken,
      expireTime: Date.now() + SERVICE_TOKEN_TTL_MS
    };
    this.token = tk;
    await this.tokenStore.saveToken(tk);
    hilog.info(DOMAIN, TAG, 'login success, userId=%{public}s', userId);
    MiDebug.log('Account', 'login OK userId=' + userId);
    return tk;
  }

  async loginWithOtp(otp: string): Promise<MiToken> {
    if (!this.pendingOtp) {
      throw new Error('\u65E0\u5F85\u9A8C\u8BC1\u7684OTP\u8BF7\u6C42');
    }
    const deviceId = this.pendingOtp.deviceId;
    const sid = this.pendingOtp.sid;
    const flag = this.pendingOtp.flag;
    const otpMethod = this.pendingOtp.method;
    const otpMethodStr = otpMethod === MiOtpMethod.Email ? 'Email' : 'Phone';
    this.deviceId = deviceId;
    hilog.info(DOMAIN, TAG, 'loginWithOtp otp=%{public}s method=%{public}s', otp.substring(0, 2) + '***', otpMethodStr);
    const dc = Date.now();
    const verifyUrl = ACCOUNT_BASE + '/identity/auth/verify' + otpMethodStr + '?_dc=' + dc;
    const verifyData = '_flag=' + flag + '&ticket=' + encodeURIComponent(otp) + '&trust=false&_json=true';
    const verifyResp = await this.transport.request(verifyUrl, 'POST', verifyData, { 'User-Agent': this.buildOtpUa(), 'Content-Type': 'application/x-www-form-urlencoded' }, { 'deviceId': deviceId });
    const vresp = this.parseLoginResp(verifyResp);
    hilog.info(DOMAIN, TAG, 'verifyOtp code=%{public}s location=%{public}s', String(vresp['code'] ?? ''), String(vresp['location'] ?? '').substring(0, 80));
    const vLocation = vresp['location'];
    if (!vLocation || String(vLocation).length === 0 || String(vLocation) === 'undefined') {
      const code = vresp['code'];
      const desc = vresp['desc'] ?? vresp['description'] ?? '';
      throw new Error('\u9A8C\u8BC1\u7801\u9A8C\u8BC1\u5931\u8D25(code=' + String(code) + '): ' + String(desc));
    }
    let location = String(vLocation);
    if (!location.startsWith('http')) {
      location = ACCOUNT_BASE + location;
    }
    await this.transport.request(location, 'GET', null, { 'User-Agent': this.buildOtpUa() }, { 'deviceId': deviceId });
    const resp = await this.serviceLogin('serviceLogin?sid=' + sid + '&_json=true', null);
    if (resp['code'] !== 0) {
      throw new Error('OTP\u9A8C\u8BC1\u540E\u767B\u5F55\u5931\u8D25: ' + JSON.stringify(resp));
    }
    const userId = String(resp['userId']);
    const passToken = String(resp['passToken']);
    const ssecurity = String(resp['ssecurity']);
    const nonce = String(resp['nonce']);
    const respLocation = String(resp['location']);
    const serviceToken = await this.securityTokenService(respLocation, nonce, ssecurity);
    const tk: MiToken = {
      deviceId: this.deviceId,
      userId: userId,
      passToken: passToken,
      ssecurity: ssecurity,
      serviceToken: serviceToken,
      expireTime: Date.now() + SERVICE_TOKEN_TTL_MS
    };
    this.token = tk;
    await this.tokenStore.saveToken(tk);
    this.pendingOtp = null;
    hilog.info(DOMAIN, TAG, 'loginWithOtp success, userId=%{public}s', userId);
    MiDebug.log('Account', 'loginWithOtp OK userId=' + userId);
    return tk;
  }

  async resendOtp(): Promise<void> {
    if (!this.pendingOtp) {
      throw new Error('\u65E0\u5F85\u9A8C\u8BC1\u7684OTP\u8BF7\u6C42');
    }
    const otpMethodStr = this.pendingOtp.method === MiOtpMethod.Email ? 'Email' : 'Phone';
    const flag = this.pendingOtp.flag;
    const triggerUrl = ACCOUNT_BASE + '/identity/auth/verify' + otpMethodStr + '?_flag=' + flag + '&_json=true';
    await this.transport.request(triggerUrl, 'GET', null, { 'User-Agent': this.buildOtpUa() }, { 'deviceId': this.pendingOtp.deviceId });
    if (this.pendingOtp.method === MiOtpMethod.Phone) {
      const sendUrl = ACCOUNT_BASE + '/identity/auth/sendPhoneTicket';
      const sendData = 'retry=0&icode=&_json=true';
      const sendResp = await this.transport.request(sendUrl, 'POST', sendData, { 'User-Agent': this.buildOtpUa(), 'Content-Type': 'application/x-www-form-urlencoded' }, { 'deviceId': this.pendingOtp.deviceId });
      const sendJson = this.parseLoginResp(sendResp);
      const sendCode = (sendJson['code'] as number) ?? -1;
      if (sendCode !== 0 && sendCode !== null) {
        const tips = String(sendJson['tips'] ?? sendJson['desc'] ?? '');
        throw new Error('\u53D1\u9001\u9A8C\u8BC1\u7801\u5931\u8D25(code=' + String(sendCode) + '): ' + tips);
      }
    }
  }

  async logout(): Promise<void> {
    this.token = null;
    this.pendingOtp = null;
    this.transport.clearCookies();
    await this.tokenStore.clearToken();
    hilog.info(DOMAIN, TAG, 'logout');
  }

  private async serviceLogin(uri: string, data: ServiceLoginData | null): Promise<Record<string, Object>> {
    const url = ACCOUNT_BASE + '/pass/' + uri;
    const headers: Record<string, string> = { 'User-Agent': UA_LOGIN };
    const cookies: Record<string, string> = {
      'sdkVersion': '3.9',
      'deviceId': this.deviceId
    };
    if (this.token !== null && this.token.passToken.length > 0) {
      cookies['userId'] = this.token.userId;
      cookies['passToken'] = this.token.passToken;
    }
    let body: string | null = null;
    let method = 'GET';
    if (data !== null) {
      method = 'POST';
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      body = this.buildFormDataFromClass(data);
    }
    const resp = await this.transport.request(url, method, body, headers, cookies);
    return this.parseLoginResp(resp);
  }

  private async securityTokenService(location: string, nonce: string, ssecurity: string): Promise<string> {
    const nsec = 'nonce=' + nonce + '&' + ssecurity;
    const clientSign = await CryptoUtil.sha1Base64(nsec);
    const url = location + '&clientSign=' + encodeURIComponent(clientSign);
    hilog.info(DOMAIN, TAG, 'securityTokenService url=%{public}s', url.substring(0, 120));
    const headers: Record<string, string> = { 'User-Agent': UA_LOGIN };
    const resp = await this.transport.request(url, 'GET', null, headers, {} as Record<string, string>);
    const serviceTokenFromCookie = this.transport.getCookie('serviceToken');
    if (serviceTokenFromCookie.length > 0) {
      hilog.info(DOMAIN, TAG, 'securityTokenService found in cookie len=%{public}d', serviceTokenFromCookie.length);
      return serviceTokenFromCookie;
    }
    const setCookie = resp.headers['set-cookie'] ?? resp.headers['Set-Cookie'] ?? '';
    hilog.info(DOMAIN, TAG, 'securityTokenService set-cookie len=%{public}d', setCookie.length);
    const match = setCookie.match(/serviceToken=([^;]+)/);
    if (match) {
      hilog.info(DOMAIN, TAG, 'securityTokenService found in set-cookie len=%{public}d', match[1].length);
      return match[1];
    }
    try {
      const body = this.parseLoginResp(resp);
      if (body['serviceToken']) {
        return String(body['serviceToken']);
      }
      if (body['token']) {
        return String(body['token']);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'securityTokenService parse body error: %{public}s', String(e));
    }
    throw new Error('\u65E0\u6CD5\u83B7\u53D6serviceToken');
  }

  private buildOtpUa(): string {
    let deviceId = this.deviceId;
    if (deviceId.length === 0 && this.pendingOtp !== null) {
      deviceId = this.pendingOtp.deviceId;
    }
    return UA_OTP_TEMPLATE.replace('%DEVICEID%', deviceId);
  }

  private parseLoginResp(resp: MiHttpResp): Record<string, Object> {
    let text = resp.result;
    if (text.startsWith(JSON_PREFIX)) {
      text = text.substring(JSON_PREFIX.length);
    }
    text = protectBigNumbers(text);
    return JSON.parse(text) as Record<string, Object>;
  }

  private buildFormDataFromClass(data: ServiceLoginData): string {
    const pairs: string[] = [];
    pairs.push(encodeURIComponent('_json') + '=' + encodeURIComponent(data._json));
    pairs.push(encodeURIComponent('qs') + '=' + encodeURIComponent(data.qs));
    pairs.push(encodeURIComponent('sid') + '=' + encodeURIComponent(data.sid));
    pairs.push(encodeURIComponent('_sign') + '=' + encodeURIComponent(data._sign));
    pairs.push(encodeURIComponent('callback') + '=' + encodeURIComponent(data.callback));
    pairs.push(encodeURIComponent('user') + '=' + encodeURIComponent(data.user));
    pairs.push(encodeURIComponent('hash') + '=' + encodeURIComponent(data.hash));
    return pairs.join('&');
  }

  private parseUrlQuery(url: string): Record<string, string> {
    const result: Record<string, string> = {} as Record<string, string>;
    const queryStart = url.indexOf('?');
    if (queryStart < 0) {
      return result;
    }
    const query = url.substring(queryStart + 1);
    const pairs = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      const eq = pairs[i].indexOf('=');
      if (eq > 0) {
        const key = decodeURIComponent(pairs[i].substring(0, eq));
        const value = decodeURIComponent(pairs[i].substring(eq + 1));
        result[key] = value;
      }
    }
    return result;
  }
}
