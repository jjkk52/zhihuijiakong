# 代码分析与改进报告

> 本报告基于 2026-10 对代码库的完整通读。
> 应用当前功能完全正常：登录、设备控制、桌面卡片均按预期工作。
> 报告中的问题按 `P0（安全）→ P1（功能瑕疵）→ P2（性能）→ P3（可维护性）` 分级。
>
> **✅ 2026-10 更新：下述全部问题已实施修复，详见文末[「四、实施状态」](#四实施状态)。第二节中的行号为分析时快照，可能与当前代码不对应。**

---

## 一、桌面卡片点动开关工作流程（已核实）

点击桌面卡片开关到图标/颜色变化的完整链路，共 5 步：

```
[卡片UI进程]                    [卡片后台 FormExtensionAbility]              [米家云端]
点击卡片 ──postCardAction──▶ onFormEvent()
                              ├─ checkLoginStatus()（token过期则静默续签）
                              ├─ switchingDevices[did]=true（防连点）
                              ├─ 立即推送"切换中..." ──▶ 卡片变灰显示"切换中..."
                              ├─ toggleSwitchByDid() ──────────────────▶ getProperty（读现值）
                              │                                        └▶ setProperty（写反值）
                              └─ startSwitchPolling()（每200ms×最多20次）
                                      └─ pushStateToAllForms() ─────────▶ getProperty（轮询读回）
                                              │
                                              ▼
[卡片UI] @LocalStorageProp 自动重渲染 → 颜色/背景变化
```

1. **点击卡片** — `entry/src/main/ets/widget/pages/ElevatorWidget.ets:219` `handleCardClick()`
   - 卡片未绑定设备时：`postCardAction` router 跳转 `WidgetEditAbility` 选择设备
   - 已绑定时：`sendToggleMessage()` 发送消息 `{method:'toggle', did, siid, piid}`
2. **卡片后台收到消息** — `entry/src/main/ets/formability/ElevatorFormAbility.ets:68` `onFormEvent()`
   - 先 `MiAuthService.checkLoginStatus()` 确保米家凭据有效（必要时静默刷新）
   - 设置 `switchingDevices[did] = true` 防止重复触发（第 128 行）
   - **立即**调用 `pushSwitchingToAllForms()`（第 338 行）向所有绑定同一设备的卡片推送"切换中..."
3. **真正执行开关** — `entry/src/main/ets/mi/MiIOService.ets:433` `toggleSwitch()`
   - 先 `getProperty` 读取当前状态，再 `setProperty` 写入相反值
   - 均为经 HMAC-SHA256 签名的 HTTPS 请求（`/miotspec/prop/get`、`/miotspec/prop/set`）
4. **轮询确认新状态** — `ElevatorFormAbility.ets:164` `startSwitchPolling()`
   - 每 **200ms** 查询一次真实状态，最多 **20 次**（约 4 秒）
   - 每次查询到状态即通过 `pushStateToAllForms()`（第 380 行）推送 `{isOn, statusText}`
5. **卡片视觉变化** — `ElevatorWidget` 通过 `@LocalStorageProp` 接收数据自动重渲染
   - 图标 emoji 字符本身**不变**，变化的是**颜色与背景**：

| 状态 | 图标颜色 | 卡片背景 | 状态文字 |
|---|---|---|---|
| 已开启 | 深绿 `#2E7D32` | 浅绿 `#C8E6C9` | 已开启（绿字） |
| 已关闭 | 灰 `#757575` | 浅灰 `#EEEEEE` | 已关闭（灰字） |
| 已离线 | 红 `#E57373` | 浅红 `#FFEBEE` | 已离线 |
| 切换中 | 灰（见 P1-2） | 浅灰 | 切换中... |

- 另有每 5 分钟一次的系统级兜底刷新（`formProvider.setFormNextRefreshTime`）。

---

## 二、问题清单

### P0 安全类

**P0-1 Token 以明文 JSON 存储于 preferences**
- 位置：`entry/src/main/ets/mijia/PreferencesUtil.ets:44` `saveToken()` / `:56` `getToken()`
- 现状：米家 `serviceToken`、`ssecurity` 等凭据以明文 JSON 字符串写入应用沙箱的 preferences 文件。
- 影响：应用沙箱本身有系统级隔离，个人使用风险可控；但若设备被越狱/提权，凭据可直接读取。
- 建议：评估使用系统级安全存储 **Asset Store**（`@kit.AssetStoreKit`）保存关键凭据，或对 JSON 做一层加密后再落盘。

**P0-2 伪装 UA 中硬编码真实用户 ID**
- 位置：`entry/src/main/ets/mi/MiAccount.ets:17` `UA_OTP` 常量
- 现状：UA 字符串中含 `UserId/8816080`，为编写时从真实抓包数据复制的具体小米账号 ID 痕迹；所有使用者的请求都会携带同一指纹。
- 影响：多用户共用同一 UserId 指纹，容易被小米风控关联批量识别，增加账号受限风险。
- 建议：改为运行时以当前登录用户 ID 拼接，或彻底移除该字段。

### P1 功能瑕疵（不影响当前正常使用，但确属问题）

**P1-1 主页"详情"按钮文案两分支相同**
- 位置：`entry/src/main/ets/pages/Index.ets:209`
- 代码：`Button(this.showDetail ? '详情' : '详情')`
- 影响：按钮点击可正常切换详情/简洁视图（`showDetail` 状态生效），但**按钮文字永远显示"详情"**，用户无法从文字判断当前视图状态。
- 建议：区分为如 `'简洁' : '详情'`。

**P1-2 卡片切换瞬间"闪灰"**
- 位置：`entry/src/main/ets/formability/ElevatorFormAbility.ets:338` `pushSwitchingToAllForms()`
- 现状：推送"切换中..."数据时（第 360-367 行），`WidgetFormData` 仅设置了 `statusText/deviceName/iconType` 等字段，**未保留设备原有的 `isOn` 状态**（默认 `false`）。
- 影响：一盏开着的灯（绿色卡片）被点击后会**先闪回灰色"切换中..."，轮询确认后再变回绿色**，存在一瞬间的视觉跳变。
- 建议：切换前先把当前 `isOn` 一并推送给卡片，保持底色不变、仅文字变化。

**P1-3 卡片轮询不提前退出**
- 位置：`entry/src/main/ets/formability/ElevatorFormAbility.ets:164` `startSwitchPolling()`
- 现状：即使第 1 次轮询（200ms）就读到了切换后的新状态，仍会**跑满 20 次轮询**，且每次都调用 `pushStateToAllForms()` 重复推送 `updateForm`（最多 20 次冗余系统调用与流量）。
- 对照：主应用侧的 `MiDeviceService.pollSwitchState()`（`entry/src/main/ets/mijia/MiDeviceService.ets:389`）在状态达到预期值时会提前结束，两处行为不一致。
- 建议：轮询到 `state === 预期值` 即 break，并同步清除 `switchingDevices`。

### P2 性能（当前设备少无感知，规模放大后显现）

**P2-1 状态轮询未使用批量接口**
- 位置：`entry/src/main/ets/mijia/MiDeviceService.ets:347` `refreshDeviceStates()`
- 现状：每 5 秒对**每台设备单独**发一次 `/miotspec/prop/get` 请求（`Promise.all` 并发 N 个请求）。
- 事实：miot API 的 `params` 本身是数组，**一次请求即可批量查询全部设备属性**。
- 影响：3 台设备 = 每 5 秒 3 次 HTTP 请求；设备到十几台时请求数线性放大，增加延迟与被限流风险。
- 建议：合并为一次批量 `prop/get`，按 `did+siid+piid` 匹配结果分发。

**P2-2 preferences 每次访问都强制重读磁盘**
- 位置：`entry/src/main/ets/mijia/PreferencesUtil.ets:22` `getPref()`
- 现状：为保证与卡片进程的数据一致性，每次调用都先 `removePreferencesFromCacheSync` 再重新加载文件（代码注释已说明原因）。
- 影响：主应用进程也承担了每次磁盘 IO 的开销。
- 建议：可按进程类型区分策略（卡片进程强制重读、主进程利用缓存 + 关键写入点主动失效），属优化项。

**P2-3 `httpGetJson` 未复用统一 HTTP 传输层**
- 位置：`entry/src/main/ets/mi/MiIOService.ets:379`
- 现状：拉取 miot-spec 设备规格时使用独立的回调式 `http.createHttp()`，与 `MiHttpTransport` 并存两套 HTTP 代码路径。
- 建议：统一走 `MiHttpTransport`。

### P3 可维护性

**P3-1 `WidgetEditAbility` 残留旧模板 home skills（已核实：不会产生双图标）**
- 位置：`entry/src/main/module.json5:60-77`
- 事实核查：该 Ability 的 skills 使用 `"action.system.home"`，而当前 SDK（HarmonyOS 6.1，本机 `@ohos.ability.wantConstant.d.ts:44`）标准 home action 为 `ohos.want.action.home`，两者不匹配，**系统不会为其生成第二个桌面图标**，应用表现正常。
- 建议：该 skills 块为旧版模板残留死配置，删除可避免误导（仅清理，非 bug）。

**P3-2 中文字符串 `\uXXXX` 转义硬编码**
- 位置：全部页面与服务层（如 `Index.ets`、`SettingsPage.ets`、`MiAccount.ets` 等）
- 现状：所有界面文案以 `'\u672A\u767B\u5F55'` 形式内联在代码中，可读性差，无法做国际化。
- 建议：迁移至 `entry/src/main/resources/base/element/string.json`，代码中用 `$r('app.string.xxx')` 引用；颜色值（`#1976D2` 等大量硬编码）同理迁入 `color.json`。

**P3-3 Cookie 解析代码重复**
- 位置：`entry/src/main/ets/mi/MiHttpTransport.ets:117` `saveCookiesFromSetCookieString()` 与 `:142` `saveCookiesFromResponse()`
- 现状：两段约 30 行的 cookie 解析逻辑高度重复（复制粘贴关系），修改一处易漏另一处。
- 建议：提取统一的私有解析方法。

**P3-4 空 `catch` 静默吞错**
- 位置：`MiDeviceService.ets`（多处）、`MiHttpTransport.ets` 等
- 现状：`catch (e) {}` 空捕获，出错时无线索可查。
- 建议：至少补 `hilog.warn` 级别日志。

**P3-5 设备档案表的副作用与类型断言**
- 位置：`entry/src/main/ets/mi/types.ets:204` `DEVICE_PROFILES`、`:257` `getDeviceProfile()`
- 现状：档案表用对象字面量 + `as DeviceProfile` 断言构造；`getDeviceProfile()` 会改写共享对象的 `known` 字段（隐蔽副作用，所有调用方共享同一可变对象）。
- 建议：改为工厂函数每次返回新实例，用显式构造替代断言。

**P3-6 冗余的请求参数类**
- 位置：`entry/src/main/ets/mi/MiIOService.ets:20-32` `MiioGetParams` / `MiioGetHomeParams`
- 现状：两个类已定义，但 `getDeviceList()` 实际用 `Record` 字面量重新构造了请求体，类处于半弃用状态。
- 建议：二选一，删除或统一。

**P3-7 单元测试为空壳**
- 位置：`entry/src/test/*.ets`、`entry/src/ohosTest/ets/test/*.ets`
- 现状：全部为模板生成的空测试，无有效断言。
- 建议：为纯逻辑模块补充测试，优先级：`CryptoUtil`（签名安全关键）、`UserDevice.getSlotKey/getDisplayName`、`getDeviceProfile`、`MiHttpTransport` cookie 解析。

---

## 三、上传 GitHub 前已完成的处理

| 处理 | 说明 |
|---|---|
| `.gitignore` 增强 | 排除 `sign/`（发布私钥与密码）、`MYpythonSourceCode/`（含 `.mi.token` 凭据）、`*.hap/*.app` 产物、日志、截图、含设备序列号的个人安装脚本 |
| `build-profile.json5` release 段脱敏 | 密码与证书路径清空并注释说明，debug 自动签名保留原样 |
| 删除过时 `README_CONFIG.md` | 内容（电梯按钮、ArkUI-X 构建失败）与现状严重不符，已被本报告与新的 `README.md` 取代 |

---

## 四、实施状态

> 2026-10：下列改进已全部实施完毕，并已通过 ArkTS 静态检查与 debug/release 构建。

| 编号 | 问题 | 实施结果 |
|---|---|---|
| P0-1 | Token 明文存储 | ✅ 新建 `AssetTokenStore`（`@kit.AssetStoreKit`）保存凭据，首次启动自动迁移旧 preferences 明文数据并删除原记录；Asset 异常时回退 preferences 存储保证可用性 |
| P0-2 | UA 硬编码用户 ID | ✅ `UA_OTP` 改为含 `%USERID%`/`%DEVICEID%` 占位符的模板 + `buildOtpUa()` 运行时拼接；`MiIOService` 同步改为 `buildUaMiio()` 动态拼接 |
| P1-1 | "详情"按钮两分支文案相同 | ✅ 改为 `showDetail ? 简洁 : 详情`（`$r('app.string.btn_simple')` / `btn_detail`） |
| P1-2 | 卡片切换瞬间闪灰 | ✅ `pushSwitchingToAllForms` 推送时保留原 `isOn`/`isOffline`，切换中仅文字变化、底色不变 |
| P1-3 | 卡片轮询不提前退出 | ✅ `toggleSwitch` 返回写入的新值作为预期值，`startSwitchPolling` 增加 `expectedValue` 参数，`state === expectedValue` 时立即推送并清除 `switchingDevices` 提前退出 |
| P2-1 | 状态轮询未批量 | ✅ `MiIOService` 新增 `getProperties()` 批量接口，`refreshDeviceStates` 合并为单次 `/miotspec/prop/get`；失败自动回退逐设备查询 |
| P2-2 | preferences 强制重读 | ✅ `PreferencesUtil` 增加 `forceReload` 标志：主进程（`EntryAbility`）关闭强制重读走缓存，卡片进程（`ElevatorFormAbility`）保持强制重读 |
| P2-3 | `httpGetJson` 独立 HTTP 路径 | ✅ 统一走 `MiHttpTransport`，删除 `import { http }` |
| P3-1 | WidgetEditAbility 旧模板 skills | ✅ 已从 `module.json5` 删除 |
| P3-2 | `\uXXXX` 硬编码 | ✅ UI 层（Index/SettingsPage/WidgetEditPage/ElevatorWidget）文案与颜色全部迁入 `string.json`/`color.json`，`$r` 引用；服务层文案收敛为 `common/StatusTexts.ets` 常量并转为可读中文 |
| P3-3 | Cookie 解析重复 | ✅ 提取纯函数模块 `mi/CookieParser.ets`，`MiHttpTransport` 两处统一调用 |
| P3-4 | 空 catch 吞错 | ✅ 全部空 `catch` 补 `hilog.warn/error` |
| P3-5 | 档案表副作用与断言 | ✅ `types.ets` 重写：工厂函数 `createSlot`/`createProfile` 构建档案表，`getDeviceProfile` 经 `cloneProfile` 每次返回深拷贝，去除全部 `as` 断言与共享可变状态 |
| P3-6 | 冗余请求参数类 | ✅ 删除 `MiioGetParams`/`MiioGetHomeParams`，统一 `buildGetHomeParams()` 返回 `Record` |
| P3-7 | 空壳测试 | ✅ `LocalUnit.test.ets` 补 CookieParser/UserDevice/getDeviceProfile 克隆隔离/protectBigNumbers 纯逻辑测试；`Ability.test.ets` 补 CryptoUtil 已知向量（MD5/SHA-1/SHA-256/RFC 4231 HMAC）与 Base64 等测试 |

> 2026-10 追加：对照上游 [Yonsm/MiService](https://github.com/Yonsm/MiService) v3.0.2 与 [jjkk52/MiService](https://github.com/jjkk52/MiService) fork 复核协议层，确认「家庭成员账号设备列表修复」（fork commit `69881ce`：`/v2/homeroom/gethome` + `fetch_share`、`share_home_list` 合并、`/v2/home/device_list_page` 显式 dids 分批）此前已完整移植；补齐遗漏的**登录限流保护**（`MiAccount.ets`：`70022` 连续 5 次失败进入 2 小时冷却，冷却期内 `login()` / `refreshToken()` 不再发起登录请求，行为与上游 `miaccount.py` 对齐）。引用关系已在 [README.md](./README.md)「引用与致谢」声明。
