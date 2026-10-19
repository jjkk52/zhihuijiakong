# 智慧家控

基于 HarmonyOS（鸿蒙）的第三方米家（小米智能家居）设备控制应用。

使用小米账号登录后，可在手机上管理米家设备开关，并支持将任意设备绑定到**桌面卡片**，无需打开 App 即可一键开关设备。

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
- **桌面卡片**
  - 4 种尺寸：1×2 / 2×2 / 2×4 / 4×4
  - 卡片直接点击开关设备，无需打开应用
  - 每张卡片可独立绑定一个设备槽位
  - 未绑定的卡片点击后引导进入设备选择页
- **Token 自动续期**：serviceToken 过期时静默刷新，长期免登录

## 截图

> 截图整理中，后续补充。

## 项目结构

```
entry/src/main/ets/
├── common/                  # 全局上下文
│   └── GlobalContext.ets
├── entryability/            # UIAbility 入口
│   ├── EntryAbility.ets     # 主入口
│   └── WidgetEditAbility.ets# 卡片设备绑定页入口
├── formability/
│   └── ElevatorFormAbility.ets  # 桌面卡片后台（消息处理/状态轮询/刷新）
├── mijia/                   # 业务服务层
│   ├── MiAuthService.ets    # 登录态管理与静默续期
│   ├── MiDeviceService.ets  # 设备列表/状态/开关控制
│   ├── PreferencesUtil.ets  # preferences 持久化
│   └── PreferencesTokenStore.ets
├── mi/                      # 米家协议层
│   ├── MiAccount.ets        # 小米账号登录（含 OTP 流程）
│   ├── MiIOService.ets      # miot 设备接口（签名请求/属性读写）
│   ├── MiHttpTransport.ets  # HTTP 传输与 Cookie 管理
│   ├── MiTokenStore.ets     # Token 存储接口
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

## 桌面卡片使用说明

1. 在桌面添加「智慧家控」卡片（长按桌面 > 服务卡片，选择 1×2 / 2×2 / 2×4 / 4×4 尺寸）
2. 点击未绑定的卡片进入设备选择页，选择要绑定的设备槽位
3. 绑定完成后，点击卡片即可直接开关设备；卡片颜色表示状态：
   - 浅绿背景 = 已开启；浅灰 = 已关闭；浅红 = 设备离线
4. 卡片状态每 5 分钟自动同步一次（点击操作后实时轮询刷新）

## 已知问题与改进计划

当前功能完整可用，仍存在若干待改进项（含详细定位与分析），见 [IMPROVEMENTS.md](./IMPROVEMENTS.md)，主要包括：

- 安全：Token 明文存储、UA 硬编码用户 ID
- 功能：主页"详情"按钮文案不随状态切换、卡片切换瞬间闪灰、卡片轮询不提前退出
- 性能：状态轮询未使用批量接口、preferences 每次强制重读
- 可维护性：字符串/颜色未资源化、Cookie 解析代码重复、空 catch 吞错、空壳测试

## 免责声明

1. 本项目为**非官方**的第三方工具，与小米公司无任何关联
2. 项目调用的小米云服务接口为逆向分析所得，**非官方开放 API**；小米有权随时变更接口或限制非官方客户端访问
3. 使用本应用需要输入小米账号密码，凭据仅保存在设备本地沙箱中，不经任何第三方服务器中转；但请知悉使用非官方客户端存在账号被风控的理论风险
4. 本项目仅供个人学习与技术研究，请勿用于商业用途；因使用本项目造成的任何后果由使用者自行承担
