-- Personal Journal for OpenMW
-- Reusable theme-aware OpenMW MWUI widget builders.

local async = require('openmw.async')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local common = require('scripts.personal-journal.common')

local v2 = util.vector2
local whiteTex = ui.texture { path = 'white' }

local W = {}

local function linearizeChannel(c)
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function relativeLuminance(r, g, b)
    return 0.2126 * linearizeChannel(r)
         + 0.7152 * linearizeChannel(g)
         + 0.0722 * linearizeChannel(b)
end

local function contrastRatioRgb(r1, g1, b1, r2, g2, b2)
    local l1 = relativeLuminance(r1, g1, b1)
    local l2 = relativeLuminance(r2, g2, b2)
    if l1 < l2 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

local function ensureContrastColor(bg, preferred, minRatio)
    local ratio = contrastRatioRgb(bg.r, bg.g, bg.b, preferred.r, preferred.g, preferred.b)
    if ratio >= minRatio then
        return preferred
    end
    local light = util.color.rgba(0.98, 0.96, 0.90, 1.0)
    local dark = util.color.rgba(0.06, 0.04, 0.02, 1.0)
    local lightRatio = contrastRatioRgb(bg.r, bg.g, bg.b, light.r, light.g, light.b)
    local darkRatio = contrastRatioRgb(bg.r, bg.g, bg.b, dark.r, dark.g, dark.b)
    return (lightRatio >= darkRatio) and light or dark
end

function W.colorFromTable(t, fallbackAlpha)
    if not t then return util.color.rgba(1, 1, 1, fallbackAlpha or 1) end
    return util.color.rgba(t[1] or 1, t[2] or 1, t[3] or 1, t[4] or fallbackAlpha or 1)
end

function W.resolveTheme(themeKey, accentColor)
    local raw = common.THEMES[themeKey] or common.THEMES.dark
    local palette = {}
    for k, v in pairs(raw) do
        if type(v) == 'table' then
            palette[k] = W.colorFromTable(v)
        else
            palette[k] = v
        end
    end
    if accentColor then
        -- Blend custom cover tint subtly into title/active bars while guaranteeing WCAG contrast
        local baseTitle = raw.titleBg
        local baseActive = raw.buttonActiveBg
        local ar, ag, ab = accentColor.r, accentColor.g, accentColor.b
        palette.titleBg = util.color.rgba(
            baseTitle[1] * 0.65 + ar * 0.35,
            baseTitle[2] * 0.65 + ag * 0.35,
            baseTitle[3] * 0.65 + ab * 0.35,
            1.0
        )
        palette.buttonActiveBg = util.color.rgba(
            baseActive[1] * 0.65 + ar * 0.35,
            baseActive[2] * 0.65 + ag * 0.35,
            baseActive[3] * 0.65 + ab * 0.35,
            1.0
        )
        palette.titleText = ensureContrastColor(palette.titleBg, palette.titleText, 7.0)
        palette.titleMuted = ensureContrastColor(palette.titleBg, palette.titleMuted, 4.5)
        palette.titleAccent = ensureContrastColor(palette.titleBg, palette.titleAccent, 4.5)
        palette.titleSuccess = ensureContrastColor(palette.titleBg, palette.titleSuccess, 4.5)
        palette.buttonActiveText = ensureContrastColor(palette.buttonActiveBg, palette.buttonActiveText, 7.0)
    end
    return palette
end

function W.solidRect(color, size, alpha)
    return {
        type = ui.TYPE.Image,
        props = {
            resource = whiteTex,
            color = color,
            alpha = alpha or (color and color.a) or 1,
            size = size or v2(0, 0),
            relativeSize = size and nil or v2(1, 1),
        },
    }
end

function W.hDivider(palette, width)
    return {
        type = ui.TYPE.Image,
        props = {
            resource = whiteTex,
            color = palette.divider,
            size = v2(width or 0, 1),
            relativeSize = width and nil or v2(1, 0),
        },
    }
end

function W.vDivider(palette, height)
    return {
        type = ui.TYPE.Image,
        props = {
            resource = whiteTex,
            color = palette.divider,
            size = v2(1, height or 0),
            relativeSize = height and nil or v2(0, 1),
        },
    }
end

function W.spacer(w, h)
    return {
        type = ui.TYPE.Widget,
        props = {
            size = v2(w or 0, h or 0),
        },
    }
end

