# Changelog

## 1.0.10

The status bar and notification use the app's own logo, and the wording is layered again.

- Icons: the status-bar icon is no longer the system's refresh glyph but a white silhouette of the app logo; the color logo in the notification's large icon and banner is now transparent instead of sitting on a white block.
- Live activity: the first line holds only the state word (running, approve, answer, needs input, done), and context usage moves to the notification card's first line as "running丨context 45%". The island is too small for it, so it stays out.
- Notification: the running timer is gone — the design doc already ruled out elapsed time.
- Sidebar: the filter, expand-all and project plus buttons have no white circle to align by, so they get left padding to put their visual right edge back on the 16 line; the project row's trailing slot is a fixed 36 wide, so the SSH/WSL tag no longer shifts between collapsed and expanded.
- Composer: the clear button goes from a 48 hit area with a 22 icon to 36 with 18, matching the plus and send next to it.
- HyperOS focus-notification templates are no longer attached: they need a Xiaomi Store listing and scene review before SystemUI grants access, and this app ships for personal use only.

## 1.0.9

Sharper live-activity wording and a stop button on the notification.

- Live activity: waiting states are split into "approve" and "answer" when the open conversation makes it clear, and fall back to a single "needs input" otherwise. A running conversation shows its context usage in the chip ("running · context 45%"). Wording no longer says "waiting for you" everywhere.
- Notification: a "stop" action stops the running turn without opening the app; tapping the body still opens the conversation. The indeterminate progress bar and the expanded big-text detail are gone.
- Background keep-alive: while a turn runs or waits on you, a minimal foreground service keeps the process from being frozen, so the link no longer drops when you switch away and the island shows real progress. It stops on done or idle, never auto-starts, and does not request battery-optimization exemption.
- The status-bar icon stays the app logo throughout; states only change the text, never the icon.

## 1.0.8

Follows the upstream fork's connection and message-area work, adds live activity, and gives the sidebar a clearer hierarchy.

- Connection: a probe now runs on its own request stream, so a stale reply can no longer keep a dead link alive; a failed write ends the waiting request at once; messages of 256 KiB and above are parsed off the main isolate. Reconnects recover on a new connection generation.
- Conversation status: a turn that finishes quickly or while the link was down is still reported; a conversation open on screen is not counted as unread.
- Message area: tool screenshots open as one gallery you can swipe through, and they appear once under the step title; images load lazily.
- File preview: Markdown images inside a project now render inline and open full screen.
- Live activity: a status-bar chip / HyperOS island shows "waiting for you", "running" and "finished, unread" — never the conversation body. No foreground service and no auto-start; it disappears when the process ends.
- Sidebar: SSH projects read `folder@host` with an SSH / WSL badge, so same-named folders stay apart; projects and conversations now use two type levels, and row heights no longer jump when a group folds.
- Message bubbles use 88% of the width (capped at 640).

## 1.0.7

Clearer conversation status, roomier tap targets, and tidier spacing.

- The sidebar dot now tells four states apart: blue breathing while an agent runs, red pulsing when it waits on you, green breathing when a finished conversation is unread, and a faint gray dot otherwise. Motion stops when the system asks for reduced animation.
- Icon buttons keep a 36 visual size but get a 44–48 hit area, so they are easier to hit without looking larger. The header capsule is the same height as the round menu button.
- The device footer reports the real path: LAN 直连, WAN 直连, Relay 中继, or 连接中…; there is no vague "直连" any more.
- Spacing fixes: the title clears the menu button, the search icon sits closer to its text, the composer has equal margins on both sides, and the model name starts right after the plus.
- Selected conversations tint over white instead of cutting a hole in the background; the expand/collapse icons are folders and folder-tree.
- Amber is the first accent and the default; the accent description is back to the upstream wording.

## 1.0.6

Accent colors stay accents, wider message bubbles, and a tip jar.

- The chosen accent now only tints emphasis (buttons, selected rows, links). Your own messages are always white bubbles, and the bot's replies use a light gray bubble so the two stay distinct.
- Message bubbles grow with their content: a short line stays short, a long one uses up to 88% of the width and keeps a safe margin on both sides.
- About now shows WeChat and Alipay tip codes side by side between the description and the website card; tap either to enlarge.
- Every accent color, including green, is kept once chosen; black-gold remains the default.

## 1.0.5

Black-gold palette everywhere, cleaner sidebars, and a tidier composer.

