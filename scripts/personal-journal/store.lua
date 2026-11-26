-- Personal Journal for OpenMW
-- Pure Lua data store: Notebooks, Notes, Tags, Search, Sorting, Undo, Checklists, and Migration.
-- Zero OpenMW runtime dependencies so it can be unit-tested standalone in Lua 5.1/LuaJIT.

local common = require('scripts.personal-journal.common')

local Store = {}
Store.__index = Store

local function makeWelcomeNote(ctx)
    local dateStr = (ctx and ctx.dateShort) or '16 Last Seed, 3E 427'
    local locStr = (ctx and ctx.location and ctx.location ~= '') and ctx.location or 'Seyda Neen'
    return {
        id = 'note_1',
        notebookId = 'nb_journal',
        title = 'Arrival in Morrowind',
        body = table.concat({
            string.format('Date: %s', dateStr),
            string.format('Location: %s', locStr),
            '----------------------------------------',
            '',
            'I have stepped off the prison ship with little more than my name and this blank leather journal.',
            '',
            'How to use your Personal Journal:',
            '- Organize entries into Notebooks on the left, and filter by #tags or Pinned notes.',
            '- Edit any title, tag, or page freely with no restrictions.',
            '- Use quick buttons (+Date, +Loc, +Task, Template) for fast roleplay and planning.',
            '- Switch to Checklist view to click checkboxes directly:',
            '- [ ] Speak with Socucius Ergalla and gather supplies',
            '- [ ] Deliver the package to Caius Cosades in Balmora',
            '- [ ] Write your own story across Vvardenfell',
        }, '\n'),
        tags = { 'welcome', 'roleplay' },
        pinned = true,
        createdAt = (ctx and ctx.gameTime) or 0,
        updatedAt = (ctx and ctx.gameTime) or 0,
        createdDate = dateStr,
        updatedDate = dateStr,
        location = locStr,
    }
end

function Store.createDefaultData(ctx)
    local notebooks = {}
    for _, nb in ipairs(common.DEFAULT_NOTEBOOKS) do
        notebooks[#notebooks + 1] = {
            id = nb.id,
            name = nb.name,
            createdAt = (ctx and ctx.gameTime) or 0,
        }
    end
    local welcome = makeWelcomeNote(ctx)
    return {
        schemaVersion = common.SCHEMA_VERSION,
        nextNotebookId = 10,
        nextNoteId = 2,
        journalTitle = 'Personal Journal',
        notebooks = notebooks,
        notes = { welcome },
        selectedNoteId = welcome.id,
        activeView = 'all', -- 'all' | 'pinned' | 'notebook' | 'tag'
        activeNotebookId = notebooks[1].id,
        activeTag = nil,
        sortBy = 'updated',
    }
end

function Store.new(initialData, ctx)
    local self = setmetatable({}, Store)
    self.undoStack = {}
    self:load(initialData, ctx)
    return self
end

