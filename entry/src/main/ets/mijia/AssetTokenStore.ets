import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MiTokenStore } from '../mi/MiTokenStore';
import { MiToken, protectBigNumbers } from '../mi/types';
import { PreferencesUtil } from './PreferencesUtil';

const DOMAIN = 0x0200;
const TAG = 'AssetTokenStore';
const TOKEN_ALIAS = 'zhjk_mi_service_token';

export class AssetTokenStore implements MiTokenStore {
  private assetBroken: boolean = false;

  async saveToken(token: MiToken): Promise<boolean> {
    const json = JSON.stringify(token);
    if (!this.assetBroken) {
      try {
        await this.removeAsset();
        const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        query.set(asset.Tag.SECRET, AssetTokenStore.stringToBytes(json));
        query.set(asset.Tag.ALIAS, AssetTokenStore.stringToBytes(TOKEN_ALIAS));
        query.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
        await asset.add(query);
        return true;
      } catch (error) {
        this.assetBroken = true;
        const err = error as BusinessError;
        hilog.warn(DOMAIN, TAG, 'asset add failed code=%{public}d, fallback to preferences', err.code);
      }
    }
    return await PreferencesUtil.saveToken(token);
  }

  async getToken(): Promise<MiToken | undefined> {
    if (!this.assetBroken) {
      try {
        const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        query.set(asset.Tag.ALIAS, AssetTokenStore.stringToBytes(TOKEN_ALIAS));
        query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
        const result = await asset.query(query);
        if (result.length > 0) {
          const secret = result[0].get(asset.Tag.SECRET);
          if (secret instanceof Uint8Array) {
            const tokenStr = AssetTokenStore.bytesToString(secret);
            if (tokenStr.length > 0) {
              return JSON.parse(protectBigNumbers(tokenStr)) as MiToken;
            }
          }
        }
        const legacy = await PreferencesUtil.getToken();
        if (legacy !== undefined) {
          hilog.info(DOMAIN, TAG, 'migrating legacy preferences token to asset store');
          const saved = await this.saveToken(legacy);
          if (saved && !this.assetBroken) {
            await PreferencesUtil.clearToken();
            hilog.info(DOMAIN, TAG, 'legacy token migrated, plaintext removed from preferences');
          }
          return legacy;
        }
        return undefined;
      } catch (error) {
        this.assetBroken = true;
        const err = error as BusinessError;
        hilog.warn(DOMAIN, TAG, 'asset query failed code=%{public}d, fallback to preferences', err.code);
      }
    }
    return await PreferencesUtil.getToken();
  }

  async clearToken(): Promise<boolean> {
    if (!this.assetBroken) {
      try {
        await this.removeAsset();
      } catch (error) {
        const err = error as BusinessError;
        hilog.warn(DOMAIN, TAG, 'asset remove failed code=%{public}d', err.code);
      }
    }
    return await PreferencesUtil.clearToken();
  }

  private async removeAsset(): Promise<void> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, AssetTokenStore.stringToBytes(TOKEN_ALIAS));
    try {
      await asset.remove(query);
    } catch (error) {
      const err = error as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        throw new Error(`asset remove failed: ${err.code}`);
      }
    }
  }

  private static stringToBytes(s: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(s);
  }

  private static bytesToString(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  }
}