- The default accent is black-gold (the desktop's): pale-gold fills with black icons for the primary actions, white circles and pills for the secondary ones, over the gray page. A stored green from an older build migrates to it.
- New-conversation screen: the app mark sits above a greeting that uses the profile name; the project card and the three suggestions share one left edge, and the suggestions are plain white with a gray Try others below.
- Composer: the model name sits next to the plus and ellipsizes when long; Send and Stop are theme-colored icons without their own round backgrounds, sized to match the text.
- Sidebar: the project's colored icon is back (no folder badge), the selected conversation is a pale-gold row, search is an outlined pill, conversation titles are not bold, dividers are gone, times line up in a fixed column, and SSH projects read as user · host.
- Long-press menus: a project offers Pin and Remove (amber, since the folder stays); a conversation offers Pin, Rename, Archive and Delete (red). Favorites are removed.
- All bottom sheets keep a safe margin and one of three shared heights; filtering, choosing a desktop and choosing a project rise from the bottom.
- Device footer uses monitor-smartphone and a plain LAN / Relay line without latency; the desktop and project pickers highlight the current choice in pale gold.

## 1.0.4

Black-gold look, reworked navigation and input, and a smoother first screen.

- Accent now defaults to black-gold, matching the desktop: pale gold buttons with black icons for New conversation, Send and Stop; secondary actions sit on white circular or pill surfaces over the gray page.
- Sidebar: project rows use their colored rounded-square icon again (no folder badge), the selected conversation is a pale-gold rounded row with a pixel loader instead of the status dot, search has a rounded outline, and conversation titles are no longer bold.
- Conversation header shows only the desktop and project; the git branch is gone from the header and the project card, and the project picker shows only folder name and path.
- Input bar: the model sits beside the plus button with smaller text, Send is smaller, and the add menu renames its entries to Files and Commands while putting permissions and mode on one row.
- Bottom sheets keep a safe margin instead of filling the screen, with three shared heights; filtering conversations, choosing a desktop and choosing a project now rise from the bottom.
- Suggestions carry an icon each and alternate backgrounds; the empty conversation shows the app mark and greets by profile name ("name, good evening") when one is set.
- Device footer uses monitor-smartphone, a smaller name and a plain LAN / Relay line without latency.

## 1.0.3

BaoCodeX's conversation-first layout, based on YCode. The independent `juneix.baocodex` package does not replace the old app or migrate its pairings and drafts.

- Remove the bottom tabs. Use an 80% sidebar for workspaces and conversations, and open Files, Bots and Settings as pages with Back navigation.
- Open the workspace sidebar with a right swipe and a session drawer with a left swipe. The drawer's top half holds shortcuts (files, all changes, background tasks); the bottom half holds session actions (pin, rename, archive, delete). The top-right More button opens the same drawer. Keep the central workspace button as a project picker, not a sidebar shortcut.
- Add expand/collapse all, five conversations per group with show-more controls, relative times and local grouping by project, last update date or status.
- Add time-of-day greetings and refreshed suggestions that only fill the draft. Show the model name and a context-usage percentage beside the send/stop actions, with the ring drawn from real usage.
- Put images, camera, file mentions and slash commands in the input menu; move permissions to a native Android text dropdown and modes to a segmented control.
- Add the Bot mascot and profile-name greeting while retaining one current conversation per Bot and hiding inapplicable controls.
- Move directory list/grid switching into the file toolbar. Preserve file preview, source, diffs and existing archive actions; archive browsing and creation-time sorting are not added.
- Rename the app and APK release assets to BaoCodeX and retain the existing signing and update-safety checks. The app icon now uses `baocodex.svg` rendered with the standard rounded-corner mask; new layout screenshots and device validation follow cloud builds.

## 0.1.2

Personal preview for testing, installed alongside the original YCode without replacing its pairing or data.

- Open directly into a local new-conversation draft, with project task suggestions; create a desktop session only when sending or configuring it.
- Switch projects and conversations through a shared sidebar. Show five conversations per project by default, with independent expand/collapse controls.
- Keep the stop action available while typing or queueing a follow-up message.
- Explain offline approval and menu states, disable remote writes, and keep local answers and drafts.
- Preserve upstream context usage and file rewind, and use the personal build's configured repository for updates.
- Build signed arm64 preview APKs in GitHub Actions and publish pre-releases, not production releases.

## 0.1.1

Context usage and undoing file changes need BaoCode desktop 1.9.3 or later; with an older desktop they don't appear and everything else works as before.

- New: a context usage ring in the composer, orange above 80%; tap it to see what each part takes and how much is left before auto-compact. With BaoCode desktop 1.9.4 or later it updates as the conversation goes; with 1.9.3, when you open the conversation.
- New: when you edit an earlier message and send it again, YCode can undo the files the agent changed after it — asking, undoing or keeping as the desktop's "Edited Messages" setting says (Claude Code and BaoCode Agent).
- New: an arrow on a project's row unfolds its conversations right on the home list, without opening the project.
- Improved: picking a project in the filter closes the panel and lists that project's conversations directly; new conversations then start in it.
- Improved: checking for updates reads a small file attached to the release first, so it no longer fails when many people share one network and GitHub's hourly limit runs out.
- Fixed: file links written as `/D:/path` by a model on a Windows desktop now open.

## 0.1.0

The first open-source release of YCode, an unofficial Android client for the BaoCode desktop app.

- Pair with your computer by QR code, pasted link or LAN discovery, end-to-end encrypted over link v2.
- Conversations, Bots, Files and Settings tabs; streaming messages, edit and resend, queued sends, images and @ files, / commands.
- Checks for updates on launch and downloads and installs them in the app.
