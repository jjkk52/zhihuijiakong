# 智慧家控

基于 HarmonyOS（鸿蒙）的第三方米家（小米智能家居）设备控制应用。

**核心亮点：桌面卡片一键控制** —— 可将任意米家设备绑定到 4 种尺寸的桌面卡片（1×2 / 2×2 / 2×4 / 4×4），在桌面上**直接点击开关设备，无需打开 App**，状态实时可见。

> 米家官方 App 在 HarmonyOS（鸿蒙）上**不支持设备桌面服务卡片**——无法把设备开关「钉」到桌面一键控制。本应用正是为填补这一空白而生。

使用小米账号登录后，即可在手机上管理米家设备开关，并把常用设备「钉」到桌面，像开关一样使用。

> ⚠️ **本项目为非官方第三方应用**，通过逆向分析米家云端接口实现，仅供学习交流使用，请阅读文末[免责声明](#免责声明)。

## 功能特性

- **账号登录**：小米账号手机号 + 密码登录，支持短信验证码（OTP）二次验证与重发
- **设备管理**
  - 自动发现账号下的全部米家设备（含共享家庭设备）
  - 按名称/型号搜索、添加、移除设备
  - 自定义设备备注名与图标（18 种图标可选）
  - 多开关设备支持（双键/三键开关自动拆分为独立控制槽位）
- **状态控制**
  - 5 秒自动刷新设备开关状态
  - 设备离线状态实时标识
  - 点击卡片即切换开关，轮询确认最终状态
- **桌面卡片（核心功能）**
  - 4 种尺寸：1×2 / 2×2 / 2×4 / 4×4，与系统桌面原生融合
  - 卡片直接点击开关设备，无需打开应用
  - 每张卡片可独立绑定一个设备槽位，多张卡片可同时绑定不同设备
  - 未绑定的卡片点击后引导进入设备选择页，一次配置长期使用
  - 点击操作后实时轮询确认设备状态，卡片颜色随状态变化（开启/关闭/离线）
  - 后台定时同步 + 应用内变更主动推送，桌面状态始终与设备保持一致
- **Token 自动续期**：serviceToken 过期时静默刷新，长期免登录

## 截图

> 截图整理中，后续补充。

## 项目结构

```
entry/src/main/ets/
├── common/
│   ├── GlobalContext.ets    # 全局上下文
│   └── StatusTexts.ets      # 状态文案常量（服务层共用）
├── entryability/            # UIAbility 入口
│   ├── EntryAbility.ets     # 主入口
│   └── WidgetEditAbility.ets# 卡片设备绑定页入口
├── formability/
│   └── ElevatorFormAbility.ets  # 桌面卡片后台（消息处理/状态轮询/刷新）
├── mijia/                   # 业务服务层
│   ├── MiAuthService.ets    # 登录态管理与静默续期
│   ├── MiDeviceService.ets  # 设备列表/状态/开关控制（批量查询）
│   ├── PreferencesUtil.ets  # preferences 持久化（进程级缓存策略）
│   ├── AssetTokenStore.ets  # Asset Store 安全凭据存储（含明文迁移）
│   └── PreferencesTokenStore.ets  # preferences 回退存储
├── mi/                      # 米家协议层
│   ├── MiAccount.ets        # 小米账号登录（含 OTP 流程）
│   ├── MiIOService.ets      # miot 设备接口（签名请求/属性读写）
│   ├── MiHttpTransport.ets  # HTTP 传输与 Cookie 管理
│   ├── MiTokenStore.ets     # Token 存储接口
│   ├── CookieParser.ets     # Set-Cookie 解析（纯函数，可单测）
│   ├── LoginCooldown.ets    # 登录限流冷却（纯逻辑，可单测）
│   ├── CryptoUtil.ets       # MD5/SHA/HMAC/Base64
│   ├── MiDebug.ets          # 调试日志
│   └── types.ets            # 数据模型与设备档案表
├── pages/
│   ├── Index.ets            # 主页（设备卡片墙）
│   ├── SettingsPage.ets     # 设置页（登录/设备管理）
│   └── WidgetEditPage.ets   # 卡片设备绑定页
└── widget/pages/
    └── ElevatorWidget.ets   # 桌面卡片 UI（4 种尺寸）
```

## 下载与安装

- **直接下载**：前往 [Releases](https://github.com/jjkk52/zhihuijiakong/releases) 下载未签名 HAP 包（`zhihuijiakong-v1.0.2-unsigned.hap`）
- **源码构建**：克隆本仓库后使用 DevEco Studio 构建运行（见下方[构建与运行](#构建与运行)）

> ⚠️ 本项目以**未签名包**形式分发，未签名 HAP **不能直接安装**到设备，需先完成调试签名。

### 使用开源工具签名安装（免 DevEco Studio，推荐）

无需下载几个 GB 的 DevEco Studio，只需一个华为开发者账号，即可用以下社区开源工具一键「签名 + 安装」：

| 工具 | 平台 | 特点 |
|---|---|---|
| [小白调试助手 auto-installer](https://github.com/likuai2010/auto-installer) | Windows / macOS / Linux | 社区最常用：华为账号登录后自动生成调试证书与 Profile，一键签名、安装、启动 |
| [鸿蒙安装助手 hap-installer](https://github.com/amw1933/hap-installer) | Windows | 绿色免安装单文件 exe：华为账号登录后把 HAP 拖进窗口即可签名安装 |
| [HapInstaller](https://github.com/LMV475/hap-installer) | HarmonyOS 手机端 | 安装到手机后可**完全脱离 PC**，直接在手机上为其他 HAP 签名安装 |

通用流程：手机开启 USB / 无线调试 → 电脑连接手机 → 工具内登录华为账号 → 导入下载的未签名 HAP → 一键签名安装。

> 上述均为第三方开源工具（签名 Profile 绑定你自己的华为账号与设备），使用前请自行评估安全性；更多侧载实践可参考 [harmonyos-sideload-guide](https://github.com/Richard1037/harmonyos-sideload-guide)。

### DevEco Studio 源码构建

克隆本仓库后使用 DevEco Studio 构建运行，见下方[构建与运行](#构建与运行)。

## 构建与运行

### 环境要求

- [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 6.1 及以上
- HarmonyOS SDK 6.1.1 (API 24)，兼容 6.1.0 (API 23)
- 一台 HarmonyOS 手机（开发者模式 + USB 调试）或模拟器
- ⚠️ **项目路径必须为纯 ASCII 字符**（仅字母、数字、`-`、`_`、`.` 等），包含中文的路径会导致 hvigor 构建失败；克隆时请确保目标文件夹名不含中文

### 步骤

1. 克隆仓库并使用 DevEco Studio 打开项目根目录
2. 首次打开会提示签名缺失：进入 `File > Project Structure > Signing Configs`，勾选 **Automatically generate signature** 自动生成本机调试签名
3. 连接设备后点击运行（或执行 `hvigorw` 命令行构建）

### 关于签名（本项目分发未签名包）

本项目以**未签名包**形式分发：仓库不含任何签名材料，`build-profile.json5` 中的发布签名信息已脱敏（密码与证书路径清空），克隆后构建产出的 HAP 不携带发布签名。

- **本地调试运行**：首次打开项目时进入 `File > Project Structure > Signing Configs`，勾选 **Automatically generate signature** 自动生成本机调试签名，即可构建并安装调试包
- **分发/使用未签名包**：未签名 HAP 不能直接安装到设备，使用者需自行完成签名（如通过 DevEco Studio 自动签名，或自行申请证书签名）后再安装
- **自行配置发布签名**（可选）：在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) 申请发布证书（`.cer`）、Profile（`.p7b`）与密钥库（`.p12`），填入 `build-profile.json5` 的 `release > material` 字段，或通过 DevEco Studio `File > Project Structure > Signing Configs` 配置

## 权限说明

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | 访问米家云端接口（登录、设备列表、开关控制） |
| `ohos.permission.GET_NETWORK_INFO` | 获取网络状态 |

## 桌面卡片使用说明（核心功能）

1. 在桌面添加「智慧家控」卡片（长按桌面 > 服务卡片，选择 1×2 / 2×2 / 2×4 / 4×4 尺寸）
2. 点击未绑定的卡片进入设备选择页，选择要绑定的设备槽位
3. 绑定完成后，点击卡片即可直接开关设备，全程无需打开应用；卡片颜色表示状态：
   - 浅绿背景 = 已开启；浅灰 = 已关闭；浅红 = 设备离线
4. 卡片状态每 5 分钟自动同步一次；点击开关后立即轮询设备真实状态并刷新卡片，确保「所见即所控」
5. 可添加多张卡片分别绑定不同设备（如客厅灯、电梯开关、热水器），打造个人专属的桌面控制面板

## 安全与质量

- **凭据安全**：米家登录凭据经系统级 **Asset Store** 安全存储，首次升级自动迁移旧明文数据；Asset 服务异常时自动回退本地 preferences 存储保证可用
- **请求安全**：所有云端请求均经 HMAC-SHA256 签名的 HTTPS 通道
- **测试**：核心纯逻辑（加解密已知向量、Cookie 解析、设备档案克隆隔离等）已补充单元测试

历史问题与改进的完整分析见 [IMPROVEMENTS.md](./IMPROVEMENTS.md)（其中所列问题已全部修复，含实施状态表）。

## 引用与致谢

本项目的米家云协议层（`entry/src/main/ets/mi/`）在开发过程中参考并移植了以下开源项目，特此声明与致谢：

### [Yonsm/MiService](https://github.com/Yonsm/MiService)（MIT License，PyPI 包名 `miservice`）

小米云服务 Python 库。本项目以下实现以其 **v3.0.2** 为参考移植为 ArkTS：

- 小米账号登录流程（serviceLogin / serviceLoginAuth2 / serviceToken 客户端签名，含短信/邮箱 OTP 二次验证与重发）
- HTTP 传输层的 Cookie 管理与请求 UA 约定
- MiIO 设备接口的签名请求与批量属性读写（`/miotspec/prop/get|set`）
- 登录限流保护：检测小米账号限流错误码 `70022`，连续 5 次失败后进入 2 小时冷却期，冷却期内不再发起登录请求，避免账号被服务端进一步封锁

### [jjkk52/MiService](https://github.com/jjkk52/MiService)（MIT License）

上述项目的 fork。其「家庭成员账号设备列表为空」修复（commit `69881ce`）已被本项目完整吸收：

- 家庭/房间接口改用 `/v2/homeroom/gethome` 并携带 `fetch_share` / `fetch_share_dev` 参数
- 合并 `homelist` 与 `share_home_list`，家庭成员账号也能看到共享家庭与设备
- 设备列表改用 `/v2/home/device_list_page` 按显式 dids 分批（50 个/批）拉取，共享设备不再丢失

以上项目的原始版权与许可请见其仓库中的 [LICENSE](https://github.com/Yonsm/MiService/blob/main/LICENSE) 文件。

## 免责声明

1. 本项目为**非官方**的第三方工具，与小米公司无任何关联
2. 项目调用的小米云服务接口为逆向分析所得，**非官方开放 API**；小米有权随时变更接口或限制非官方客户端访问
3. 使用本应用需要输入小米账号密码，凭据仅保存在设备本地沙箱中，不经任何第三方服务器中转；但请知悉使用非官方客户端存在账号被风控的理论风险
4. 本项目仅供个人学习与技术研究，请勿用于商业用途；因使用本项目造成的任何后果由使用者自行承担
