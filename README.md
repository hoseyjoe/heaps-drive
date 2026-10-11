# heaps-drive

Drive a Heaps app's real GUI from outside — click, type, wait, read state, screenshot — without the
user's mouse or keyboard. Presses are synthetic `hxd.Event`s handed to `hxd.Window.event()`, the
path SDL input takes, so h2d Interactives and HaxeUI handle them as real ones; the window opens
off-screen and never takes the foreground. HashLink desktop only, so far.

Lifted from Simplified's desktop automation channel; the design is JoeClash's
`docs/superpowers/specs/2026-10-10-gui-drive-design.md`.

## Using it

1. `-lib heaps-drive -D drive` in a build of its own. Without `-D drive` nothing compiles in.
2. Before the window is made: `drive.heaps.OffScreen.install();` (`DRIVE_VISIBLE=1` keeps it on screen).
3. Once the scene exists:
   `drive.Start.start(host, [new drive.haxeui.Targets(s2d), new drive.h2d.Targets(s2d), /* yours */], s2d, hxd.Window.getInstance(), dir);`
   `host` is an `IDriveHost` (your wait conditions, `state`, `quit`), or null.
4. `node tools/drive.mjs --file <dir>/drive.json <cmd> '<json args>'`, or import `connect` from it.

## Targets

`#id` and `text:` / `text~:` for HaxeUI; `name:` and `text:` / `text~:` for h2d (a label Text over a
sibling Interactive — the smallest one if several); your own prefixes through an `ITargets`. A target
matching more than one thing, in one finder or across finders, is `ambiguous` with the candidates.
Every position is a window pixel.

## Tests

    haxe test.hxml           # headless: protocol, session, server, finder, command table
    haxe test-heaps.hxml     # windowed: the h2d and HaxeUI finders, real hit-testing
    node tools/selftest.mjs  # end to end: launch the example off-screen and drive it
