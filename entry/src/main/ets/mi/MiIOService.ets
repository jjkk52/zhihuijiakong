import { hilog } from '@kit.PerformanceAnalysisKit';
import { CryptoUtil } from './CryptoUtil';
import { MiHttpTransport } from './MiHttpTransport';
import { MiAccount } from './MiAccount';
import { MiDevice, MiioPropParam, MiioResultItem, MiioResponse, MiHttpResp, HomeRoom, MiToken, protectBigNumbers } from './types';
import { MiDebug } from './MiDebug';
import { MiAuthError, MSG_AUTH_EXPIRED, MSG_NOT_LOGGED_IN } from './MiErrors';
import { PreferencesUtil } from '../mijia/PreferencesUtil';

const DOMAIN = 0x0200;
const TAG = 'MiIOService';

const API_BASE = 'https://api.io.mi.com/app';
const SID_IO = 'xiaomiio';
const JSON_PREFIX = '&&&START&&&';
const SPEC_INSTANCES_URL = 'https://miot-spec.org/miot-spec-v2/instances?status=all';
const SPEC_INSTANCE_URL_PREFIX = 'https://miot-spec.org/miot-spec-v2/instance?type=';

class MiioPropGetReq {
  params: MiioPropParam[] = [];
}

class MiioPropSetReq {
  params: MiioPropParam[] = [];
}

function isSplitDeviceDid(did: string): boolean {
  const idx = did.lastIndexOf('.s');
  if (idx <= 0) {
    return false;
  }
  let i = idx + 2;
  if (i >= did.length) {
    return false;
  }
  while (i < did.length) {
    const c = did.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
    i++;
  }
  return true;
}

export class MiIOService {
  private account: MiAccount;
  private transport: MiHttpTransport = new MiHttpTransport();
  private switchSiidCache: Record<string, number[]> = {};
  private modelUrnMap: Record<string, string> = {};
  private specInstancesLoaded: boolean = false;
  private homeListCache: Object[] | null = null;
  private shareHomeListCache: Object[] | null = null;
  private roomMapCache: Record<string, HomeRoom> | null = null;
  private homeListCacheTime: number = 0;

  constructor(account: MiAccount) {
    this.account = account;
  }

  clearCache(): void {
    this.homeListCache = null;
    this.shareHomeListCache = null;
    this.roomMapCache = null;
    this.homeListCacheTime = 0;
    this.switchSiidCache = {};
  }

