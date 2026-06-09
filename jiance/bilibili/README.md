# B站私信监控 (Bilibili Message Monitor)

自动监控 B站私信 (message.bilibili.com)，检测到新消息时弹窗提醒。

## 工作原理

- 每 **10 分钟** 自动向 B站私信 API 发送请求，获取最新私信列表
- 使用 B站 WBI 签名机制，自动获取并计算签名密钥
- 检测 `session_list` 字段变化，有更新时弹出 Windows 通知
- 使用 Windows 任务计划程序在后台定时执行，开机自动运行

---

## 第一次使用

### 1. 导出 Cookies

在**当前文件夹**打开 PowerShell（在文件夹空白处 `Shift + 右键` → "在此处打开 PowerShell 窗口"），运行：

```
powershell -NoProfile -ExecutionPolicy Bypass -File ".\cdp-export-cookies.ps1"
```

脚本会：
- 重启 Edge 浏览器并自动打开 B站首页
- 请你在浏览器中**登录** `bilibili.com`
- 登录成功后，回到 PowerShell 窗口按 **Enter**
- 自动导出 cookies 到当前目录的 `cookies.txt`

> ⚠️ 注意：导出完成后 Edge **不要关闭**，保持打开可以延长 cookie 有效期。

### 2. 启动监控

双击 `start.bat` 即可。

脚本会自动：
- 创建 Windows 定时任务（每 10 分钟执行一次）
- 立即执行一次检查，验证一切正常

---

## 日常使用

启动后无需任何操作，脚本会在后台自动运行。

| 场景 | 你会看到 |
|------|---------|
| 有新私信 | 右下角弹出 Windows Toast 通知 "消息有更新，点击查看" |
| Cookie 过期 | 弹出气泡通知 "请重新登录网站并导出 cookies.txt" |
| 一切正常 | 无通知（安静运行） |

---

## Cookie 过期了怎么办？

Cookies 一般有效 **几小时到一天**。过期后会弹窗提醒。

在当前文件夹打开 PowerShell，重新导出：

```
powershell -NoProfile -ExecutionPolicy Bypass -File ".\cdp-export-cookies.ps1"
```

> 提示：导出 cookies 后不需要重新运行 `start.bat`，定时任务会自动使用新的 cookies。

---

## 常用操作

| 操作 | 方法 |
|------|------|
| 停止监控 | 双击 `stop.bat` |
| 修改检查频率 | `Win+R` → 输入 `taskschd.msc` → 找到 `BilibiliMessageMonitor` 任务 |
| 手动检查一次 | 在当前文件夹 PowerShell 中运行：`powershell -NoProfile -ExecutionPolicy Bypass -File ".\check-messages.ps1"` |
| 重新导出 cookie | 在当前文件夹 PowerShell 中运行：`powershell -NoProfile -ExecutionPolicy Bypass -File ".\cdp-export-cookies.ps1"` |

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `start.bat` | 一键启动：创建定时任务 + 首次检查 |
| `stop.bat` | 停止监控，删除定时任务 |
| `check-messages.ps1` | 核心检测脚本（含 B站 WBI 签名） |
| `cdp-export-cookies.ps1` | 通过 Edge CDP 导出 cookies（无需插件） |
| `config.json` | 配置文件（API 地址、请求头等） |
| `cookies.txt` | 导出的 cookies（自动生成，不要手动编辑） |
| `last_state.json` | 上次检查状态（自动生成，不要手动编辑） |
| `README.md` | 本说明文件 |