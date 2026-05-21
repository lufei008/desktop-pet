# 桌面小宠物

一个轻量级 Windows 桌面小宠物。当前版本使用 PowerShell + WPF，可以直接运行，不需要编译，也不依赖 Codex 运行。

English: [README.md](README.md)

## 功能

- 透明无边框桌宠窗口，默认置顶
- 支持 `assets/` 下多个宠物包，右键切换宠物
- 右键切换语言：中文 / English
- 托盘图标：显示、隐藏、切换动作、退出
- 位置、大小、语言、宠物、置顶、锁定状态会保存到 `data/settings.json`
- 可选开机自启
- 本地 API：`http://127.0.0.1:17888/state`
- 系统状态联动：CPU、内存、用户空闲、电池状态会影响宠物动作
- 宠物生活状态：饱食、清洁、心情、精力
- 右键互动：喂食、打扫、洗澡、玩耍、休息
- Bully 和 Kai 已扩展专用互动/生活状态动画
- 宠物包导入/导出 `.pet.zip`
- 宠物制作器目前作为实验入口保留，后续再继续扩展

## 快速启动

双击：

```text
start-pet.bat
```

启动指定宠物：

```text
start-pet.bat bully
start-pet.bat kai
```

PowerShell 启动：

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\DesktopPet.ps1 -PetId bully
```

启动宠物制作器：

```text
start-creator.bat
```

## 操作

- 左键点击：打招呼
- 双击：跳一跳
- 拖动：移动宠物
- 右键：切换宠物、切换语言、切换动作、喂食、打扫、洗澡、玩耍、休息、锁定位置、系统联动、开机自启、放大、缩小、置顶、退出
- 托盘图标双击：显示宠物

## 生活互动

每只宠物会保存独立的生活状态：

```text
饱食：太低时会求关注
清洁：太低时会求关注
心情：太低时会委屈趴下
精力：太低时会休息或委屈趴下
```

右键互动效果：

```text
喂食 -> 增加饱食、心情、精力
打扫 -> 增加清洁、心情
洗澡 -> 大幅增加清洁，消耗少量精力
玩耍 -> 增加心情，消耗精力、饱食和清洁
休息 -> 增加精力
```

生活状态会随时间缓慢下降，保存在 `data/care.json`。

## 系统状态联动

默认开启。右键菜单可以关闭。

当前规则：

```text
CPU >= 82%              -> 专注中
CPU >= 95% 且内存 >= 90% -> 委屈趴下
内存 >= 88%             -> 求关注
用户空闲 >= 5 分钟       -> 休息
用户空闲后回来           -> 打招呼
电量 <= 15% 且未充电     -> 求关注
```

规则使用最近几次采样的平均值，并有最短保持时间，避免动作频繁跳变。

## 本地 API

读取状态：

```powershell
Invoke-WebRequest http://127.0.0.1:17888/state
```

触发动作：

```powershell
Invoke-WebRequest 'http://127.0.0.1:17888/action?state=waving'
```

照顾宠物：

```powershell
Invoke-WebRequest 'http://127.0.0.1:17888/care?action=feed'
Invoke-WebRequest 'http://127.0.0.1:17888/care?action=play'
```

可用状态：

```text
idle
running-right
running-left
waving
jumping
failed
waiting
running
review
feeding
cleaning
bathing
playing
resting
hungry
dirty
tired
lonely
```

## 宠物包格式

每只宠物一个目录：

```text
assets/<pet-id>/
  pet.json
  spritesheet.png
  spritesheet.webp
```

运行器使用 `spritesheet.png`。

图集规格：

```text
1536 x 3744
8 列 x 18 行
单格 192 x 208
透明背景
```

旧的 9 行宠物包仍可运行；缺少扩展动画时，运行器会自动退回到基础动作。

行定义：

```text
0 idle / 休息
1 running-right / 向右挪动
2 running-left / 向左挪动
3 waving / 打招呼
4 jumping / 跳一跳
5 failed / 委屈趴下
6 waiting / 求关注
7 running / 专注中
8 review / 认真观察
9 feeding / 喂食
10 cleaning / 打扫
11 bathing / 洗澡
12 playing / 玩耍
13 resting / 休息
14 hungry / 饥饿
15 dirty / 需要清洁
16 tired / 疲惫
17 lonely / 孤单
```

## 分享宠物

导出：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-Pet.ps1 -PetId bully
```

导入：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Import-Pet.ps1 -PackagePath .\exports\bully.pet.zip
```

导入工具只接受 `pet.json`、`spritesheet.png`、`spritesheet.webp`、预览图和说明文件，不执行别人宠物包里的脚本。

## 制作宠物（暂缓扩展）

目前先保留实验入口，主线先做桌宠本体互动。图形界面：

```text
start-creator.bat
```

命令行创建并安装一个离线模板宠物：

```powershell
$request = powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\creator\PetCreator.ps1 `
  -Command new-request `
  -PetId demo-dog `
  -DisplayName "Demo Dog" `
  -Description "一只戴蓝帽子的可爱英式斗牛犬，贴纸风格"

$run = ($request | ConvertFrom-Json).runDir

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\creator\PetCreator.ps1 `
  -Command generate `
  -RunDir $run `
  -Install
```

真正接入模型时，复制 `creator/model-config.example.json` 为 `creator/model-config.local.json`，把 provider 配成 `command`，让你的脚本读取请求 JSON，并把 `pet.json` 和 `spritesheet.png` 写入输出目录。

## 开源说明

代码使用 MIT License，见 [LICENSE](LICENSE)。

仓库里的宠物图是本项目生成的资源。如果你替换或新增宠物，请确认自己有权分享对应素材。
