import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const DEBUG_MODE = false;

class MiDebugLogger {
  private logPath: string = '';
  private initialized: boolean = false;

  init(context: common.Context): void {
    if (!DEBUG_MODE) {
      return;
    }
    this.logPath = context.filesDir + '/mi_debug.log';
    this.initialized = true;
    this.writeLine('=== MiDebugLogger initialized ===');
  }

  log(tag: string, msg: string): void {
    if (!DEBUG_MODE || !this.initialized) {
      return;
    }
    const ts = new Date().toISOString();
    const line = `[${ts}] [${tag}] ${msg}`;
    this.writeLine(line);
  }

  logRequest(tag: string, url: string, method: string, headers: Record<string, string>,
    cookies: Record<string, string>, body: string | null): void {
    if (!DEBUG_MODE || !this.initialized) {
      return;
    }
    this.log(tag, '>>> REQUEST >>>');
    this.log(tag, `${method} ${url}`);
    const hKeys = Object.keys(headers);
    for (let i = 0; i < hKeys.length; i++) {
      this.log(tag, `  H: ${hKeys[i]}: ${headers[hKeys[i]]}`);
    }
    const cKeys = Object.keys(cookies);
    for (let i = 0; i < cKeys.length; i++) {
      this.log(tag, `  C: ${cKeys[i]}=***`);
    }
    if (body !== null) {
      this.log(tag, `  BODY: ${body.substring(0, 500)}`);
    }
  }

  logResponse(tag: string, code: number, headers: Record<string, string>, body: string): void {
    if (!DEBUG_MODE || !this.initialized) {
      return;
    }
    this.log(tag, '<<< RESPONSE <<<');
    this.log(tag, `  CODE: ${code}`);
    const hKeys = Object.keys(headers);
    for (let i = 0; i < hKeys.length; i++) {
      this.log(tag, `  H: ${hKeys[i]}: ${headers[hKeys[i]].substring(0, 200)}`);
    }
    this.log(tag, `  BODY: ${body.substring(0, 500)}`);
  }

  logSign(tag: string, uri: string, ssecurity: string, nonce: string, snonce: string,
    msg: string, signature: string, dataStr: string): void {
    if (!DEBUG_MODE || !this.initialized) {
      return;
    }
    this.log(tag, '--- SIGN DATA ---');
    this.log(tag, `  uri: ${uri}`);
    this.log(tag, `  nonce: ${nonce}`);
    this.log(tag, `  snonce: ${snonce}`);
  }

  private writeLine(line: string): void {
    try {
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto(line + '\n');
      const file = fileIo.openSync(this.logPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
      fileIo.writeSync(file.fd, data.buffer);
      fileIo.closeSync(file.fd);
    } catch (e) {
    }
  }

}

export const MiDebug: MiDebugLogger = new MiDebugLogger();
