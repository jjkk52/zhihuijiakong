import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { CryptoUtil } from '../../../main/ets/mi/CryptoUtil';

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    beforeAll(() => {
    })
    beforeEach(() => {
    })
    afterEach(() => {
    })
    afterAll(() => {
    })
    it('assertContain', 0, () => {
      hilog.info(0x0000, 'testTag', '%{public}s', 'it begin');
      let a = 'abc';
      let b = 'b';
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    })
  })

  describe('CryptoUtilTest', () => {
    it('md5KnownVector', 0, async () => {
      const digest = await CryptoUtil.md5HexUpper('abc');
      expect(digest).assertEqual('900150983CD24FB0D6963F7D28E17F72');
    })

    it('md5EmptyString', 0, async () => {
      const digest = await CryptoUtil.md5HexUpper('');
      expect(digest).assertEqual('D41D8CD98F00B204E9800998ECF8427E');
    })

    it('sha1KnownVector', 0, async () => {
      const digest = await CryptoUtil.sha1Base64('abc');
      expect(digest).assertEqual('qZk+NkcGgWq6PiVxeFDCbJzQ2J0=');
    })

    it('sha256KnownVector', 0, async () => {
      const encoder = new util.TextEncoder();
      const digest = await CryptoUtil.sha256Base64(encoder.encodeInto('abc'));
      const hex = CryptoUtil.bytesToHexUpper(CryptoUtil.base64Decode(digest));
      expect(hex).assertEqual('BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD');
    })

    it('hmacSha256Rfc4231Case2', 0, async () => {
      const encoder = new util.TextEncoder();
      const key = encoder.encodeInto('Jefe');
      const digest = await CryptoUtil.hmacSha256Base64(key, 'what do ya want for nothing?');
      const hex = CryptoUtil.bytesToHexUpper(CryptoUtil.base64Decode(digest));
      expect(hex).assertEqual('5BDCC146BF60754E6A042426089575C75A003F089D2739839DEC58B964EC3843');
    })

    it('base64RoundTrip', 0, () => {
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto('hello 智慧家控');
      const encoded = CryptoUtil.base64Encode(data);
      const decoded = CryptoUtil.base64Decode(encoded);
      expect(decoded.length).assertEqual(data.length);
      for (let i = 0; i < data.length; i++) {
        expect(decoded[i]).assertEqual(data[i]);
      }
    })

    it('bytesToHexUpper', 0, () => {
      const bytes = new Uint8Array([0x00, 0x0F, 0xA5, 0xFF]);
      expect(CryptoUtil.bytesToHexUpper(bytes)).assertEqual('000FA5FF');
    })

    it('concatBytes', 0, () => {
      const a = new Uint8Array([1, 2, 3]);
      const b = new Uint8Array([4, 5]);
      const merged = CryptoUtil.concatBytes(a, b);
      expect(merged.length).assertEqual(5);
      expect(merged[0]).assertEqual(1);
      expect(merged[3]).assertEqual(4);
      expect(merged[4]).assertEqual(5);
    })

    it('randomAlphanumericLengthAndCharset', 0, () => {
      const result = CryptoUtil.randomAlphanumeric(32);
      expect(result.length).assertEqual(32);
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      for (let i = 0; i < result.length; i++) {
        expect(chars.includes(result.charAt(i))).assertTrue();
      }
    })
  })
}
