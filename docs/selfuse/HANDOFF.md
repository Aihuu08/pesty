# 交接说明：Pesty 自用版（写给 Mac 上的 Claude Code）

> 你好，接手的 Claude。这份文档由云端会话写成：云端在 Linux 容器里完成了代码，用 fork 上的 GitHub Actions（macOS）完成了编译和测试，但**没有在真实的 Mac 桌面上运行过 App**。你的任务是带用户在他的 M3 Max 上把剩下的步骤走完。
>
> **关于用户**：开发新手，中文母语。请用中文、一步一步地说明；每条命令都解释它做什么；需要用户动手的地方（系统设置、点按钮）要写清楚在哪里点。不要假设用户懂 git 或 Xcode。

---

## 0. 用户定下的规则（必须遵守）

1. 自用版本，**不上架、不发布**。
2. **不新增第三方依赖**，**不加任何联网代码**（包括遥测、更新检查）。每次改完都用下面的命令确认：
   ```bash
   grep -rnE 'URLSession|NSURLConnection|Network\.|nw_|CFSocket|WKWebView|SCNetwork|CFStream|getaddrinfo|socket\(' Sources || echo "no network APIs"
   ```
3. 保留 MIT 许可证和原作者（momenbasel）的版权声明。
4. **不要运行** `scripts/sign_notarize.sh`、`scripts/release_build.sh`、`scripts/build_mas.sh`，里面用的是原作者的签名身份。**不要修改 `#if MAS` 里的 CloudKit 代码**，发现问题只报告。
5. 没能在本机验证的结论，一律标注“未验证”。
6. **删除文件或大范围重构之前，先问用户。** 不加新功能，除非用户同意。
7. 只推送到用户自己的 fork（`Aihuu08/pesty`），**不要 force push**。当前分支：`claude/sweet-thompson-fycdit`。
8. 卸载 Homebrew 版之前**先问用户**。

---

## 1. 已经做完的事

| 阶段 | 提交 | 内容 |
|---|---|---|
| 1 | `d2126e5` | 安全审查报告 `docs/selfuse/01-security-review.md`（**请先读它**）；复现测试；CI 增加 `swift test`，并对 `claude/**` 分支也触发 |
| 2 | `4e8a200` | 搜索：拼音全拼和首字母、简繁互搜、全半角/大小写/变音折叠，每个片段预先建索引；修复输入法问题（首字符触发聚焦的路径、fallback 路径、组字时的数字键） |
| 2 | `1db9a75` | 简体中文界面：`packaging/Localizable.xcstrings`（193 条），`build_app.sh` 编译进 `.app`，Info.plist 声明 en 和 zh-Hans |
| 3 | `1c39ac7` | iCloud Drive 监听每次事件后重新挂载；图片文件名只允许纯文件名（修复路径穿越）；store.json 读不出来时先另存一份，不再被覆盖；粘贴文件类片段只接受 file URL；拖拽链接只允许 http(s) |
| 3 | （本文档所在提交） | `build_app.sh` 支持 `SIGN_IDENTITY` 自签证书签名；`scripts/dev/measure_idle.sh`；本交接文档 |

CI（GitHub 的 macOS 15 + Xcode 26.3）的结果见第 6 节。

### 新增和修改的主要文件
- `Sources/Pesty/Search/SearchIndex.swift`、`ClipSearch.swift`：搜索索引，只用 Foundation 和系统 ICU 变换
- `Sources/Pesty/Util/InputSourceKind.swift`：判断当前是输入法还是纯键盘布局
- `Sources/Pesty/Store/FileChangeWatcher.swift`、`StoredFileName.swift`：监听修复、文件名校验
- `packaging/Localizable.xcstrings`：字符串目录，是唯一的翻译来源
- `scripts/dev/extract_l10n_keys.py --check`：检查源码里的字符串是否都在目录中，并且都有中文
- `Tests/PestyTests/*`：新增 30 多个测试，包括搜索和保存的基准测试

---

## 2. 你要做的事（按顺序）

