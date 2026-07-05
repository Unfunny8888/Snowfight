# Snowfight ❄️

A native iOS recreation of the classic late-90s **SnowCraft** snowball fight game —
same idea, same structure, rebuilt with modern touches.

Your team of three red kids defends the bottom of a snowy field against waves of
green kids. Duck behind snow forts, pelt the enemy, and survive as many levels
as you can.

## What's in the game

**Faithful to the original**
- Red team vs. green team snowball battle on a snowy field
- Chunky pixel-art kids (windup + throw animations, knockdowns, buried KOs)
- Destructible snow forts that soak up hits and crumble in stages
- Arcing snowballs with shadows, splat marks left in the snow

**Improvements over the original**
- Endless **levels** with scaling difficulty: more enemies, faster movement,
  quicker and more accurate throwing every level
- **Power-ups** that drop onto the field:
  - ❄️ Mega Balls — bigger snowballs that deal double damage
  - ☕️ Cocoa — heals the whole team
  - ⚡️ Rapid Fire — much faster throw cooldown
- Per-kid **HP pips**, knockdown invulnerability frames, and between-level healing
  (downed teammates climb back up with 1 HP)
- **Score & high score** with survivor bonuses, persisted between runs
- **Haptic feedback** for throws, hits, KOs, and level clears
- **Synthesized retro sound effects** — generated at launch, no audio files
- Falling snow, pause menu, and a proper title screen

All art is procedurally generated pixel art (rendered from pixel maps in code),
so the project contains no image or audio assets beyond the app icon.

## Controls

| Action | Gesture |
|---|---|
| Throw a snowball | Touch one of your kids and **drag** — an arrow shows the shot; release to throw. Longer drag = longer throw. |
| Move | **Tap** the snow to send the selected kid there |
| Select a kid | Tap them |
| Pause | `II` button, top-right |

## Requirements & running

- **Xcode 16+** (the project uses buildable-folder references)
- iOS 16.0+ deployment target, iPhone & iPad, portrait

```
open Snowfight.xcodeproj
```

Pick a simulator or device and hit **Run**. There are no dependencies to
install — the project is a single app target with zero packages.

## Project layout

```
Snowfight/
├── SnowfightApp.swift        SwiftUI entry point hosting the SpriteKit view
└── Game/
    ├── MenuScene.swift       Title screen
    ├── GameScene.swift       Battlefield: input, game loop, AI, scoring
    ├── KidNode.swift         A kid: HP, movement, animations, knockdowns
    ├── FortNode.swift        Destructible snow fort
    ├── Snowball.swift        Arcing projectile with fake-height simulation
    ├── PowerUpNode.swift     Field pickups
    ├── PixelArt.swift        All textures, generated from pixel maps
    ├── SoundSynth.swift      Runtime-synthesized WAV sound effects
    ├── Haptics.swift         Feedback generators
    ├── GameConfig.swift      Every tuning knob in one place
    └── GameMath.swift        CGPoint helpers
```
