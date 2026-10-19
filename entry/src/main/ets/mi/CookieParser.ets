const ATTR_NAMES: string[] = ['path', 'domain', 'expires', 'max-age', 'httponly', 'secure', 'samesite'];

export class CookieParser {
  static parseSetCookieString(setCookieStr: string): Record<string, string> {
    const result: Record<string, string> = {} as Record<string, string>;
    const rawParts = setCookieStr.split(',');
    for (let i = 0; i < rawParts.length; i++) {
      const part = rawParts[i].trim();
      if (part.length === 0) {
        continue;
      }
      const segs = part.split(';');
      if (segs.length === 0) {
        continue;
      }
      const kv = segs[0].trim();
      const eq = kv.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const cookieKey = kv.substring(0, eq).trim();
      if (cookieKey.length === 0 || CookieParser.isAttrName(cookieKey)) {
        continue;
      }
      result[cookieKey] = kv.substring(eq + 1).trim();
    }
    return result;
  }

  private static isAttrName(name: string): boolean {
    const lower = name.toLowerCase();
    for (let i = 0; i < ATTR_NAMES.length; i++) {
      if (lower === ATTR_NAMES[i]) {
        return true;
      }
    }
    return false;
  }
}
