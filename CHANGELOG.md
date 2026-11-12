# Changelog

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
