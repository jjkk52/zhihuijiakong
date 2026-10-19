import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MiHttpResp } from './types';
import { MiDebug } from './MiDebug';

const DOMAIN = 0x0200;
const TAG = 'MiHttpTransport';

export class MiHttpTransport {
  private cookieJar: Record<string, string> = {};

  async request(
    url: string,
    method: string,
    body: string | null,
    headers: Record<string, string>,
    cookies: Record<string, string>
  ): Promise<MiHttpResp> {
    hilog.info(DOMAIN, TAG, 'request url=%{public}s method=%{public}s', url, method);
    MiDebug.logRequest('HTTP', url, method, headers, cookies, body);
    return new Promise((resolve: (value: MiHttpResp) => void, reject: (reason: Error) => void) => {
      const httpRequestObj = http.createHttp();
      const finalHeaders: Record<string, string> = {};
      const headerKeys = Object.keys(headers);
      for (let i = 0; i < headerKeys.length; i++) {
        finalHeaders[headerKeys[i]] = headers[headerKeys[i]];
      }
      const mergedCookies: Record<string, string> = {};
      const jarKeys = Object.keys(this.cookieJar);
      for (let i = 0; i < jarKeys.length; i++) {
        mergedCookies[jarKeys[i]] = this.cookieJar[jarKeys[i]];
      }
      const cookieKeys = Object.keys(cookies);
      for (let i = 0; i < cookieKeys.length; i++) {
        mergedCookies[cookieKeys[i]] = cookies[cookieKeys[i]];
      }
      const cookieStr = Object.keys(mergedCookies).map((k: string) => k + '=' + mergedCookies[k]).join('; ');
      if (cookieStr.length > 0) {
        finalHeaders['Cookie'] = cookieStr;
      }
      const options: http.HttpRequestOptions = {
        method: method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: finalHeaders,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      };
      if (body !== null && body.length > 0) {
        const encoder = new util.TextEncoder();
        const encoded = encoder.encodeInto(body);
        options.extraData = encoded.buffer;
      }
      const capturedCookies: string[] = [];
      httpRequestObj.on('headersReceive', (header: Object) => {
        try {
          const hdr = header as Record<string, Object>;
          const keys = Object.keys(hdr);
          for (let i = 0; i < keys.length; i++) {
            if (keys[i].toLowerCase() === 'set-cookie') {
              const val = String(hdr[keys[i]]);
              if (val.length > 0) {
                capturedCookies.push(val);
                hilog.info(DOMAIN, TAG, 'headersReceive set-cookie len=%{public}d', val.length);
              }
            }
          }
        } catch (e) {
        }
      });
      httpRequestObj.request(url, options, (err: Error, response: http.HttpResponse) => {
        if (err) {
          httpRequestObj.destroy();
          hilog.error(DOMAIN, TAG, 'request error: %{public}s url=%{public}s', err.message, url);
          reject(new Error('HTTP\u8BF7\u6C42\u5931\u8D25: ' + err.message));
        } else {
          for (let c = 0; c < capturedCookies.length; c++) {
            this.saveCookiesFromSetCookieString(capturedCookies[c]);
          }
          const result = response.result as string;
          let respHeaders: Record<string, string> = {};
          try {
            const rawHeaders = response.header;
            if (rawHeaders !== null && rawHeaders !== undefined && typeof rawHeaders === 'object') {
              const hdrKeys = Object.keys(rawHeaders as Object);
              for (let h = 0; h < hdrKeys.length; h++) {
                respHeaders[hdrKeys[h]] = String((rawHeaders as Record<string, Object>)[hdrKeys[h]]);
              }
            }
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'parse headers error: %{public}s', String(e));
          }
          this.saveCookiesFromResponse(respHeaders);
          httpRequestObj.destroy();
          hilog.info(DOMAIN, TAG, 'request done code=%{public}d cookies=%{public}d captured=%{public}d',
            response.responseCode, Object.keys(this.cookieJar).length, capturedCookies.length);
          MiDebug.logResponse('HTTP', response.responseCode, respHeaders, result);
          const hr: MiHttpResp = { result: result, headers: respHeaders };
          resolve(hr);
        }
      });
    });
  }

  getCookieString(): string {
    return Object.keys(this.cookieJar).map((k: string) => k + '=' + this.cookieJar[k]).join('; ');
  }

  getCookie(name: string): string {
    return this.cookieJar[name] ?? '';
  }

  clearCookies(): void {
    this.cookieJar = {} as Record<string, string>;
  }

  private saveCookiesFromSetCookieString(setCookieStr: string): void {
    try {
      const rawParts = setCookieStr.split(',');
      for (let j = 0; j < rawParts.length; j++) {
        const part = rawParts[j].trim();
        if (part.length === 0) {
          continue;
        }
        const segs = part.split(';');
        if (segs.length > 0) {
          const kv = segs[0].trim();
          const eq = kv.indexOf('=');
          if (eq > 0) {
            const cookieKey = kv.substring(0, eq).trim();
            if (cookieKey.length > 0 && cookieKey.toLowerCase() !== 'path' && cookieKey.toLowerCase() !== 'domain' && cookieKey.toLowerCase() !== 'expires' && cookieKey.toLowerCase() !== 'max-age' && cookieKey.toLowerCase() !== 'httponly' && cookieKey.toLowerCase() !== 'secure' && cookieKey.toLowerCase() !== 'samesite') {
              const value = kv.substring(eq + 1).trim();
              this.cookieJar[cookieKey] = value;
            }
          }
        }
      }
    } catch (e) {
    }
  }

  private saveCookiesFromResponse(headers: Record<string, string>): void {
    try {
      const keys = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i].toLowerCase();
        if (key === 'set-cookie') {
          const setCookie = headers[keys[i]];
          if (!setCookie) {
            continue;
          }
          const rawParts = String(setCookie).split(',');
          for (let j = 0; j < rawParts.length; j++) {
            const part = rawParts[j].trim();
            if (part.length === 0) {
              continue;
            }
            const segs = part.split(';');
            if (segs.length > 0) {
              const kv = segs[0].trim();
              const eq = kv.indexOf('=');
              if (eq > 0) {
                const cookieKey = kv.substring(0, eq).trim();
                if (cookieKey.length > 0 && cookieKey.toLowerCase() !== 'path' && cookieKey.toLowerCase() !== 'domain' && cookieKey.toLowerCase() !== 'expires' && cookieKey.toLowerCase() !== 'max-age' && cookieKey.toLowerCase() !== 'httponly' && cookieKey.toLowerCase() !== 'secure' && cookieKey.toLowerCase() !== 'samesite') {
                  const value = kv.substring(eq + 1).trim();
                  this.cookieJar[cookieKey] = value;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveCookiesFromResponse error: %{public}s', String(e));
    }
  }
}
