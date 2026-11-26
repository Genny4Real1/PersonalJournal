-- Personal Journal for OpenMW
-- Player script: coordinates input, UI mode lifecycle, persistence, sounds, and public Lua interface.

local ambient = require('openmw.ambient')
local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local ui = require('openmw.ui')
local I = require('openmw.interfaces')
local calendar = require('openmw_aux.calendar')

local common = require('scripts.personal-journal.common')
local settings = require('scripts.personal-journal.settings')
local Store = require('scripts.personal-journal.store')
local JournalUI = require('scripts.personal-journal.ui_journal')

local l10n = core.l10n(common.MOD_ID)
local sharedSection = storage.playerSection(common.SHARED_STORAGE_KEY)

-- Initialize OpenMW Settings page & trigger
settings.init()

local journalRecordId = nil
local requestedInitialGrant = false
local saveDataCache = nil -- per-character serialized journal data
local weOwnUiMode = false
local closingSelf = false

local function getContext()
    local gameTime = core.getGameTime()
    local okShort, dateShort = pcall(calendar.formatGameTime, '%d %B, 3E %Y', gameTime)
    local okFull, dateFull = pcall(calendar.formatGameTime, '%H:%M, %d %B, 3E %Y', gameTime)
    local loc = ''
    if self.cell then
        if self.cell.name and self.cell.name ~= '' then
            loc = self.cell.name
        elseif self.cell.region and self.cell.region ~= '' then
            loc = common.titleCaseRegion(self.cell.region)
        end
    end
    return {
        gameTime = gameTime,
        dateShort = okShort and dateShort or '16 Last Seed, 3E 427',
        dateFull = okFull and dateFull or '09:00, 16 Last Seed, 3E 427',
        location = loc,
    }
end

local store = Store.new(nil, getContext())

local function isSharedMode()
    return settings.getGeneral('storageMode') == 'shared'
end

local function loadActiveStore()
    if isSharedMode() then
        local sharedData = sharedSection:getCopy('journalData')
        store:load(sharedData, getContext())
    else
        store:load(saveDataCache, getContext())
    end
end

local function persistActiveStore()
    local serialized = store:serialize()
    if isSharedMode() then
        sharedSection:set('journalData', serialized)
    else
        saveDataCache = serialized
    end
end

local function playSound(soundId)
    if settings.getGeneral('playSounds') == false then return end
    pcall(ambient.playSound, soundId, { scale = false })
end

local function playerHasJournalItem()
    if not journalRecordId then return false end
    local inv = types.Actor.inventory(self)
    if not inv then return false end
    return inv:countOf(journalRecordId) > 0
end

local journalUI = nil

local function refreshHudButton()
    if not journalUI then return end
    local showSetting = settings.getAppearance('showHudButton') == true
    local mode = I.UI.getMode()
    local shouldShow = showSetting and (mode == 'Interface') and not journalUI:isOpen()
    journalUI:updateHudButton(shouldShow, function()
        if journalUI:isOpen() then
            -- Handled by closeJournal
            journalUI.onCloseRequest()
        else
            -- Handled by openJournal
            self:sendEvent(common.EVENTS.OPEN_JOURNAL, { source = 'hud' })
        end
    end)
end

local function closeJournal(keepUiMode)
    if not journalUI or not journalUI:isOpen() then return end
    journalUI:close()
    playSound('book close')
    if weOwnUiMode and not keepUiMode then
        weOwnUiMode = false
        closingSelf = true
        I.UI.setMode()
        closingSelf = false
    else
        weOwnUiMode = false
    end
    refreshHudButton()
end

local function openJournal(opts)
    opts = opts or {}
    if not journalUI then return false end

    if opts.source == 'hotkey' and settings.getGeneral('requireItem') == true then
        if not playerHasJournalItem() then
            ui.showMessage(l10n('msgJournalRequired'))
            return false
        end
    end

    if journalUI:isOpen() then
        journalUI:open(opts)
        return true
    end

    -- Enter a clean Interface mode with hidden vanilla windows so the player gets a full cursor & pause
    weOwnUiMode = true
    I.UI.setMode('Interface', { windows = {} })
    journalUI:open(opts)
    playSound('book open')
    refreshHudButton()
    return true
end

local function toggleJournal(source)
    if journalUI and journalUI:isOpen() then
        if journalUI:hasTextFocus() then return end
        closeJournal(false)
    else
        openJournal({ source = source or 'hotkey' })
    end
end

journalUI = JournalUI.new {
    store = store,
    settings = settings,
    getContext = getContext,
    onPersist = persistActiveStore,
    onCloseRequest = function()
        closeJournal(false)
    end,
    onPlaySound = playSound,
    onTakeWorldObject = function(worldObj)
        core.sendGlobalEvent('PersonalJournal_TakeWorldObject', {
            player = self,
            worldObject = worldObj,
        })
        playSound('item book up')
        ui.showMessage(l10n('msgPickedUpJournal'))
    end,
}

-- Load initial store (shared mode loads immediately; per-save loads in onLoad)
loadActiveStore()

