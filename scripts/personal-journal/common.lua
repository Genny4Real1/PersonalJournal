-- Personal Journal for OpenMW
-- Shared constants, themes, templates, and pure utility helpers.

local M = {}

M.MOD_ID = 'PersonalJournal'
M.MOD_VERSION = '1.0.0'
M.SCHEMA_VERSION = 1

M.SETTINGS_PAGE = 'PersonalJournal'
M.SETTINGS_GENERAL = 'SettingsPersonalJournalGeneral'
M.SETTINGS_APPEARANCE = 'SettingsPersonalJournalAppearance'
M.SHARED_STORAGE_KEY = 'PersonalJournal_SharedData'

M.TRIGGER_TOGGLE = 'PersonalJournal_Toggle'

-- Events exchanged between Global and Player scripts
M.EVENTS = {
    OPEN_JOURNAL = 'PersonalJournal_Open',
    JOURNAL_GIVEN = 'PersonalJournal_JournalGiven',
    REQUEST_GIVE_JOURNAL = 'PersonalJournal_RequestGiveJournal',
    REQUEST_RECLAIM_JOURNAL = 'PersonalJournal_RequestReclaimJournal',
    REQUEST_INVENTORY_CHECK = 'PersonalJournal_RequestInventoryCheck',
    INVENTORY_CHECK_RESULT = 'PersonalJournal_InventoryCheckResult',
}

-- Curated vanilla Morrowind leather/bound book records used as template
-- for the dynamically created Personal Journal item (fallback iterates all books).
M.BOOK_TEMPLATE_CANDIDATES = {
    'bk_darkestdarkness',
    'bk_brief_history_empire_1',
    'bk_abcs',
    'bk_charterfg',
    'bk_a_game_at_dinner',
}

M.BOOK_NAME = 'Personal Journal'
M.BOOK_TEXT = '<DIV ALIGN="CENTER"><FONT COLOR="000000" SIZE="3" FACE="Magic Cards"><BR>Personal Journal<BR><BR>Use this journal from your inventory to open your personal notes.<BR></FONT></DIV>'

-- Default starter notebooks (user can freely rename, add, or delete any of them)
M.DEFAULT_NOTEBOOKS = {
    { id = 'nb_journal', name = 'Journal' },
    { id = 'nb_quests', name = 'Quests & Leads' },
    { id = 'nb_tasks', name = 'Tasks & Lists' },
    { id = 'nb_people', name = 'People & Places' },
    { id = 'nb_lore', name = 'Alchemy & Lore' },
}

-- Sort modes for the notes list
M.SORT_MODES = {
    'updated',
    'created',
    'title',
}

M.SORT_LABELS = {
    updated = 'Updated',
    created = 'Created',
    title = 'Title',
}

-- Window size presets (width, height)
M.WINDOW_PRESETS = {
    compact = { w = 780, h = 490, sidebar = 165, list = 205 },
    standard = { w = 960, h = 600, sidebar = 190, list = 240 },
    large = { w = 1140, h = 700, sidebar = 210, list = 275 },
}

-- Quick-key mapping table for out-of-the-box hotkey convenience
M.QUICK_KEY_OPTIONS = {
    'N',
    'K',
    'O',
    'F6',
    'F7',
    'F8',
    'None',
}

