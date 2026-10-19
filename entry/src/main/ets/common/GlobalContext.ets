import { common } from '@kit.AbilityKit';

export class GlobalContext {
  private static context: common.Context | null = null;

  static initContext(context: common.Context): void {
    GlobalContext.context = context;
  }

  static getContext(): common.Context {
    if (!GlobalContext.context) {
      throw new Error('GlobalContext not initialized');
    }
    return GlobalContext.context;
  }
}
