-- Personal Journal for OpenMW
-- Joplin-inspired 3-pane personal notebook & ESO Notebook 2018-style draggable window.

local async = require('openmw.async')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local common = require('scripts.personal-journal.common')
local Store = require('scripts.personal-journal.store')
local W = require('scripts.personal-journal.ui_widgets')

local v2 = util.vector2

local JournalUI = {}
JournalUI.__index = JournalUI

function JournalUI.new(deps)
    local self = setmetatable({}, JournalUI)
    self.store = deps.store
    self.settings = deps.settings
    self.getContext = deps.getContext
    self.onPersist = deps.onPersist
    self.onCloseRequest = deps.onCloseRequest
    self.onPlaySound = deps.onPlaySound
    self.onTakeWorldObject = deps.onTakeWorldObject

    -- Live UI elements (sub-elements prevent TextEdit focus loss during typing/search!)
    self.rootElement = nil
    self.sidebarElement = nil
    self.notesListElement = nil
    self.editorElement = nil
    self.footerElement = nil
    self.modalElement = nil
    self.hudButtonElement = nil

    -- View & interaction state
    self.visible = false
    self.isTextFocused = false
    self.windowLocked = false
    self.windowPos = nil -- util.vector2 remembered across open/close
    self.dragState = nil
    self.searchQuery = ''
    self.editorMode = 'edit' -- 'edit' | 'checklist'
    self.statusMessage = 'Saved'
    self.worldObject = nil -- non-nil if opened from a journal placed in the world

    -- Pagination offsets for clean scrolling
    self.nbOffset = 0
    self.tagOffset = 0
    self.noteOffset = 0
    self.checklistOffset = 0

    -- Active modal dialog state
    self.modalState = nil
    self.modalInputValue = ''

    return self
end

function JournalUI:isOpen()
    return self.visible
end

function JournalUI:hasTextFocus()
    return self.visible and self.isTextFocused
end

function JournalUI:getMetrics()
    local presetKey = self.settings.getAppearance('windowPreset') or 'standard'
    local preset = common.WINDOW_PRESETS[presetKey] or common.WINDOW_PRESETS.standard
    local screen = ui.screenSize()

    local winW = math.min(preset.w, math.max(660, math.floor(screen.x - 40)))
    local winH = math.min(preset.h, math.max(440, math.floor(screen.y - 40)))
    local border = 4
    local innerW = winW - border * 2
    local innerH = winH - border * 2
    local titleH = 36
    local footerH = 28
    local bodyH = innerH - titleH - footerH - 2

    local scale = winW / preset.w
    local sidebarW = math.max(155, math.floor(preset.sidebar * scale))
    local listW = math.max(195, math.floor(preset.list * scale))
    local editorW = math.max(280, innerW - sidebarW - listW - 2)

    local fontSize = tonumber(self.settings.getAppearance('fontSize')) or 16
    fontSize = util.clamp(math.floor(fontSize), 12, 26)

    return {
        screen = screen,
        winW = winW,
        winH = winH,
        innerW = innerW,
        innerH = innerH,
        titleH = titleH,
        footerH = footerH,
        bodyH = bodyH,
        sidebarW = sidebarW,
        listW = listW,
        editorW = editorW,
        fontSize = fontSize,
    }
end

function JournalUI:getPalette()
    local themeKey = self.settings.getAppearance('theme') or 'dark'
    local accentColor = self.settings.getAppearance('accentColor')
    return W.resolveTheme(themeKey, accentColor)
end

function JournalUI:clampWindowPos(pos, m)
    local x = util.clamp(pos.x, 4, math.max(4, m.screen.x - m.winW - 4))
    local y = util.clamp(pos.y, 4, math.max(4, m.screen.y - m.winH - 4))
    return v2(math.floor(x), math.floor(y))
end

function JournalUI:getWindowPos(m)
    if not self.windowPos then
        self.windowPos = v2(
            math.floor((m.screen.x - m.winW) * 0.5),
            math.floor((m.screen.y - m.winH) * 0.5)
        )
    end
    self.windowPos = self:clampWindowPos(self.windowPos, m)
    return self.windowPos
end

function JournalUI:saveIfAuto(silentStatus)
    if self.settings.getGeneral('autoSave') ~= false then
        self.onPersist()
        if not silentStatus then
            self.statusMessage = 'Auto-saved'
        end
    else
        self.statusMessage = 'Unsaved changes'
    end
end

function JournalUI:explicitSave()
    local note = self.store:getSelectedNote()
    if note then
        self.store:captureUndoSnapshot(note.id)
    end
    self.onPersist()
    self.statusMessage = 'Saved'
    self.onPlaySound('book page')
    self:refreshFooter()
    self:refreshNotesList()
end

-- === Safe element lifecycle ===

local function destroyEl(el)
    if el and el.layout then
        el:destroy()
    end
end

function JournalUI:destroyModal()
    destroyEl(self.modalElement)
    self.modalElement = nil
    self.modalState = nil
    self.modalInputValue = ''
end

function JournalUI:destroyMainElements()
    self:destroyModal()
    destroyEl(self.footerElement)
    destroyEl(self.editorElement)
    destroyEl(self.notesListElement)
    destroyEl(self.sidebarElement)
    destroyEl(self.rootElement)
    self.footerElement = nil
    self.editorElement = nil
    self.notesListElement = nil
    self.sidebarElement = nil
    self.rootElement = nil
    self.isTextFocused = false
    self.dragState = nil
end

function JournalUI:open(opts)
    opts = opts or {}
    self.worldObject = opts.worldObject or nil
    if self.visible then
        self:rebuildAll()
        return
    end
    self.visible = true
    self.statusMessage = 'Saved'
    self:rebuildAll()
end

function JournalUI:close()
    if not self.visible then return end
    self.onPersist()
    self:destroyMainElements()
    self.visible = false
    self.worldObject = nil
end

-- === Refresh helpers (partial updates keep TextEdit focus intact!) ===

function JournalUI:refreshFooter()
    if not self.visible or not self.footerElement then return end
    local m = self:getMetrics()
    local palette = self:getPalette()
    self.footerElement.layout = self:buildFooterLayout(m, palette)
    self.footerElement:update()
end

function JournalUI:refreshSidebar()
    if not self.visible or not self.sidebarElement then return end
    local m = self:getMetrics()
    local palette = self:getPalette()
    self.sidebarElement.layout = self:buildSidebarLayout(m, palette)
    self.sidebarElement:update()
end

function JournalUI:refreshNotesList()
    if not self.visible or not self.notesListElement then return end
    local m = self:getMetrics()
    local palette = self:getPalette()
    self.notesListElement.layout = self:buildNotesListLayout(m, palette)
    self.notesListElement:update()
