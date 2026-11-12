# Changelog

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
