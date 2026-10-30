# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.2.0] - 2026-10-30

### Changed
- Redesigned play screen, in line with the other games: the question box
  fills the available room, and the four answers are one full-width pad
  with large bold numbers that are easy to read and hit. The status line
  reads "difficulty · Correct: n/m (p%) · Streak: n · ✓" and wraps in
  landscape instead of being cut off.
- Title-bar menu in the same order as every other game, with the current
  value shown: New game (was "New") and "Difficulty: Easy" (was a bare
  "Easy").
- New README screenshot.

### Fixed
- Long questions ran off both sides of the question box, and the question
  was oversized on high-DPI screens: its size was set in pixels and then
  scaled again by the screen DPI. It is now fitted to the box and centred.

## [1.1.15] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.14] - 2026-08-05

### Added
- Add ES and DE translations

## [1.1.13] - 2026-08-05

### Changed
- Add issue/PR templates and CONTRIBUTING.md

### Fixed
- Use English source strings for i18n (was French, showed wrong in English locale)

## [1.1.12] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

### Fixed
- Correct vertical centering of question text

## [1.1.9] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.1.8] - 2026-07-29

### Changed
- Use bordered buttons for the answer grid

## [1.1.6] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE

## [1.1.1] - 2026-07-15

### Added
- Adopt TitleBar header, sync common/ with game-common

### Changed
- Remove ../game-common/ fallback from package.path

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0