end

function JournalUI:refreshEditor()
    if not self.visible or not self.editorElement then return end
    self.isTextFocused = false
    local m = self:getMetrics()
    local palette = self:getPalette()
    self.editorElement.layout = self:buildEditorLayout(m, palette)
    self.editorElement:update()
    self:refreshFooter()
end

function JournalUI:rebuildAll()
    if not self.visible then return end
    local savedModal = self.modalState
    self:destroyMainElements()
    local m = self:getMetrics()
    local palette = self:getPalette()

    self.sidebarElement = ui.create(self:buildSidebarLayout(m, palette))
    self.notesListElement = ui.create(self:buildNotesListLayout(m, palette))
    self.editorElement = ui.create(self:buildEditorLayout(m, palette))
    self.footerElement = ui.create(self:buildFooterLayout(m, palette))
    self.rootElement = ui.create(self:buildRootLayout(m, palette))

    if savedModal then
        self:openModal(savedModal)
    end
end

-- === Modal Dialogs (Confirm Delete / Undo, New Notebook, Rename Notebook, Template Picker) ===

function JournalUI:openModal(modalSpec)
    self:destroyModal()
    self.modalState = modalSpec
    self.modalInputValue = modalSpec.initialValue or ''
    local m = self:getMetrics()
    local palette = self:getPalette()
    self.modalElement = ui.create(self:buildModalLayout(m, palette, modalSpec))
end

function JournalUI:buildModalLayout(m, palette, spec)
    local boxW = spec.width or 380
    local contentRows = {
        W.label(spec.title or 'Confirm', palette.textHeader, 16),
        W.spacer(0, 6),
        W.hDivider(palette, boxW - 28),
        W.spacer(0, 8),
    }

    if spec.message then
        contentRows[#contentRows + 1] = W.label(spec.message, palette.text, 14, {
            size = v2(boxW - 28, 48),
            autoSize = false,
            multiline = true,
            wordWrap = true,
        })
        contentRows[#contentRows + 1] = W.spacer(0, 8)
    end

    if spec.kind == 'input' then
        contentRows[#contentRows + 1] = W.textField {
            palette = palette,
            width = boxW - 28,
            height = 30,
            textSize = 15,
            text = self.modalInputValue,
            onChange = function(text)
                self.modalInputValue = text
            end,
            onFocusGain = function() self.isTextFocused = true end,
            onFocusLoss = function() self.isTextFocused = false end,
        }
        contentRows[#contentRows + 1] = W.spacer(0, 10)
    elseif spec.kind == 'templates' then
        for _, tpl in ipairs(common.TEMPLATES) do
            contentRows[#contentRows + 1] = W.button {
                palette = palette,
                label = '+ ' .. tpl.label,
                width = boxW - 28,
                height = 28,
                textSize = 14,
                onClick = function()
                    self:applyTemplate(tpl)
                    self:destroyModal()
                end,
            }
            contentRows[#contentRows + 1] = W.spacer(0, 4)
        end
        contentRows[#contentRows + 1] = W.spacer(0, 6)
    end

    local btnRow = {}
    if spec.kind == 'confirm' or spec.kind == 'input' then
        btnRow[#btnRow + 1] = W.button {
            palette = palette,
            label = spec.confirmLabel or 'Confirm',
            danger = spec.danger,
            active = not spec.danger,
            width = 110,
            height = 28,
            textSize = 14,
            onClick = function()
                local val = self.modalInputValue
                local cb = spec.onConfirm
                self:destroyModal()
                if cb then cb(val) end
            end,
        }
        btnRow[#btnRow + 1] = W.spacer(10, 0)
    end
    btnRow[#btnRow + 1] = W.button {
        palette = palette,
        label = 'Cancel',
        width = 96,
        height = 28,
        textSize = 14,
        onClick = function()
            self:destroyModal()
        end,
    }

    contentRows[#contentRows + 1] = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            align = ui.ALIGNMENT.End,
            size = v2(boxW - 28, 30),
        },
        content = ui.content(btnRow),
    }

    local boxH = spec.kind == 'templates' and 265 or (spec.kind == 'input' and 175 or 165)

    return {
        layer = 'Windows',
        type = ui.TYPE.Widget,
        props = {
            size = m.screen,
            position = v2(0, 0),
        },
        content = ui.content {
            -- Dimmed backdrop that blocks clicks underneath
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    color = util.color.rgb(0, 0, 0),
                    alpha = 0.55,
                    relativeSize = v2(1, 1),
                },
                events = {
                    mouseClick = async:callback(function() end),
                },
            },
            {
                template = I.MWUI.templates.bordersThick,
                type = ui.TYPE.Widget,
                props = {
                    size = v2(boxW, boxH),
                    relativePosition = v2(0.5, 0.5),
                    anchor = v2(0.5, 0.5),
                },
                content = ui.content {
                    W.solidRect(palette.windowBg),
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = false,
                            position = v2(10, 10),
                            size = v2(boxW - 20, boxH - 20),
                        },
                        content = ui.content(contentRows),
                    },
                },
            },
        },
    }
end

-- === Actions ===

function JournalUI:createNewNote(isDiary)
    local ctx = self.getContext()
    local opts
    if isDiary then
        local tpl = common.TEMPLATES[1]
        opts = {
            title = tpl.title(ctx),
            body = tpl.body(ctx),
            tags = tpl.tags,
        }
    else
        opts = {
            title = 'Untitled Note',
            body = '',
            tags = '',
        }
    end
    self.store:createNote(opts, ctx)
    self.editorMode = 'edit'
    self.noteOffset = 0
    self.onPlaySound('book page')
    self:saveIfAuto()
    self:refreshSidebar()
    self:refreshNotesList()
    self:refreshEditor()
end

function JournalUI:applyTemplate(tpl)
    local note = self.store:getSelectedNote()
    local ctx = self.getContext()
    local tplBody = tpl.body(ctx)
    if not note then
        self.store:createNote({
            title = tpl.title(ctx),
            body = tplBody,
            tags = tpl.tags,
        }, ctx)
    else
        local newTitle = note.title
        if common.trim(newTitle) == '' or newTitle == 'Untitled Note' then
            newTitle = tpl.title(ctx)
        end
        local newBody = note.body
        if common.trim(newBody) == '' then
            newBody = tplBody
        else
            newBody = newBody .. '\n\n' .. tplBody
        end
        local mergedTags = common.formatTags(note.tags)
        if mergedTags == '' then
            mergedTags = tpl.tags
        else
            mergedTags = mergedTags .. ', ' .. tpl.tags
        end
        self.store:updateNote(note.id, {
            title = newTitle,
            body = newBody,
            tags = mergedTags,
        }, ctx)
    end
    self.editorMode = 'edit'
    self.onPlaySound('book page2')
    self:saveIfAuto()
    self:refreshSidebar()
    self:refreshNotesList()
    self:refreshEditor()
