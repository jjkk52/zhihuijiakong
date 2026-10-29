export class MiAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MiAuthError';
  }
}

export const MSG_AUTH_EXPIRED: string = '认证失效，请重新登录';
export const MSG_NOT_LOGGED_IN: string = '未登录';

export function isAuthError(error: Object | null | undefined): boolean {
  if (error === null || error === undefined) {
    return false;
  }
  if (error instanceof MiAuthError) {
    return true;
  }
  const msg = String(error);
  return msg.includes(MSG_AUTH_EXPIRED) || msg.includes(MSG_NOT_LOGGED_IN);
}
