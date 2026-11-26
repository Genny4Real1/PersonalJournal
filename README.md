# Personal Journal for OpenMW

A **Joplin-inspired personal notebook & roleplay journal** built in pure **OpenMW Lua** — inspired by ESO's *Notebook 2018* and modern note-taking tools, designed from the ground up for both **deep Morrowind roleplaying** and **in-game productivity**.

You receive a physical **Personal Journal** item at the start of your journey (zero weight, zero value, no `.esp` required), and you can write, organize, search, and edit your notes freely inside Morrowind with **zero restrictions**.

---

## Features

### Authentic Physical Journal Item (No ESP Required)
- **Obtained at Journey Start:** Automatically added to your inventory once character generation finishes (or immediately on first load of an existing save).
- **Use From Inventory:** Click/use your Personal Journal in your inventory to open your notebook immediately.
- **Place on Your Desk for Roleplay:** Drop your Personal Journal onto a table or desk in your home; activating it in the world opens your journal right there, with a **Take** button in the title bar to pick it back up.
- **Zero Dependencies & Zero Conflicts:** 100% pure OpenMW Lua (`personal-journal.omwscripts`). No `.esp` or `.omwaddon` plugin, fully compatible with Vanilla Morrowind, Tribunal, Bloodmoon, Tamriel Rebuilt, Project Cyrodiil, Skyrim: Home of the Nords, and any modlist.

### Joplin-Style Organization
- **Notebooks (Folders):** Comes with starter notebooks (*Journal*, *Quests & Leads*, *Tasks & Lists*, *People & Places*, *Alchemy & Lore*) — freely create, rename, or delete notebooks at any time. Deleting a notebook safely moves its notes so nothing is ever lost.
- **Tags (`#tag`):** Attach comma-separated tags to any note and click any tag in the sidebar to filter instantly.
- **Pinned Notes & Smart Views:** Pin important checklists, guild duties, or alchemy recipes so they always stay at the top and appear under **Pinned**.
- **Instant Live Search & Sorting:** Search across titles, note bodies, tags, locations, and Tamrielic dates in real time. Sort by **Updated**, **Created**, or **Title**.

### Unrestricted Editing & Roleplay / Productivity Tools
- **100% Unrestricted In-Game Editing:** Edit any title, tag, or page anytime with no character locks or read-only barriers.
- **Interactive Checklists:** Write `- [ ]` tasks in any note, then click **Tasks** to switch into clickable checkbox mode and check off tasks live (`[ ]` <-> `[x]`). Switch back to **Edit** mode anytime.
- **Tamrielic Calendar & Location Stamps:** One-click **`+Date`** (`09:42, 16 Last Seed, 3E 427`), **`+Loc`** (current cell or region), **`+Task`** (`- [ ] `), and **`+ Diary`** (creates a pre-titled, pre-dated roleplay diary entry).
- **Built-in Templates:** Insert ready-made structures for **Diary**, **Quest Lead**, **Task List**, **NPC Dossier**, and **Alchemy / Lore**.
- **Undo, Duplicate & Safety Prompts:** Revert edits back to your last saved snapshot (`Undo`), duplicate notes (`Dup`), auto-save as you type, and configure optional Delete/Undo confirmation prompts (just like *Notebook 2018*).

### Customizable Interface (Notebook 2018 Style)
- **Draggable & Lockable Window:** Drag the title bar anywhere on screen and toggle **Lock / Move** to keep it fixed in place.
- **Themes & Cover Tint:** Switch live between **Morrowind Dark**, **Warm Parchment**, and **Ashlander Slate**, plus customize your **Cover & Header Tint** color in Settings.
- **Window Sizes & Font Scaling:** Toggle between **Compact**, **Standard**, and **Large** window presets and adjust editor font size (`A-` / `A+` from 12 to 26).
- **Flexible Storage Scope:** Choose between **Per-Save (Character)** storage (authentic per-character RP journal stored in your `.omwsave`) or **Shared (Across Saves)** storage (persists across reloads and characters).
- **Optional HUD Quick Button:** Enable a subtle clickable **Journal** button while menus are open.

---

## Requirements

- **OpenMW 0.49 or newer** (tested with OpenMW 0.49 / 0.50 / 0.51).

---

## Installation

1. Extract the `PersonalJournal` folder into your OpenMW mods directory.
2. Open your `openmw.cfg` file (on Linux: `~/.config/openmw/openmw.cfg`, on Windows: `Documents\My Games\OpenMW\openmw.cfg`).
3. Add the folder to your `data=` list:
   ```ini
   data="/path/to/PersonalJournal"
   ```
4. Add the script manifest to your `content=` list:
   ```ini
   content=personal-journal.omwscripts
   ```
5. Launch OpenMW! You can customize all options under **Options -> Scripts -> Personal Journal**.

---

## Controls & Shortcuts

| Action | Default |
|---|---|
| Open / Close Personal Journal | **`N`** (configurable in Settings, or use the **Personal Journal** item in your inventory) |
| Save Current Note Snapshot | **`Ctrl + S`** (or click **Save**) |
| Close Modal / Close Journal | **`Escape`** (or click **`X`**) |
| Move Window | Drag the top title bar (when unlocked) |

---

## Console & Modder Lua API (`I.PersonalJournal`)

Open the console (`~`), switch to `luap`, and use:

```lua
-- Open, close, or toggle the journal
I.PersonalJournal.open()
I.PersonalJournal.close()
I.PersonalJournal.toggle()

-- Reclaim a fresh Personal Journal item if you ever dropped or lost it
I.PersonalJournal.reclaimJournal()

-- Programmatically add a note from another Lua mod or console
I.PersonalJournal.addNote({
    title = "Caius Cosades",
    body = "Meet Caius in Balmora.\n- [ ] Ask about the Blades",
    tags = "main-quest, balmora",
    pinned = true,
})
```

---

## Credits & License

- Released under the **MIT License** — see [LICENSE](LICENSE).
- Inspired by *Notebook 2018* (ESO) and *Joplin*.