end

function JournalUI:appendSnippet(snippet)
    local note = self.store:getSelectedNote()
    if not note then return end
    local ctx = self.getContext()
    local body = note.body or ''
    if body ~= '' and body:sub(-1) ~= '\n' then
        body = body .. '\n'
    end
    body = body .. snippet
    self.store:updateNote(note.id, { body = body }, ctx)
    self:saveIfAuto()
    self:refreshEditor()
end

function JournalUI:requestDeleteNote(note)
    local doDelete = function()
        self.store:deleteNote(note.id)
        self.onPlaySound('book page2')
        self:saveIfAuto()
        self:refreshSidebar()
        self:refreshNotesList()
        self:refreshEditor()
    end
    if self.settings.getGeneral('confirmDelete') ~= false then
        self:openModal {
            kind = 'confirm',
            title = 'Delete Note',
            message = string.format('Permanently delete "%s"?', common.truncate(note.title, 42)),
            confirmLabel = 'Delete',
            danger = true,
            onConfirm = doDelete,
        }
    else
        doDelete()
    end
end

function JournalUI:requestUndoNote(note)
    local doUndo = function()
        if self.store:undoNote(note.id) then
            self.statusMessage = 'Reverted'
            self.onPlaySound('book page2')
            self:refreshNotesList()
            self:refreshEditor()
        end
    end
    if self.settings.getGeneral('confirmUndo') == true then
        self:openModal {
            kind = 'confirm',
            title = 'Undo Changes',
            message = 'Revert this note back to its last saved snapshot?',
            confirmLabel = 'Revert',
            onConfirm = doUndo,
        }
    else
        doUndo()
    end
end

function JournalUI:requestCreateNotebook()
    self:openModal {
        kind = 'input',
        title = 'New Notebook',
        message = 'Enter a name for your new notebook:',
        initialValue = '',
        confirmLabel = 'Create',
        onConfirm = function(name)
            local nb = self.store:createNotebook(name, self.getContext())
            if nb then
                self.store:setView('notebook', nb.id)
                self.noteOffset = 0
                self.onPlaySound('book page')
                self:saveIfAuto()
                self:refreshSidebar()
                self:refreshNotesList()
                self:refreshEditor()
            end
        end,
    }
end

function JournalUI:requestRenameNotebook(nb)
    self:openModal {
        kind = 'input',
        title = 'Rename Notebook',
        message = string.format('Rename "%s" to:', nb.name),
        initialValue = nb.name,
        confirmLabel = 'Rename',
        onConfirm = function(newName)
            if self.store:renameNotebook(nb.id, newName) then
                self:saveIfAuto()
                self:refreshSidebar()
                self:refreshNotesList()
                self:refreshEditor()
            end
        end,
    }
end

function JournalUI:requestDeleteNotebook(nb)
    if #self.store:getNotebooks() <= 1 then return end
    local doDelete = function()
        if self.store:deleteNotebook(nb.id) then
            self.nbOffset = 0
            self.noteOffset = 0
            self.onPlaySound('book page2')
            self:saveIfAuto()
            self:refreshSidebar()
            self:refreshNotesList()
            self:refreshEditor()
        end
    end
    if self.settings.getGeneral('confirmDelete') ~= false then
        self:openModal {
            kind = 'confirm',
            title = 'Delete Notebook',
            message = string.format('Delete notebook "%s"? Any notes inside will be moved safely to your first notebook.', nb.name),
            confirmLabel = 'Delete',
            danger = true,
            onConfirm = doDelete,
        }
    else
        doDelete()
    end
end

-- === Layout Builders ===

