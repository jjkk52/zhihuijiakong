const MS_PER_HOUR = 60 * 60 * 1000;

export class LoginCooldown {
  private failures: number = 0;
  private cooldownUntil: number = 0;
  private readonly retryMax: number;
  private readonly cooldownMs: number;

  constructor(retryMax: number, cooldownMs: number) {
    this.retryMax = retryMax;
    this.cooldownMs = cooldownMs;
  }

  getFailures(): number {
    return this.failures;
  }

  isCoolingDown(now: number): boolean {
    return this.failures >= this.retryMax && now < this.cooldownUntil;
  }

  remainingHours(now: number): number {
    if (!this.isCoolingDown(now)) {
      return 0;
    }
    return Math.ceil((this.cooldownUntil - now) / MS_PER_HOUR);
  }

  check(now: number): void {
    if (this.failures >= this.retryMax) {
      if (now < this.cooldownUntil) {
        const hours = this.remainingHours(now);
        throw new Error('\u767B\u5F55\u5931\u8D25\u6B21\u6570\u8FC7\u591A\uFF0C\u8BF7' + String(hours) + '\u5C0F\u65F6\u540E\u91CD\u8BD5');
      }
      this.failures = 0;
    }
  }

  recordFailure(now: number): void {
    this.failures++;
    if (this.failures === this.retryMax) {
      this.cooldownUntil = now + this.cooldownMs;
    }
  }

  reset(): void {
    this.failures = 0;
    this.cooldownUntil = 0;
  }
}