function Store:load(rawData, ctx)
    if type(rawData) ~= 'table' or type(rawData.notebooks) ~= 'table' or type(rawData.notes) ~= 'table' then
        self.data = Store.createDefaultData(ctx)
    else
        self.data = common.deepCopy(rawData)
        self.data.schemaVersion = self.data.schemaVersion or common.SCHEMA_VERSION
        self.data.journalTitle = self.data.journalTitle or 'Personal Journal'
        self.data.nextNotebookId = tonumber(self.data.nextNotebookId) or (#self.data.notebooks + 10)
        self.data.nextNoteId = tonumber(self.data.nextNoteId) or (#self.data.notes + 10)
        self.data.activeView = self.data.activeView or 'all'
        self.data.sortBy = self.data.sortBy or 'updated'

        -- Guarantee at least one notebook exists
        if #self.data.notebooks == 0 then
            self.data.notebooks[1] = {
                id = 'nb_journal',
                name = 'Journal',
                createdAt = (ctx and ctx.gameTime) or 0,
            }
        end

        -- Normalize all notes
        local validNotebooks = {}
        for _, nb in ipairs(self.data.notebooks) do
            validNotebooks[nb.id] = true
        end
        local fallbackNbId = self.data.notebooks[1].id
        for _, note in ipairs(self.data.notes) do
            note.title = tostring(note.title or 'Untitled Note')
            note.body = tostring(note.body or '')
            note.tags = common.parseTags(note.tags)
            note.pinned = note.pinned == true
            note.createdAt = tonumber(note.createdAt) or 0
            note.updatedAt = tonumber(note.updatedAt) or note.createdAt
            note.createdDate = tostring(note.createdDate or '')
            note.updatedDate = tostring(note.updatedDate or note.createdDate)
            note.location = tostring(note.location or '')
            if not validNotebooks[note.notebookId] then
                note.notebookId = fallbackNbId
            end
        end

        if self.data.activeView == 'notebook' and not validNotebooks[self.data.activeNotebookId] then
            self.data.activeView = 'all'
            self.data.activeNotebookId = fallbackNbId
        end
    end
    self.undoStack = {}
    self:ensureValidSelection()
end

function Store:serialize()
    return common.deepCopy(self.data)
end

-- === Notebooks CRUD ===

function Store:getNotebooks()
    return self.data.notebooks
end

function Store:getNotebookById(notebookId)
    for _, nb in ipairs(self.data.notebooks) do
        if nb.id == notebookId then
            return nb
        end
    end
    return nil
end

function Store:createNotebook(name, ctx)
    local clean = common.trim(name)
    if clean == '' then
        return nil, 'Notebook name cannot be empty.'
    end
    local id = 'nb_' .. tostring(self.data.nextNotebookId)
    self.data.nextNotebookId = self.data.nextNotebookId + 1
    local nb = {
        id = id,
        name = clean,
        createdAt = (ctx and ctx.gameTime) or 0,
    }
    self.data.notebooks[#self.data.notebooks + 1] = nb
    return nb
end

function Store:renameNotebook(notebookId, newName)
    local clean = common.trim(newName)
    if clean == '' then
        return false, 'Notebook name cannot be empty.'
    end
    local nb = self:getNotebookById(notebookId)
    if not nb then
        return false, 'Notebook not found.'
    end
    nb.name = clean
    return true
end

function Store:deleteNotebook(notebookId)
    if #self.data.notebooks <= 1 then
        return false, 'At least one notebook must remain.'
    end
    local idx = nil
    for i, nb in ipairs(self.data.notebooks) do
        if nb.id == notebookId then
            idx = i
            break
        end
    end
    if not idx then
        return false, 'Notebook not found.'
    end

    table.remove(self.data.notebooks, idx)
    local fallbackId = self.data.notebooks[1].id

    -- Reassign notes from deleted notebook to the first remaining notebook so no notes are lost
    for _, note in ipairs(self.data.notes) do
        if note.notebookId == notebookId then
            note.notebookId = fallbackId
        end
    end

    if self.data.activeNotebookId == notebookId then
        self.data.activeNotebookId = fallbackId
        if self.data.activeView == 'notebook' then
            self.data.activeView = 'all'
        end
    end
    return true
end

function Store:countNotesInNotebook(notebookId)
    local count = 0
    for _, note in ipairs(self.data.notes) do
        if note.notebookId == notebookId then
            count = count + 1
        end
    end
    return count
end

function Store:countPinnedNotes()
    local count = 0
    for _, note in ipairs(self.data.notes) do
        if note.pinned then
            count = count + 1
        end
    end
    return count
end

function Store:getAllTags()
    local counts = {}
    for _, note in ipairs(self.data.notes) do
        if type(note.tags) == 'table' then
            for _, tag in ipairs(note.tags) do
                counts[tag] = (counts[tag] or 0) + 1
            end
        end
    end
    local list = {}
    for tag, count in pairs(counts) do
        list[#list + 1] = { name = tag, count = count }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.name < b.name
    end)
    return list
end

-- === Notes CRUD ===

function Store:getNoteById(noteId)
    if not noteId then return nil end
    for _, note in ipairs(self.data.notes) do
        if note.id == noteId then
            return note
        end
    end
    return nil
end

function Store:getSelectedNote()
    return self:getNoteById(self.data.selectedNoteId)
end

function Store:selectNote(noteId)
    local note = self:getNoteById(noteId)
    if not note then return nil end
    self.data.selectedNoteId = note.id
    self:captureUndoSnapshot(note.id)
    return note
end

function Store:ensureValidSelection()
    if self.data.selectedNoteId and self:getNoteById(self.data.selectedNoteId) then
        if not self.undoStack[self.data.selectedNoteId] then
            self:captureUndoSnapshot(self.data.selectedNoteId)
        end
        return
    end
    local first = self.data.notes[1]
    self.data.selectedNoteId = first and first.id or nil
    if first then
        self:captureUndoSnapshot(first.id)
    end
end

function Store:createNote(opts, ctx)
    opts = opts or {}
    local targetNb = opts.notebookId
    if not targetNb or not self:getNotebookById(targetNb) then
        if self.data.activeView == 'notebook' and self:getNotebookById(self.data.activeNotebookId) then
            targetNb = self.data.activeNotebookId
        else
            targetNb = self.data.notebooks[1].id
        end
    end
    local now = (ctx and ctx.gameTime) or 0
    local dateStr = (ctx and ctx.dateShort) or ''
    local locStr = (ctx and ctx.location) or ''
    local id = 'note_' .. tostring(self.data.nextNoteId)
    self.data.nextNoteId = self.data.nextNoteId + 1

    local note = {
        id = id,
        notebookId = targetNb,
        title = opts.title or 'Untitled Note',
        body = opts.body or '',
        tags = common.parseTags(opts.tags),
        pinned = opts.pinned == true or (self.data.activeView == 'pinned'),
        createdAt = now,
        updatedAt = now,
        createdDate = dateStr,
        updatedDate = dateStr,
        location = locStr,
    }
    -- If created while filtering by a tag, auto-attach that tag so the note stays visible
    if self.data.activeView == 'tag' and self.data.activeTag and self.data.activeTag ~= '' then
        local hasTag = false
        for _, t in ipairs(note.tags) do
            if t == self.data.activeTag then
                hasTag = true
                break
            end
        end
        if not hasTag then
            note.tags[#note.tags + 1] = self.data.activeTag
        end
    end

    self.data.notes[#self.data.notes + 1] = note
    self.data.selectedNoteId = note.id
    self:captureUndoSnapshot(note.id)
    return note
end

function Store:duplicateNote(noteId, ctx)
    local src = self:getNoteById(noteId)
    if not src then return nil end
    return self:createNote({
        notebookId = src.notebookId,
        title = src.title .. ' (Copy)',
        body = src.body,
        tags = common.deepCopy(src.tags),
        pinned = false,
    }, ctx)
end

function Store:updateNote(noteId, fields, ctx)
    local note = self:getNoteById(noteId)
    if not note then return false end
    if fields.title ~= nil then
        note.title = tostring(fields.title)
    end
    if fields.body ~= nil then
        note.body = tostring(fields.body)
    end
    if fields.tags ~= nil then
        note.tags = common.parseTags(fields.tags)
    end
    if fields.notebookId ~= nil and self:getNotebookById(fields.notebookId) then
        note.notebookId = fields.notebookId
    end
    if fields.pinned ~= nil then
        note.pinned = fields.pinned == true
    end
    if ctx then
        if ctx.gameTime ~= nil then note.updatedAt = ctx.gameTime end
        if ctx.dateShort ~= nil then note.updatedDate = ctx.dateShort end
    end
    return true
end

function Store:deleteNote(noteId)
    local idx = nil
    for i, note in ipairs(self.data.notes) do
        if note.id == noteId then
            idx = i
            break
        end
    end
    if not idx then return false end
    table.remove(self.data.notes, idx)
    self.undoStack[noteId] = nil
    if self.data.selectedNoteId == noteId then
        local filtered = self:getFilteredNotes('')
        if #filtered > 0 then
            self.data.selectedNoteId = filtered[1].id
        elseif #self.data.notes > 0 then
            self.data.selectedNoteId = self.data.notes[1].id
        else
            self.data.selectedNoteId = nil
        end
        if self.data.selectedNoteId then
            self:captureUndoSnapshot(self.data.selectedNoteId)
        end
    end
    return true
end

function Store:cycleNoteNotebook(noteId, direction, ctx)
    local note = self:getNoteById(noteId)
    if not note or #self.data.notebooks <= 1 then return nil end
    local curIdx = 1
    for i, nb in ipairs(self.data.notebooks) do
        if nb.id == note.notebookId then
            curIdx = i
            break
        end
    end
    local count = #self.data.notebooks
    local nextIdx = ((curIdx - 1 + (direction or 1)) % count) + 1
    local targetNb = self.data.notebooks[nextIdx]
    self:updateNote(noteId, { notebookId = targetNb.id }, ctx)
    return targetNb
end

-- === Undo / Snapshot (inspired by ESO Notebook 2018) ===

function Store:captureUndoSnapshot(noteId)
    local note = self:getNoteById(noteId)
    if not note then return end
    self.undoStack[noteId] = {
        title = note.title,
        body = note.body,
        tags = common.deepCopy(note.tags),
        notebookId = note.notebookId,
    }
end

function Store:hasUnsavedChanges(noteId)
    local note = self:getNoteById(noteId)
    local snap = self.undoStack[noteId]
    if not note or not snap then return false end
    if note.title ~= snap.title or note.body ~= snap.body or note.notebookId ~= snap.notebookId then
        return true
    end
    if common.formatTags(note.tags) ~= common.formatTags(snap.tags) then
        return true
    end
    return false
end

function Store:undoNote(noteId)
    local note = self:getNoteById(noteId)
    local snap = self.undoStack[noteId]
    if not note or not snap then return false end
    note.title = snap.title
    note.body = snap.body
    note.tags = common.deepCopy(snap.tags)
    if self:getNotebookById(snap.notebookId) then
        note.notebookId = snap.notebookId
    end
    return true
end

-- === Filtering, Search & Sorting ===

function Store:setView(view, param)
    self.data.activeView = view or 'all'
    if view == 'notebook' then
        self.data.activeNotebookId = param
        self.data.activeTag = nil
    elseif view == 'tag' then
        self.data.activeTag = param
    else
        self.data.activeTag = nil
    end
end

function Store:cycleSort()
    local current = self.data.sortBy or 'updated'
    local nextIdx = 1
    for i, mode in ipairs(common.SORT_MODES) do
        if mode == current then
            nextIdx = (i % #common.SORT_MODES) + 1
            break
        end
    end
    self.data.sortBy = common.SORT_MODES[nextIdx]
    return self.data.sortBy
end

local function noteHasTag(note, tag)
    if type(note.tags) ~= 'table' then return false end
    for _, t in ipairs(note.tags) do
        if t == tag then return true end
    end
    return false
end

local function noteMatchesQuery(note, queryLower)
    if queryLower == '' then return true end
    if note.title:lower():find(queryLower, 1, true) then return true end
    if note.body:lower():find(queryLower, 1, true) then return true end
    if note.location:lower():find(queryLower, 1, true) then return true end
    if note.createdDate:lower():find(queryLower, 1, true) then return true end
    if note.updatedDate:lower():find(queryLower, 1, true) then return true end
    if type(note.tags) == 'table' then
        for _, t in ipairs(note.tags) do
            if t:find(queryLower, 1, true) then return true end
        end
    end
    return false
end

function Store:getFilteredNotes(searchQuery)
    local queryLower = common.trim(searchQuery or ''):lower()
    local view = self.data.activeView or 'all'
    local results = {}

    for _, note in ipairs(self.data.notes) do
        local passesView = true
        if view == 'pinned' then
            passesView = note.pinned == true
        elseif view == 'notebook' then
            passesView = note.notebookId == self.data.activeNotebookId
        elseif view == 'tag' then
            passesView = noteHasTag(note, self.data.activeTag)
        end
        if passesView and noteMatchesQuery(note, queryLower) then
            results[#results + 1] = note
        end
    end

    local sortBy = self.data.sortBy or 'updated'
    table.sort(results, function(a, b)
        if a.pinned ~= b.pinned then
            return a.pinned == true
        end
        if sortBy == 'title' then
            local ta, tb = a.title:lower(), b.title:lower()
            if ta ~= tb then return ta < tb end
        elseif sortBy == 'created' then
            if a.createdAt ~= b.createdAt then return a.createdAt > b.createdAt end
        else
            if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        end
        return a.id > b.id
    end)

    return results
end

-- === Interactive Checklist Parser / Toggler (Joplin-style Markdown tasks) ===

function Store.parseLines(body)
    local lines = {}
    if type(body) ~= 'string' or body == '' then
        return { { index = 1, raw = '', isTask = false, checked = false, text = '' } }
    end
    local idx = 1
    local pos = 1
    local len = #body
    while pos <= len do
        local nl = body:find('\n', pos, true)
        local line
        if nl then
            line = body:sub(pos, nl - 1)
            pos = nl + 1
        else
            line = body:sub(pos)
            pos = len + 1
        end
        local prefix, mark, rest = line:match('^(%s*[-*]%s*%[)([ xX])(%].*)$')
        if prefix then
            lines[#lines + 1] = {
                index = idx,
                raw = line,
                isTask = true,
                checked = (mark == 'x' or mark == 'X'),
                text = common.trim(rest:sub(2)),
            }
        else
            lines[#lines + 1] = {
                index = idx,
                raw = line,
                isTask = false,
                checked = false,
                text = line,
            }
        end
        idx = idx + 1
    end
    if body:sub(-1) == '\n' then
        lines[#lines + 1] = { index = idx, raw = '', isTask = false, checked = false, text = '' }
    end
    return lines
end

function Store:toggleChecklistLine(noteId, lineIndex, ctx)
    local note = self:getNoteById(noteId)
    if not note then return false end
    local lines = Store.parseLines(note.body)
    local target = lines[lineIndex]
    if not target or not target.isTask then return false end

    local prefix, mark, rest = target.raw:match('^(%s*[-*]%s*%[)([ xX])(%].*)$')
    if not prefix then return false end
    local newMark = (mark == 'x' or mark == 'X') and ' ' or 'x'
    lines[lineIndex].raw = prefix .. newMark .. rest

    local out = {}
    for i, item in ipairs(lines) do
        out[i] = item.raw
    end
    self:updateNote(noteId, { body = table.concat(out, '\n') }, ctx)
    return true
end

return Store