### 步骤 1：检查环境
```bash
xcodebuild -version   # 需要 Xcode 26 或更高（代码用到 macOS 26 SDK 的 NSGlassEffectView，Xcode 16 编不过）
swift --version
```
如果没有 Xcode 26：让用户从 App Store 安装 Xcode，装好后运行一次 `sudo xcodebuild -license accept`，再运行 `sudo xcode-select -s /Applications/Xcode.app`。

### 步骤 2：备份（必须先做，做完再继续）
先让用户**退出正在运行的 Pesty**（菜单栏图标 → Quit Pesty），然后：
```bash
BK=~/Pesty-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK"
[ -d ~/Library/Application\ Support/Pesty ] && ditto ~/Library/Application\ Support/Pesty "$BK/ApplicationSupport-Pesty"
[ -d ~/Library/Mobile\ Documents/com~apple~CloudDocs/Pesty ] && ditto ~/Library/Mobile\ Documents/com~apple~CloudDocs/Pesty "$BK/iCloudDrive-Pesty"
defaults export com.greycorelabs.pesty "$BK/defaults.plist" 2>/dev/null || true
ls -la "$BK"; du -sh "$BK"
```
把 `$BK` 的完整路径告诉用户，并记下来，回滚时要用。
顺便记录一下现在 store.json 的大小：`ls -l ~/Library/Application\ Support/Pesty/store.json`。

### 步骤 3：编译和测试
```bash
swift build && swift test 2>&1 | tail -40
```
- 应该全部通过。
- 记下输出里 `SEARCH-BENCH`、`SAVE-BENCH`、`HTML-IMPORT-NETWORK` 这几行。
- 想看更准的性能数字（release 构建），可以跑：
  ```bash
  swift test -c release -Xswiftc -enable-testing --filter 'SearchBenchmarkTests/testSummary|SaveBenchmarkTests'
  ```

### 步骤 4：自签名证书（加固签名，审查报告第 G 条）
让用户在「钥匙串访问」里操作：
1. 菜单栏 **钥匙串访问 → 证书助理 → 创建证书…**
2. 名称填 `Pesty Local Signing`；身份类型选 **自签名根证书**；证书类型选 **代码签名**；点「创建」。
3. 确认：`security find-certificate -c "Pesty Local Signing" -Z | grep SHA-1`

如果用户不想做这一步，可以跳过，`build_app.sh` 会退回到 ad-hoc 签名并打印提示。

### 步骤 5：打包
```bash
SIGN_IDENTITY="Pesty Local Signing" VERSION=1.3.0-ou BUILD=1 ./scripts/build_app.sh
codesign -dv --verbose=2 packaging/Pesty.app 2>&1 | grep -E 'Identifier|Authority|Signature'
codesign -d -r- packaging/Pesty.app   # 应该能看到 certificate leaf = H"…"
ls packaging/Pesty.app/Contents/Resources/   # 应该有 en.lproj 和 zh-Hans.lproj
```
第一次签名时，钥匙串会弹窗询问是否允许 codesign 使用这个密钥，让用户点「始终允许」。

### 步骤 6：处理已经装着的版本
```bash
brew list --cask 2>/dev/null | grep -i pesty; ls -d /Applications/Pesty.app 2>/dev/null
```
- 如果装着 Homebrew 版，**先问用户**。同意后运行：`brew uninstall --cask momenbasel/pesty/pesty`
- 如果 `/Applications/Pesty.app` 是 App Store 版或手动安装的版本，同样先问，再移到废纸篓。

### 步骤 7：安装和授权
```bash
ditto packaging/Pesty.app /Applications/Pesty.app
open /Applications/Pesty.app
```
引导用户授权辅助功能：**系统设置 → 隐私与安全性 → 辅助功能**。如果列表里有旧的 Pesty，先用「−」删掉，再用「+」添加 `/Applications/Pesty.app`，然后打开开关。也可以在 Pesty 的设置 → 权限里点「打开设置」。

