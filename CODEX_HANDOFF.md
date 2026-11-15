# CODEX_HANDOFF — 个人助理（Gerenzhuli）

写给 Codex 的交接文档：只执行、不自由发挥。视觉真值是网页原型 artifact `ge-ren-zhu-li`（定稿版：首页为三格数字 + 早报大卡 + 分组卡片，提醒页为竖向时间线，出行页为行程时间线）；本工程是对它的 SwiftUI 实现，**不要改设计、不要改文案口径**。

## 1. 工程现状

- 位置：`gerenzhuli/`，App 名 `Gerenzhuli`，iOS 17+，SwiftUI + SwiftData。
- 18 个 Swift 文件（`Gerenzhuli/` 下），`tools/gen_pbxproj.py` 已生成 `project.pbxproj` + `Gerenzhuli.xcscheme`，全部 18 个文件都在编译清单里。
- 五个页签：今日 / 日历 / 提醒 / 订阅 / 出行。**没有通讯录**——用户已拍板拿掉，换成出行；`ContactsView.swift` 已删除，全工程无任何 `Contact` / `CNContact` 引用，也**不要**再加回来。
- 语音输入已实现：`VoiceInputService`（Speech 转写）+ `LLMService`（大模型解析）+ `VoiceInputView`（聆听面板 + 确认卡）。API Key 由用户在设置页填进钥匙串，**绝不写死在代码里**。
- 出行页 `TravelView.swift`：行程时间线（出发 / 交通 / 住宿 / 要去的地方）、票挂在行程下、MapKit 导航入口、钱包票证占位、Photos 配图（PHPicker）、订票查价比价 + 下单确认占位（不写死支付）。
- 动效（2026-11-15 补）：切页弹簧过渡 + 标签栏 `matchedGeometryEffect` 选中胶囊；所有自定义卡片/按钮按压 0.97 + 轻震（`GZPressableStyle`，见 `Theme.swift`）；展开收起走 `GZ.spring`、箭头旋转同步；首页入场 stagger；日历选中环 `matchedGeometryEffect` 滑动；语音面板弹簧滑入 + 声波呼吸 + 确认卡弹簧缩放；列表行滚动淡出（`scrollTransition`）。只走 transform / opacity，不许加旋转、闪烁类花哨动效。
- 首页同步（2026-11-15 补，用户反馈“语音添加后提醒页显示了，首页没同步”）：首页新增「提醒」标题列表（未完成、按日期升序、最近 5 条，点进提醒页）；「接下来」放宽为今天全部（含已过时间）+ 明天、最多 5 条；无明确时间的日程默认明天 09:00，不再用点确认那一刻的 `Date()`；本地规则解析支持中文数字时间（“明天下午三点”→15:00）；`addReminder/addEvent/addSubscriber` 返回 Bool，保存失败时确认卡报错、不显示“已添加”；订阅平台不再默认 Netflix，须用户在确认卡必选；订阅月收入由订阅行实时加总。实测重点：语音新增提醒/日程后首页标题和数字是否同步变、中文数字时间是否解析正确、保存失败是否报错。

## 2. 验证命令（在 Mac 上跑，Linux 上跑不了）

```bash
cd gerenzhuli
python3 tools/gen_pbxproj.py          # 增删文件后重生成工程，脚本会先校验文件齐全
xcodebuild -project Gerenzhuli.xcodeproj -scheme Gerenzhuli \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project Gerenzhuli.xcodeproj -scheme Gerenzhuli \
  -destination 'platform=iOS Simulator,name=iPhone 16' test  # 目前无测试目标，预计提示无测试可跑
```

本次交付前只做了：grep 旧称零残留、grep「通讯录/Contact」零残留、18 个 Swift 文件逐文件括号平衡检查、pbxproj 内 18 个文件 + Bundle ID 核对。**没有编译验证**（Linux 上无 Xcode），编译报错由 Codex 在 Mac 上逐条修，修完发原生截图回来做偏差评审。

## 3. 必做配置（用户本人过）

1. **Bundle ID 占位**：现为 `com.lidawang.gerenzhuli`（见 `project.pbxproj` 的 `PRODUCT_BUNDLE_IDENTIFIER`），换成用户自己的。
2. **签名**：Xcode 里登录用户本人的 Apple ID，选 Team，`CODE_SIGN_STYLE = Automatic`，`DEVELOPMENT_TEAM` 目前为空字符串。Apple ID 登录时的双重验证码必须用户本人过。
3. **App 图标**：`Assets.xcassets/AppIcon.appiconset/Icon-1024.png` 目前是深墨绿渐变占位图，上架前换正式图标。
4. **大模型 Key**：用户在 App 设置页自己填（钥匙串），Codex 不填、不写死。
5. **TestFlight**：Archive → Distribute App → App Store Connect → TestFlight。需要用户名下的苹果开发者账号（$99/年）。

## 4. 权限键清单（Info.plist，已配好，核对即可）

| 键 | 用途 |
|---|---|
| `NSRemindersUsageDescription` | 提醒事项读写 |
| `NSCalendarsFullAccessUsageDescription` / `NSCalendarsUsageDescription` | 日历读写 |
| `NSMicrophoneUsageDescription` | 语音输入收音 |
| `NSSpeechRecognitionUsageDescription` | 语音转文字 |
| `NSLocationWhenInUseUsageDescription` | 出行导航（MapKit 打开苹果地图） |

**不要加通讯录权限**（`NSContactsUsageDescription`），通讯录已拿掉。`Gerenzhuli.entitlements` 目前为空（无特殊能力；钱包票证是占位，未接 PassKit，不加 entitlement）。

## 5. 种子数据替换 TODO（上线前必须做）

- `Store.swift` 的 `Seed.load`：提醒、日程、15 位订阅、两条出行示例、12 项早报占位，全部换真实数据。
  - 提醒 + 日历：`PermissionsService` 授权后用 `EKEventStore` 拉取本机数据。
  - 订阅：Notion 台账 / 取码系统接口（月收入由订阅行实时加总，见 `Store.monthlyTotal`；种子只有 15 行，加总不等于全量台账折合 ¥926）。
  - 早报：接每日 08:10 的早报任务；内容一律「待生成」占位，**绝不编造新闻**。
  - 出行：订票查价接真实票务接口（替换 `BookingSheet` 的示例报价）；地点用地名反编码存经纬度；钱包票证接 PassKit。
- `LLMService.swift`：`baseURL` 默认 `https://api.openai.com/v1`，模型默认 `gpt-4o-mini`，用户可在设置页改。

## 6. 已知未做 / 勿当成已完成

- 未在真机 / 模拟器上编译验证过（见 §2）。
- 语音解析：没填 Key 时走本地规则，确认卡上如实标注来源；**不要**把本地规则结果冒充成大模型。
- 原型里「正在理解…」这类文案在原生版里不要出现，除非真在调大模型。
- 出行配图目前只在本次会话内展示（`@State [UIImage]`），未落库；要持久化再把图片存进 SwiftData（`Data` 字段）或文件目录。

## 7. 上架检查单

- [ ] Bundle ID 换成用户的，Team 选好，Archive 成功
- [ ] 真机跑一遍五个页签：今日、提醒时间线勾选同步、订阅筛选、出行新建行程 + 订票流程、语音说一句进确认卡
- [ ] 权限逐项实测：提醒、日历、麦克风、语音识别、定位（导航）
- [ ] 正式 App 图标替换占位图
- [ ] 种子数据按 §5 替换（或确认先用种子上 TestFlight 内测）
- [ ] TestFlight 邀请发到用户手机，用户首启验收
