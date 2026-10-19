import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class CryptoUtil {
  static base64Encode(data: Uint8Array): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(data);
  }

  static base64Decode(str: string): Uint8Array {
    const helper = new util.Base64Helper();
    return helper.decodeSync(str);
  }

  static async md5HexUpper(data: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const input = encoder.encodeInto(data);
    const md = cryptoFramework.createMd('MD5');
    await md.update({ data: input });
    const result = await md.digest();
    return CryptoUtil.bytesToHexUpper(result.data);
  }

  static async sha1Base64(data: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const input = encoder.encodeInto(data);
    const md = cryptoFramework.createMd('SHA1');
    await md.update({ data: input });
    const result = await md.digest();
    return CryptoUtil.base64Encode(result.data);
  }

  static async sha256Base64(data: Uint8Array): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data });
    const result = await md.digest();
    return CryptoUtil.base64Encode(result.data);
  }

  static async hmacSha256Base64(key: Uint8Array, message: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const msgData = encoder.encodeInto(message);
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = await symKeyGenerator.convertKey({ data: key });
    const mac = cryptoFramework.createMac('SHA256');
    await mac.init(symKey);
    await mac.update({ data: msgData });
    const result = await mac.doFinal();
    return CryptoUtil.base64Encode(result.data);
  }

  static bytesToHexUpper(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i];
      hex += ((b >> 4) & 0x0F).toString(16) + (b & 0x0F).toString(16);
    }
    return hex.toUpperCase();
  }

  static concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
    const result = new Uint8Array(a.length + b.length);
    result.set(a, 0);
    result.set(b, a.length);
    return result;
  }

  static randomAlphanumeric(length: number): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const randBytes = CryptoUtil.randomBytes(length);
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(randBytes[i] % chars.length);
    }
    return result;
  }

  static randomBytes(length: number): Uint8Array {
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(length);
    return new Uint8Array(blob.data.buffer, blob.data.byteOffset, blob.data.byteLength);
  }
}