function W.label(text, color, textSize, opts)
    opts = opts or {}
    local props = {
        text = tostring(text or ''),
        textColor = color,
        textSize = textSize or 14,
    }
    if opts.size then props.size = opts.size end
    if opts.autoSize ~= nil then props.autoSize = opts.autoSize end
    if opts.wordWrap ~= nil then props.wordWrap = opts.wordWrap end
    if opts.multiline ~= nil then props.multiline = opts.multiline end
    if opts.textAlignH then props.textAlignH = opts.textAlignH end
    if opts.textAlignV then props.textAlignV = opts.textAlignV end
    return {
        type = ui.TYPE.Text,
        props = props,
    }
end

function W.button(opts)
    local palette = opts.palette
    local disabled = opts.disabled == true
    local bg
    local fg
    if disabled then
        bg = opts.bg or palette.buttonDisabledBg or palette.buttonBg
        fg = palette.textDisabled or palette.textMuted
    else
        bg = opts.bg or (opts.active and palette.buttonActiveBg or palette.buttonBg)
        fg = opts.fg or (opts.danger and palette.textDanger or (opts.active and (palette.buttonActiveText or palette.textHeader) or palette.text))
    end
    local textSize = opts.textSize or 13
    local padX = opts.padX or 6
    local padY = opts.padY or 3
    local labelStr = tostring(opts.label or '')
    -- Enforce minimum 24x24px interactive target size per accessibility guidelines
    local h = math.max(24, opts.height or (textSize + padY * 2 + 4))
    local w = math.max(24, opts.width or (math.ceil(#labelStr * textSize * 0.56) + padX * 2 + 6))
    local alignH = opts.alignH or ui.ALIGNMENT.Center
    local innerPadX = opts.selectedIndicator and 9 or (opts.borderless and 6 or 4)

    local labelNode = {
        type = ui.TYPE.Text,
        props = {
            text = labelStr,
            textColor = fg,
            textSize = textSize,
            autoSize = false,
            size = v2(math.max(10, w - innerPadX * 2 - 2), math.max(10, h - 4)),
            textAlignH = alignH,
            textAlignV = ui.ALIGNMENT.Center,
        },
    }

    local events = nil
    if opts.onClick and not disabled then
        events = {
            mouseClick = async:callback(function()
                opts.onClick()
            end),
        }
    end

    local contentNodes = {
        W.solidRect(bg),
    }
    if opts.selectedIndicator and palette.selectionStrip then
        contentNodes[#contentNodes + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = whiteTex,
                color = palette.selectionStrip,
                size = v2(3, h),
            },
        }
    end
    contentNodes[#contentNodes + 1] = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            align = alignH,
            arrange = ui.ALIGNMENT.Center,
            position = v2(innerPadX, 0),
            size = v2(math.max(10, w - innerPadX - (opts.borderless and 6 or 4)), h - (opts.borderless and 0 or 4)),
        },
        content = ui.content { labelNode },
    }

    return {
        template = opts.borderless and nil or I.MWUI.templates.borders,
        type = ui.TYPE.Widget,
        props = {
            size = v2(w, h),
        },
        events = events,
        content = ui.content(contentNodes),
    }
end

function W.textField(opts)
    local palette = opts.palette
    local width = opts.width or 180
    local height = opts.height or 26
    local textSize = opts.textSize or 14
    local multiline = opts.multiline == true
    local pad = opts.pad or 4

    local events = {}
    if opts.onChange then
        events.textChanged = async:callback(function(text)
            opts.onChange(text)
        end)
    end
    if opts.onFocusGain then
        events.focusGain = async:callback(function()
            opts.onFocusGain()
        end)
    end
    if opts.onFocusLoss then
        events.focusLoss = async:callback(function()
            opts.onFocusLoss()
        end)
    end

    return {
        template = I.MWUI.templates.borders,
        type = ui.TYPE.Widget,
        props = {
            size = v2(width, height),
        },
        content = ui.content {
            W.solidRect(opts.bg or palette.inputBg),
            {
                type = ui.TYPE.TextEdit,
                name = opts.name,
                props = {
                    position = v2(pad, pad),
                    size = v2(math.max(16, width - pad * 2 - 4), math.max(16, height - pad * 2 - 4)),
                    text = tostring(opts.text or ''),
                    textSize = textSize,
                    textColor = opts.fg or palette.text,
                    multiline = multiline,
                    wordWrap = multiline,
                    autoSize = false,
                },
                events = events,
            },
        },
    }
end

function W.panelBox(color, width, height, children)
    return {
        type = ui.TYPE.Widget,
        props = {
            size = v2(width, height),
        },
        content = ui.content {
            W.solidRect(color),
            {
                type = ui.TYPE.Widget,
                props = {
                    relativeSize = v2(1, 1),
                },
                content = ui.content(children),
            },
        },
    }
end

return W
