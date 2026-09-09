# WARSEED 临时反馈服务器操作指南

本工具让一台 Windows 电脑在试玩期间临时收集匿名意见。它不是公网生产服务，不应直接映射到互联网。

## 最快启动

试玩包解压后，服务器电脑双击：

```text
START_WARSEED_FEEDBACK_SERVER.cmd
```

脚本使用 Python 3 标准库，监听本机所有网卡的 `8765` 端口，并打印每个可用局域网地址。首次启动若 Windows 防火墙询问，只允许“专用网络”，不要允许公用网络。

数据默认保存在：

```text
%LOCALAPPDATA%\WARSEED\feedback-server\submissions\
```

关闭服务器窗口或按 `Ctrl+C` 即停止收集，已有 JSON 不会删除。

## 同一台电脑试玩

包内 `feedback_server_url.txt` 默认是：

```text
http://127.0.0.1:8765/feedback
```

先启动服务器，再双击 `START_WARSEED_PLAYTEST.cmd`。每次合法反馈会先保存在 Godot 用户数据目录，然后发送到本机。

## 局域网多台电脑试玩

1. 在服务器窗口找到类似 `http://192.168.1.20:8765/feedback` 的地址；
2. 将每台试玩电脑包内 `feedback_server_url.txt` 改为该地址，文件只保留一行；
3. 确保设备位于同一个受信任的专用局域网；
4. 在试玩电脑浏览器访问 `http://服务器IP:8765/health`，应看到 `status: ok`；
5. 启动试玩。掉线时反馈留在玩家电脑，恢复后可在战后问卷点击“重试待发送反馈”。

也可从 PowerShell 指定端口或数据目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start_feedback_server.ps1 `
  -Lan -Port 8765 -DataDirectory "D:\WARSEED-Feedback"
```

## 查看与导出

- 看板：`http://127.0.0.1:8765/dashboard`
- 健康检查：`http://127.0.0.1:8765/health`
- JSON 汇总：`http://127.0.0.1:8765/api/summary`
- CSV 下载：`http://127.0.0.1:8765/export.csv`

看板重点汇总评分、错误报告数和玩家选择的“优先完善板块”。CSV 包含开放回答，适合后续按重复问题、严重度和涉及板块归类。

## 隐私和边界

- 默认匿名，不要求姓名、账号或联系方式；
- 自动字段只有构建、关卡、战果、语言、分辨率、局数和匿名会话 ID；
- HTTP 服务会在控制台显示请求来源地址，但不会把 IP 写入反馈 JSON；
- 当前是局域网明文 HTTP，必须只用于受信任的临时网络；
- 删除服务端数据前应先停止服务并备份所需 JSON/CSV；
- 游戏内自填反馈属于玩家意见记录，但不自动等同于严格观察员 `HUMAN` 放行证据。

## 常见问题

端口被占用时，换一个端口并同步修改 `feedback_server_url.txt`。局域网无法访问时，依次检查服务器窗口仍在运行、两机是否同网段、防火墙是否允许 Python 的专用网络访问，以及地址是否误用了 `127.0.0.1`。
