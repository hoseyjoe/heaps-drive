# heaps-drive

Drive an app's real GUI from outside — click, type, wait, read state, screenshot — without the
user's mouse or keyboard. Two backends:

- **Heaps on HashLink.** Presses are synthetic `hxd.Event`s handed to `hxd.Window.event()`, the
  path SDL input takes, so h2d Interactives and HaxeUI handle them as real ones; the window opens
  off-screen and never takes the foreground.
- **HaxeUI on C#** (`haxeui-cs`, Avalonia). Presses are raw Avalonia events handed to the window's
  own input delegate by haxeui-cs's `AppDriver`, never the OS's input queue. Either headless (no
  window at all) or in a real window put past the right edge of every display, shown without
  activation, out of the taskbar and Alt+Tab, with the styles that stop a click activating it.

Lifted from Simplified's desktop automation channel; the design is JoeClash's
`docs/superpowers/specs/2026-10-10-gui-drive-design.md`.

## Installing

    haxelib git heaps-drive https://github.com/hoseyjoe/heaps-drive.git

(or `haxelib dev heaps-drive <your clone>` to work on it). Not on lib.haxe.org.

## Using it (Heaps, HashLink)

1. `-lib heaps-drive -D drive` in a build of its own. Without `-D drive` nothing compiles in.
2. Before the window is made: `drive.heaps.OffScreen.install();` (`DRIVE_VISIBLE=1` keeps it on screen).
   Off-screen it also replaces heaps' blocking "Uncaught Exception" window: an uncaught error goes
   to stderr and the process exits with code 70.
3. Once the scene exists:
   `drive.Start.start(host, [new drive.haxeui.Targets(s2d), new drive.h2d.Targets(s2d), /* yours */], s2d, hxd.Window.getInstance(), dir);`
   `host` is an `IDriveHost` (your wait conditions, `state`, `quit`), or null.
4. `node tools/drive.mjs --file <dir>/drive.json <cmd> '<json args>'`, or import `connect` from it.

## Using it (HaxeUI on C#)

Needs `haxeui-cs` **with driver support, from commit `0d65add` on**: `AppDriver` and `-D haxeui_cs_drive`
(raw input, capture, the off-screen window, `NewClick`), the file-picker refusal in a driven build, and an
uncaught error in a timer ending the app with exit 70. Against a haxeui-cs without them it does not
compile, or an app that throws sits there with its event loop dead and a client waits for nothing. Also
`haxeui-core`, dotnet.

1. `-lib heaps-drive -lib haxeui-core -lib haxeui-cs -D haxeui_cs_drive -D drive` in a build of its own
   (plus `-D haxeui_cs_headless` for the headless one). Without `-D haxeui_cs_drive` nothing compiles in.
2. Before `new HaxeUIApp`: `drive.cs.OffScreen.install();`. In a window build it asks for the window
   described above (`DRIVE_VISIBLE=1` puts it on a display for a human to watch: it still gets the
   non-activating, tool-window styles every driven window gets, which should keep it from taking focus,
   but **this mode has never been run**, so that is by reading the code, not by a run; do not expect it
   to be safe to leave a person's work open next to it). Headless it does nothing. An uncaught error ends the process (haxeui-cs reports it on
   stderr and exits 70 for an error in a `haxe.Timer`, `MainLoop` or `Host.StartTimer`; an error thrown
   headless ends it the usual .NET way), and the socket closes with it.
3. Once the UI is ready: `drive.cs.Channel.start(host, [new drive.haxeui.Targets(), /* yours */], dir);`
   then, only when headless, `drive.cs.Channel.runHeadless();` (it runs the app, and does not return).
   `examples/HelloCs.hx` is the whole thing.
4. The same client as above. Positions are window units (what Avalonia lays out in, not device pixels);
   `shot` is one image pixel per window unit, whatever the display's or `Toolkit.scale`'s scaling.

Each `click` is a click of its own: `drive.cs.Input` calls `AppDriver.NewClick()` before it, so two
commands back to back on one field are never counted by Avalonia as a double click (which selects a
word); `click` with `double: true` is one gesture of two presses.

C# limits: no copy, cut or paste keys (as on HashLink); `type` takes any text, including characters
outside the BMP; file pickers refuse in a driven build (haxeui-cs), because a native picker would take
the user's focus.

## Targets

`#id` and `text:` / `text~:` for HaxeUI; `name:` and `text:` / `text~:` for h2d (a label Text over a
sibling Interactive — the smallest one if several, ambiguous if two tie); your own prefixes through an
`ITargets`. A target matching more than one thing, in one finder or across finders, is `ambiguous`
with the candidates. Every position is a window pixel. With the HaxeUI finder among them, `key`
answers `{focused}` (the focused component's id, or its type); `Commands.focused` is that hook.

## Tests

    haxe test.hxml           # headless: protocol, session, server, finder, command table
    haxe test-heaps.hxml     # windowed, off-screen: the h2d and HaxeUI finders, real hit-testing
    node tools/selftest.mjs  # end to end: launch the example off-screen and drive it (HashLink)

    node tools/selftest-channel-cs.mjs             # the channel on C#, headless: transport limits and framing
    haxe tests-cs/input.hxml                       # drive.cs.Input's text (surrogate pairs, half a character), headless
    node tools/selftest-cs.mjs headless            # examples/HelloCs, headless, through the real socket
    node tools/selftest-cs.mjs window              # the same in a real window put off every display
    node tools/selftest-cs.mjs window --scale 1.5  # with Toolkit.scale 1.5: clicks and crops still line up

The C# selftests build `examples/hello-cs*.hxml` from this checkout (`-cp src`), launch the app,
check every command, the abandoned-drag and abandoned-key cases, an idle app's latency and a crash
(its own run: non-zero exit, message on stderr, no hang), and in `window` mode read from the app
after every check that its window is not active and not on any display. They set no `DRIVE_VISIBLE`.