-- Roleplay & productivity note templates
M.TEMPLATES = {
    {
        id = 'diary',
        label = 'Diary',
        title = function(ctx)
            if ctx.location and ctx.location ~= '' then
                return string.format('%s - %s', ctx.dateShort, ctx.location)
            end
            return ctx.dateShort
        end,
        tags = 'diary, roleplay',
        body = function(ctx)
            return table.concat({
                string.format('Date: %s', ctx.dateFull),
                string.format('Location: %s', ctx.location ~= '' and ctx.location or 'The Wilds'),
                '----------------------------------------',
                '',
                'Events of the day:',
                '- ',
                '',
                'Thoughts & Reflections:',
                '',
                'Next Steps:',
                '- [ ] ',
            }, '\n')
        end,
    },
    {
        id = 'quest',
        label = 'Quest Lead',
        title = function() return 'New Lead / Investigation' end,
        tags = 'quest, lead',
        body = function(ctx)
            return table.concat({
                string.format('Logged: %s (%s)', ctx.dateShort, ctx.location ~= '' and ctx.location or 'Unknown'),
                'Contact / Patron: ',
                'Destination: ',
                '----------------------------------------',
                '',
                'Clues & Directions:',
                '- ',
                '',
                'Objectives:',
                '- [ ] ',
                '- [ ] ',
                '',
                'Reward / Outcome:',
                '',
            }, '\n')
        end,
    },
    {
        id = 'checklist',
        label = 'Task List',
        title = function() return 'Tasks & Supplies' end,
        tags = 'tasks, todo',
        body = function(ctx)
            return table.concat({
                string.format('Prepared: %s', ctx.dateShort),
                '----------------------------------------',
                '',
                'Priority Tasks:',
                '- [ ] ',
                '- [ ] ',
                '- [ ] ',
                '',
                'Gear & Supplies to Buy:',
                '- [ ] Restore Health / Magicka potions',
                '- [ ] Repair hammers / lockpicks',
                '- [ ] ',
            }, '\n')
        end,
    },
    {
        id = 'npc',
        label = 'NPC Dossier',
        title = function() return 'Person of Interest' end,
        tags = 'people, dossier',
        body = function(ctx)
            return table.concat({
                'Name: ',
                'Faction / Role: ',
                string.format('Where Met: %s (%s)', ctx.location ~= '' and ctx.location or 'Unknown', ctx.dateShort),
                '----------------------------------------',
                '',
                'Services / Training / Trade:',
                '- ',
                '',
                'Notes & Impressions:',
                '',
            }, '\n')
        end,
    },
    {
        id = 'alchemy',
        label = 'Alchemy / Lore',
        title = function() return 'Recipe & Lore Notes' end,
        tags = 'alchemy, lore',
        body = function(ctx)
            return table.concat({
                string.format('Recorded: %s', ctx.dateShort),
                '----------------------------------------',
                '',
                'Effect / Topic: ',
                'Ingredients / Sources:',
                '- ',
                '- ',
                '',
                'Observations:',
                '',
            }, '\n')
        end,
    },
}