### 步骤 8：验证清单（和用户一起逐项打勾）
**基本功能**
- [ ] 热键（默认 ⇧⌘V）能呼出粘贴栏
- [ ] 回车直接粘贴到前一个 App；⇧+快速粘贴数字键会以纯文本粘贴
- [ ] 各类片段都能记录和粘贴：文本、富文本（从「文本编辑」或 Pages 拷贝）、图片（截图后 ⌘⌃⇧4）、文件（在访达里拷贝）、颜色（从颜色面板拷贝）
- [ ] 固定板：新建、重命名、把片段固定进去、删除
- [ ] 用你的密码管理器拷贝一次密码，确认 Pesty **没有**记录。如果记录了，在设置 → 隐私里把它加进「排除的 App」，并告诉用户

**中文输入法（系统简体拼音）**
- [ ] 呼出粘贴栏，**不点搜索框**，直接用拼音打「nihao」：第一个字母就应该进入拼音组字（出现候选框），而不是变成英文字母 n
- [ ] 组字时按回车：应该上屏英文字母，**不会**粘贴片段；组字时按方向键：应该在候选词之间移动，**不会**切换卡片
- [ ] 组字时按数字 1–9 选词：应该正常选词，**不会**触发快速粘贴
- [ ] 组字时按 Esc：应该取消组字，**不会**关掉粘贴栏
- [ ] 选词上屏后，按回车粘贴当前选中的片段
- [ ] 中文搜索：「你好」、「nihao」、「nh」都能找到含「你好」的片段；繁体「這個」能找到简体「这个」
- [ ] 搜索框里删除时，组字状态下的 Backspace 只删拼音

**本地化**
- [ ] 用简体中文启动：`open -n /Applications/Pesty.app --args -AppleLanguages "(zh-Hans)"`，检查设置页、菜单栏菜单、右键菜单、提示条、卡片底部、空状态、编辑器，看有没有漏翻或文字被截断的地方（截图给用户看）
- [ ] 用英文启动一次：`--args -AppleLanguages "(en)"`
- [ ] 先退出再切换语言：`osascript -e 'quit app "Pesty"'`

**零网络**
- [ ] 让 Pesty 闲置 5 分钟：`scripts/dev/measure_idle.sh`，最后一节应该显示 `none`
- [ ] **审查报告 B 项**：从网页拷贝一段带图片的内容，在粘贴栏里右键该片段 →「清除格式后粘贴」和「粘贴为 Markdown」。同时在另一个终端运行 `nettop -p $(pgrep -x Pesty) -L 5`，或者在执行前后各跑一次 `lsof -nP -i -a -p $(pgrep -x Pesty)`。如果出现连接，说明 HTML 导入会联网，按第 4 节处理

### 步骤 9：需要用户做的决定（用 AskUserQuestion 问）
**iCloud Drive 同步怎么处理？**（用户先说过「阶段 3 再决定」，后来又说「全听你的建议」。云端没有替他做这个决定，只修了监听和文件名安全。）

- **方案 A：保留，并加墓碑（tombstone）**
  - `Snapshot` 增加可选字段 `deletedIDs: [UUID: Date]`；旧版本的 JSON 没有这个字段，按空处理，**向后兼容**。
  - 删除和裁剪时记一条墓碑；`mergeExternal` 合并时跳过有墓碑的 id。墓碑保留 30 天后清理。
  - `mergeExternal` 补上「排除的 App」过滤。
  - 优点：多台 Mac 同步可用，删除不再复活。缺点：约 80–120 行改动；需要两台 Mac 才能真正验证；剪贴板历史仍然以明文放在 iCloud Drive（除非开启「高级数据保护」）。
- **方案 B：移除 iCloud Drive 同步**
  - 删除设置开关、粘贴栏上的同步按钮、`setICloudSync`、`mergeExternal`、`copyImages`、`FileChangeWatcher` 等。
  - 如果用户现在开着同步，先把数据迁回 `~/Library/Application Support/Pesty`。
  - 优点：代码更少，隐私最好，审查报告的 A/D/E/F 几条风险整体消失。缺点：以后想在多台 Mac 之间同步就没有了。
  - **这是删除代码，动手前必须得到用户明确同意。**
- **云端的建议**：如果用户只有一台 Mac，或者不需要同步，选 **B**；需要多台 Mac 同步，选 **A**。
- 先问清楚：「你有几台 Mac？需要在它们之间同步剪贴板吗？」

