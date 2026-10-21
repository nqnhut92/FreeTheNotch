# FreeTheNotch features

Detailed feature guide and settings reference. For installation and a quick overview, see the [README](../README.md). Implementation details are in [Technical Design](TECHNICAL_DESIGN.md).

- **Version:** 0.3.0 (2026-10-21)

[Notch](#notch) · [AI Usage](#ai-usage) · [System panel](#system-panel) · [Side Notch](#side-notch) · [Lock screen](#lock-screen) · [Mouse scrolling](#mouse-scrolling) · [Privacy](#privacy) · [Permissions](#permissions) · [Settings](#settings) · [Known limits](#known-limits)

## Notch

Hover the notch to open it, move away to close it. The closed island hugs the camera housing and is exactly as tall as the camera cutout. On displays without a notch it shows as a small pill as tall as the menu bar.

### Live activities

| Activity | What you see |
|---|---|
| Now Playing | Artwork on the left, waveform tinted to the artwork on the right |
| Timer | Timer icon on the left, countdown and progress bar on the right |
| Caps Lock | ⇪ indicator while Caps Lock is on |
| Volume / keyboard backlight | Replaces the macOS bezel with a ring HUD in the island |
| Battery | Charging, low battery (with sound) and fully charged animations |
| Bluetooth | A drop-down card when a device connects |
| AI sessions | Codex / Claude Code Working, permission Waiting, and Done for 4 seconds |
| AI quota | A battery-style warning HUD when a Session / Week quota window reaches 80% |

### Pages

Home is always visible and first. You can reorder or hide the other page icons. With Remember last tab off, the notch opens on Home.

- **Home**
  - Optional **Quote of the Day** at the top (off by default; Settings → Appearance). Quotes come from [ZenQuotes](https://zenquotes.io/) (downloaded 50 at a time) or from a built-in list of old authors and proverbs, which also fills in when offline. A new quote every 1, 2, 4 or 8 hours or once a day; click it for another one.
  - The player: artwork with the source app's badge, scrolling title and artist, a waveform, a seek bar, and controls for shuffle, repeat, previous, play/pause and next.
  - An audio output picker. For Apple Music this is the AirPlay picker, with multi-room and per-device volume.
  - **Up next** for Apple Music. With repeat one, it shows the same song.
  - A week calendar beside the player, with the Vietnamese lunar date under the date. When nothing is playing, a full month view takes over, with events, reminders and Join buttons for Zoom, Teams, Meet and more.
  - A battery strip. On the left is the Mac (charge, status, health, cycles, temperature, power). On the right is one ring per Bluetooth device. AirPods are split into buds and case, like the iOS widget, and are shown even while resting in the case nearby.
- **Clipboard:** history of text and images (screenshots, copied image files) as a grid of cards, with search, limits and retention rules. Click a card to copy it again, hover for its delete button, right-click to pin.
- **AI Usage:** Codex and Claude quota/reset times, local token totals and estimated API cost.
- **Timer:** quick presets. A running timer stays on the closed island.
- **Calculator:** iOS-style keypad, keyboard input (click the display first), history, and click-to-copy.
- **QR:** offline QR code generator. Copy the image or save it as PNG.

### Skins

Optional decorations around the island, chosen in Settings → Skins:

| Skin | Decoration |
|---|---|
| Jungle | Vines, plus a tiger cub on a swing |
| Cozy Cat | A cat hanging off the edge |
| Christmas | Twinkling lights, plus a reindeer |
| Sakura | Falling cherry blossoms, plus a walking dog |
| Custom | Any Lottie animation you import |

Pets dance to the music's tempo while something is playing. Skins never block clicks.

Skins use more energy than None. Plugged in, they run at full smoothness. On battery or in Low Power Mode they run at a lower frame rate and hold still after 20 seconds without hover or music; hovering or music wakes them. They always hold still while the screen is locked or asleep.

## AI Usage

Account name/email appears when available from the provider’s local login/profile; Claude Desktop profile labels require an organization match with its cached usage.

The AI Usage tab sits between Clipboard and Timer by default. Its enabled Codex and Claude rows show session/week quota used and reset times, alongside Today and rolling 7-day token totals from local Codex/Claude Code logs. Cost is an API-equivalent estimate in USD using [OpenRouter model prices](https://openrouter.ai/api/v1/models), including cache prices where supplied; it is not the subscription bill. Local totals cover the selected profile’s logs and are not matched to the currently displayed quota account. Unknown model prices appear as unavailable.

Each profile created with [claude-multiprofile](https://github.com/jmdarre-v/claude-multiprofile) gets its own Claude row, tagged with the profile name, after the default Codex and Claude rows. Profiles are read from the tool's own list every minute, so new or removed profiles appear without restarting. A Desktop profile shows the quota from its own Claude window (open Settings → Usage in that window); a Claude Code profile uses its own login and logs. A profile never shows another account's quota. Each account is one card: name and email on the left; Session and Week bars with percentage used and reset time, then Today / 7-day tokens and cost, on the right. More than three accounts scroll. Orange quota text means the reading is old.

Claude Desktop quota is read from its most recently viewed Usage settings cache, labeled with its captured date/time. After 30 minutes it remains visible as **Old data** rather than asking to reconnect. If the cache entry disappears, the last reading remains in memory until a newer one is found or the app quits. Open Claude → Settings → Usage to update it, then refresh here. This path reads no login token and makes no quota network request. Desktop chat tokens are not included in local Code logs.

Enabled providers refresh once a minute, including with the notch closed; the refresh button at the bottom of the tab refreshes every account now. Login is read from the provider's existing credential file, then Keychain. **Connect**, shown in a row that needs it and in Settings → AI Usage, allows a Keychain prompt when needed. Settings has Codex/Claude enable switches, each provider’s status and refresh action. Disabling both automatically hides AI Usage; re-enabling either shows it again. If login expires, open the provider's app or CLI to renew it and refresh; FreeTheNotch does not rotate or rewrite shared login credentials. Local totals remain available when quota cannot be fetched. Accounts signed in only with an API key may not expose subscription quota.

Settings → Live Activities → **AI sessions** shows Codex and Claude Code turns in the closed notch: Working, permission Waiting when the local registry reports it, and Done for 4 seconds after an explicit completion. Sessions hosted by Claude Desktop's Code mode are supported; regular Desktop chats do not expose this state. The reader follows [CodeNotch's session monitors](https://github.com/vinzdg/codenotch/tree/main/Sources/Sessions), uses local lifecycle records and process liveness, and does not upload prompts or tool arguments. Quiet sessions without a live process or recent writes disappear rather than being marked Done.

Settings → HUD → **Quota warning at 80%** shows a four-second warning when a Session or Week window is at least 80% used. Each window warns once per app run; a new reset window allows a new warning (small timestamp drift is ignored). Old Claude cache readings and expired quota windows never raise new warnings. Both switches are also on the AI Usage settings page. Settings includes preview buttons for each enabled provider's session and quota HUD.

Settings → Appearance → Notch Tabs lets you drag to reorder and toggle each tab's visibility. Home is permanently visible and fixed first, with no toggle or drag handle. Other hidden tabs keep their place, and hiding the currently open tab selects Home. Hiding a tab does not stop its underlying feature (for example an active timer).

## System panel

With Side Notch off, left-click the menu bar coffee cup to open the full panel. With Side Notch on, click its individual system icons to open each section directly.

- **Keep Awake:** 15 min to 8 h, until a set time, or until stopped. Options to pause while locked, stop when the battery is low, and nudge the pointer so chat apps stay "Available". The cup turns orange while active.
- **System:** CPU and GPU temperature and usage with sparklines, a per-core matrix, the apps using the most CPU, GPU and memory, memory pressure, and uptime.
- **Network:** live up/down rates, per-app traffic, session totals, local IP addresses, and a Cloudflare speed test.
- **Disks:** usage, live read/write, SMART health and temperature, and eject.
- **Power:** battery history, apps ranked by energy use, system and adapter watts, time remaining, health and cycles.
- **Utilities:** Cleaning Mode locks the keyboard (and optionally the trackpad) so you can wipe it. Press Esc five times to exit.

The menu bar cup stays: right-click it for quick Keep Awake, Cleaning Mode, Side Notch on/off, Hide from Screen Sharing, Settings and Quit. Left-click it for the full panel when Side Notch is off.

## Side Notch

An optional black notch welded to the left or right edge of the screen, centred vertically, in the style of [CodeNotch](https://github.com/vinzdg/codenotch) (off by default; Settings → Side Notch, or right-click the cup). It uses the same displays as the notch (Settings → General → Displays: Built-in, Main display or All displays); its own settings choose the edge (Left or Right) and the zoom (1× or 2×; the drawing scales down to fit shorter displays). When the Dock is on the left or right, the Side Notch always takes the other edge, whatever the setting says. It holds seven cells, top to bottom by default (drag them into another order in Settings → Side Notch → Cells):

**DuoGlyph** (top), which works like the iPhone's combined status indicator:

- **Ring:** battery level, with the number across the top. Green, number and bolt included, while charging; a plug, and no colour, when on power but not charging (macOS "Charging On Hold": charge limit, Optimized Charging, or full); red below 20% on battery.
- **Centre:** the Wi-Fi symbol. Lit arcs follow signal strength; dimmed when Wi-Fi is off or not connected.
- **Dots:** output volume, five dots of about 20% each. All dimmed when muted.

**Bluetooth** (second): the Bluetooth logo, blue while Bluetooth is on and dimmed while it is off.

**System icons:** Keep Awake, System, Network, Disks and Power each open their own section without tabs, a cup header or Settings/Quit buttons. Their larger glyphs use orange, purple, teal, grey and green respectively. Click the same icon to close, another to switch, or outside the popover to dismiss. Utilities is available in the full menu bar panel; Cleaning Mode also stays in the right-click menu.

Click the DuoGlyph for one menu with three tabs, **Wi-Fi | Battery | Sound**, each laid out like the macOS menu of the same name. It reopens on the last tab used. Right-click does nothing.

**Wi-Fi tab:** power toggle, the Ethernet connection if any, Known Networks (current one in blue), a fold-out Other Networks list, Network Settings and Wi-Fi Settings. Network names need Location access. Personal Hotspot devices are not listed (macOS has no public API for them). Joining from the list works for open networks and networks that need just a password; a saved network asks for its password once, because the app cannot read the System keychain. Anything else goes through System Settings.

**Battery tab:** power source and status (charging time, Charging On Hold, time remaining), Energy Mode (Automatic, Low Power and, on Macs that have it, High Power), apps using significant energy, and Battery Settings. Changing the Energy Mode asks for an administrator password each time, because `pmset` needs it. "Charge to Full Now" is not there: macOS has no public API for it.

**Sound tab:** a volume slider (dimmed when the current output has no volume control), the output devices (click one to switch to it; virtual outputs such as Microsoft Teams Audio are hidden, as in macOS), and Sound Settings. AirPlay speakers and TVs macOS has not connected to yet, such as a HomePod, are not listed: macOS finds those through private APIs.

Click the Bluetooth logo for a Bluetooth menu laid out like the macOS one: a power switch, the paired accessories (connected ones first, in blue, with their battery level when the device reports one; iPhone, iPad, Watch, HomePod and Apple TV are left out, as macOS does), then Bluetooth Settings. Click an accessory to connect or disconnect it. The power switch uses a private macOS function (the one `blueutil` uses); if it ever stops working, the switch opens Bluetooth settings instead.

## Lock screen

While the Mac is locked the notch is replaced by a lock notch: a padlock beside the camera that opens when you unlock, then the notch shrinks away, as on the iPhone (Atoll's lock-screen live activity). Small widgets sit under the clock:

- Rings for the Mac battery, AirPods, Bluetooth mice, keyboards and trackpads, local temperature, and air quality.
- A running timer.
- Now Playing, under the timer, styled like the notch player: artwork, title, artist, seek bar, shuffle, repeat and transport buttons. Shown only while something is playing; paused counts as not playing.
- Artwork wallpaper (off by default): while music plays, the lock-screen wallpaper becomes the artwork, sharp in the middle over a blur of itself, as Atoll does. The other widgets hide and the player becomes bare controls under the artwork; click the artwork (anywhere on it) to switch back to your wallpaper and widgets. The switch crossfades; on the way back the clock and password field reappear a moment after your wallpaper, once macOS has caught up. Long song titles and artists scroll, on the card and under the artwork. Your wallpaper comes back when you unlock, when the music pauses or stops, and, if the app crashed while locked, the next time it starts.
- The current or next calendar event.
- Today's reminders.

Every widget can be turned off. Widgets are white with a soft shadow, like the macOS lock-screen clock.

Settings → Lock Screen opens with a preview, pinned above the switches so you can watch it while you change them: your wallpaper, the widgets where they sit on the real lock screen, and the lock notch. It uses live data from the Mac; with **Samples** on, widgets that have nothing to show (no AirPods, no music, no weather yet) get sample data so every switch visibly does something. **Widgets** zooms in on them (drag the picture to look around), clicking the player's artwork tries the artwork wallpaper, and **Lock & unlock** plays the lock-notch animation. Widgets show on the main display only, under the clock macOS draws there. With more than one display, the menu in the preview's top-right corner switches between them. The clock and password field in the preview stand in for the ones macOS draws.

## Mouse scrolling

Open **Settings → Utilities → Mouse Scrolling** and turn on Smooth scrolling to ease mouse-wheel movement across apps. It is off by default and requires Accessibility; use Grant Accessibility if needed. Adjust Scroll speed, or expand More options for Response, Coast and Excluded apps. Higher response follows the wheel sooner; higher coast extends the glide. Excluded apps keep native wheel scrolling. Trackpad and Magic Mouse gestures, and Control-scroll zoom, retain their native behavior.


## Privacy

FreeTheNotch has no account or telemetry service of its own and does not run AI models. By default the notch, Side Notch, system panel and lock-screen widgets are hidden from screenshots, screen recordings and screen sharing. Calendar, reminders, clipboard and settings stay on this Mac. Network calls: Open-Meteo for weather and air quality, Cloudflare for a speed test you start, zenquotes.io when Quote of the Day uses the online source, and quota from OpenAI/Anthropic once a minute for enabled AI Usage providers, plus public OpenRouter prices at most daily. Claude Desktop quota can instead come from its local usage cache. AI Usage reads existing local login credentials and token counters; conversation text and local logs are never uploaded.

## Permissions

macOS asks the first time a feature needs a permission. Everything else works without it.

| Permission | Used for |
|---|---|
| Accessibility | Volume and keyboard-backlight HUD (media keys), Cleaning Mode, Keep Awake pointer nudge, smooth mouse scrolling |
| Calendars, Reminders | Agenda in the notch and on the lock screen |
| Bluetooth | Device connections and battery levels |
| Location | Lock-screen temperature and air quality; Wi-Fi network names in the Side Notch |
| Automation → Music | Shuffle, repeat, Up next and AirPlay for Apple Music |

FreeTheNotch never asks to record the screen or system audio.

## Settings

Open Settings from the gear in the open notch, from the system panel, or from the menu bar cup's right-click menu.

| Section | Contents |
|---|---|
| General | Launch at login, which displays show the notch, hover delay, remember last tab, hide from screen sharing |
| Appearance | Liquid Glass, lunar date, notch tab order (drag ≡, Reset order), battery strip, Quote of the Day (source, interval) |
| Skins | Skin picker with live previews, pet size (Custom remembers a size for each animation, up to 2.5×) and speed, Custom skin's animation (pick, import/delete your own Lottie files), hide while the notch is open |
| Live Activities | Now Playing, Caps Lock, Bluetooth pop-up, AI session status and previews |
| Clipboard | History on/off, maximum items (5/10/25/50), retention |
| AI Usage | Codex/Claude switches, account status, refresh/connect, session Live Activities and quota warnings |
| HUD | Volume and keyboard-backlight HUD; power notifications (charging, low, full); AI quota warnings at 80%; low-battery threshold and sound; test buttons |
| Side Notch | Show Side Notch, edge (Left/Right; the Dock can override it), cell order, zoom |
| Utilities | Keep Awake and Cleaning Mode defaults; smooth mouse scrolling |
| Lock Screen | Preview, each widget and ring (reminders follow "Upcoming event"), artwork wallpaper |
| About | Version, GitHub link, acknowledgements, Quit |

## Known limits

- **Waveform:** the waveform is a fixed animation and the pet dances to the song's tempo; neither follows the real audio. Reading the audio would need the System Audio Recording permission and its purple indicator.
- **Up next:** shows only for Apple Music, and is hidden while shuffle is on (except with repeat one). Music does not expose its real queue.
- **iPhone, Watch and iPad batteries:** macOS gets these over iCloud through private APIs, so FreeTheNotch cannot show them.
- **Keyboards without battery reporting:** some keyboards (for example Keychron) never report battery to macOS, so FreeTheNotch has no level for them.
- **Screen sharing:** a few apps that use ScreenCaptureKit may still capture the notch.