-- Color palettes (plain RGB tables {r, g, b, a} in [0..1] so pure Lua tests work without openmw.util)
-- Designed to meet WCAG 2.1 AA/AAA contrast (>= 4.5:1 normal text, >= 7:1 primary reading text).
M.THEMES = {
    dark = {
        name = 'Morrowind Dark',
        windowBg = { 0.07, 0.06, 0.05, 0.97 },
        titleBg = { 0.12, 0.09, 0.06, 1.0 },
        sidebarBg = { 0.09, 0.08, 0.06, 0.98 },
        listBg = { 0.10, 0.09, 0.07, 0.98 },
        editorBg = { 0.06, 0.05, 0.04, 0.98 },
        inputBg = { 0.03, 0.03, 0.02, 1.0 },
        buttonBg = { 0.17, 0.14, 0.09, 1.0 },
        buttonActiveBg = { 0.30, 0.22, 0.12, 1.0 },
        buttonDisabledBg = { 0.11, 0.09, 0.07, 1.0 },
        itemSelectedBg = { 0.25, 0.19, 0.11, 1.0 },
        itemAltBg = { 0.12, 0.10, 0.08, 0.75 },
        text = { 0.92, 0.85, 0.70, 1.0 },
        textHeader = { 0.98, 0.91, 0.74, 1.0 },
        textMuted = { 0.74, 0.67, 0.54, 1.0 },
        textAccent = { 0.97, 0.79, 0.40, 1.0 },
        textDanger = { 0.97, 0.50, 0.45, 1.0 },
        textSuccess = { 0.58, 0.88, 0.56, 1.0 },
        textDisabled = { 0.56, 0.50, 0.40, 1.0 },
        titleText = { 0.98, 0.91, 0.74, 1.0 },
        titleMuted = { 0.80, 0.73, 0.60, 1.0 },
        titleAccent = { 0.98, 0.80, 0.42, 1.0 },
        titleSuccess = { 0.62, 0.90, 0.58, 1.0 },
        buttonActiveText = { 0.99, 0.94, 0.80, 1.0 },
        itemSelectedText = { 0.99, 0.94, 0.80, 1.0 },
        itemSelectedMuted = { 0.85, 0.78, 0.64, 1.0 },
        itemSelectedAccent = { 0.99, 0.82, 0.44, 1.0 },
        divider = { 0.44, 0.35, 0.23, 0.90 },
        selectionStrip = { 0.95, 0.75, 0.35, 1.0 },
    },
    parchment = {
        name = 'Warm Parchment',
        windowBg = { 0.89, 0.83, 0.70, 0.98 },
        titleBg = { 0.24, 0.16, 0.09, 1.0 },
        sidebarBg = { 0.84, 0.77, 0.63, 1.0 },
        listBg = { 0.87, 0.80, 0.67, 1.0 },
        editorBg = { 0.93, 0.88, 0.76, 1.0 },
        inputBg = { 0.97, 0.93, 0.84, 1.0 },
        buttonBg = { 0.79, 0.71, 0.55, 1.0 },
        buttonActiveBg = { 0.33, 0.22, 0.12, 1.0 },
        buttonDisabledBg = { 0.83, 0.76, 0.62, 1.0 },
        itemSelectedBg = { 0.73, 0.63, 0.46, 1.0 },
        itemAltBg = { 0.83, 0.76, 0.62, 0.85 },
        text = { 0.11, 0.07, 0.03, 1.0 },
        textHeader = { 0.07, 0.04, 0.01, 1.0 },
        textMuted = { 0.28, 0.20, 0.11, 1.0 },
        textAccent = { 0.40, 0.16, 0.02, 1.0 },
        textDanger = { 0.52, 0.04, 0.04, 1.0 },
        textSuccess = { 0.06, 0.33, 0.09, 1.0 },
        textDisabled = { 0.37, 0.29, 0.19, 1.0 },
        titleText = { 0.98, 0.93, 0.80, 1.0 },
        titleMuted = { 0.86, 0.78, 0.63, 1.0 },
        titleAccent = { 0.99, 0.82, 0.45, 1.0 },
        titleSuccess = { 0.64, 0.92, 0.60, 1.0 },
        buttonActiveText = { 0.98, 0.93, 0.80, 1.0 },
        itemSelectedText = { 0.06, 0.03, 0.01, 1.0 },
        itemSelectedMuted = { 0.16, 0.10, 0.04, 1.0 },
        itemSelectedAccent = { 0.24, 0.09, 0.01, 1.0 },
        divider = { 0.48, 0.38, 0.24, 0.90 },
        selectionStrip = { 0.33, 0.18, 0.06, 1.0 },
    },
    slate = {
        name = 'Ashlander Slate',
        windowBg = { 0.09, 0.10, 0.12, 0.97 },
        titleBg = { 0.13, 0.15, 0.19, 1.0 },
        sidebarBg = { 0.11, 0.12, 0.15, 0.98 },
        listBg = { 0.12, 0.14, 0.17, 0.98 },
        editorBg = { 0.07, 0.08, 0.10, 0.98 },
        inputBg = { 0.04, 0.05, 0.07, 1.0 },
        buttonBg = { 0.18, 0.21, 0.26, 1.0 },
        buttonActiveBg = { 0.22, 0.33, 0.45, 1.0 },
        buttonDisabledBg = { 0.12, 0.14, 0.17, 1.0 },
        itemSelectedBg = { 0.20, 0.28, 0.38, 1.0 },
        itemAltBg = { 0.14, 0.16, 0.19, 0.75 },
        text = { 0.90, 0.92, 0.95, 1.0 },
        textHeader = { 0.98, 0.99, 1.00, 1.0 },
        textMuted = { 0.68, 0.73, 0.80, 1.0 },
        textAccent = { 0.58, 0.83, 0.99, 1.0 },
        textDanger = { 0.99, 0.52, 0.52, 1.0 },
        textSuccess = { 0.52, 0.89, 0.65, 1.0 },
        textDisabled = { 0.53, 0.58, 0.65, 1.0 },
        titleText = { 0.97, 0.98, 1.00, 1.0 },
        titleMuted = { 0.74, 0.79, 0.86, 1.0 },
        titleAccent = { 0.64, 0.86, 1.00, 1.0 },
        titleSuccess = { 0.56, 0.91, 0.68, 1.0 },
        buttonActiveText = { 0.98, 0.99, 1.00, 1.0 },
        itemSelectedText = { 0.98, 0.99, 1.00, 1.0 },
        itemSelectedMuted = { 0.78, 0.84, 0.91, 1.0 },
        itemSelectedAccent = { 0.70, 0.89, 1.00, 1.0 },
        divider = { 0.32, 0.37, 0.44, 0.90 },
        selectionStrip = { 0.58, 0.83, 0.99, 1.0 },
    },
    highContrast = {
        name = 'High Contrast',
        windowBg = { 0.03, 0.03, 0.03, 0.99 },
        titleBg = { 0.07, 0.07, 0.07, 1.0 },
        sidebarBg = { 0.05, 0.05, 0.05, 1.0 },
        listBg = { 0.06, 0.06, 0.06, 1.0 },
        editorBg = { 0.03, 0.03, 0.03, 1.0 },
        inputBg = { 0.01, 0.01, 0.01, 1.0 },
        buttonBg = { 0.12, 0.12, 0.14, 1.0 },
        buttonActiveBg = { 0.14, 0.28, 0.46, 1.0 },
        buttonDisabledBg = { 0.08, 0.08, 0.09, 1.0 },
        itemSelectedBg = { 0.14, 0.26, 0.42, 1.0 },
        itemAltBg = { 0.09, 0.09, 0.10, 0.95 },
        text = { 0.98, 0.98, 0.98, 1.0 },
        textHeader = { 1.00, 1.00, 1.00, 1.0 },
        textMuted = { 0.80, 0.82, 0.86, 1.0 },
        textAccent = { 1.00, 0.86, 0.30, 1.0 },
        textDanger = { 1.00, 0.54, 0.54, 1.0 },
        textSuccess = { 0.52, 0.95, 0.62, 1.0 },
        textDisabled = { 0.62, 0.64, 0.68, 1.0 },
        titleText = { 1.00, 1.00, 1.00, 1.0 },
        titleMuted = { 0.84, 0.86, 0.90, 1.0 },
        titleAccent = { 1.00, 0.86, 0.30, 1.0 },
        titleSuccess = { 0.55, 0.96, 0.65, 1.0 },
        buttonActiveText = { 1.00, 1.00, 1.00, 1.0 },
        itemSelectedText = { 1.00, 1.00, 1.00, 1.0 },
        itemSelectedMuted = { 0.88, 0.91, 0.96, 1.0 },
        itemSelectedAccent = { 1.00, 0.88, 0.40, 1.0 },
        divider = { 0.45, 0.48, 0.54, 1.0 },
        selectionStrip = { 1.00, 0.86, 0.30, 1.0 },
    },
}