function JournalUI:buildTitleBar(m, palette)
    local ctx = self.getContext()
    local subtitle = ctx.dateShort
    if ctx.location and ctx.location ~= '' then
        subtitle = subtitle .. '  |  ' .. common.truncate(ctx.location, 28)
    end

    local rightButtons = {}
    if self.worldObject then
        rightButtons[#rightButtons + 1] = W.button {
            palette = palette,
            label = 'Take',
            height = 24,
            textSize = 12,
            active = true,
            onClick = function()
                local obj = self.worldObject
                self.worldObject = nil
                if self.onTakeWorldObject then
                    self.onTakeWorldObject(obj)
                end
                self:rebuildAll()
            end,
        }
        rightButtons[#rightButtons + 1] = W.spacer(4, 0)
    end

    rightButtons[#rightButtons + 1] = W.button {
        palette = palette,
        label = self.windowLocked and 'Locked' or 'Move',
        height = 24,
        textSize = 12,
        active = self.windowLocked,
        onClick = function()
            self.windowLocked = not self.windowLocked
            self:rebuildAll()
        end,
    }
    rightButtons[#rightButtons + 1] = W.spacer(4, 0)

    rightButtons[#rightButtons + 1] = W.button {
        palette = palette,
        label = 'Theme',
        height = 24,
        textSize = 12,
        onClick = function()
            local order = { 'dark', 'parchment', 'slate', 'highContrast' }
            local cur = self.settings.getAppearance('theme') or 'dark'
            local nextTheme = 'dark'
            for i, k in ipairs(order) do
                if k == cur then
                    nextTheme = order[(i % #order) + 1]
                    break
                end
            end
            self.settings.setAppearance('theme', nextTheme)
        end,
    }
    rightButtons[#rightButtons + 1] = W.spacer(4, 0)

    rightButtons[#rightButtons + 1] = W.button {
        palette = palette,
        label = 'Size',
        height = 24,
        textSize = 12,
        onClick = function()
            local order = { 'compact', 'standard', 'large' }
            local cur = self.settings.getAppearance('windowPreset') or 'standard'
            local nextPreset = 'standard'
            for i, k in ipairs(order) do
                if k == cur then
                    nextPreset = order[(i % #order) + 1]
                    break
                end
            end
            self.windowPos = nil -- re-center cleanly on resize
            self.settings.setAppearance('windowPreset', nextPreset)
        end,
    }
    rightButtons[#rightButtons + 1] = W.spacer(6, 0)

    rightButtons[#rightButtons + 1] = W.button {
        palette = palette,
        label = 'X',
        height = 24,
        width = 26,
        textSize = 12,
        danger = true,
        onClick = function()
            self.onCloseRequest()
        end,
    }

    local titleEvents = {
        mousePress = async:callback(function(e)
            if self.windowLocked or e.button ~= 1 then return end
            local metrics = self:getMetrics()
            self.dragState = {
                startMouse = e.position,
                startPos = self:getWindowPos(metrics),
            }
        end),
        mouseMove = async:callback(function(e)
            if not self.dragState or self.windowLocked or not self.rootElement then return end
            local metrics = self:getMetrics()
            local delta = e.position - self.dragState.startMouse
            local newPos = self:clampWindowPos(self.dragState.startPos + delta, metrics)
            self.windowPos = newPos
            self.rootElement.layout.props.position = newPos
            self.rootElement:update()
        end),
        mouseRelease = async:callback(function()
            self.dragState = nil
        end),
    }

    return {
        type = ui.TYPE.Widget,
        props = {
            size = v2(m.innerW, m.titleH),
        },
        events = titleEvents,
        content = ui.content {
            W.solidRect(palette.titleBg),
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                    position = v2(10, 0),
                    size = v2(m.innerW - 20, m.titleH),
                },
                content = ui.content {
                    W.label(self.store.data.journalTitle or 'Personal Journal', palette.titleText, 16),
                    W.spacer(12, 0),
                    W.label(subtitle, palette.titleMuted, 12),
                    {
                        type = ui.TYPE.Widget,
                        external = { grow = 1 },
                    },
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            arrange = ui.ALIGNMENT.Center,
                        },
                        content = ui.content(rightButtons),
                    },
                },
            },
        },
    }
end

function JournalUI:buildSidebarLayout(m, palette)
    local pad = 8
    local innerW = m.sidebarW - pad * 2
    local view = self.store.data.activeView
    local totalNotes = #self.store.data.notes
    local pinnedCount = self.store:countPinnedNotes()
    local notebooks = self.store:getNotebooks()
    local tags = self.store:getAllTags()

    local rows = {}

    -- Smart views
    rows[#rows + 1] = W.button {
        palette = palette,
        label = string.format('All Notes (%d)', totalNotes),
        width = innerW,
        height = 25,
        textSize = 13,
        alignH = ui.ALIGNMENT.Start,
        active = view == 'all',
        selectedIndicator = view == 'all',
        borderless = view ~= 'all',
        bg = (view == 'all') and palette.itemSelectedBg or palette.sidebarBg,
        fg = (view == 'all') and palette.itemSelectedText or palette.text,
        onClick = function()
            self.store:setView('all')
            self.noteOffset = 0
            self:refreshSidebar()
            self:refreshNotesList()
        end,
    }
    rows[#rows + 1] = W.spacer(0, 2)
    rows[#rows + 1] = W.button {
        palette = palette,
        label = string.format('Pinned (%d)', pinnedCount),
        width = innerW,
        height = 25,
        textSize = 13,
        alignH = ui.ALIGNMENT.Start,
        active = view == 'pinned',
        selectedIndicator = view == 'pinned',
        borderless = view ~= 'pinned',
        bg = (view == 'pinned') and palette.itemSelectedBg or palette.sidebarBg,
        fg = (view == 'pinned') and palette.itemSelectedText or palette.text,
        onClick = function()
            self.store:setView('pinned')
            self.noteOffset = 0
            self:refreshSidebar()
            self:refreshNotesList()
        end,
    }

    rows[#rows + 1] = W.spacer(0, 6)
    rows[#rows + 1] = W.hDivider(palette, innerW)
    rows[#rows + 1] = W.spacer(0, 6)

    -- Notebooks Header + New button
    rows[#rows + 1] = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
            size = v2(innerW, 26),
        },
        content = ui.content {
            W.label('NOTEBOOKS', palette.textAccent, 12),
            { type = ui.TYPE.Widget, external = { grow = 1 } },
            W.button {
                palette = palette,
                label = '+ New',
                height = 24,
                textSize = 12,
                padX = 6,
                padY = 2,
                onClick = function()
                    self:requestCreateNotebook()
                end,
            },
        },
    }
    rows[#rows + 1] = W.spacer(0, 4)

    -- Paginated Notebooks List (dynamically sized to never overflow sidebar height)
    local activeNb = (view == 'notebook') and self.store:getNotebookById(self.store.data.activeNotebookId) or nil
    local overhead = 128 + (activeNb and 28 or 0)
    local availH = math.max(120, (m.bodyH - pad * 2) - overhead)
    local tagPageSize = (#tags > 0) and math.min(5, math.max(2, math.floor(availH * 0.36 / 26))) or 0
    local tagNavH = (#tags > tagPageSize) and 26 or 0
    local tagUsedH = (#tags == 0) and 18 or (math.min(#tags, tagPageSize) * 26 + tagNavH)

    local nbPageSize = math.max(3, math.floor((availH - tagUsedH) / 26))
    if #notebooks > nbPageSize then
        nbPageSize = math.max(2, math.floor((availH - tagUsedH - 26) / 26))
    end
    local maxNbOffset = math.max(0, #notebooks - nbPageSize)
    self.nbOffset = util.clamp(self.nbOffset, 0, maxNbOffset)

    local endNb = math.min(#notebooks, self.nbOffset + nbPageSize)
    for i = self.nbOffset + 1, endNb do
        local nb = notebooks[i]
        local isSel = (view == 'notebook' and self.store.data.activeNotebookId == nb.id)
        local cnt = self.store:countNotesInNotebook(nb.id)
        local text = string.format('%s (%d)', common.truncate(nb.name, 16), cnt)
        rows[#rows + 1] = W.button {
            palette = palette,
            label = text,
            width = innerW,
            height = 24,
            textSize = 13,
            alignH = ui.ALIGNMENT.Start,
            active = isSel,
            selectedIndicator = isSel,
            borderless = not isSel,
            bg = isSel and palette.itemSelectedBg or palette.sidebarBg,
            fg = isSel and palette.itemSelectedText or palette.text,
            onClick = function()
                self.store:setView('notebook', nb.id)
                self.noteOffset = 0
                self:refreshSidebar()
                self:refreshNotesList()
            end,
        }
        rows[#rows + 1] = W.spacer(0, 2)
    end

    if #notebooks > nbPageSize then
        rows[#rows + 1] = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, size = v2(innerW, 24) },
            content = ui.content {
                W.button {
                    palette = palette,
                    label = '^ Up',
                    width = 48,
                    height = 24,
                    textSize = 12,
                    disabled = self.nbOffset <= 0,
                    onClick = function()
                        self.nbOffset = math.max(0, self.nbOffset - 1)
                        self:refreshSidebar()
                    end,
                },
                W.spacer(4, 0),
                W.button {
                    palette = palette,
                    label = 'Dn v',
                    width = 48,
                    height = 24,
                    textSize = 12,
                    disabled = self.nbOffset >= maxNbOffset,
                    onClick = function()
                        self.nbOffset = math.min(maxNbOffset, self.nbOffset + 1)
                        self:refreshSidebar()
                    end,
                },
            },
        }
        rows[#rows + 1] = W.spacer(0, 2)
    end

    -- Active notebook Rename / Delete controls
    if activeNb then
        rows[#rows + 1] = W.spacer(0, 2)
        rows[#rows + 1] = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, size = v2(innerW, 24) },
            content = ui.content {
                W.button {
                    palette = palette,
                    label = 'Rename',
                    width = math.floor((innerW - 4) / 2),
                    height = 24,
                    textSize = 12,
                    onClick = function()
                        self:requestRenameNotebook(activeNb)
                    end,
                },
                W.spacer(4, 0),
                W.button {
                    palette = palette,
                    label = 'Delete',
                    width = math.floor((innerW - 4) / 2),
                    height = 24,
                    textSize = 12,
                    danger = true,
                    disabled = #notebooks <= 1,
                    onClick = function()
                        self:requestDeleteNotebook(activeNb)
                    end,
                },
            },
        }
    end

    rows[#rows + 1] = W.spacer(0, 6)
    rows[#rows + 1] = W.hDivider(palette, innerW)
    rows[#rows + 1] = W.spacer(0, 6)

    -- Tags section (no '#' prefix so OpenMW MyGUI does not parse tag names as color codes!)
    rows[#rows + 1] = W.label('TAGS', palette.textAccent, 12)
    rows[#rows + 1] = W.spacer(0, 4)

    if #tags == 0 then
        rows[#rows + 1] = W.label('No tags yet', palette.textMuted, 12)
    else
        local maxTagOffset = math.max(0, #tags - tagPageSize)
        self.tagOffset = util.clamp(self.tagOffset, 0, maxTagOffset)
        local endTag = math.min(#tags, self.tagOffset + tagPageSize)
        for i = self.tagOffset + 1, endTag do
            local t = tags[i]
            local isSel = (view == 'tag' and self.store.data.activeTag == t.name)
            rows[#rows + 1] = W.button {
                palette = palette,
                label = string.format('%s (%d)', common.truncate(t.name, 16), t.count),
                width = innerW,
                height = 24,
                textSize = 12,
                alignH = ui.ALIGNMENT.Start,
                active = isSel,
                selectedIndicator = isSel,
                borderless = not isSel,
                bg = isSel and palette.itemSelectedBg or palette.sidebarBg,
                fg = isSel and palette.itemSelectedText or palette.text,
                onClick = function()
                    self.store:setView('tag', t.name)
                    self.noteOffset = 0
                    self:refreshSidebar()
                    self:refreshNotesList()
                end,
            }
            rows[#rows + 1] = W.spacer(0, 2)
        end
        if #tags > tagPageSize then
            rows[#rows + 1] = {
                type = ui.TYPE.Flex,
                props = { horizontal = true, size = v2(innerW, 24) },
                content = ui.content {
                    W.button {
                        palette = palette,
                        label = '^ Up',
                        width = 48,
                        height = 24,
                        textSize = 12,
                        disabled = self.tagOffset <= 0,
                        onClick = function()
                            self.tagOffset = math.max(0, self.tagOffset - 1)
                            self:refreshSidebar()
                        end,
                    },
                    W.spacer(4, 0),
                    W.button {
                        palette = palette,
                        label = 'Dn v',
                        width = 48,
                        height = 24,
                        textSize = 12,
                        disabled = self.tagOffset >= maxTagOffset,
                        onClick = function()
                            self.tagOffset = math.min(maxTagOffset, self.tagOffset + 1)
                            self:refreshSidebar()
                        end,
                    },
                },
            }
        end
    end

    return W.panelBox(palette.sidebarBg, m.sidebarW, m.bodyH, {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                position = v2(pad, pad),
                size = v2(innerW, m.bodyH - pad * 2),
            },
            content = ui.content(rows),
        },
    })
end

function JournalUI:buildNotesListLayout(m, palette)
    local pad = 8
    local innerW = m.listW - pad * 2
    local listAreaH = m.bodyH - 87 -- below search bar and action buttons
    local filtered = self.store:getFilteredNotes(self.searchQuery)
    local selectedId = self.store.data.selectedNoteId

    local cardH = 58
    local cardGap = 4
    local pageSize = math.max(3, math.floor((listAreaH - 30) / (cardH + cardGap)))
    local maxOffset = math.max(0, #filtered - pageSize)
    self.noteOffset = util.clamp(self.noteOffset, 0, maxOffset)

    local rows = {}

    if #filtered == 0 then
        rows[#rows + 1] = W.spacer(0, 14)
        rows[#rows + 1] = W.label(
            self.searchQuery ~= '' and 'No matching notes.' or 'No notes in this view.',
            palette.textMuted,
            13
        )
    else
        local endIdx = math.min(#filtered, self.noteOffset + pageSize)
        for i = self.noteOffset + 1, endIdx do
            local note = filtered[i]
            local isSel = (note.id == selectedId)
            local nb = self.store:getNotebookById(note.notebookId)
            local titlePrefix = note.pinned and '* ' or ''
            local titleStr = titlePrefix .. common.truncate(note.title ~= '' and note.title or 'Untitled Note', 22)
            local metaStr = note.updatedDate ~= '' and note.updatedDate or 'No date'
            if self.store.data.activeView ~= 'notebook' and nb then
                metaStr = common.truncate(nb.name, 12) .. ' | ' .. metaStr
            end
            local snippet = common.truncate(note.body, 27)
            if snippet == '' then snippet = '(Empty note)' end

            local cardContent = {
                W.solidRect(isSel and palette.itemSelectedBg or palette.itemAltBg),
            }
            if isSel and palette.selectionStrip then
                cardContent[#cardContent + 1] = W.solidRect(palette.selectionStrip, v2(3, cardH))
            end
            cardContent[#cardContent + 1] = {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    position = v2(isSel and 8 or 6, 4),
                    size = v2(innerW - (isSel and 14 or 12), cardH - 8),
                },
                content = ui.content {
                    W.label(titleStr, isSel and palette.itemSelectedText or palette.text, 13),
                    W.spacer(0, 2),
                    W.label(common.truncate(metaStr, 28), isSel and palette.itemSelectedAccent or palette.textAccent, 12),
                    W.spacer(0, 2),
                    W.label(snippet, isSel and palette.itemSelectedMuted or palette.textMuted, 12),
                },
            }

            rows[#rows + 1] = {
                template = isSel and I.MWUI.templates.borders or nil,
                type = ui.TYPE.Widget,
                props = {
                    size = v2(innerW, cardH),
                },
                events = {
                    mouseClick = async:callback(function()
                        if self.store.data.selectedNoteId ~= note.id then
                            self:saveIfAuto(true)
                            self.store:selectNote(note.id)
                            self.checklistOffset = 0
                            self.onPlaySound('book page')
                            self:refreshNotesList()
                            self:refreshEditor()
                        end
                    end),
                },
                content = ui.content(cardContent),
            }
            rows[#rows + 1] = W.spacer(0, cardGap)
        end
    end

    -- Pagination footer for notes list
    local navRow = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
            size = v2(innerW, 24),
        },
        content = ui.content {
            W.button {
                palette = palette,
                label = '< Prev',
                height = 24,
                textSize = 12,
                padX = 5,
                disabled = self.noteOffset <= 0,
                onClick = function()
                    self.noteOffset = math.max(0, self.noteOffset - pageSize)
                    self:refreshNotesList()
                end,
            },
            { type = ui.TYPE.Widget, external = { grow = 1 } },
            W.label(
                #filtered > 0
                    and string.format('%d-%d / %d', self.noteOffset + 1, math.min(#filtered, self.noteOffset + pageSize), #filtered)
                    or '0 / 0',
                palette.textMuted,
                12
            ),
            { type = ui.TYPE.Widget, external = { grow = 1 } },
            W.button {
                palette = palette,
                label = 'Next >',
                height = 24,
                textSize = 12,
                padX = 5,
                disabled = self.noteOffset >= maxOffset,
                onClick = function()
                    self.noteOffset = math.min(maxOffset, self.noteOffset + pageSize)
                    self:refreshNotesList()
                end,
            },
        },
    }

    return {
        type = ui.TYPE.Widget,
        props = {
            size = v2(innerW, listAreaH),
        },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    size = v2(innerW, listAreaH - 28),
                },
                content = ui.content(rows),
            },
            {
                type = ui.TYPE.Widget,
                props = {
                    position = v2(0, listAreaH - 26),
                    size = v2(innerW, 26),
                },
                content = ui.content { navRow },
            },
        },
    }
end

function JournalUI:buildMiddlePane(m, palette)
    local pad = 8
    local innerW = m.listW - pad * 2
    local sortLabel = common.SORT_LABELS[self.store.data.sortBy] or 'Updated'
    local actionPad = (innerW < 210) and 4 or 6

    return W.panelBox(palette.listBg, m.listW, m.bodyH, {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                position = v2(pad, pad),
                size = v2(innerW, m.bodyH - pad * 2),
            },
            content = ui.content {
                -- Search row (never rebuilt while typing!)
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        arrange = ui.ALIGNMENT.Center,
                        size = v2(innerW, 28),
                    },
                    content = ui.content {
                        W.textField {
                            palette = palette,
                            width = innerW - 38,
                            height = 26,
                            textSize = 13,
                            pad = 3,
                            text = self.searchQuery,
                            onChange = function(text)
                                self.searchQuery = text
                                self.noteOffset = 0
                                self:refreshNotesList()
                            end,
                            onFocusGain = function() self.isTextFocused = true end,
                            onFocusLoss = function() self.isTextFocused = false end,
                        },
                        W.spacer(4, 0),
                        W.button {
                            palette = palette,
                            label = 'Clr',
                            width = 34,
                            height = 26,
                            textSize = 12,
                            disabled = self.searchQuery == '',
                            onClick = function()
                                if self.searchQuery ~= '' then
                                    self.searchQuery = ''
                                    self.noteOffset = 0
                                    self:rebuildAll()
                                end
                            end,
                        },
                    },
                },
                W.spacer(0, 6),
                -- Action row: + Note | + Diary | Sort
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        arrange = ui.ALIGNMENT.Center,
                        size = v2(innerW, 26),
                    },
                    content = ui.content {
                        W.button {
                            palette = palette,
                            label = '+ Note',
                            height = 24,
                            textSize = 12,
                            padX = actionPad,
                            active = true,
                            onClick = function()
                                self:createNewNote(false)
                            end,
                        },
                        W.spacer(4, 0),
                        W.button {
                            palette = palette,
                            label = '+ Diary',
                            height = 24,
                            textSize = 12,
                            padX = actionPad,
                            onClick = function()
                                self:createNewNote(true)
                            end,
                        },
                        { type = ui.TYPE.Widget, external = { grow = 1 } },
                        W.button {
                            palette = palette,
                            label = sortLabel,
                            height = 24,
                            textSize = 12,
                            padX = actionPad,
                            onClick = function()
                                self.store:cycleSort()
                                self:saveIfAuto(true)
                                self:rebuildAll()
                            end,
                        },
                    },
                },
                W.spacer(0, 6),
                W.hDivider(palette, innerW),
                W.spacer(0, 4),
                -- Independent sub-element for filtered note cards
                self.notesListElement,
            },
        },
    })
end

function JournalUI:buildChecklistBody(note, innerW, bodyAreaH, m, palette)
    local lines = Store.parseLines(note.body)
    local rowH = math.max(26, m.fontSize + 10)
    local pageSize = math.max(5, math.floor((bodyAreaH - 38) / rowH))
    local maxOffset = math.max(0, #lines - pageSize)
    self.checklistOffset = util.clamp(self.checklistOffset, 0, maxOffset)

    local rows = {}
    local endIdx = math.min(#lines, self.checklistOffset + pageSize)
    for i = self.checklistOffset + 1, endIdx do
        local line = lines[i]
        if line.isTask then
            rows[#rows + 1] = {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                    size = v2(innerW - 12, rowH),
                },
                content = ui.content {
                    W.button {
                        palette = palette,
                        label = line.checked and '[x]' or '[ ]',
                        width = 36,
                        height = math.max(24, rowH - 2),
                        textSize = math.max(12, m.fontSize - 1),
                        active = line.checked,
                        fg = line.checked and palette.buttonActiveText or palette.textAccent,
                        onClick = function()
                            self.store:toggleChecklistLine(note.id, line.index, self.getContext())
                            self.onPlaySound('book page')
                            self:saveIfAuto()
                            self:refreshEditor()
                        end,
                    },
                    W.spacer(8, 0),
                    W.label(
                        line.text ~= '' and line.text or '(empty task)',
                        line.checked and palette.textMuted or palette.text,
                        m.fontSize
                    ),
                },
            }
        else
            rows[#rows + 1] = {
                type = ui.TYPE.Widget,
                props = { size = v2(innerW - 12, rowH) },
                content = ui.content {
                    W.label(line.raw, palette.text, m.fontSize),
                },
            }
        end
    end

    local navBar = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
            position = v2(6, bodyAreaH - 28),
            size = v2(innerW - 12, 24),
        },
        content = ui.content {
            W.label('Click [ ] checkboxes to toggle tasks live.', palette.textMuted, 12),
            { type = ui.TYPE.Widget, external = { grow = 1 } },
            W.button {
                palette = palette,
                label = '^ Up',
                height = 24,
                textSize = 12,
                padX = 5,
                disabled = self.checklistOffset <= 0,
                onClick = function()
                    self.checklistOffset = math.max(0, self.checklistOffset - pageSize)
                    self:refreshEditor()
                end,
            },
            W.spacer(4, 0),
            W.label(string.format('%d-%d / %d', self.checklistOffset + 1, endIdx, #lines), palette.textMuted, 12),
            W.spacer(4, 0),
            W.button {
                palette = palette,
                label = 'Down v',
                height = 24,
                textSize = 12,
                padX = 5,
                disabled = self.checklistOffset >= maxOffset,
                onClick = function()
                    self.checklistOffset = math.min(maxOffset, self.checklistOffset + pageSize)
                    self:refreshEditor()
                end,
            },
        },
    }

    return {
        template = I.MWUI.templates.borders,
        type = ui.TYPE.Widget,
        props = {
            size = v2(innerW, bodyAreaH),
        },
        content = ui.content {
            W.solidRect(palette.inputBg),
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    position = v2(6, 6),
                    size = v2(innerW - 12, bodyAreaH - 38),
                },
                content = ui.content(rows),
            },
            navBar,
        },
    }
end

function JournalUI:buildEditorLayout(m, palette)
    local pad = 10
    local innerW = m.editorW - pad * 2
    local note = self.store:getSelectedNote()

    if not note then
        return W.panelBox(palette.editorBg, m.editorW, m.bodyH, {
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                    size = v2(m.editorW, m.bodyH),
                },
                content = ui.content {
                    W.label('No note selected', palette.textHeader, 18),
                    W.spacer(0, 8),
                    W.label('Create a new note or dated diary entry to start writing.', palette.textMuted, 14),
                    W.spacer(0, 14),
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = true },
                        content = ui.content {
                            W.button {
                                palette = palette,
                                label = '+ New Note',
                                active = true,
                                height = 28,
                                textSize = 14,
                                onClick = function() self:createNewNote(false) end,
                            },
                            W.spacer(10, 0),
                            W.button {
                                palette = palette,
                                label = '+ Dated Diary Entry',
                                height = 28,
                                textSize = 14,
                                onClick = function() self:createNewNote(true) end,
                            },
                        },
                    },
                },
            },
        })
    end

    local nb = self.store:getNotebookById(note.notebookId)
    local nbName = nb and nb.name or 'Journal'
    local titleW = math.max(150, innerW - 146)
    local tagsW = math.max(90, innerW - 222)
    local bodyAreaH = math.max(120, m.bodyH - pad * 2 - 102)
    local compactTools = innerW < 450
    local toolPadX = compactTools and 3 or 5
    local toolGap = compactTools and 2 or 3

    local bodyWidget
    if self.editorMode == 'checklist' then
        bodyWidget = self:buildChecklistBody(note, innerW, bodyAreaH, m, palette)
    else
        bodyWidget = W.textField {
            palette = palette,
            name = 'noteBodyEdit',
            width = innerW,
            height = bodyAreaH,
            textSize = m.fontSize,
            multiline = true,
            pad = 6,
            text = note.body,
            onChange = function(text)
                self.store:updateNote(note.id, { body = text }, self.getContext())
                self:saveIfAuto()
                self:refreshFooter()
            end,
            onFocusGain = function() self.isTextFocused = true end,
            onFocusLoss = function()
                self.isTextFocused = false
                self:refreshNotesList()
            end,
        }
    end

    return W.panelBox(palette.editorBg, m.editorW, m.bodyH, {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                position = v2(pad, pad),
                size = v2(innerW, m.bodyH - pad * 2),
            },
            content = ui.content {
                -- Row 1: Editable Note Title + Pin + Edit/Tasks toggle
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        arrange = ui.ALIGNMENT.Center,
                        size = v2(innerW, 30),
                    },
                    content = ui.content {
                        W.textField {
                            palette = palette,
                            name = 'noteTitleEdit',
                            width = titleW,
                            height = 28,
                            textSize = math.min(20, m.fontSize + 2),
                            fg = palette.textHeader,
                            pad = 4,
                            text = note.title,
                            onChange = function(text)
                                self.store:updateNote(note.id, { title = text }, self.getContext())
                                self:saveIfAuto()
                                self:refreshNotesList()
                                self:refreshFooter()
                            end,
                            onFocusGain = function() self.isTextFocused = true end,
                            onFocusLoss = function() self.isTextFocused = false end,
                        },
                        W.spacer(6, 0),
                        W.button {
                            palette = palette,
                            label = note.pinned and '* Pin' or 'Pin',
                            width = 58,
                            height = 28,
                            textSize = 12,
                            active = note.pinned,
                            onClick = function()
                                self.store:updateNote(note.id, { pinned = not note.pinned }, self.getContext())
                                self:saveIfAuto()
                                self:refreshSidebar()
                                self:refreshNotesList()
                                self:refreshEditor()
                            end,
                        },
                        W.spacer(4, 0),
                        W.button {
                            palette = palette,
                            label = self.editorMode == 'edit' and 'Tasks' or 'Edit',
                            width = 76,
                            height = 28,
                            textSize = 12,
                            active = self.editorMode == 'checklist',
                            onClick = function()
                                self.editorMode = (self.editorMode == 'edit') and 'checklist' or 'edit'
                                self.checklistOffset = 0
                                self:refreshEditor()
                            end,
                        },
                    },
                },
                W.spacer(0, 6),
                -- Row 2: Notebook selector & Tags input
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        arrange = ui.ALIGNMENT.Center,
                        size = v2(innerW, 26),
                    },
                    content = ui.content {
                        W.button {
                            palette = palette,
                            label = '<',
                            width = 24,
                            height = 24,
                            textSize = 12,
                            disabled = #self.store:getNotebooks() <= 1,
                            onClick = function()
                                self.store:cycleNoteNotebook(note.id, -1, self.getContext())
                                self:saveIfAuto()
                                self:refreshSidebar()
                                self:refreshNotesList()
                                self:refreshEditor()
                            end,
                        },
                        W.spacer(4, 0),
                        W.label(common.truncate(nbName, 16), palette.textAccent, 12, {
                            size = v2(114, 22),
                            autoSize = false,
                            textAlignH = ui.ALIGNMENT.Center,
                            textAlignV = ui.ALIGNMENT.Center,
                        }),
                        W.spacer(4, 0),
                        W.button {
                            palette = palette,
                            label = '>',
                            width = 24,
                            height = 24,
                            textSize = 12,
                            disabled = #self.store:getNotebooks() <= 1,
                            onClick = function()
                                self.store:cycleNoteNotebook(note.id, 1, self.getContext())
                                self:saveIfAuto()
                                self:refreshSidebar()
                                self:refreshNotesList()
                                self:refreshEditor()
                            end,
                        },
                        W.spacer(8, 0),
                        W.label('Tags:', palette.textMuted, 12),
                        W.spacer(4, 0),
                        W.textField {
                            palette = palette,
                            name = 'noteTagsEdit',
                            width = tagsW,
                            height = 26,
                            textSize = 13,
                            pad = 3,
                            text = common.formatTags(note.tags),
                            onChange = function(text)
                                self.store:updateNote(note.id, { tags = text }, self.getContext())
                                self:saveIfAuto()
                                self:refreshFooter()
                            end,
                            onFocusGain = function() self.isTextFocused = true end,
                            onFocusLoss = function()
                                self.isTextFocused = false
                                self:refreshSidebar()
                                self:refreshNotesList()
                            end,
                        },
                    },
                },
                W.spacer(0, 6),
                -- Row 3: Quick-insert RP/Productivity toolbar + Font + Undo/Save/Dup/Del
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        arrange = ui.ALIGNMENT.Center,
                        size = v2(innerW, 26),
                    },
                    content = ui.content {
                        W.button {
                            palette = palette,
                            label = '+Date',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                self:appendSnippet('[' .. self.getContext().dateFull .. '] ')
                            end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = '+Loc',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                local loc = self.getContext().location
                                self:appendSnippet('Location: ' .. (loc ~= '' and loc or 'The Wilds') .. '\n')
                            end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = '+Task',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                self:appendSnippet('- [ ] ')
                            end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = compactTools and 'Tmpl' or 'Templates',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                self:openModal {
                                    kind = 'templates',
                                    title = 'Insert Roleplay / Productivity Template',
                                    width = 340,
                                }
                            end,
                        },
                        W.spacer(compactTools and 4 or 6, 0),
                        W.button {
                            palette = palette,
                            label = 'A-',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                local sz = math.max(12, m.fontSize - 1)
                                self.settings.setAppearance('fontSize', sz)
                            end,
                        },
                        W.spacer(2, 0),
                        W.button {
                            palette = palette,
                            label = 'A+',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                local sz = math.min(26, m.fontSize + 1)
                                self.settings.setAppearance('fontSize', sz)
                            end,
                        },
                        { type = ui.TYPE.Widget, external = { grow = 1 } },
                        W.button {
                            palette = palette,
                            label = 'Undo',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function() self:requestUndoNote(note) end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = 'Save',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            active = true,
                            onClick = function() self:explicitSave() end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = 'Dup',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            onClick = function()
                                self.store:duplicateNote(note.id, self.getContext())
                                self.onPlaySound('book page')
                                self:saveIfAuto()
                                self:refreshSidebar()
                                self:refreshNotesList()
                                self:refreshEditor()
                            end,
                        },
                        W.spacer(toolGap, 0),
                        W.button {
                            palette = palette,
                            label = 'Del',
                            height = 24,
                            textSize = 12,
                            padX = toolPadX,
                            danger = true,
                            onClick = function() self:requestDeleteNote(note) end,
                        },
                    },
                },
                W.spacer(0, 8),
                -- Row 4: Unrestricted multiline body editor or interactive checklist view
                bodyWidget,
            },
        },
    })
end

function JournalUI:buildFooterLayout(m, palette)
    local note = self.store:getSelectedNote()
    local stats = common.countStats(note and note.body or '')
    local storageLabel = (self.settings.getGeneral('storageMode') == 'shared') and 'Shared' or 'Per-Save'

    local leftText = self.statusMessage
    if note then
        local stamp = note.updatedDate ~= '' and note.updatedDate or note.createdDate
        if stamp ~= '' then
            leftText = leftText .. '  |  Updated: ' .. stamp
        end
        if note.location and note.location ~= '' then
            leftText = leftText .. '  (' .. common.truncate(note.location, 24) .. ')'
        end
    end

    local rightText = string.format(
        'Words: %d  |  Lines: %d  |  Chars: %d  |  %s',
        stats.words, stats.lines, stats.chars, storageLabel
    )

    local statusColor = (self.statusMessage == 'Unsaved changes') and palette.titleAccent or palette.titleSuccess

    return W.panelBox(palette.titleBg, m.innerW, m.footerH, {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
                position = v2(10, 0),
                size = v2(m.innerW - 20, m.footerH),
            },
            content = ui.content {
                W.label(leftText, statusColor, 12),
                { type = ui.TYPE.Widget, external = { grow = 1 } },
                W.label(rightText, palette.titleMuted, 12),
            },
        },
    })
end

function JournalUI:buildRootLayout(m, palette)
    local pos = self:getWindowPos(m)

    return {
        layer = 'Windows',
        template = I.MWUI.templates.bordersThick,
        type = ui.TYPE.Widget,
        props = {
            position = pos,
            size = v2(m.winW, m.winH),
        },
        content = ui.content {
            W.solidRect(palette.windowBg),
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                    position = v2(0, 0),
                    size = v2(m.innerW, m.innerH),
                },
                content = ui.content {
                    self:buildTitleBar(m, palette),
                    W.hDivider(palette, m.innerW),
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            size = v2(m.innerW, m.bodyH),
                        },
                        content = ui.content {
                            self.sidebarElement,
                            W.vDivider(palette, m.bodyH),
                            self:buildMiddlePane(m, palette),
                            W.vDivider(palette, m.bodyH),
                            self.editorElement,
                        },
                    },
                    W.hDivider(palette, m.innerW),
                    self.footerElement,
                },
            },
        },
    }
end

-- === Optional HUD / Menu Quick Button (inspired by ESO Notebook 2018) ===

function JournalUI:updateHudButton(shouldShow, onToggle)
    if not shouldShow then
        destroyEl(self.hudButtonElement)
        self.hudButtonElement = nil
        return
    end
    local palette = self:getPalette()
    local layout = {
        layer = 'Windows',
        type = ui.TYPE.Widget,
        props = {
            relativePosition = v2(1, 0),
            anchor = v2(1, 0),
            position = v2(-16, 16),
            size = v2(88, 28),
        },
        content = ui.content {
            W.button {
                palette = palette,
                label = 'Journal',
                width = 88,
                height = 28,
                textSize = 13,
                active = self.visible,
                onClick = onToggle,
            },
        },
    }
    if self.hudButtonElement and self.hudButtonElement.layout then
        self.hudButtonElement.layout = layout
        self.hudButtonElement:update()
    else
        self.hudButtonElement = ui.create(layout)
    end
end

return JournalUI