-- React to settings changes in real time
settings.subscribe(function(sectionKey, key)
    if sectionKey == common.SETTINGS_GENERAL and key == 'storageMode' then
        loadActiveStore()
        if journalUI:isOpen() then
            journalUI:rebuildAll()
        end
    elseif sectionKey == common.SETTINGS_APPEARANCE then
        if journalUI:isOpen() then
            journalUI:rebuildAll()
        end
        refreshHudButton()
    end
end)

-- Register OpenMW custom input trigger handler
input.registerTriggerHandler(common.TRIGGER_TOGGLE, async:callback(function()
    if journalUI:isOpen() then
        if not journalUI:hasTextFocus() and not journalUI.modalState then
            closeJournal(false)
        end
    else
        if I.UI.getMode() == nil then
            openJournal({ source = 'hotkey' })
        end
    end
end))

local function onKeyPress(key)
    if journalUI:isOpen() then
        -- Ctrl+S explicit save works even while typing inside any text field
        if key.withCtrl and key.code == input.KEY.S then
            journalUI:explicitSave()
            return
        end
        -- Ctrl+N creates a new note when no modal is open
        if key.withCtrl and key.code == input.KEY.N and not journalUI.modalState then
            journalUI:createNewNote(false)
            return
        end
        -- Close modal first if one is open and user presses Escape
        if key.code == input.KEY.Escape and journalUI.modalState then
            journalUI:destroyModal()
            return
        end
        -- Quick-key closes journal ONLY when no TextEdit has keyboard focus
        local quickCode = settings.getQuickKeyCode()
        if quickCode and key.code == quickCode and not key.withCtrl and not key.withAlt and not key.withSuper then
            if not journalUI:hasTextFocus() and not journalUI.modalState then
                closeJournal(false)
            end
        end
        return
    end

    -- When closed: only respond in normal gameplay (no menu/console/dialogue active)
    if I.UI.getMode() ~= nil then return end
    local quickCode = settings.getQuickKeyCode()
    if quickCode and key.code == quickCode and not key.withCtrl and not key.withAlt and not key.withSuper then
        openJournal({ source = 'hotkey' })
    end
end

local function onUpdate()
    if not requestedInitialGrant and types.Player.isCharGenFinished(self) then
        requestedInitialGrant = true
        if settings.getGeneral('giveAtStart') ~= false then
            core.sendGlobalEvent(common.EVENTS.REQUEST_GIVE_JOURNAL, {
                player = self,
                silent = false,
            })
        end
    end
end

local function onSave()
    persistActiveStore()
    return {
        journalData = saveDataCache,
        journalRecordId = journalRecordId,
        requestedInitialGrant = requestedInitialGrant,
        windowLocked = journalUI.windowLocked,
    }
end

local function onLoad(data)
    if data then
        saveDataCache = data.journalData
        journalRecordId = data.journalRecordId
        requestedInitialGrant = data.requestedInitialGrant == true
        if data.windowLocked ~= nil then
            journalUI.windowLocked = data.windowLocked == true
        end
    end
    loadActiveStore()
end

local function onJournalGiven(data)
    if not data then return end
    if data.recordId then
        journalRecordId = data.recordId
    end
    if data.silent then return end
    if data.alreadyOwned then
        if data.reclaimed then
            ui.showMessage(l10n('msgJournalAlreadyOwned'))
        end
        return
    end
    if data.reclaimed then
        ui.showMessage(l10n('msgJournalReclaimed'))
    else
        local keyName = settings.getGeneral('quickKey') or 'N'
        ui.showMessage(l10n('msgJournalReceived', { key = keyName }))
    end
end

local function reclaimJournal()
    core.sendGlobalEvent(common.EVENTS.REQUEST_RECLAIM_JOURNAL, {
        player = self,
    })
end

return {
    engineHandlers = {
        onKeyPress = onKeyPress,
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
    },
    eventHandlers = {
        [common.EVENTS.OPEN_JOURNAL] = function(data)
            openJournal(data)
        end,
        [common.EVENTS.JOURNAL_GIVEN] = onJournalGiven,
        UiModeChanged = function(data)
            if not closingSelf and journalUI:isOpen() and data.newMode == nil then
                closeJournal(true)
            end
            refreshHudButton()
        end,
    },
    -- Public Lua interface for other mods or `luap` console commands:
    --   I.PersonalJournal.open()
    --   I.PersonalJournal.reclaimJournal()
    --   I.PersonalJournal.addNote({ title = "...", body = "...", tags = "..." })
    interfaceName = common.MOD_ID,
    interface = {
        version = 1,
        open = function() return openJournal({ source = 'api' }) end,
        close = function() closeJournal(false) end,
        toggle = function() toggleJournal('api') end,
        isOpen = function() return journalUI:isOpen() end,
        reclaimJournal = reclaimJournal,
        getNotebooks = function() return common.deepCopy(store:getNotebooks()) end,
        getNotes = function() return common.deepCopy(store.data.notes) end,
        addNote = function(opts)
            local note = store:createNote(opts, getContext())
            persistActiveStore()
            if journalUI:isOpen() then
                journalUI:refreshSidebar()
                journalUI:refreshNotesList()
                journalUI:refreshEditor()
            end
            return common.deepCopy(note)
        end,
    },
}
