# Desktop Pet

A lightweight Windows desktop pet. It runs independently with PowerShell + WPF, so there is no build step and no Codex runtime dependency.

中文说明见 [README.zh-CN.md](README.zh-CN.md).

## Features

- Transparent borderless desktop pet window, always on top by default
- Multiple pet packages under `assets/`
- Right-click pet switcher and language switcher
- Tray icon for show, hide, action switching, and exit
- Persisted pet, language, size, position, topmost, lock, API, and system-link settings
- Optional Windows auto-start
- Local API at `http://127.0.0.1:17888/state`
- System status link: CPU, memory, user idle time, and battery state can drive pet actions
- Pet care stats: fullness, cleanliness, mood, and energy
- Care interactions: feed, clean, bath, play, rest
- Bully and Kai now include dedicated interaction and care-state animations
- Pet package import/export as `.pet.zip`
- Pet creator is kept as an experimental entry point and is not the current focus

## Quick Start

Double-click:

```text
start-pet.bat
```

Start a specific pet:

```text
start-pet.bat bully
start-pet.bat kai
```

Or run with PowerShell:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\DesktopPet.ps1 -PetId bully
```

Open the creator:

```text
start-creator.bat
```

## Controls

- Left click: greeting animation
- Double click: jump animation
- Drag: move the pet
- Right click: pets, language, actions, care interactions, movement lock, system link, auto-start, size, topmost, exit
- Tray icon double-click: show the pet

## Pet Care

Each pet has its own saved care state:

```text
Fullness     low values make the pet ask for attention
Cleanliness  low values make the pet ask for attention
Mood         low values make the pet sulk
Energy       low values make the pet rest or sulk
```

Care interactions:

```text
Feed  -> increases fullness, mood, and energy
Clean -> increases cleanliness and mood
Bath  -> greatly increases cleanliness and costs a little energy
Play  -> increases mood and costs energy, fullness, and cleanliness
Rest  -> increases energy
```

Care values decay slowly over time and are saved in `data/care.json`.

## System Link

System link is enabled by default and can be disabled from the right-click menu.

Current rules:

```text
CPU >= 82%                -> focused
CPU >= 95% and RAM >= 90% -> sulking
RAM >= 88%                -> asking for attention
User idle >= 5 minutes    -> relaxing
User returns after idle   -> greeting
Battery <= 15%, unplugged -> asking for attention
```

The runtime uses short moving averages and a minimum hold time, so brief CPU spikes do not make the pet switch constantly.

## Local API

Read state:

```powershell
Invoke-WebRequest http://127.0.0.1:17888/state
```

Trigger an action:

```powershell
Invoke-WebRequest 'http://127.0.0.1:17888/action?state=waving'
```

Care for the pet:

```powershell
Invoke-WebRequest 'http://127.0.0.1:17888/care?action=feed'
Invoke-WebRequest 'http://127.0.0.1:17888/care?action=play'
```

Available states:

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

## Pet Package Format

Each pet lives in its own folder:

```text
assets/<pet-id>/
  pet.json
  spritesheet.png
  spritesheet.webp
```

The runtime uses `spritesheet.png`.

The spritesheet layout is:

```text
1536 x 3744
8 columns x 18 rows
192 x 208 cells
transparent background
```

Older 9-row pet packages still run. Missing extended animations fall back to base actions.

Rows:

```text
0 idle / relaxing
1 running-right / move right
2 running-left / move left
3 waving / greeting
4 jumping / jump
5 failed / sulking
6 waiting / asking for attention
7 running / focused
8 review / inspecting
9 feeding / feed
10 cleaning / clean
11 bathing / bath
12 playing / play
13 resting / rest
14 hungry / hungry
15 dirty / needs cleaning
16 tired / tired
17 lonely / lonely
```

## Share Pets

Export:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-Pet.ps1 -PetId bully
```

Import:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Import-Pet.ps1 -PackagePath .\exports\bully.pet.zip
```

The importer only accepts pet metadata, spritesheets, previews, readmes, and license files. It does not execute scripts from shared pet packages.

## Create Pets (Paused)

The creator is kept as an experimental entry point. The current product focus is the local pet runtime and interactions. Graphical creator:

```text
start-creator.bat
```

Command-line offline template example:

```powershell
$request = powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\creator\PetCreator.ps1 `
  -Command new-request `
  -PetId demo-dog `
  -DisplayName "Demo Dog" `
  -Description "A cute English bulldog with a blue cap, sticker style."

$run = ($request | ConvertFrom-Json).runDir

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\creator\PetCreator.ps1 `
  -Command generate `
  -RunDir $run `
  -Install
```

To connect a real model pipeline, copy `creator/model-config.example.json` to `creator/model-config.local.json`, configure a `command` provider, read the request JSON, and write `pet.json` plus `spritesheet.png` into the output directory.

## License

Code is licensed under the MIT License. See [LICENSE](LICENSE).

Pet artwork in this repository is generated project artwork. If you replace or add pets, make sure you have the right to share those assets.
