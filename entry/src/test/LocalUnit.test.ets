import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { CookieParser } from '../main/ets/mi/CookieParser';
import { LoginCooldown } from '../main/ets/mi/LoginCooldown';
import {
  UserDevice,
  DeviceProfile,
  getDeviceProfile,
  getDeviceHomeRoomText,
  isMultiSlotProfile,
  protectBigNumbers
} from '../main/ets/mi/types';

function buildDevice(): UserDevice {
  const ud = new UserDevice();
  ud.did = 'did-1';
  ud.name = '客厅开关';
  ud.model = 'lumi.switch.acn017';
  ud.siid = 2;
  ud.piid = 1;
  return ud;
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('assertContain', 0, () => {
      let a = 'abc';
      let b = 'b';
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
  });

  describe('CookieParserTest', () => {
    it('parseSingleCookie', 0, () => {
      const result = CookieParser.parseSetCookieString('serviceToken=abc123; Path=/; Domain=mi.com; HTTPOnly');
      expect(result['serviceToken']).assertEqual('abc123');
      expect(Object.keys(result).length).assertEqual(1);
    });

    it('parseMultipleCookies', 0, () => {
      const result = CookieParser.parseSetCookieString('serviceToken=tok1, userId=12345, yetAnother=xyz');
      expect(result['serviceToken']).assertEqual('tok1');
      expect(result['userId']).assertEqual('12345');
      expect(result['yetAnother']).assertEqual('xyz');
      expect(Object.keys(result).length).assertEqual(3);
    });

    it('skipsAttrSegments', 0, () => {
      const result = CookieParser.parseSetCookieString('expires=Wed, 21 Oct 2015 07:28:00 GMT, path=/, token=v1');
      expect(result['token']).assertEqual('v1');
      expect(Object.keys(result).length).assertEqual(1);
    });

    it('skipsEmptyAndInvalidSegments', 0, () => {
      const result = CookieParser.parseSetCookieString(',, noequal, =novalue, ok=1');
      expect(result['ok']).assertEqual('1');
      expect(Object.keys(result).length).assertEqual(1);
    });

    it('emptyInput', 0, () => {
      const result = CookieParser.parseSetCookieString('');
      expect(Object.keys(result).length).assertEqual(0);
    });
  });

  describe('LoginCooldownTest', () => {
    const MAX = 5;
    const COOLDOWN = 2 * 60 * 60 * 1000;
    const T0 = 1700000000000;

    it('noBlockInitially', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      expect(cd.getFailures()).assertEqual(0);
      expect(cd.isCoolingDown(T0)).assertFalse();
      expect(cd.remainingHours(T0)).assertEqual(0);
      cd.check(T0);
    });

    it('countsFailuresWithoutBlockingBeforeMax', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      for (let i = 1; i < MAX; i++) {
        cd.recordFailure(T0);
        expect(cd.getFailures()).assertEqual(i);
        expect(cd.isCoolingDown(T0 + 1)).assertFalse();
      }
      cd.check(T0 + 1);
    });

    it('cooldownTriggersAtMaxFailure', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      for (let i = 0; i < MAX; i++) {
        cd.recordFailure(T0);
      }
      expect(cd.getFailures()).assertEqual(MAX);
      expect(cd.isCoolingDown(T0)).assertTrue();
      expect(cd.isCoolingDown(T0 + COOLDOWN - 1)).assertTrue();
      expect(cd.isCoolingDown(T0 + COOLDOWN)).assertFalse();
      expect(cd.remainingHours(T0 + 1)).assertEqual(2);
      expect(cd.remainingHours(T0 + COOLDOWN - 1)).assertEqual(1);
      expect(cd.remainingHours(T0 + COOLDOWN)).assertEqual(0);
    });

    it('checkThrowsWhileCoolingDown', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      for (let i = 0; i < MAX; i++) {
        cd.recordFailure(T0);
      }
      let threw = false;
      try {
        cd.check(T0 + 1);
      } catch (e) {
        threw = true;
        expect(String(e).includes('2')).assertTrue();
      }
      expect(threw).assertTrue();
    });

    it('checkResetsAfterCooldownExpires', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      for (let i = 0; i < MAX; i++) {
        cd.recordFailure(T0);
      }
      cd.check(T0 + COOLDOWN + 1);
      expect(cd.getFailures()).assertEqual(0);
      cd.check(T0 + COOLDOWN + 2);
    });

    it('failuresBeyondMaxDoNotExtendCooldown', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      for (let i = 0; i < MAX; i++) {
        cd.recordFailure(T0);
      }
      cd.recordFailure(T0 + 1000);
      expect(cd.getFailures()).assertEqual(MAX + 1);
      expect(cd.isCoolingDown(T0 + COOLDOWN - 1)).assertTrue();
      expect(cd.isCoolingDown(T0 + COOLDOWN)).assertFalse();
    });

    it('resetClearsState', 0, () => {
      const cd = new LoginCooldown(MAX, COOLDOWN);
      cd.recordFailure(T0);
      cd.reset();
      expect(cd.getFailures()).assertEqual(0);
      expect(cd.isCoolingDown(T0 + 1)).assertFalse();
      cd.check(T0 + 2);
    });
  });

  describe('UserDeviceTest', () => {
    it('makeSlotKey', 0, () => {
      expect(UserDevice.makeSlotKey('did-1', 2, 1)).assertEqual('did-1_2_1');
    });

    it('getSlotKeyFallsBackToDid', 0, () => {
      const ud = buildDevice();
      expect(UserDevice.getSlotKey(ud)).assertEqual('did-1');
      ud.slotKey = 'did-1_2_1';
      expect(UserDevice.getSlotKey(ud)).assertEqual('did-1_2_1');
    });

    it('getDisplayNamePrefersAlias', 0, () => {
      const ud = buildDevice();
      expect(UserDevice.getDisplayName(ud)).assertEqual('客厅开关');
      ud.alias = '我的开关';
      expect(UserDevice.getDisplayName(ud)).assertEqual('我的开关');
    });

    it('getDisplayNameAppendsSlotLabelForMultiSlot', 0, () => {
      const ud = buildDevice();
      ud.slotLabel = '左键';
      expect(UserDevice.getDisplayName(ud)).assertEqual('客厅开关 左键');
      ud.alias = '我的开关';
      expect(UserDevice.getDisplayName(ud)).assertEqual('我的开关');
    });

    it('getSourceInfoEmptyWithoutAlias', 0, () => {
      const ud = buildDevice();
      expect(UserDevice.getSourceInfo(ud)).assertEqual('');
      ud.alias = '我的开关';
      expect(UserDevice.getSourceInfo(ud)).assertEqual('客厅开关');
    });

    it('getHomeRoomText', 0, () => {
      const ud = buildDevice();
      expect(UserDevice.getHomeRoomText(ud)).assertEqual('');
      ud.homeName = '家';
      expect(UserDevice.getHomeRoomText(ud)).assertEqual('家');
      ud.roomName = '客厅';
      expect(UserDevice.getHomeRoomText(ud)).assertEqual('家 · 客厅');
    });
  });

  describe('DeviceProfileTest', () => {
    it('knownModelByExactKey', 0, () => {
      const profile = getDeviceProfile('yeelink.light.light');
      expect(profile.known).assertTrue();
      expect(profile.label).assertEqual('射灯');
    });

    it('knownModelByPrefix', 0, () => {
      const profile = getDeviceProfile('yeelink.light.ceil1');
      expect(profile.known).assertTrue();
      expect(profile.label).assertEqual('灯');
    });

    it('unknownModelReturnsDefault', 0, () => {
      const profile = getDeviceProfile('not.exist.model');
      expect(profile.known).assertFalse();
      expect(profile.label).assertEqual('设备');
      expect(profile.slots.length).assertEqual(0);
    });

    it('profileIsClonedPerCall', 0, () => {
      const p1 = getDeviceProfile('lumi.switch.acn017');
      const p2 = getDeviceProfile('lumi.switch.acn017');
      expect(p1.known).assertTrue();
      expect(isMultiSlotProfile(p1)).assertTrue();
      expect(p1.slots.length).assertEqual(2);
      p1.label = '已修改';
      p1.slots[0].label = '已修改按键';
      expect(p2.label).assertEqual('开关');
      expect(p2.slots[0].label).assertEqual('左键');
      const p3 = getDeviceProfile('lumi.switch.acn017');
      expect(p3.label).assertEqual('开关');
      expect(p3.slots[0].label).assertEqual('左键');
    });
  });

  describe('PureHelpersTest', () => {
    it('getDeviceHomeRoomTextCombinations', 0, () => {
      expect(getDeviceHomeRoomText('家', '客厅')).assertEqual('家 · 客厅');
      expect(getDeviceHomeRoomText('', '客厅')).assertEqual('客厅');
      expect(getDeviceHomeRoomText('家', '')).assertEqual('家');
      expect(getDeviceHomeRoomText('', '')).assertEqual('');
    });

    it('protectBigNumbersQuotesLongNumbers', 0, () => {
      const json = '{"userId":123456789012345678,"count":42}';
      const protectedJson = protectBigNumbers(json);
      expect(protectedJson.includes('"123456789012345678"')).assertTrue();
      expect(protectedJson.includes('"42"')).assertFalse();
      const parsed: Record<string, Object> = JSON.parse(protectedJson) as Record<string, Object>;
      expect(String(parsed['userId'])).assertEqual('123456789012345678');
      expect(parsed['count']).assertEqual(42);
    });

    it('protectBigNumbersKeepsShortNumbers', 0, () => {
      const json = '{"userId":8816080,"siid":2,"piid":1}';
      expect(protectBigNumbers(json)).assertEqual(json);
    });

    it('protectBigNumbersHandlesTrailingValue', 0, () => {
      const json = '{"token":9876543210987654}';
      const protectedJson = protectBigNumbers(json);
      expect(protectedJson.includes('"9876543210987654"')).assertTrue();
    });
  });
}
