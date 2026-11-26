-- Personal Journal for OpenMW
-- Registers the native OpenMW Settings page, groups, input trigger, and reactive accessors.

local async = require('openmw.async')
local input = require('openmw.input')
local storage = require('openmw.storage')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local common = require('scripts.personal-journal.common')

local M = {}

local generalSection = nil
local appearanceSection = nil
local listeners = {}

local function notifyListeners(sectionKey, key)
    for _, fn in ipairs(listeners) do
        fn(sectionKey, key)
    end
end

function M.init()
    -- Register bindable input trigger for OpenMW's native inputBinding UI
    if not input.triggers[common.TRIGGER_TOGGLE] then
        input.registerTrigger {
            key = common.TRIGGER_TOGGLE,
            l10n = common.MOD_ID,
            name = 'toggleTrigger_name',
            description = 'toggleTrigger_desc',
        }
    end

    I.Settings.registerPage {
        key = common.SETTINGS_PAGE,
        l10n = common.MOD_ID,
        name = 'modName',
        description = 'modDescription',
    }

    I.Settings.registerGroup {
        key = common.SETTINGS_GENERAL,
        page = common.SETTINGS_PAGE,
        l10n = common.MOD_ID,
        name = 'groupGeneralName',
        description = 'groupGeneralDesc',
        order = 0,
        permanentStorage = true,
        settings = {
            {
                key = 'quickKey',
                renderer = 'select',
                name = 'quickKey_name',
                description = 'quickKey_desc',
                default = 'N',
                argument = {
                    l10n = common.MOD_ID,
                    items = common.QUICK_KEY_OPTIONS,
                },
            },
            {
                key = 'toggleBinding',
                renderer = 'inputBinding',
                name = 'toggleTrigger_name',
                description = 'toggleTrigger_desc',
                default = 'PersonalJournal_Toggle_Key',
                argument = {
                    type = 'trigger',
                    key = common.TRIGGER_TOGGLE,
                },
            },
            {
                key = 'giveAtStart',
                renderer = 'checkbox',
                name = 'giveAtStart_name',
                description = 'giveAtStart_desc',
                default = true,
            },
            {
                key = 'requireItem',
                renderer = 'checkbox',
                name = 'requireItem_name',
                description = 'requireItem_desc',
                default = false,
            },
            {
                key = 'storageMode',
                renderer = 'select',
                name = 'storageMode_name',
                description = 'storageMode_desc',
                default = 'perSave',
                argument = {
                    l10n = common.MOD_ID,
                    items = { 'perSave', 'shared' },
                },
            },
            {
                key = 'autoSave',
                renderer = 'checkbox',
                name = 'autoSave_name',
                description = 'autoSave_desc',
                default = true,
            },
            {
                key = 'confirmDelete',
                renderer = 'checkbox',
                name = 'confirmDelete_name',
                description = 'confirmDelete_desc',
                default = true,
            },
            {
                key = 'confirmUndo',
                renderer = 'checkbox',
                name = 'confirmUndo_name',
                description = 'confirmUndo_desc',
                default = false,
            },
            {
                key = 'playSounds',
                renderer = 'checkbox',
                name = 'playSounds_name',
                description = 'playSounds_desc',
                default = true,
            },
        },
    }

    I.Settings.registerGroup {
        key = common.SETTINGS_APPEARANCE,
        page = common.SETTINGS_PAGE,
        l10n = common.MOD_ID,
        name = 'groupAppearanceName',
        description = 'groupAppearanceDesc',
        order = 1,
        permanentStorage = true,
        settings = {
            {
                key = 'theme',
                renderer = 'select',
                name = 'theme_name',
                description = 'theme_desc',
                default = 'dark',
                argument = {
                    l10n = common.MOD_ID,
                    items = { 'dark', 'parchment', 'slate', 'highContrast' },
                },
            },
            {
                key = 'accentColor',
                renderer = 'color',
                name = 'accentColor_name',
                description = 'accentColor_desc',
                default = util.color.hex('4a3520'),
            },
            {
                key = 'windowPreset',
                renderer = 'select',
                name = 'windowPreset_name',
                description = 'windowPreset_desc',
                default = 'standard',
                argument = {
                    l10n = common.MOD_ID,
                    items = { 'compact', 'standard', 'large' },
                },
            },
            {
                key = 'fontSize',
                renderer = 'number',
                name = 'fontSize_name',
                description = 'fontSize_desc',
                default = 16,
                argument = {
                    integer = true,
                    min = 12,
                    max = 26,
                },
            },
            {
                key = 'showHudButton',
                renderer = 'checkbox',
                name = 'showHudButton_name',
                description = 'showHudButton_desc',
                default = false,
            },
        },
    }

    generalSection = storage.playerSection(common.SETTINGS_GENERAL)
    appearanceSection = storage.playerSection(common.SETTINGS_APPEARANCE)

    generalSection:subscribe(async:callback(function(section, key)
        notifyListeners(section, key)
    end))
    appearanceSection:subscribe(async:callback(function(section, key)
        notifyListeners(section, key)
    end))
end

function M.subscribe(fn)
    listeners[#listeners + 1] = fn
end

function M.getGeneral(key)
    if not generalSection then return nil end
    return generalSection:get(key)
end

function M.getAppearance(key)
    if not appearanceSection then return nil end
    return appearanceSection:get(key)
end

function M.setAppearance(key, value)
    if not appearanceSection then return end
    appearanceSection:set(key, value)
end

function M.getQuickKeyCode()
    local keyName = M.getGeneral('quickKey') or 'N'
    if keyName == 'None' then return nil end
    return input.KEY[keyName]
end

return M
