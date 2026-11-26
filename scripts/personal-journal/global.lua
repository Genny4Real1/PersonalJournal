-- Personal Journal for OpenMW
-- Global script: creates the physical Personal Journal book record, grants it at the
-- start of the player's journey, and intercepts inventory use & world activation.

local types = require('openmw.types')
local world = require('openmw.world')
local I = require('openmw.interfaces')

local common = require('scripts.personal-journal.common')

local journalRecordId = nil
local journalGranted = false

local function findTemplateBook()
    for _, candidateId in ipairs(common.BOOK_TEMPLATE_CANDIDATES) do
        local rec = types.Book.records[candidateId]
        if rec and not rec.isScroll and rec.model and rec.model ~= '' and rec.icon and rec.icon ~= '' then
            return rec
        end
    end
    for _, rec in ipairs(types.Book.records) do
        if not rec.isScroll and rec.model and rec.model ~= '' and rec.icon and rec.icon ~= '' then
            return rec
        end
    end
    return nil
end

local function ensureJournalRecord()
    if journalRecordId and types.Book.records[journalRecordId] then
        return journalRecordId
    end

    local template = findTemplateBook()
    local draftTable = {
        name = common.BOOK_NAME,
        text = common.BOOK_TEXT,
        weight = 0,
        value = 0,
        isScroll = false,
        enchantCapacity = 0,
        model = template and template.model or 'meshes\\m\\text_book_01.nif',
        icon = template and template.icon or 'icons\\m\\tx_book_01.tga',
    }
    if template then
        draftTable.template = template
    end

    local ok, draftOrErr = pcall(types.Book.createRecordDraft, draftTable)
    if not ok then
        print('[PersonalJournal] Failed to create book record draft: ' .. tostring(draftOrErr))
        return nil
    end

    local okRec, newRecord = pcall(world.createRecord, draftOrErr)
    if not okRec or not newRecord then
        print('[PersonalJournal] Failed to register book record: ' .. tostring(newRecord))
        return nil
    end

    journalRecordId = newRecord.id
    return journalRecordId
end

local function syncRecordIdToPlayer(player)
    if not player or not player:isValid() then return end
    local recId = ensureJournalRecord()
    if recId then
        player:sendEvent(common.EVENTS.JOURNAL_GIVEN, {
            recordId = recId,
            alreadyGranted = journalGranted,
            silent = true,
        })
    end
end

local function giveJournalToPlayer(player, opts)
    opts = opts or {}
    if not player or not player:isValid() then return false end
    local recId = ensureJournalRecord()
    if not recId then return false end

    local inv = types.Actor.inventory(player)
    local count = inv:countOf(recId)
    if count > 0 then
        journalGranted = true
        player:sendEvent(common.EVENTS.JOURNAL_GIVEN, {
            recordId = recId,
            alreadyOwned = true,
            reclaimed = opts.reclaim == true,
            silent = opts.silent == true,
        })
        return false
    end

    local item = world.createObject(recId, 1)
    item:moveInto(inv)
    journalGranted = true

    player:sendEvent(common.EVENTS.JOURNAL_GIVEN, {
        recordId = recId,
        alreadyOwned = false,
        reclaimed = opts.reclaim == true,
        silent = opts.silent == true,
    })
    return true
end

local function isJournalBook(obj)
    if not obj or not journalRecordId then return false end
    return obj.recordId == journalRecordId
end

-- Intercept using the Personal Journal from inventory
I.ItemUsage.addHandlerForType(types.Book, function(book, actor)
    if not isJournalBook(book) then return end
    if actor and actor.type == types.Player then
        actor:sendEvent(common.EVENTS.OPEN_JOURNAL, {
            source = 'inventory',
            recordId = journalRecordId,
        })
        return false -- suppress vanilla static book UI
    end
end)

-- Intercept activating a Personal Journal placed in the game world (e.g. on a desk)
I.Activation.addHandlerForType(types.Book, function(book, actor)
    if not isJournalBook(book) then return end
    if actor and actor.type == types.Player then
        actor:sendEvent(common.EVENTS.OPEN_JOURNAL, {
            source = 'world',
            recordId = journalRecordId,
            worldObject = book,
        })
        return false -- suppress vanilla static book UI
    end
end)

local function takeWorldJournal(data)
    if not data or not data.player or not data.worldObject then return end
    local player = data.player
    local obj = data.worldObject
    if not player:isValid() or not obj:isValid() then return end
    if not isJournalBook(obj) then return end
    if obj.parentContainer then return end
    obj:moveInto(types.Actor.inventory(player))
end

return {
    engineHandlers = {
        onSave = function()
            return {
                journalRecordId = journalRecordId,
                journalGranted = journalGranted,
            }
        end,
        onLoad = function(data)
            if data then
                journalRecordId = data.journalRecordId
                journalGranted = data.journalGranted == true
            end
            ensureJournalRecord()
        end,
        onPlayerAdded = function(player)
            syncRecordIdToPlayer(player)
        end,
    },
    eventHandlers = {
        [common.EVENTS.REQUEST_GIVE_JOURNAL] = function(data)
            local player = data and data.player or world.players[1]
            if not player then return end
            if journalGranted and not (data and data.force) then
                syncRecordIdToPlayer(player)
                return
            end
            giveJournalToPlayer(player, {
                reclaim = false,
                silent = data and data.silent,
            })
        end,
        [common.EVENTS.REQUEST_RECLAIM_JOURNAL] = function(data)
            local player = data and data.player or world.players[1]
            if not player then return end
            giveJournalToPlayer(player, {
                reclaim = true,
                silent = false,
            })
        end,
        PersonalJournal_TakeWorldObject = takeWorldJournal,
    },
}
