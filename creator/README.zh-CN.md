# 宠物制作器

这个目录提供自定义宠物制作入口。运行器只认标准宠物包：

```text
assets/<pet-id>/
  pet.json
  spritesheet.png
  spritesheet.webp
```

制作器负责把文字描述、参考图片和模型配置变成这个格式。

## 启动

图形界面：

```text
..\start-creator.bat
```

校验配置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PetCreator.ps1 -Command validate-config
```

创建请求：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PetCreator.ps1 `
  -Command new-request `
  -PetId my-pet `
  -DisplayName "My Pet" `
  -Description "一只可爱的自定义桌宠，贴纸风格"
```

生成并安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PetCreator.ps1 `
  -Command generate `
  -RunDir .\runs\my-pet-20260518-203000 `
  -Install
```

## Provider

默认 `local-template` 是离线模板生成器，用来测试完整流程，不调用 AI 模型。

接入真实模型时，复制：

```text
model-config.example.json -> model-config.local.json
```

然后把 provider 设置为 `command`。你的命令会收到：

```text
PET_CREATOR_REQUEST
PET_CREATOR_OUTPUT_DIR
PET_CREATOR_REFERENCE_IMAGE
PET_CREATOR_PET_ID
PET_CREATOR_DISPLAY_NAME
PET_CREATOR_DESCRIPTION
```

命令需要把以下文件写到 `PET_CREATOR_OUTPUT_DIR`：

```text
pet.json
spritesheet.png
```

## 输出规格

```text
spritesheet.png
1536 x 1872
8 列 x 9 行
单格 192 x 208
透明背景
```

## 安全边界

- 不把 API Key 写进仓库。
- 推荐从环境变量读取模型密钥。
- 导入共享宠物包时不执行脚本。
- 参考图片和生成结果的版权由使用者自行确认。
