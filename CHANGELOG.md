# Changelog

## [1.0.1] - 2026-11-26

### Added
- New **High Contrast** (`highContrast`) visual theme in Settings and the title bar `Theme` cycler.
- `Ctrl + N` keyboard shortcut to create a new note while the journal is open.
- Selection accent strip (`selectionStrip`) and borders on active sidebar items and note cards so selection does not rely on background color alone.
- Dynamic WCAG contrast guard in `W.resolveTheme` so custom `accentColor` tints preserve readable title bar, footer, and active button text.

### Changed
- Redesigned `Morrowind Dark`, `Warm Parchment`, and `Ashlander Slate` with dedicated semantic color roles (`titleText`, `titleMuted`, `titleAccent`, `titleSuccess`, `buttonActiveText`, `buttonDisabledBg`, `textDisabled`, `itemSelectedText`, `itemSelectedMuted`, `itemSelectedAccent`) meeting WCAG 2.1 AA/AAA contrast (>= 4.5:1 normal text, >= 7.0:1 primary text).
- Enforced minimum `24x24px` interactive button target sizes and bumped small `11px` labels to `>= 12px` across the title bar, sidebar, notes list, checklist view, and editor toolbar (using compact `Tmpl` label when narrow).
- Replaced the search clear `x` label with `Clr` and disabled button `I.MWUI.templates.disabled` dimming with legible `buttonDisabledBg` / `textDisabled` styling.

### Fixed
- Fixed sidebar tag labels (`TAGS`) turning dark/red or losing `#` due to OpenMW MyGUI `#` color-tag parsing.
- Fixed unreadable note title, header subtitle, footer, modal headings, and selected card text in **Warm Parchment**, as well as low-contrast muted/selected text in **Morrowind Dark** and **Ashlander Slate**.

## [1.0.0] - 2026-11-26

### Added
- Pure OpenMW Lua Personal Journal mod (`personal-journal.omwscripts`) with zero `.esp` dependencies.
- Physical **Personal Journal** book item granted automatically at journey start (or first load on existing saves), usable from inventory or placed in the world on a desk.
- Joplin-style 3-pane interface: Notebooks & Tags sidebar, searchable/sortable Notes list, and unrestricted multiline Note Editor.
- Interactive Checklist mode (`Tasks` / `Edit` toggle) for clicking `- [ ]` / `- [x]` checkboxes directly.
- Roleplay & productivity quick-insert tools (`+Date`, `+Loc`, `+Task`, `+ Diary`, and 5 built-in templates).
- Draggable & lockable window with 3 visual themes (*Morrowind Dark*, *Warm Parchment*, *Ashlander Slate*), custom cover tint color, 3 window size presets, and adjustable editor font size.
- Undo snapshot support, note duplication, auto-save, and optional Delete/Undo confirmation dialogs.
- Per-Save (character) and Shared (persistent across saves) storage modes.
- Full native OpenMW Settings menu (`Options -> Scripts -> Personal Journal`), English localization (`l10n/PersonalJournal/en.yaml`), and `I.PersonalJournal` modder API.
