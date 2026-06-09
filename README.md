# 携客云消息监控 (XKY Monitor)

自动监控携客云平台 (console.xiekeyun.com) 的消息列表，检测到新消息时弹窗提醒。

## 工作原理

- 每 **10 分钟** 自动向携客云 API 发送请求，获取最新消息列表
- 对比前后两次的消息 ID 集合，有变化时弹出 Windows 通知
- 使用 Windows 任务计划程序在后台定时执行，开机自动运行

---

## 第一次使用

### 1. 获取 Company-Code

`config.json` 中的 `Company-Code` 是你的公司唯一标识，需要从浏览器中获取。

参考示意图 `company-code-guide.png`：

1. 浏览器登录 `console.xiekeyun.com`，进入消息列表页面
2. 按 **F12** 打开开发者工具，切换到 **Network（网络）** 标签页
3. 刷新页面，在请求列表中找到任意一条 `console.xiekeyun.com` 的请求
4. 点击该请求，在右侧 **Request Headers（请求头）** 中找到 `Company-Code` 字段
5. 将该值填入 `config.json` 的 `"Company-Code"` 中

### 2. 导出 Cookies

在**当前文件夹**打开 PowerShell（在文件夹空白处 `Shift + 右键` → "在此处打开 PowerShell 窗口"），运行：

```
powershell -NoProfile -ExecutionPolicy Bypass -File ".\export-cookies.ps1"
```

脚本会：
- 重启 Edge 浏览器并自动打开携客云登录页
- 请你在浏览器中**登录** `console.xiekeyun.com`
- 登录成功后，回到 PowerShell 窗口按 **Enter**
- 自动导出 cookies 到当前目录的 `cookies.txt`

> ⚠️ 注意：导出完成后 Edge **不要关闭**，保持打开可以延长 cookie 有效期。

### 3. 启动监控

双击 `start.bat` 即可。

脚本会自动：
- 创建 Windows 定时任务（每 10 分钟执行一次）
- 立即执行一次检查，验证一切正常

---

## 日常使用

启动后无需任何操作，脚本会在后台自动运行。

| 场景 | 你会看到 |
|------|---------|
| 有新消息 | 右下角弹出气泡通知 "页面内容已更新！" |
| Cookie 过期 | 弹出气泡通知 "请重新导出 cookies.txt" |
| 一切正常 | 无通知（安静运行） |

---

## Cookie 过期了怎么办？

Cookies 一般有效 **几小时到一天**。过期后会弹窗提醒。

在当前文件夹打开 PowerShell，重新导出：

```
powershell -NoProfile -ExecutionPolicy Bypass -File ".\export-cookies.ps1"
```

> 提示：导出 cookies 后不需要重新运行 `start.bat`，定时任务会自动使用新的 cookies。

---

## 常用操作

| 操作 | 方法 |
|------|------|
| 停止监控 | 双击 `stop.bat` |
| 修改检查频率 | `Win+R` → 输入 `taskschd.msc` → 找到 `MessageMonitor` 任务 |
| 手动检查一次 | 在当前文件夹 PowerShell 中运行：`powershell -NoProfile -ExecutionPolicy Bypass -File ".\check-messages.ps1"` |
| 重新导出 cookie | 在当前文件夹 PowerShell 中运行：`powershell -NoProfile -ExecutionPolicy Bypass -File ".\export-cookies.ps1"` |

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `start.bat` | 一键启动：创建定时任务 + 首次检查 |
| `stop.bat` | 停止监控，删除定时任务 |
| `check-messages.ps1` | 核心检测脚本 |
| `export-cookies.ps1` | 通过 Edge CDP 导出 cookies（无需插件） |
| `config.json` | 配置文件（API 地址、请求头、Company-Code 等） |
| `cookies.txt` | 导出的 cookies（自动生成，不要手动编辑） |
| `last_state.json` | 上次检查状态（自动生成，不要手动编辑） |
| `company-code-guide.png` | Company-Code 获取示意图 |
| `README.md` | 本说明文件 |

---

## 分享给其他人

将整个文件夹压缩发送给对方。对方解压后需要：

1. **获取自己的 Company-Code**：参考 `company-code-guide.png` 示意图，按上方步骤操作
2. 修改 `config.json` 中的 `Company-Code` 为自己的公司代码
3. 在当前文件夹 PowerShell 中运行 `powershell -NoProfile -ExecutionPolicy Bypass -File ".\export-cookies.ps1"` 导出自己的 cookies
4. 双击 `start.bat` 启动

> 📌 解压位置没有要求，任意目录都可以，脚本会自动识别所在路径。
