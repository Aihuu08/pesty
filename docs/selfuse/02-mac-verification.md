# 真机验证记录（Mac 本机）

机器：M3 Max / 48GB，Xcode 27.1，Swift 6.4。分支 `claude/sweet-thompson-fycdit`，基于提交 `fa83c16`。

## 编译和测试（2026-10-22）
- `swift build`：通过。1 条新警告：`SettingsView.swift:104` 用到 Combine 但没有 `import Combine`（Swift 6.4 新增的检查，不影响运行）。
- `swift test`：36 个测试全部通过（源码里就是 36 个测试函数，HANDOFF 里写的 37 是笔误）。
- 基准数据（debug 构建）：
  - `SEARCH-BENCH clips=5000 legacy=87.73ms/keystroke indexed=3.68ms/keystroke build=264ms`
  - `SAVE-BENCH clips=5000 bytes=11927161 encode=48ms write=3ms decode=28ms`
  - `HTML-IMPORT-NETWORK connections=0`

## 签名和安装
- 自签名证书 `Pesty Local Signing`（代码签名，有效期到 2027-10-22）。macOS 27 上「钥匙串访问」会跳转到「密码」App，要直接打开 `/System/Library/CoreServices/Certificate Assistant.app` 创建。
- `build_app.sh` 打包通过，designated requirement 绑定了证书指纹；en.lproj、zh-Hans.lproj 都在。
- 本机之前没有装过 Pesty，没有旧数据，第 2 步（备份）和第 6 步（卸载）跳过。
- 辅助功能授权后，⇧⌘V + 回车能把内容粘进「文本编辑」。

## 第 8 步验证清单

### 中文输入法（系统简体拼音）：全部通过
- [x] 不点搜索框直接打拼音：首字母进入组字，出现候选框
- [x] 组字时按回车：上屏英文，不会粘贴片段
- [x] 组字时按方向键：在候选词之间移动，不会切换卡片
- [x] 组字时按数字选词：正常选词，不会快速粘贴
- [x] 组字时按 Esc：只取消组字，粘贴栏不关
- [x] 上屏后回车：粘贴当前选中的片段
- [x] 拼音全拼和首字母搜索（nihao、nh、pg）
- 说明：组字过程中（拼音还没上屏）就已经按拼音过滤卡片了。

### 零网络
- [x] **HTML 转换（审查报告 B 项）：0 次请求。** 方法：本机开一个陷阱 HTTP 服务器（127.0.0.1:8765，任何进程来访问都会记录），往剪贴板放一段纯 HTML（没有 RTF，保证走 HTML 转换），里面用 link、@import、背景图 url()、script、img、srcset、iframe、video poster、svg image、内联 style url()、object、embed、table background 共 14 种写法指向陷阱服务器。在粘贴栏里对这张卡片执行「清除格式后粘贴」和「粘贴为 Markdown」：陷阱服务器 0 次访问，同时每 0.5 秒用 lsof 检查 Pesty，也没有任何网络连接。
  - Markdown 输出正确：`**粗体中文**和*斜体*，还有一个[链接](https://example.com/)。`，h2 转成粗体，中文没有乱码。
  - 这个方法比直接盯 Pesty 进程更可靠：WebKit 的加载可能发生在 `com.apple.WebKit.Networking` 进程里，只看 Pesty 会漏；而浏览器复制的内容通常带 RTF，根本走不到 HTML 那条路。
- [x] **闲置 5 分钟**（`scripts/dev/measure_idle.sh`）：网络连接 `none`；平均 CPU 0.01%（5 分钟内共用了 0.55 秒 CPU 时间）；内存 phys_footprint 56 MB（峰值 310 MB，出现在前面做 HTML 转换的时候，WebKit 导入器用掉的，之后就释放了），RSS 约 148 MB。另外在 HTML 测试和闲置测试期间，每 0.5 秒检查一次连接，持续约 15 分钟，一次也没出现。
- 持久化顺带确认：复制一条后正常退出、重新打开，历史保留。

### 基本功能
- [x] **密码管理器（Bitwarden 桌面版）不会被记录**：Bitwarden 复制密码时会打上 `org.nspasteboard.ConcealedType` 标记，Pesty 默认开启的「忽略密码」会跳过它，所以不用加进「排除的 App」。
- [x] 用脚本模拟复制，四种类型都正确识别：文件（file）、颜色（color，#FF599E）、图片（image，TIFF 存成 PNG）、富文本（richText，带 RTF）。
- [x] 粘贴：富文本和颜色都能粘进「文本编辑」，颜色粘出来是 `#FF599E` 文本。用户确认没问题，图片、文件的粘贴和固定板没有逐项测试（用户决定跳过）。
- 截图需要终端有「屏幕录制」权限，没有改这个系统设置，改用直接复制图片来测。

### 本地化
- 设置页「历史和固定板占用空间」右边的「1 个片段 · 4 KB」被挤成两行（KB 单独换行）。

## 第 9 步：iCloud Drive 同步的决定（2026-10-22）
- 用户决定：**先不用同步，代码保持不变**（方案 A、B 都没做）。
- 理由：同步默认是关的（`iCloudSync` 默认 false，本机也没设置过）；粘贴栏上的同步按钮只在已经开启同步时才显示（`BarView.swift` 的 `if settings.iCloudSync { syncButton }`），所以只有去设置里手动打开开关才会启用，不会误触开启。不开同步，审查报告 A/D/E/F 几条风险就不会触发。
- 说明：这个同步是 **Mac 和 Mac 之间**通过 iCloud Drive 同步 store.json，不包括 iPhone。iPhone 和 Mac 之间复制粘贴用系统自带的「通用剪贴板」（接力），Pesty 会照常记录在 Mac 上粘贴过来的内容。
- 以后想要多台 Mac 同步，再按 HANDOFF 第 2 节步骤 9 的方案 A（墓碑）来做；想彻底删掉，就按方案 B。

## 没有测的和遗留事项
- 没有测：固定板（新建、重命名、固定、删除）；图片和文件的粘贴效果（用户决定跳过）；本地化的完整检查和英文启动。
- 签名证书 2027-10-22 过期。过期后已经装好的 App 照常运行；要重新编译就得新建证书，新证书指纹不同，需要重新授权辅助功能。
- `SettingsView.swift:104` 的 Combine 警告没有修（加一行 `import Combine` 就能消掉）。
