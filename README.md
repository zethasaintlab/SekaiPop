<div align="center">

<h1>SekaiPop</h1>

<img src="assets/highlights.svg" alt="Phone control center, Sekai Pad equalizer, Edit Desktop, shader wallpaper transitions, two lockscreens, installs from a bare Arch" width="82%">

<br>

[Showcase](#showcase) &nbsp;|&nbsp; [What makes it different](#different) &nbsp;|&nbsp; [Requirements](#requirements) &nbsp;|&nbsp; [Installation](#installation) &nbsp;|&nbsp; [Keybinds](#keybinds) &nbsp;|&nbsp; [Troubleshooting](#troubleshooting)

<br>

<div align="left">

> ⚠️ **Warning: this is a passion project, and it is heavily vibe-coded.**
>
> I designed and directed SekaiPop myself: the visuals, the UI, how everything should animate and how everything should behave. Claude wrote most of the code to make that possible, so expect rough edges and bugs.

</div>

<br>

<img src="assets/shot-desktop-widgets.png" alt="SekaiPop desktop with clock, weather, calendar, to-do, palette, user card, sticky notes and lyrics widgets" width="100%">

<sub>Clock, weather, calendar, to-do, palette, user card, sticky notes, lyrics and custom images. Every widget is draggable, resizable and optional.</sub>

</div>

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="showcase"><img src="assets/tag-showcase.svg" alt="Showcase" height="80"></h2>

<table>
<tr>
<td width="50%" valign="top">
<img src="assets/shot-quick-panel-phone.png" alt="Quick Panel phone with Wi-Fi, Bluetooth, mic, speaker, brightness and notifications" width="100%">
<br><b>Quick Panel: the control center is a phone</b><br>
Wi-Fi, Bluetooth, mic, speaker, brightness, night light, easy effects and notifications sit on a 2.5D phone that bounces up from the bottom of the screen. A new notification makes it rise just far enough to show it.
</td>
<td width="50%" valign="top">
<img src="assets/shot-settings-phone.png" alt="Settings as a landscape phone in the Monochrome theme" width="100%">
<br><b>Settings: flip the phone sideways</b><br>
Settings opens by rotating the Quick Panel phone into landscape. Six pages: Quick, General, Bar, Desktop, Hyprland and About / Update. Shown here in the Monochrome theme.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/shot-sekai-pad-eq.png" alt="Sekai Pad: a ten-band equalizer drawn as a handheld game console" width="100%">
<br><b>Sekai Pad: the equalizer is a handheld console</b><br>
A 10-band EQ (EasyEffects) with a D-pad for picking a band, face buttons for save, undo and auto, and preset cartridges you slot in at the top.
</td>
<td width="50%" valign="top">
<img src="assets/shot-edit-desktop.png" alt="Edit Desktop mode with a shelf of widgets, bar, dock, views, theme and presets" width="100%">
<br><b>Edit Desktop: rearrange it like a scrapbook</b><br>
Press <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>E</kbd>. Left click adds or edits, right click removes, drag moves. Widgets, bar, dock, views, themes and presets all live here.
</td>
</tr>
</table>

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="different"><img src="assets/tag-different.svg" alt="What makes it different" height="80"></h2>

Most shells pick one look and theme it. SekaiPop starts from a single design language, applies it to everything, and adds a few ideas of its own.

<table>
<tr>
<td width="50%" valign="top"><b>One block, everywhere</b><br>Every pill, key, card and popup is an outline, a thin cream ring, a fill and a hard shadow straight down, like a keycap that sinks when you press it. Nothing looks bolted on.</td>
<td width="50%" valign="top"><b>The shell is a phone</b><br>The Quick Panel, Settings and the app launcher are phones. Settings is the same phone rotating into landscape. Things pop up when they turn on and get swallowed when they turn off, instead of fading.</td>
</tr>
<tr>
<td valign="top"><b>Sekai Pad</b><br>An equalizer designed as hardware: a D-pad, face buttons, a screen with the live curve, and preset cartridges.</td>
<td valign="top"><b>Edit Desktop</b><br>A full-screen layout editor built from the same blocks, with tabs for Widgets, Bar, Dock, Views, Theme and Presets.</td>
</tr>
<tr>
<td valign="top"><b>Presets that survive updates</b><br>Wearing an old preset doesn't drag in widgets that were added later. Lockscreen style, folder paths and other machine-specific choices are left alone. Wore the wrong one, or deleted one? There's an Undo for both.</td>
<td valign="top"><b>Themes with personality</b><br>Six character-unit themes (Virtual Singer, Leo/need, MORE MORE JUMP!, Vivid BAD SQUAD, Wonderlands×Showtime, Nightcord at 25:00), Monochrome, Wallpaper (matugen) and a Custom palette, each in Light, Dark and Darker. They reach window borders, GTK, Qt and KDE colours, the terminal and a Vencord (Discord) theme.</td>
</tr>
<tr>
<td valign="top"><b>Shader wallpaper transitions</b><br>Ring, Iris, Star (it spins), Blocks, Flash, Fade and Random. The bands cover the whole desktop, then reveal the new wallpaper, in your theme's colours. The same transition plays into and out of the lockscreen.</td>
<td valign="top"><b>Two lockscreens</b><br>Gacha, and Calendar: a poster with three frames cut from your wallpaper, the clock as four keycaps, a month card and two-press Restart / Shut down keys. Hold <kbd>Ctrl</kbd> and Enter becomes Sleep. While locked, the desktop sleeps: widgets are freed, cava and video wallpapers stop, and everything wakes up one by one on unlock. Fingerprint unlock is available when <code>fprintd</code> is installed and prints are enrolled (Settings > General > Launcher & lock > Fingerprint unlock (off by default)).</td>
</tr>
<tr>
<td valign="top"><b>A dock with real tools</b><br>Search, Files (Music, Pictures, Videos, Documents, Trash, with video thumbnails), Clipboard, Timer, a media card with seeking, and the Shelf: a drag-and-drop tray where items become polaroids, vinyls, books, folders and notes held with tape.</td>
<td valign="top"><b>Music that feels alive</b><br>A media pill with a live wave, a cava visualizer widget, and a lyrics widget that asks several providers (LyricsPlus, NetEase, LRCLIB, QQ Music, Kugou), picks the best one per song, highlights word by word and has a source picker.</td>
</tr>
<tr>
<td valign="top"><b>Discord voice</b><br>A bar pill and popup showing who is in the call, who is speaking, mute and deafen, through a small Vencord companion plugin. Optional; it needs the official Discord client patched with the standalone Vencord installer, plus <code>git</code>, <code>node</code> and <code>pnpm</code>. Run <code>sekaipop/scripts/discordVoice/vencord-companion/install.sh</code> to add the plugin.</td>
<td valign="top"><b>Configure without config files</b><br>Drag screens around a to-scale Displays layout and set resolution, scale and refresh rate. Set keyboard layouts with a bar switcher. Open a cheatsheet that builds itself from your Hyprland bind descriptions. Tune night light, gamma and brightness, and get a reload popup that shows shell errors.</td>
</tr>
<tr>
<td valign="top"><b>A full desktop</b><br>On-screen display, polkit prompt, notifications, screen snip (region, OCR to clipboard, Google Lens, screen record, colour picker), Game Mode, Focus Mode, Overview, on-screen keyboard and a welcome tour. Bar and dock work on any edge in four styles: Float, Straight, Transparent and Capsule.</td>
<td valign="top"><b>A conservative multi-distro installer</b><br>One shared installer supports explicitly allowlisted Arch-family, Fedora, Debian and Ubuntu baselines, with native package backends, read-only planning, scoped desktop integration, and configuration backup/restore.</td>
</tr>
</table>

<img src="assets/divider.svg" alt="" width="100%">


<h2 id="requirements"><img src="assets/tag-requirements.svg" alt="Requirements" height="80"></h2>

The multi-distro installer is designed for a **mutable, systemd-based x86_64 desktop**. It requires a normal user account with <code>sudo</code> access. Do not run it as root.

| Distribution | Supported baseline | Package backend | Conditions |
|---|---|---|---|
| Arch Linux | Rolling | pacman | A stale sync database requires explicit <code>--system-upgrade</code> authorization for a full system upgrade. |
| EndeavourOS | Rolling | pacman | Uses the Arch package profile. |
| CachyOS | Rolling | pacman | Uses the Arch package profile. |
| Fedora | 44 | DNF5 | Compatible Hyprland >= 0.55 must already be installed; no COPR is enabled. |
| Debian | 13 (trixie) | APT | Official <code>trixie-backports</code> must already be configured for Quickshell and Hyprland. |
| Ubuntu | 26.10 (Stonking Stingray) | APT | Universe must already be enabled. |

**Not supported:** openSUSE, Gentoo, NixOS, Kali Linux, Fedora Atomic/ostree variants, other unverified derivatives, and architectures other than x86_64. The installer uses exact <code>ID</code>, <code>VERSION_ID</code>, and release-codename checks. <code>ID_LIKE</code> is informational only and does not route Linux Mint or another derivative to Debian/Arch/Fedora.

### Runtime requirements

- **Hyprland 0.55+** for SekaiPop's Lua configuration/API.
- **Qt 6.7+**.
- Quickshell with SekaiPop's required QML modules: Hyprland, Wayland, IO, Widgets, PAM, Polkit, Notifications, UPower, PipeWire, MPRIS and SystemTray.
- Shaders in the repository are built with Qt 6.12. Qt Shader Tools / <code>qsb</code> is required only when the effective Qt runtime is older than 6.12 and shader recompilation is needed.
- Install and configure GPU drivers yourself. The installer never changes GPU drivers, kernel modules or Secure Boot.

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="installation"><img src="assets/tag-installation.svg" alt="Installation" height="80"></h2>

Clone the complete fork and inspect the package/deployment plan first:

<pre><code>git clone https://github.com/zethasaintlab/SekaiPop.git
cd SekaiPop
./install.sh --plan
./install.sh</code></pre>

The complete repository is required: the installer deploys the existing <code>sekaipop/</code> shell and <code>hypr/</code> configuration. It does not duplicate or download a separate runtime tree.

### Installer options

| Option | Purpose |
|---|---|
| <code>--plan</code> / <code>--dry-run</code> | Read-only package and deployment plan; no repository refresh or configuration writes. |
| <code>--check</code> | Read-only runtime, Qt, QML, plugin and Quickshell checks. |
| <code>--profile minimal|standard|full</code> | Select core, standard, or expanded optional dependencies. |
| <code>--deps-only</code> | Install selected dependencies and system integration without copying the shell. |
| <code>--no-deps</code> | Deploy configuration without a package transaction. |
| <code>--no-update</code> | Skip APT/DNF metadata refresh. |
| <code>--no-desktop-layer</code> | Omit optional portals, font bundles and desktop convenience packages. |
| <code>--hypr merge|full|skip</code> | Add a session hook to the existing config, deploy the complete SekaiPop Hyprland config, or leave Hyprland untouched. |
| <code>--restore</code> | Restore the most recent configuration snapshot. |
| <code>--system-upgrade</code> | Arch-family only; explicitly authorizes a full <code>pacman -Syu</code> transaction. |
| <code>--yes</code> | Accept ordinary confirmations; does not authorize external repositories. |

### Package source and desktop safety

Only repositories already configured by the user are queried. No AUR helper, COPR, PPA, arbitrary RPM/DEB source, or source build is enabled. The installer does not alter GPU drivers, global portal defaults, KDE settings, or unrelated Quickshell processes. It uses path-scoped Quickshell instance operations.

### Checking and restoring

<pre><code>./check-deps.sh
./install.sh --restore</code></pre>

The installer snapshots existing configuration before replacement and keeps persistent <code>~/.local/state/sekaipop</code> application state separate from the replaceable shell deployment. Mocked tests do not constitute a live distro or graphical-session certification; see <code>MULTI-DISTRO.md</code> for the support matrix and validation boundary.

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="keybinds"><img src="assets/tag-keybinds.svg" alt="Keybinds" height="80"></h2>

Press <kbd>Super</kbd> + <kbd>/</kbd> any time for the full list, grouped.

To change one, open **Settings > Hyprland > Keybinds** (or `qs -c sekaipop ipc call keybinds toggle`): a keyboard slab shows what is on every key. Pick an action, press **Press keys**, then press the new keys (or switch the modifiers on and click a key on the board). It works straight away, and **Reset** puts it back.

| Keys | Action |
|---|---|
| <kbd>Super</kbd> (tap) or <kbd>Super</kbd> + <kbd>A</kbd> | Apps (launcher phone) |
| <kbd>Super</kbd> + <kbd>N</kbd> | Quick Panel |
| <kbd>Super</kbd> + <kbd>Tab</kbd> | Overview |
| <kbd>Super</kbd> + <kbd>I</kbd> | Settings |
| <kbd>Super</kbd> + <kbd>/</kbd> | Cheatsheet |
| <kbd>Super</kbd> + <kbd>K</kbd> | On-screen keyboard |
| <kbd>Super</kbd> + <kbd>M</kbd> | Equalizer (Sekai Pad) |
| <kbd>Super</kbd> + <kbd>G</kbd> | Game Mode |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>E</kbd> | Edit Desktop |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F</kbd> | Focus Mode |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>T</kbd> | Wallpaper picker |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd> | Random wallpaper |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> | Theme picker |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> | Dark mode toggle |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>R</kbd> | Restart the shell |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Screen snip |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd> | Character recognition (OCR) to clipboard |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>A</kbd> | Google Lens |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd> | Record region |
| <kbd>Super</kbd> + <kbd>V</kbd> / <kbd>Super</kbd> + <kbd>.</kbd> | Clipboard history / emoji |

Volume and brightness keys go through the shell's on-screen display.

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="troubleshooting"><img src="assets/tag-troubleshooting.svg" alt="Troubleshooting" height="80"></h2>

| Problem | Try |
|---|---|
| Shell doesn't start | Run `qs -c sekaipop log`, and make sure you logged into the plain **Hyprland** session, not uwsm |
| "Failed to load configuration" after an update ("... is not a type" for something the file declares) | Restart the shell, don't reload it: **Restart shell** on the error card, or `qs kill -c sekaipop; qs -c sekaipop -d`. A reload stays inside the same process, which can hold on to the old files' state (issue #79) |
| Black screen after install | `./install.sh --restore`, then read `~/.cache/sekaipop/hypr-errors.log` |
| Icons are missing | Install `ttf-material-symbols-variable`, then `fc-cache -f` |
| Shaders or transitions don't draw | Qt older than 6.12 needs the shaders rebuilt: `bash ~/.config/quickshell/sekaipop/shaders/compile-shaders.sh` (needs `qt6-shadertools`) |
| Hyprland rejected part of the config | `hyprctl configerrors` shows what it refused to load |
| Something is missing | Run `./check-deps.sh`; it lists every missing package and QML module |

<img src="assets/divider.svg" alt="" width="100%">

<h2 id="credits"><img src="assets/tag-credits.svg" alt="Credits and license" height="80"></h2>

> [!CAUTION]
> The region selector's **search** action uploads the cropped screenshot to `uguu.se` before opening Google Lens. Don't use it on anything private.

SekaiPop is built on other people's work, and I'm grateful to all of them.

**The foundation**

- **[end4](https://github.com/end-4)** and [dots-hyprland](https://github.com/end-4/dots-hyprland) (Illogical Impulse): the foundation of this whole shell. The Hyprland configuration in `hypr/` is adapted from it, the installer follows the idea of `./setup install`, and the Anti-Flashbang shaders are copied unchanged (GPL-3.0). The cheat sheet, the Overview and the way Settings is organised also take after it.
- **[pCtrade](https://github.com/pctrade)** (end4-pC): the inspiration for how customizable this shell is, and for his support along the way. The `aurora`, `dots`, `mirror` and `ring` audio visualizers are ported from his work.
- **[p3dro](https://github.com/P3DROVFX)**'s fork of Illogical Impulse: the Discord Voice service the bar pill and popup are ported from.
- **[ilyamiro](https://github.com/ilyamiro)** and his Serpentium shell: the equalizer engine behind the Sekai Pad. The 10-band EasyEffects backend (`equalizer.sh`) came to SekaiPop through the pC fork, and the welcome screen follows the structure of his `Start.qml`. The handheld-console design of the Sekai Pad is SekaiPop's own.

**Projects it uses**

- [Quickshell](https://quickshell.org) and [Hyprland](https://hyprland.org), which it runs on.
- [matugen](https://github.com/InioX/matugen) by InioX, for colours drawn from the wallpaper.
- Material Discord by CapnKitten and system24 by refact0r, the base of the Discord theme.
- [emojibase](https://github.com/milesj/emojibase) (MIT), for the launcher's emoji data.
- Material Symbols (icons) and Google Sans Flex (text).
- [hyprland-scroll-overview](https://github.com/yayuuu/hyprland-scroll-overview) by yayuuu, an optional plugin the shell can use.
- [Open-Meteo](https://open-meteo.com) for the weather, and LRCLIB, LyricsPlus, NetEase Cloud Music, QQ Music and Kugou for lyrics.

Because it includes GPL-3.0 code, **this repository is distributed under GPL-3.0**. See [LICENSE](LICENSE).

Character themes and names are fan references to *Project SEKAI COLORFUL STAGE! feat. Hatsune Miku*. This is an unofficial fan project, not affiliated with SEGA, Colorful Palette or Crypton Future Media. Wallpapers shown in the screenshots belong to their original artists.

<img src="assets/divider.svg" alt="" width="100%">
