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
- Three ways to play:
  - **Solo** — endless levels vs. AI, scaling difficulty
  - **2 Players · 1 Device** — same-screen versus, one team per half, first to 3 rounds
  - **Nearby · 2 Devices** — auto-matchmade local-network battle over MultipeerConnectivity
- Endless **levels** with scaling difficulty: more enemies, faster movement,
  quicker and more accurate throwing every level
- **Power-ups** that drop onto the field:
  - ❄️ Mega Balls — bigger snowballs that deal double damage
  - ☕️ Cocoa — heals the whole team
  - ⚡️ Rapid Fire — much faster throw cooldown
- Per-kid **HP pips**, knockdown invulnerability frames, and between-level healing
  (downed teammates climb back up with 1 HP)
- **Score & high score** with survivor bonuses, persisted between runs
- **Haptic feedback** and **screen shake** on knockouts; **footprints** in the snow
- **Character-voiced audio** faithful to the original's charm: synthesized kid
  voices ("ow!", the wailing cry of a downed kid, giggles, cheers) over soft
  snow foley, plus a jaunty looping chiptune. Music and sound toggle from the menu.

All art **and audio** are procedurally generated at runtime (pixel maps and a
tiny PCM voice/chiptune synth), so the project contains no image or audio assets
beyond the app icon.

### Multiplayer

- **Same-device versus** splits the screen: the bottom player drives the red
  team, the top player the green team, each with their own aim arrow. Best of
  five rounds.
- **Nearby versus** needs no codes or setup — open *Nearby* on two devices on
  the same Wi-Fi/Bluetooth and they find each other automatically, roll for
  host, and drop into the match. The host simulates the whole battle and streams
  ~12 snapshots/second; the guest renders them (board flipped so its own team is
  at the bottom) and sends back touch commands. Requires local-network
  permission, declared in `Info.plist`.

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
├── Info.plist                Local-network / Bonjour keys for nearby play
└── Game/
    ├── MenuScene.swift       Title screen + mode select + audio toggles
    ├── LobbyScene.swift      Nearby-match auto-matchmaking screen
    ├── GameScene.swift       Battlefield: input, game loop, AI, scoring, host sim
    ├── OnlineGuestScene.swift Guest renderer for nearby matches
    ├── GameMode.swift        Solo / local-versus / host-online
    ├── MultipeerSession.swift Local-network connection + role election
    ├── NetProtocol.swift     Codable wire format (snapshots, inputs, events)
    ├── KidNode.swift         A kid: HP, movement, animations, knockdowns
    ├── FortNode.swift        Destructible snow fort
    ├── Snowball.swift        Arcing projectile with fake-height simulation
    ├── PowerUpNode.swift     Field pickups
    ├── PixelArt.swift        All textures, generated from pixel maps
    ├── SoundSynth.swift      Runtime-synthesized voices, foley, and music
    ├── Haptics.swift         Feedback generators
    ├── GameConfig.swift      Every tuning knob in one place
    └── GameMath.swift        CGPoint helpers
```