  async miioRequest(uri: string, data: Object): Promise<Object> {
    hilog.info(DOMAIN, TAG, 'miioRequest uri=%{public}s', uri);
    const currentToken = this.account.getToken();
    if (currentToken === null) {
      throw new MiAuthError(MSG_NOT_LOGGED_IN);
    }
    hilog.info(DOMAIN, TAG, 'miioRequest userId=%{public}s', currentToken.userId);
    MiDebug.log('MiIO', 'miioRequest uri=' + uri);
    let respJson = await this.sendMiioRequest(uri, data, currentToken);
    if (this.isAuthError(respJson)) {
      hilog.warn(DOMAIN, TAG, 'miioRequest auth error, try silent refresh uri=%{public}s', uri);
      MiDebug.log('MiIO', 'auth error, silent refresh uri=' + uri);
      const refreshed = await this.account.refreshToken(SID_IO);
      const newToken = this.account.getToken();
      if (newToken === null) {
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
      if (!refreshed) {
        throw new Error('\u767B\u5F55\u72B6\u6001\u6821\u9A8C\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u7F51\u7EDC\u540E\u91CD\u8BD5');
      }
      respJson = await this.sendMiioRequest(uri, data, newToken);
      if (this.isAuthError(respJson)) {
        await this.account.invalidateToken();
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
    }
    const code = respJson.code;
    if (code !== 0) {
      if (this.isAuthError(respJson)) {
        await this.account.invalidateToken();
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
      throw new Error('MiIO\u8BF7\u6C42\u5931\u8D25: ' + JSON.stringify(respJson));
    }
    if (!respJson.result) {
      throw new Error('MiIO\u54CD\u5E94\u7F3A\u5C11result: ' + JSON.stringify(respJson));
    }
    return respJson.result;
  }

  private async sendMiioRequest(uri: string, data: Object, token: MiToken): Promise<MiioResponse> {
    const url = API_BASE + uri;
    const signedData = await this.signData(uri, data, token.ssecurity);
    const body = this.buildFormDataFromRecord(signedData);
    const headers: Record<string, string> = {
      'User-Agent': this.buildUaMiio(token),
      'x-xiaomi-protocal-flag-cli': 'PROTOCAL-HTTP2',
      'Content-Type': 'application/x-www-form-urlencoded'
    };
    const cookies: Record<string, string> = {
      'userId': token.userId,
      'serviceToken': token.serviceToken,
      'PassportDeviceId': token.deviceId
    };
    const resp = await this.transport.request(url, 'POST', body, headers, cookies);
    return this.parseJsonResp(resp);
  }

  private buildUaMiio(token: MiToken): string {
    return 'iOS-14.4-6.0.103-iPhone12,3--' + token.deviceId + '-' + token.userId + '-84A3F44E137B71AE-iPhone';
  }

  private isAuthError(respJson: MiioResponse): boolean {
    if (respJson.code === 0) {
      return false;
    }
    if (respJson.code === 401 || respJson.code === 403) {
      return true;
    }
    const message = String(respJson.message ?? '').toLowerCase();
    return message.includes('auth') || message.includes('unauthorized') || message.includes('signature');
  }

  async getDeviceList(): Promise<MiDevice[]> {
    hilog.info(DOMAIN, TAG, 'getDeviceList start');
    const dids = await this.getHomeDids();
    let list: Object[] = [];
    if (dids.length > 0) {
      const pageSize = 50;
      for (let i = 0; i < dids.length; i += pageSize) {
        const batch = dids.slice(i, i + pageSize);
        const payload: Record<string, Object> = {} as Record<string, Object>;
        payload['getVirtualModel'] = true;
        payload['getHuamiDevices'] = 0;
        payload['get_split_device'] = false;
        payload['support_smart_home'] = true;
        payload['limit'] = 200;
        payload['dids'] = batch;
        const result = await this.miioRequest('/v2/home/device_list_page', payload) as Record<string, Object>;
        const page = (result['list'] as Object[]) ?? [];
        list = list.concat(page);
      }
    } else {
      const reqParams: Record<string, Object> = {} as Record<string, Object>;
      reqParams['getVirtualModel'] = true;
      reqParams['getHuamiDevices'] = 0;
      const result = await this.miioRequest('/home/device_list', reqParams) as Record<string, Object>;
      list = (result['list'] as Object[]) ?? [];
    }
    const devices: MiDevice[] = [];
    for (let i = 0; i < list.length; i++) {
      const d = list[i] as Record<string, Object>;
      const did = String(d['did'] ?? '');
      if (isSplitDeviceDid(did)) {
        continue;
      }
      const dev: MiDevice = {
        did: did,
        name: String(d['name']),
        model: String(d['model'] ?? ''),
        online: Boolean(d['isOnline'] ?? true),
        token: String(d['token'] ?? ''),
        homeName: '',
        roomName: ''
      };
      devices.push(dev);
    }
    hilog.info(DOMAIN, TAG, 'getDeviceList count=%{public}d', devices.length);
    return devices;
  }

  private async getHomeDids(): Promise<string[]> {
    const homes = await this.getHomeList();
    const dids: string[] = [];
    const seen: Record<string, boolean> = {} as Record<string, boolean>;
    for (let i = 0; i < homes.length; i++) {
      const home = homes[i] as Record<string, Object>;
      const homeDids = (home['dids'] as Object[]) ?? [];
      for (let j = 0; j < homeDids.length; j++) {
        const did = String(homeDids[j]);
        if (did.length > 0 && seen[did] === undefined) {
          seen[did] = true;
          dids.push(did);
        }
      }
      const roomlist = (home['roomlist'] as Object[]) ?? [];
      for (let j = 0; j < roomlist.length; j++) {
        const room = roomlist[j] as Record<string, Object>;
        const roomDids = (room['dids'] as Object[]) ?? [];
        for (let k = 0; k < roomDids.length; k++) {
          const did = String(roomDids[k]);
          if (did.length > 0 && seen[did] === undefined) {
            seen[did] = true;
            dids.push(did);
          }
        }
      }
    }
    return dids;
  }

  private async getHomeList(): Promise<Object[]> {
    const now = Date.now();
    if (this.homeListCache !== null && (now - this.homeListCacheTime) < 60000) {
      return this.homeListCache;
    }
    const reqParams: Record<string, Object> = this.buildGetHomeParams();
    const result = await this.miioRequest('/v2/homeroom/gethome', reqParams) as Record<string, Object>;
    const homelist = (result['homelist'] as Object[]) ?? [];
    const shareHomeList = (result['share_home_list'] as Object[]) ?? [];
    const merged = homelist.concat(shareHomeList);
    this.homeListCache = merged;
    this.shareHomeListCache = shareHomeList;
    this.homeListCacheTime = now;
    this.roomMapCache = null;
    return merged;
  }

  async getDeviceListByHome(homeId: string): Promise<MiDevice[]> {
    hilog.info(DOMAIN, TAG, 'getDeviceListByHome homeId=%{public}s', homeId);
    const payload: Record<string, Object> = {} as Record<string, Object>;
    payload['getVirtualModel'] = true;
    payload['getHuamiDevices'] = 0;
    payload['homeId'] = homeId;
    const result = await this.miioRequest('/home/device_list', payload) as Record<string, Object>;
    const list = (result['list'] as Object[]) ?? [];
    hilog.info(DOMAIN, TAG, 'getDeviceListByHome raw count=%{public}d', list.length);
    const devices: MiDevice[] = [];
    for (let i = 0; i < list.length; i++) {
      const d = list[i] as Record<string, Object>;
      const dev: MiDevice = {
        did: String(d['did']),
        name: String(d['name']),
        model: String(d['model'] ?? ''),
        online: Boolean(d['isOnline'] ?? true),
        token: String(d['token'] ?? ''),
        homeName: '',
        roomName: ''
      };
      devices.push(dev);
    }
    return devices;
  }

  async getHomeRooms(): Promise<Record<string, HomeRoom>> {
    if (this.roomMapCache !== null) {
      return this.roomMapCache;
    }
    hilog.info(DOMAIN, TAG, 'getHomeRooms start');
    const homes = await this.getHomeList();
    hilog.info(DOMAIN, TAG, 'getHomeRooms homes=%{public}d', homes.length);
    const map: Record<string, HomeRoom> = {};
    for (let i = 0; i < homes.length; i++) {
      const home = homes[i] as Record<string, Object>;
      const homeName = String(home['name'] ?? '');
      const roomlist = (home['roomlist'] as Object[]) ?? [];
      for (let j = 0; j < roomlist.length; j++) {
        const room = roomlist[j] as Record<string, Object>;
        const roomName = String(room['name'] ?? '');
        const dids = (room['dids'] as Object[]) ?? [];
        for (let k = 0; k < dids.length; k++) {
          const hr = new HomeRoom();
          hr.homeName = homeName;
          hr.roomName = roomName;
          map[String(dids[k])] = hr;
        }
      }
    }
    this.roomMapCache = map;
    hilog.info(DOMAIN, TAG, 'getHomeRooms count=%{public}d', Object.keys(map).length);
    return map;
  }

  async getShareHomeIds(): Promise<string[]> {
    const now = Date.now();
    let shareHomeList: Object[];
    if (this.shareHomeListCache !== null && (now - this.homeListCacheTime) < 60000) {
      shareHomeList = this.shareHomeListCache;
    } else {
      const reqParams: Record<string, Object> = this.buildGetHomeParams();
      const result = await this.miioRequest('/v2/homeroom/gethome', reqParams) as Record<string, Object>;
      shareHomeList = (result['share_home_list'] as Object[]) ?? [];
    }
    const ids: string[] = [];
    for (let i = 0; i < shareHomeList.length; i++) {
      const home = shareHomeList[i] as Record<string, Object>;
      const id = String(home['id'] ?? '');
      if (id.length > 0) {
        ids.push(id);
      }
    }
    hilog.info(DOMAIN, TAG, 'getShareHomeIds count=%{public}d', ids.length);
    return ids;
  }

  async getDeviceSwitchSiids(model: string): Promise<number[]> {
    const cached = this.switchSiidCache[model];
    if (cached !== undefined) {
      return cached;
    }
    try {
      const persisted = await PreferencesUtil.getJsonArray('switch_siids_' + model);
      if (persisted !== undefined) {
        const siids: number[] = [];
        for (let i = 0; i < persisted.length; i++) {
          siids.push(Number(persisted[i]));
        }
        this.switchSiidCache[model] = siids;
        return siids;
      }
      if (!this.specInstancesLoaded) {
        await this.loadSpecInstances();
      }
      const urn = this.modelUrnMap[model];
      if (urn === undefined || urn.length === 0) {
        return [];
      }
      const spec = await this.httpGetJson(SPEC_INSTANCE_URL_PREFIX + encodeURIComponent(urn));
      const services = (spec['services'] as Object[]) ?? [];
      const siids: number[] = [];
      for (let i = 0; i < services.length; i++) {
        const svc = services[i] as Record<string, Object>;
        const type = String(svc['type'] ?? '');
        if (type.includes('service:switch:')) {
          const iid = svc['iid'];
          if (typeof iid === 'number') {
            siids.push(iid);
          }
        }
      }
      this.switchSiidCache[model] = siids;
      await PreferencesUtil.saveJsonArray('switch_siids_' + model, siids.map((v: number) => String(v)));
      hilog.info(DOMAIN, TAG, 'getDeviceSwitchSiids model=%{public}s count=%{public}d', model, siids.length);
      return siids;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getDeviceSwitchSiids failed: %{public}s', String(e));
      return [];
    }
  }

  private async loadSpecInstances(): Promise<void> {
    const data = await this.httpGetJson(SPEC_INSTANCES_URL);
    const instances = (data['instances'] as Object[]) ?? [];
    for (let i = 0; i < instances.length; i++) {
      const inst = instances[i] as Record<string, Object>;
      const model = String(inst['model'] ?? '');
      const urn = String(inst['type'] ?? '');
      if (model.length > 0 && urn.length > 0) {
        this.modelUrnMap[model] = urn;
      }
    }
    this.specInstancesLoaded = true;
    hilog.info(DOMAIN, TAG, 'loadSpecInstances count=%{public}d', Object.keys(this.modelUrnMap).length);
  }

  private buildGetHomeParams(): Record<string, Object> {
    const params: Record<string, Object> = {} as Record<string, Object>;
    params['limit'] = 150;
    params['fetch_share'] = true;
    params['fetch_share_dev'] = true;
    params['plat_form'] = 0;
    params['app_ver'] = 9;
    return params;
  }

  private async httpGetJson(url: string): Promise<Record<string, Object>> {
    const resp = await this.transport.request(url, 'GET', null, {} as Record<string, string>, {} as Record<string, string>);
    return JSON.parse(protectBigNumbers(resp.result)) as Record<string, Object>;
  }

  async getProperty(did: string, siid: number, piid: number): Promise<number | boolean | string | null> {
    hilog.info(DOMAIN, TAG, 'getProperty did=%{public}s siid=%{public}d piid=%{public}d', did, siid, piid);
    const param: MiioPropParam = { did: did, siid: siid, piid: piid };
    const req = new MiioPropGetReq();
    req.params = [param];
    const result = await this.miioRequest('/miotspec/prop/get', req);
    const arr = result as MiioResultItem[];
    if (arr && arr.length > 0) {
      if (arr[0].code === 401 || arr[0].code === 403) {
        await this.account.invalidateToken();
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
      if (arr[0].code === 0) {
        return arr[0].value as number | boolean | string;
      }
    }
    return null;
  }

  async getProperties(params: MiioPropParam[]): Promise<MiioResultItem[]> {
    hilog.info(DOMAIN, TAG, 'getProperties count=%{public}d', params.length);
    const req = new MiioPropGetReq();
    req.params = params;
    const result = await this.miioRequest('/miotspec/prop/get', req);
    const arr = result as MiioResultItem[];
    for (let i = 0; i < arr.length; i++) {
      if (arr[i].code === 401 || arr[i].code === 403) {
        await this.account.invalidateToken();
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
    }
    return arr;
  }

  async setProperty(did: string, siid: number, piid: number, value: number | boolean | string): Promise<boolean> {
    hilog.info(DOMAIN, TAG, 'setProperty did=%{public}s siid=%{public}d piid=%{public}d value=%{public}s', did, siid, piid, String(value));
    const param: MiioPropParam = { did: did, siid: siid, piid: piid, value: value };
    const req = new MiioPropSetReq();
    req.params = [param];
    const result = await this.miioRequest('/miotspec/prop/set', req);
    const arr = result as MiioResultItem[];
    if (arr && arr.length > 0) {
      if (arr[0].code === 401 || arr[0].code === 403) {
        await this.account.invalidateToken();
        throw new MiAuthError(MSG_AUTH_EXPIRED);
      }
      return arr[0].code === 0 || arr[0].code === 1;
    }
    return false;
  }

  async toggleSwitch(did: string, siid: number, piid: number): Promise<boolean | null> {
    const currentValue = await this.getProperty(did, siid, piid);
    if (currentValue === null) {
      throw new Error('无法获取当前状态，不能翻转');
    }
    const newValue = !currentValue;
    const ok = await this.setProperty(did, siid, piid, newValue);
    return ok ? newValue : null;
  }

  private async signData(uri: string, data: Object, ssecurity: string): Promise<Record<string, string>> {
    const dataStr = JSON.stringify(data);
    const randomBytes = CryptoUtil.randomBytes(8);
    const timeMinutes = Math.floor(Date.now() / 1000 / 60);
    const timeBuffer = new ArrayBuffer(4);
    const timeView = new DataView(timeBuffer);
    timeView.setUint32(0, timeMinutes, false);
    const timeBytes = new Uint8Array(timeBuffer);
    const nonceBytes = CryptoUtil.concatBytes(randomBytes, timeBytes);
    const nonce = CryptoUtil.base64Encode(nonceBytes);
    const ssecurityBytes = CryptoUtil.base64Decode(ssecurity);
    const nonceDecoded = CryptoUtil.base64Decode(nonce);
    const combined = CryptoUtil.concatBytes(ssecurityBytes, nonceDecoded);
    const snonce = await CryptoUtil.sha256Base64(combined);
    const msg = uri + '&' + snonce + '&' + nonce + '&data=' + dataStr;
    const snonceDecoded = CryptoUtil.base64Decode(snonce);
    const signature = await CryptoUtil.hmacSha256Base64(snonceDecoded, msg);
    MiDebug.logSign('MiIO', uri, ssecurity, nonce, snonce, msg, signature, dataStr);
    const result: Record<string, string> = {} as Record<string, string>;
    result['_nonce'] = nonce;
    result['data'] = dataStr;
    result['signature'] = signature;
    return result;
  }

  private buildFormDataFromRecord(data: Record<string, string>): string {
    const keys = Object.keys(data);
    const pairs: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      pairs.push(encodeURIComponent(keys[i]) + '=' + encodeURIComponent(data[keys[i]]));
    }
    return pairs.join('&');
  }

  private parseJsonResp(resp: MiHttpResp): MiioResponse {
    if (resp.statusCode === 401 || resp.statusCode === 403) {
      const unauthorized: MiioResponse = {
        code: 401,
        message: 'http unauthorized',
        result: null
      };
      return unauthorized;
    }
    let text = resp.result;
    if (text.startsWith(JSON_PREFIX)) {
      text = text.substring(JSON_PREFIX.length);
    }
    text = protectBigNumbers(text);
    try {
      return JSON.parse(text) as MiioResponse;
    } catch (e) {
      throw new Error('MiIO\u54CD\u5E94\u89E3\u6790\u5931\u8D25(status=' + String(resp.statusCode) + ')');
    }
  }
}