### 步骤 10：最终交付
告诉用户：改了什么（第 1 节）、性能数据（第 6 节 + 本机实测）、还剩什么问题（第 5 节）、他还需要手动做什么、怎么回滚（第 3 节）。

---

## 3. 回滚办法
1. 退出 Pesty：`osascript -e 'quit app "Pesty"'`
2. 删掉自编译版：`rm -rf /Applications/Pesty.app`
3. 恢复数据（`$BK` 是步骤 2 的备份目录）：
   ```bash
   rm -rf ~/Library/Application\ Support/Pesty
   ditto "$BK/ApplicationSupport-Pesty" ~/Library/Application\ Support/Pesty
   defaults import com.greycorelabs.pesty "$BK/defaults.plist"
   ```
4. 想换回官方版：`brew install --cask momenbasel/pesty/pesty`
5. 只想撤销代码改动：`git checkout main`，然后重新编译。也可以 `git revert <提交号>` 只撤销其中某个阶段。

数据格式说明：本次改动**没有改变** store.json 的格式，旧版 Pesty 能直接读新版写出的数据，反过来也一样。如果以后加墓碑（方案 A），新增的是可选字段，旧版会忽略它。

---

## 4. 如果 HTML 导入会联网（审查报告 B 项）
CI 里有一个测试 `HTMLImportNetworkTests`：它在 127.0.0.1 上开一个监听端口，再把引用这个地址的 HTML 交给 `FormatConverter`，看有没有连接进来。这个监听只在测试代码里，不在 App 里。
- 测试**通过**：HTML 导入不会去加载远程资源。请把审查报告 B 项改成「已验证（CI 与本机）：不联网」。
- 测试**失败**：在 `FormatConverter.attributed(for:)` 里导入 HTML 之前，先去掉 `<img>`、`<link>`、`<script>`、`<iframe>`、`<object>`、`<embed>` 标签，`<style>` 块里的 `@import`，以及所有 `url(...)`；或者干脆只用 RTF。改完后测试应该通过。这算安全修复，不算新功能，但还是要告诉用户。

---

## 5. 已知限制和遗留问题
- **多音字**：每个汉字只取默认读音（重庆 → zhongqing，银行 → yinxing）。要支持多音字需要自带词典，这违反「不加依赖」，所以没做。
- 单个片段只为前 10,000 个字符生成拼音；普通的折叠搜索覆盖全文。
- 卡片预览最多排版前 1,500 个字符（10 行内肯定够用），用来避免超大片段拖慢界面。
- 输入法的主路径修复（`inputContext.activate()`）**未在真机验证**，以第 8 步的人工测试为准。如果首字母仍然以英文出现，备选方案是：在 `AppController.handleKey` 里聚焦成功后不再返回原事件，而是 `DispatchQueue.main.async { NSApp.postEvent(event, atStart: true) }` 重新投递一次。
- `Theme.swift` 里的 `clipRelative` 没有任何地方用到，是死代码。按规则没有删，要删先问用户。
- 第一次搜索前，后台需要先建好索引（5000 条在 CI 的 debug 构建上约 0.5 秒）。在这之前搜索也能用，只是会在主线程上按需逐条建索引。
- iCloud Drive 同步：删除会复活，排除的 App 规则在合并时也不生效（报告 D 项），等第 2 节步骤 9 的决定。
- 每次捕获都会重写整个 store.json。目前的 CI 数据见第 6 节；如果本机数据显示主线程耗时明显（超过 15ms），可以把 `saveNow` 的编码和写入挪到后台串行队列，格式不变。动手前先给用户看数据。

## 6. CI 数据（GitHub macOS 15 runner，debug 构建，仅供参考；以本机为准）
| 项目 | 旧 | 新 |
|---|---|---|
| 5000 条历史，每次按键过滤 | 167.5 ms | 5.8 ms |
| 5000 条建索引（后台，一次性） | — | 546 ms |
| store.json 保存（5000 条，含富文本） | 见下方 SAVE-BENCH | — |

SAVE-BENCH 和 HTML-IMPORT-NETWORK 的结果由最新一次 CI 填入，见第 7 节。

## 7. 最新 CI 结果
（这一节在推送时更新）