function M.trim(str)
    if type(str) ~= 'string' then return '' end
    return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.truncate(str, maxLen)
    if type(str) ~= 'string' then return '' end
    local singleLine = str:gsub('[\r\n]+', ' ')
    singleLine = M.trim(singleLine)
    if #singleLine <= maxLen then return singleLine end
    if maxLen <= 3 then return singleLine:sub(1, maxLen) end
    return singleLine:sub(1, maxLen - 3) .. '...'
end

function M.parseTags(raw)
    local result = {}
    local seen = {}
    if type(raw) == 'table' then
        for _, t in ipairs(raw) do
            local clean = M.trim(tostring(t)):lower():gsub('^#+', '')
            if clean ~= '' and not seen[clean] then
                seen[clean] = true
                result[#result + 1] = clean
            end
        end
        return result
    end
    if type(raw) ~= 'string' then return result end
    for token in raw:gmatch('[^,;]+') do
        local clean = M.trim(token):lower():gsub('^#+', '')
        if clean ~= '' and not seen[clean] then
            seen[clean] = true
            result[#result + 1] = clean
        end
    end
    return result
end

function M.formatTags(tags)
    if type(tags) ~= 'table' or #tags == 0 then return '' end
    return table.concat(tags, ', ')
end

function M.countStats(text)
    if type(text) ~= 'string' or text == '' then
        return { chars = 0, words = 0, lines = 1 }
    end
    local chars = #text
    local words = 0
    for _ in text:gmatch('%S+') do
        words = words + 1
    end
    local lines = 1
    for _ in text:gmatch('\n') do
        lines = lines + 1
    end
    return { chars = chars, words = words, lines = lines }
end

function M.deepCopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[M.deepCopy(k)] = M.deepCopy(v)
    end
    return copy
end

function M.titleCaseRegion(region)
    if type(region) ~= 'string' or region == '' then return '' end
    return (region:gsub('(%a)([%w_\']*)', function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

return M
