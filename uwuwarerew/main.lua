local library = {
    flags = {},
    windows = {},
    options = {},          -- [flag] = option (for configs)
    open = true,
    activePopup = nil,
    popupGeneration = 0,
    _accentObjects = {},   -- static accent-colored instances for SetAccent
}

--Services
local runService   = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local textService  = game:GetService("TextService")
local inputService = game:GetService("UserInputService")
local httpService  = game:GetService("HttpService")

--Theme
library.theme = {
    accent       = Color3.fromRGB(255, 65, 65),
    window       = Color3.fromRGB(20, 20, 20),
    header       = Color3.fromRGB(10, 10, 10),
    folderHeader = Color3.fromRGB(14, 14, 14),
    control      = Color3.fromRGB(35, 35, 35),
    controlHover = Color3.fromRGB(55, 55, 55),
    popup        = Color3.fromRGB(28, 28, 28),
    rowHover     = Color3.fromRGB(40, 40, 40),
    dark         = Color3.fromRGB(20, 20, 20),
    border       = Color3.fromRGB(45, 45, 45),
    text         = Color3.fromRGB(255, 255, 255),
    subtext      = Color3.fromRGB(150, 150, 150),
    disabled     = Color3.fromRGB(100, 100, 100),
    font         = Enum.Font.Gotham,
    fontBold     = Enum.Font.GothamBold,
}
local theme = library.theme

local WINDOW_WIDTH  = 230
local HEADER_SIZE   = 38
local FOLDER_HEADER = 30

--Drag state
local dragging, dragInput, dragStart, startPos, dragObject

local blacklistedKeys = {
    Enum.KeyCode.Unknown, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
    Enum.KeyCode.Slash, Enum.KeyCode.Tab, Enum.KeyCode.Backspace, Enum.KeyCode.Escape,
}
local whitelistedMouseinputs = {
    Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3,
}

--=====================================================================
-- Helpers
--=====================================================================
function library:Create(class, properties)
    properties = typeof(properties) == "table" and properties or {}
    local inst = Instance.new(class)
    for property, value in properties do
        if property ~= "Parent" then
            inst[property] = value
        end
    end
    if properties.Parent then
        inst.Parent = properties.Parent
    end
    return inst
end

function library:Draw(class, properties)
    properties = type(properties) == "table" and properties or {}
    local object = Drawing.new(class)
    for p, v in properties do
        object[p] = v
    end
    return object
end

local function tween(object, time, properties, style)
    local t = tweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
    t:Play()
    return t
end

local function addCorner(object, radius)
    return library:Create("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = object })
end

local function addStroke(object, color, thickness)
    return library:Create("UIStroke", { Color = color or theme.border, Thickness = thickness or 1, Parent = object })
end

local function keyCheck(x, list)
    for _, v in list do
        if v == x then
            return true
        end
    end
end

local function snap(value, step)
    return math.round(value / step) * step
end

local function decimalsOf(step)
    local fraction = tostring(step):match("%.(%d+)")
    return fraction and #fraction or 0
end

local function formatNumber(value, step)
    local places = decimalsOf(step)
    if places == 0 then
        return tostring(math.round(value))
    end
    return string.format("%." .. places .. "f", value)
end

local function within(point, position, size)
    return point.X >= position.X and point.X <= position.X + size.X
       and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

--Chroma (frame-rate independent)
local chromaColor = Color3.fromRGB(255, 0, 0)
local chromaHue = 0
runService.RenderStepped:Connect(function(dt)
    chromaHue = (chromaHue + dt / 5) % 1
    chromaColor = Color3.fromHSV(chromaHue, 1, 1)
end)

--Popup helpers -------------------------------------------------------
local function closeActivePopup()
    if library.activePopup then
        library.activePopup:Close()
    end
end

-- positions a popup next to its anchor, clamped to the screen; opens
-- upward when there is not enough room below
local function positionPopup(holder, anchor, height)
    local base = library.base
    local anchorPos = anchor.AbsolutePosition
    local anchorSize = anchor.AbsoluteSize
    local screen = base.AbsoluteSize
    local width = holder.AbsoluteSize.X

    local x = math.clamp(anchorPos.X, 6, math.max(screen.X - width - 6, 6))
    local y = anchorPos.Y + anchorSize.Y + 4
    if y + height > screen.Y - 6 then
        y = math.max(anchorPos.Y - height - 4, 6)
    end
    holder.Position = UDim2.new(0, x, 0, y)
end

-- shared open/close animation for CanvasGroup popups; returns true when
-- the popup ended up open
local function openPopup(option, holder, anchor, height)
    if library.activePopup == option then
        option:Close()
        return false
    end
    closeActivePopup()
    library.popupGeneration += 1
    option.open = true
    library.activePopup = option
    holder.Size = UDim2.new(0, holder.Size.X.Offset, 0, height)
    positionPopup(holder, anchor, height)
    holder.Visible = true
    holder.GroupTransparency = 1
    tween(holder, 0.15, { GroupTransparency = 0 })
    return true
end

local function closePopup(option, holder)
    library.popupGeneration += 1
    local generation = library.popupGeneration
    option.open = false
    if library.activePopup == option then
        library.activePopup = nil
    end
    tween(holder, 0.15, { GroupTransparency = 1 })
    task.delay(0.16, function()
        if library.popupGeneration == generation and not option.open then
            holder.Visible = false
        end
    end)
end

--=====================================================================
-- Holders (windows + folders)
--=====================================================================
local function createOptionHolder(holderTitle, parent, parentTable, subHolder)
    local size = subHolder and FOLDER_HEADER or HEADER_SIZE

    parentTable.main = library:Create("Frame", {
        LayoutOrder = subHolder and parentTable.position or 0,
        Position = UDim2.new(0, 20 + (WINDOW_WIDTH + 20) * (parentTable.position or 0), 0, 20),
        Size = UDim2.new(0, WINDOW_WIDTH, 0, size),
        BackgroundColor3 = theme.window,
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
        Parent = parent,
    })
    addCorner(parentTable.main, 6)
    if not subHolder then
        addStroke(parentTable.main, theme.border)
    end

    local title = library:Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size),
        BackgroundColor3 = subHolder and theme.folderHeader or theme.header,
        BorderSizePixel = 0,
        Text = holderTitle,
        TextSize = subHolder and 15 or 17,
        Font = theme.fontBold,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parentTable.main,
    })
    addCorner(title, 6)
    library:Create("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = title })
    -- square off the bottom of the rounded header so it meets the content
    library:Create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, -12, 1, 0),
        Size = UDim2.new(1, 12, 0, 6),
        BackgroundColor3 = subHolder and theme.folderHeader or theme.header,
        BorderSizePixel = 0,
        Parent = title,
    })

    if not subHolder then
        -- thin accent strip under the window header
        local accentLine = library:Create("Frame", {
            ZIndex = 2,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, -12, 1, 0),
            Size = UDim2.new(1, 12, 0, 2),
            BackgroundColor3 = theme.accent,
            BorderSizePixel = 0,
            Parent = title,
        })
        table.insert(library._accentObjects, accentLine)
    end

    local arrow = library:Create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, size - 18, 0, size - 18),
        Rotation = parentTable.open and 90 or 180,
        BackgroundTransparency = 1,
        Image = "rbxassetid://4918373417",
        ImageColor3 = parentTable.open and theme.subtext or theme.disabled,
        ScaleType = Enum.ScaleType.Fit,
        Parent = title,
    })

    parentTable.content = library:Create("Frame", {
        Position = UDim2.new(0, 0, 0, size),
        Size = UDim2.new(1, 0, 1, -size),
        BackgroundTransparency = 1,
        Parent = parentTable.main,
    })

    local layout = library:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parentTable.content,
    })
    library:Create("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 4),
        Parent = parentTable.content,
    })

    local function targetSize()
        if #parentTable.options > 0 and parentTable.open then
            return UDim2.new(0, WINDOW_WIDTH, 0, layout.AbsoluteContentSize.Y + size + 6)
        end
        return UDim2.new(0, WINDOW_WIDTH, 0, size)
    end

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        parentTable.content.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
        parentTable.main.Size = targetSize()
    end)

    if not subHolder then
        -- window dragging (direct positioning, clamped to screen)
        title.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                closeActivePopup()
                dragObject = parentTable.main
                dragging = true
                dragStart = input.Position
                startPos = dragObject.Position
            end
        end)
        title.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = input
            end
        end)
        title.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
    end

    local function setOpen(open)
        parentTable.open = open
        closeActivePopup()
        tween(arrow, 0.2, { Rotation = open and 90 or 180, ImageColor3 = open and theme.subtext or theme.disabled })
        tween(parentTable.main, 0.2, { Size = targetSize() })
    end

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and (subHolder or input.Position.X > title.AbsolutePosition.X + title.AbsoluteSize.X - size) then
            setOpen(not parentTable.open)
        end
    end)

    function parentTable:SetTitle(newTitle)
        title.Text = tostring(newTitle)
    end

    function parentTable:SetOpen(open)
        if parentTable.open ~= open then
            setOpen(open)
        end
    end

    return parentTable
end

--=====================================================================
-- Controls
--=====================================================================
local function createLabel(option, parent)
    local main = library:Create("TextLabel", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = " " .. option.text,
        TextSize = 15,
        Font = theme.fontBold,
        TextColor3 = theme.subtext,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent.content,
    })
    library:Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = main })

    function option:SetText(text)
        main.Text = " " .. tostring(text)
    end

    setmetatable(option, { __newindex = function(_, i, v)
        if i == "Text" then
            main.Text = " " .. tostring(v)
        end
    end })
end

local function createDivider(option, parent)
    local main = library:Create("Frame", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundTransparency = 1,
        Parent = parent.content,
    })
    library:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -16, 0, 1),
        BackgroundColor3 = theme.border,
        BorderSizePixel = 0,
        Parent = main,
    })
end

local function createToggle(option, parent)
    local main = library:Create("TextLabel", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 31),
        BackgroundTransparency = 1,
        Text = "  " .. option.text,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent.content,
    })

    local tickbox = library:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0, 19, 0, 19),
        BackgroundColor3 = theme.dark,
        BorderSizePixel = 0,
        Parent = main,
    })
    addCorner(tickbox, 4)
    local outline = addStroke(tickbox, option.state and theme.accent or theme.disabled)

    local fill = library:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = option.state and UDim2.new(1, -4, 1, -4) or UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        Parent = tickbox,
    })
    addCorner(fill, 3)

    local checkmark = library:Create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -4, 1, -4),
        BackgroundTransparency = 1,
        Image = "rbxassetid://4919148038",
        ImageColor3 = theme.dark,
        ImageTransparency = option.state and 0 or 1,
        Parent = tickbox,
    })

    local inContact = false
    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            option:SetState(not option.state)
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = true
            if not option.state then
                tween(outline, 0.1, { Color = theme.controlHover })
            end
        end
    end)
    main.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = false
            if not option.state then
                tween(outline, 0.1, { Color = theme.disabled })
            end
        end
    end)

    function option:SetState(state, silent)
        state = state and true or false
        library.flags[self.flag] = state
        self.state = state
        tween(fill, 0.15, { Size = state and UDim2.new(1, -4, 1, -4) or UDim2.new(0, 0, 0, 0) })
        tween(checkmark, 0.15, { ImageTransparency = state and 0 or 1 })
        tween(outline, 0.15, { Color = state and theme.accent or (inContact and theme.controlHover or theme.disabled) })
        if not silent then
            self.callback(state)
        end
    end

    function option:_refreshAccent()
        fill.BackgroundColor3 = theme.accent
        if option.state then
            outline.Color = theme.accent
        end
    end

    if option.state then
        task.defer(function() option.callback(true) end)
    end

    function option:SetText(text)
        main.Text = "  " .. tostring(text)
    end

    setmetatable(option, { __newindex = function(_, i, v)
        if i == "Text" then
            main.Text = "  " .. tostring(v)
        end
    end })
end

local function createButton(option, parent)
    local main = library:Create("Frame", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        Parent = parent.content,
    })

    local button = library:Create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -16, 1, -8),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = option.text,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        Parent = main,
    })
    addCorner(button, 4)

    local inContact = false
    local clicking = false
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            library.flags[option.flag] = true
            clicking = true
            tween(button, 0.1, { BackgroundColor3 = theme.accent })
            option.callback()
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = true
            if not clicking then
                tween(button, 0.1, { BackgroundColor3 = theme.controlHover })
            end
        end
    end)
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            clicking = false
            tween(button, 0.2, { BackgroundColor3 = inContact and theme.controlHover or theme.control })
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = false
            if not clicking then
                tween(button, 0.1, { BackgroundColor3 = theme.control })
            end
        end
    end)
end

local function createBind(option, parent)
    local binding = false
    local holdLoop

    local function displayName(key)
        if key == "None" then return "None" end
        if string.match(key, "Mouse") then
            return string.sub(key, 1, 5) .. string.sub(key, 12, 13)
        end
        return key
    end

    local main = library:Create("TextLabel", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 33),
        BackgroundTransparency = 1,
        Text = "  " .. option.text,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent.content,
    })

    local tag = library:Create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0, 40, 1, -10),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = displayName(option.key),
        TextSize = 15,
        Font = theme.font,
        TextColor3 = theme.text,
        Parent = main,
    })
    addCorner(tag, 4)

    local function resizeTag()
        tag.Size = UDim2.new(0, textService:GetTextSize(tag.Text, 15, theme.font, Vector2.new(9e9, 9e9)).X + 16, 1, -10)
    end
    resizeTag()

    local inContact = false
    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = true
            if not binding then
                tween(tag, 0.1, { BackgroundColor3 = theme.controlHover })
            end
        end
    end)
    main.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            binding = true
            tag.Text = "..."
            resizeTag()
            tween(tag, 0.2, { BackgroundColor3 = theme.accent })
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = false
            if not binding then
                tween(tag, 0.1, { BackgroundColor3 = theme.control })
            end
        end
    end)

    inputService.InputBegan:Connect(function(input)
        if inputService:GetFocusedTextBox() then return end
        if binding then
            -- Escape cancels, Backspace/Delete clears the bind
            if input.KeyCode == Enum.KeyCode.Escape then
                option:SetKey(option.key)
                return
            end
            if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                option:SetKey("None")
                return
            end
            local key
            if input.UserInputType == Enum.UserInputType.Keyboard and not keyCheck(input.KeyCode, blacklistedKeys) then
                key = input.KeyCode
            elseif keyCheck(input.UserInputType, whitelistedMouseinputs) then
                key = input.UserInputType
            end
            option:SetKey(key or option.key)
        elseif option.key ~= "None" and (input.KeyCode.Name == option.key or input.UserInputType.Name == option.key) then
            if option.hold then
                if holdLoop then holdLoop:Disconnect() end
                holdLoop = runService.Heartbeat:Connect(function()
                    option.callback()
                end)
            else
                option.callback()
            end
        end
    end)

    inputService.InputEnded:Connect(function(input)
        if option.key ~= "None" and (input.KeyCode.Name == option.key or input.UserInputType.Name == option.key) then
            if holdLoop then
                holdLoop:Disconnect()
                holdLoop = nil
                option.callback(true)
            end
        end
    end)

    function option:SetKey(key)
        binding = false
        if holdLoop then
            holdLoop:Disconnect()
            holdLoop = nil
        end
        self.key = key or self.key
        self.key = typeof(self.key) == "EnumItem" and self.key.Name or self.key
        library.flags[self.flag] = self.key
        tag.Text = displayName(self.key)
        resizeTag()
        tween(tag, 0.2, { BackgroundColor3 = inContact and theme.controlHover or theme.control })
    end
end

local function createSlider(option, parent)
    local step = (typeof(option.float) == "number" and option.float > 0) and option.float or 1

    local main = library:Create("Frame", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        Parent = parent.content,
    })

    library:Create("TextLabel", {
        Position = UDim2.new(0, 0, 0, 4),
        Size = UDim2.new(1, -70, 0, 20),
        BackgroundTransparency = 1,
        Text = "  " .. option.text,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = main,
    })

    local valueBox = library:Create("TextBox", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 5),
        Size = UDim2.new(0, 54, 0, 18),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = formatNumber(option.value, step),
        TextSize = 14,
        Font = theme.font,
        TextColor3 = theme.text,
        ClearTextOnFocus = false,
        Parent = main,
    })
    addCorner(valueBox, 4)

    local track = library:Create("Frame", {
        Position = UDim2.new(0, 10, 0, 34),
        Size = UDim2.new(1, -20, 0, 5),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Parent = main,
    })
    addCorner(track, 2)

    local fill = library:Create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    addCorner(fill, 2)

    local knob = library:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = theme.text,
        BorderSizePixel = 0,
        Parent = track,
    })
    addCorner(knob, 8)

    local function alpha(value)
        return (value - option.min) / (option.max - option.min)
    end

    local sliding = false
    local inContact = false

    local function refresh(animated)
        local a = alpha(option.value)
        if animated then
            tween(fill, 0.1, { Size = UDim2.new(a, 0, 1, 0) })
            tween(knob, 0.1, { Position = UDim2.new(a, 0, 0.5, 0) })
        else
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
        end
    end
    refresh(false)

    local function valueFromInput(input)
        local a = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        return option.min + a * (option.max - option.min)
    end

    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.Y > main.AbsolutePosition.Y + 24 then
            sliding = true
            tween(knob, 0.1, { Size = UDim2.new(0, 11, 0, 11) })
            option:SetValue(valueFromInput(input))
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = true
            tween(knob, 0.1, { Size = UDim2.new(0, 9, 0, 9) })
        end
    end)
    main.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = false
            if not sliding then
                tween(knob, 0.1, { Size = UDim2.new(0, 0, 0, 0) })
            end
        end
    end)

    inputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            option:SetValue(valueFromInput(input))
        end
    end)
    -- release anywhere on screen ends the drag (the original got stuck when
    -- the mouse was released outside the control)
    inputService.InputEnded:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
            if not inContact then
                tween(knob, 0.1, { Size = UDim2.new(0, 0, 0, 0) })
            end
        end
    end)

    valueBox.FocusLost:Connect(function()
        local typed = tonumber(valueBox.Text)
        if typed then
            option:SetValue(typed)
        else
            valueBox.Text = formatNumber(option.value, step)
        end
    end)

    function option:SetValue(value)
        value = math.clamp(snap(value, step), self.min, self.max)
        self.value = value
        library.flags[self.flag] = value
        valueBox.Text = formatNumber(value, step)
        refresh(true)
        self.callback(value)
    end

    function option:_refreshAccent()
        fill.BackgroundColor3 = theme.accent
    end
end

local function createList(option, parent)
    local ROW_HEIGHT = 32
    local MAX_VISIBLE = 6

    local main = library:Create("Frame", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent = parent.content,
    })

    local control = library:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -16, 1, -8),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Parent = main,
    })
    addCorner(control, 4)

    library:Create("TextLabel", {
        Position = UDim2.new(0, 8, 0, 4),
        Size = UDim2.new(1, -30, 0, 14),
        BackgroundTransparency = 1,
        Text = string.upper(option.text),
        TextSize = 12,
        Font = theme.fontBold,
        TextColor3 = theme.subtext,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = control,
    })

    local listvalue = library:Create("TextLabel", {
        Position = UDim2.new(0, 8, 0, 18),
        Size = UDim2.new(1, -30, 0, 22),
        BackgroundTransparency = 1,
        Text = option.value,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = control,
    })

    local arrow = library:Create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 14),
        Rotation = 90,
        BackgroundTransparency = 1,
        Image = "rbxassetid://4918373417",
        ImageColor3 = theme.subtext,
        ScaleType = Enum.ScaleType.Fit,
        Parent = control,
    })

    -- popup ------------------------------------------------------------
    local holder = library:Create("CanvasGroup", {
        ZIndex = 5,
        Size = UDim2.new(0, WINDOW_WIDTH, 0, 0),
        BackgroundColor3 = theme.popup,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        Parent = library.base,
    })
    addCorner(holder, 4)
    addStroke(holder, theme.border)
    option.popupHolder = holder
    option.anchor = control

    local scroll = library:Create("ScrollingFrame", {
        ZIndex = 5,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = theme.controlHover,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = holder,
    })
    library:Create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = scroll,
    })
    local layout = library:Create("UIListLayout", {
        Padding = UDim.new(0, 2),
        Parent = scroll,
    })
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)

    local rows = {}   -- [value] = row label

    local function popupHeight()
        local count = 0
        for _ in rows do count += 1 end
        return math.min(count, MAX_VISIBLE) * (ROW_HEIGHT + 2) + 8
    end

    local function highlightSelection()
        for value, row in rows do
            local selected = value == option.value
            row.TextColor3 = selected and theme.accent or theme.text
            row.BackgroundColor3 = selected and theme.rowHover or theme.popup
            row.BackgroundTransparency = selected and 0 or 1
        end
    end

    function option:AddValue(value)
        value = tostring(value)
        if rows[value] then return end
        if not table.find(option.values, value) then
            table.insert(option.values, value)
        end

        local row = library:Create("TextLabel", {
            ZIndex = 5,
            Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
            BackgroundColor3 = theme.popup,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "  " .. value,
            TextSize = 15,
            Font = theme.font,
            TextColor3 = theme.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = scroll,
        })
        addCorner(row, 4)
        rows[value] = row

        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                option:SetValue(value)
                option:Close()   -- the dropdown hides itself after picking
            elseif input.UserInputType == Enum.UserInputType.MouseMovement then
                if value ~= option.value then
                    row.BackgroundTransparency = 0
                    tween(row, 0.1, { BackgroundColor3 = theme.rowHover })
                end
            end
        end)
        row.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and value ~= option.value then
                tween(row, 0.1, { BackgroundColor3 = theme.popup }).Completed:Connect(function()
                    if value ~= option.value then
                        row.BackgroundTransparency = 1
                    end
                end)
            end
        end)
    end

    function option:RemoveValue(value)
        value = tostring(value)
        local row = rows[value]
        if row then
            row:Destroy()
            rows[value] = nil
        end
        local index = table.find(option.values, value)
        if index then
            table.remove(option.values, index)
        end
        if option.value == value then
            option:SetValue(option.values[1] or "")
        end
    end

    function option:SetValues(values)
        for value in rows do
            option:RemoveValue(value)
        end
        for _, value in values do
            option:AddValue(value)
        end
    end

    function option:SetValue(value)
        value = tostring(value)
        option.value = value
        library.flags[option.flag] = value
        listvalue.Text = value
        highlightSelection()
        option.callback(value)
    end

    function option:Open()
        tween(arrow, 0.2, { Rotation = -90 })
        if openPopup(option, holder, control, popupHeight()) then
            highlightSelection()
        end
    end

    function option:Close()
        tween(arrow, 0.2, { Rotation = 90 })
        closePopup(option, holder)
    end

    -- build initial rows
    if option.value ~= "" and not table.find(option.values, option.value) then
        option:AddValue(option.value)
    end
    for _, value in option.values do
        option:AddValue(value)
    end
    highlightSelection()

    local inContact = false
    control.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if option.open then
                option:Close()
            else
                option:Open()
            end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = true
            tween(control, 0.1, { BackgroundColor3 = theme.controlHover })
        end
    end)
    control.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            inContact = false
            tween(control, 0.1, { BackgroundColor3 = theme.control })
        end
    end)

    return option
end

local function createBox(option, parent)
    local main = library:Create("Frame", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent = parent.content,
    })

    local control = library:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -16, 1, -8),
        BackgroundColor3 = theme.dark,
        BorderSizePixel = 0,
        Parent = main,
    })
    addCorner(control, 4)
    local outline = addStroke(control, theme.border)

    library:Create("TextLabel", {
        Position = UDim2.new(0, 8, 0, 4),
        Size = UDim2.new(1, -16, 0, 14),
        BackgroundTransparency = 1,
        Text = string.upper(option.text),
        TextSize = 12,
        Font = theme.fontBold,
        TextColor3 = theme.subtext,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = control,
    })

    local inputvalue = library:Create("TextBox", {
        Position = UDim2.new(0, 8, 0, 18),
        Size = UDim2.new(1, -16, 0, 22),
        BackgroundTransparency = 1,
        Text = option.value,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = control,
    })

    local focused = false
    control.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if not focused then inputvalue:CaptureFocus() end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement and not focused then
            tween(outline, 0.1, { Color = theme.controlHover })
        end
    end)
    control.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and not focused then
            tween(outline, 0.1, { Color = theme.border })
        end
    end)

    inputvalue.Focused:Connect(function()
        focused = true
        tween(outline, 0.2, { Color = theme.accent })
    end)
    inputvalue.FocusLost:Connect(function(enter)
        focused = false
        tween(outline, 0.2, { Color = theme.border })
        option:SetValue(inputvalue.Text, enter)
    end)

    function option:SetValue(value, enter)
        self.value = tostring(value)
        library.flags[self.flag] = self.value
        inputvalue.Text = self.value
        self.callback(self.value, enter)
    end
end

local function createColorPickerWindow(option)
    local holder = library:Create("CanvasGroup", {
        ZIndex = 5,
        Size = UDim2.new(0, 240, 0, 180),
        BackgroundColor3 = theme.popup,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        Parent = library.base,
    })
    addCorner(holder, 4)
    addStroke(holder, theme.border)
    option.popupHolder = holder

    local hue, sat, val = Color3.toHSV(option.color)
    local currentColor = option.color
    local previousColors = { option.color }
    local originalColor = option.color
    local rainbowEnabled = false
    local rainbowLoop

    -- saturation / value square
    local satval = library:Create("ImageLabel", {
        ZIndex = 5,
        Position = UDim2.new(0, 8, 0, 8),
        Size = UDim2.new(1, -100, 1, -42),
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        BorderSizePixel = 0,
        Image = "rbxassetid://4155801252",
        ClipsDescendants = true,
        Parent = holder,
    })
    addCorner(satval, 4)

    local satvalSlider = library:Create("Frame", {
        ZIndex = 5,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(sat, 0, 1 - val, 0),
        Size = UDim2.new(0, 6, 0, 6),
        Rotation = 45,
        BackgroundColor3 = theme.text,
        BorderSizePixel = 0,
        Parent = satval,
    })

    -- hue bar
    local hueBar = library:Create("Frame", {
        ZIndex = 5,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 8, 1, -8),
        Size = UDim2.new(1, -100, 0, 20),
        BorderSizePixel = 0,
        Parent = holder,
    })
    addCorner(hueBar, 4)
    library:Create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,     Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.157, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(0.323, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.488, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.66,  Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.817, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(1,     Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hueBar,
    })

    local hueSlider = library:Create("Frame", {
        ZIndex = 5,
        Position = UDim2.new(1 - hue, -1, 0, 0),
        Size = UDim2.new(0, 2, 1, 0),
        BackgroundColor3 = theme.text,
        BorderSizePixel = 0,
        Parent = hueBar,
    })

    -- preview + action buttons
    local preview = library:Create("Frame", {
        ZIndex = 5,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.new(0, 80, 0, 80),
        BackgroundColor3 = currentColor,
        BorderSizePixel = 0,
        Parent = holder,
    })
    addCorner(preview, 4)

    local function actionButton(text, yOffset)
        local button = library:Create("TextLabel", {
            ZIndex = 5,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, yOffset),
            Size = UDim2.new(0, 80, 0, 18),
            BackgroundColor3 = theme.dark,
            BorderSizePixel = 0,
            Text = text,
            TextSize = 14,
            Font = theme.font,
            TextColor3 = theme.text,
            Parent = holder,
        })
        addCorner(button, 4)
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                tween(button, 0.1, { BackgroundColor3 = theme.rowHover })
            end
        end)
        button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                tween(button, 0.1, { BackgroundColor3 = theme.dark })
            end
        end)
        return button
    end

    local resetButton   = actionButton("Reset", 92)
    local undoButton    = actionButton("Undo", 112)
    local setButton     = actionButton("Set", 132)
    local rainbowButton = actionButton("Rainbow", 152)

    local function applyColor(color)
        currentColor = color
        hue, sat, val = Color3.toHSV(color)
        preview.BackgroundColor3 = color
        satval.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        hueSlider.Position = UDim2.new(math.clamp(1 - hue, 0, 1), -1, 0, 0)
        satvalSlider.Position = UDim2.new(sat, 0, 1 - val, 0)
        option:SetColor(color, true)
    end
    option._applyExternal = function(color)
        currentColor = color
        hue, sat, val = Color3.toHSV(color)
        preview.BackgroundColor3 = color
        satval.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        hueSlider.Position = UDim2.new(math.clamp(1 - hue, 0, 1), -1, 0, 0)
        satvalSlider.Position = UDim2.new(sat, 0, 1 - val, 0)
    end

    -- live editing (applies immediately; undo snapshot is taken per drag)
    local editingHue = false
    local editingSatVal = false

    hueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not rainbowEnabled then
            editingHue = true
            table.insert(previousColors, currentColor)
            local a = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.995)
            applyColor(Color3.fromHSV(1 - a, sat, val))
        end
    end)
    satval.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not rainbowEnabled then
            editingSatVal = true
            table.insert(previousColors, currentColor)
            local x = math.clamp((input.Position.X - satval.AbsolutePosition.X) / satval.AbsoluteSize.X, 0.005, 1)
            local y = math.clamp((input.Position.Y - satval.AbsolutePosition.Y) / satval.AbsoluteSize.Y, 0, 0.995)
            applyColor(Color3.fromHSV(hue, x, 1 - y))
        end
    end)
    inputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if editingHue then
            local a = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.995)
            applyColor(Color3.fromHSV(1 - a, sat, val))
        elseif editingSatVal then
            local x = math.clamp((input.Position.X - satval.AbsolutePosition.X) / satval.AbsoluteSize.X, 0.005, 1)
            local y = math.clamp((input.Position.Y - satval.AbsolutePosition.Y) / satval.AbsoluteSize.Y, 0, 0.995)
            applyColor(Color3.fromHSV(hue, x, 1 - y))
        end
    end)
    inputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            editingHue = false
            editingSatVal = false
        end
    end)

    resetButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not rainbowEnabled then
            previousColors = { originalColor }
            applyColor(originalColor)
        end
    end)
    undoButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not rainbowEnabled then
            local last = #previousColors
            applyColor(previousColors[last])
            if last > 1 then
                table.remove(previousColors, last)
            end
        end
    end)
    setButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not rainbowEnabled then
            table.insert(previousColors, currentColor)
            applyColor(currentColor)
        end
    end)
    rainbowButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            rainbowEnabled = not rainbowEnabled
            if rainbowEnabled then
                rainbowButton.TextColor3 = theme.accent
                rainbowLoop = runService.Heartbeat:Connect(function()
                    option._applyExternal(chromaColor)
                    option:SetColor(chromaColor, true)
                end)
            else
                if rainbowLoop then rainbowLoop:Disconnect() end
                rainbowButton.TextColor3 = theme.text
                applyColor(previousColors[#previousColors])
            end
        end
    end)

    return holder
end

local function createColor(option, parent)
    local main = library:Create("TextLabel", {
        LayoutOrder = option.position,
        Size = UDim2.new(1, 0, 0, 31),
        BackgroundTransparency = 1,
        Text = "  " .. option.text,
        TextSize = 16,
        Font = theme.font,
        TextColor3 = theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent.content,
    })
    option.anchor = main

    local swatch = library:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0, 26, 0, 19),
        BackgroundColor3 = option.color,
        BorderSizePixel = 0,
        Parent = main,
    })
    addCorner(swatch, 4)
    local outline = addStroke(swatch, theme.disabled)

    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if option.open then
                option:Close()
            else
                if not option.popupHolder then
                    createColorPickerWindow(option)
                end
                openPopup(option, option.popupHolder, main, 180)
            end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            if not option.open then
                tween(outline, 0.1, { Color = theme.controlHover })
            end
        end
    end)
    main.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if not option.open then
                tween(outline, 0.1, { Color = theme.disabled })
            end
        end
    end)

    function option:SetColor(newColor, fromPicker)
        if not fromPicker and self._applyExternal then
            self._applyExternal(newColor)
        end
        swatch.BackgroundColor3 = newColor
        library.flags[self.flag] = newColor
        self.color = newColor
        self.callback(newColor)
    end

    function option:Close()
        if self.popupHolder then
            closePopup(self, self.popupHolder)
        else
            self.open = false
        end
    end
end

--=====================================================================
-- Option loading / folder API
--=====================================================================
local function loadOptions(option, holder)
    for _, newOption in option.options do
        if newOption.type == "label" then
            createLabel(newOption, option)
        elseif newOption.type == "toggle" then
            createToggle(newOption, option)
        elseif newOption.type == "button" then
            createButton(newOption, option)
        elseif newOption.type == "list" then
            createList(newOption, option, holder)
        elseif newOption.type == "box" then
            createBox(newOption, option)
        elseif newOption.type == "bind" then
            createBind(newOption, option)
        elseif newOption.type == "slider" then
            createSlider(newOption, option)
        elseif newOption.type == "color" then
            createColor(newOption, option, holder)
        elseif newOption.type == "divider" then
            createDivider(newOption, option)
        elseif newOption.type == "folder" then
            newOption:init()
        end
    end
end

local function registerOption(option)
    if option.flag then
        library.options[option.flag] = option
    end
end

local function getFunctions(parent)
    function parent:AddLabel(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.type = "label"
        option.position = #self.options
        table.insert(self.options, option)
        return option
    end

    function parent:AddDivider(option)
        option = type(option) == "table" and option or {}
        option.type = "divider"
        option.position = #self.options
        table.insert(self.options, option)
        return option
    end

    function parent:AddToggle(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.state = typeof(option.state) == "boolean" and option.state or false
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.type = "toggle"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.state
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddButton(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.type = "button"
        option.position = #self.options
        option.flag = option.flag or option.text
        table.insert(self.options, option)
        return option
    end

    function parent:AddBind(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.key = (option.key and option.key.Name) or option.key or "None"
        option.hold = typeof(option.hold) == "boolean" and option.hold or false
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.type = "bind"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.key
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddSlider(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.min = typeof(option.min) == "number" and option.min or 0
        option.max = typeof(option.max) == "number" and option.max or 100
        option.value = math.clamp(typeof(option.value) == "number" and option.value or option.min, option.min, option.max)
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.float = typeof(option.float) == "number" and option.float or 1
        option.type = "slider"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.value
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddList(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.values = typeof(option.values) == "table" and option.values or {}
        option.value = tostring(option.value or option.values[1] or "")
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.open = false
        option.type = "list"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.value
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddBox(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.value = tostring(option.value or "")
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.type = "box"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.value
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddColor(option)
        option = typeof(option) == "table" and option or {}
        option.text = tostring(option.text)
        option.color = typeof(option.color) == "table"
            and Color3.new(tonumber(option.color[1]), tonumber(option.color[2]), tonumber(option.color[3]))
            or option.color or Color3.new(1, 1, 1)
        option.callback = typeof(option.callback) == "function" and option.callback or function() end
        option.open = false
        option.type = "color"
        option.position = #self.options
        option.flag = option.flag or option.text
        library.flags[option.flag] = option.color
        table.insert(self.options, option)
        registerOption(option)
        return option
    end

    function parent:AddFolder(title)
        local option = {}
        option.title = tostring(title)
        option.options = {}
        option.open = false
        option.type = "folder"
        option.position = #self.options
        table.insert(self.options, option)

        getFunctions(option)

        function option:init()
            createOptionHolder(self.title, parent.content, self, true)
            loadOptions(self, parent)
        end

        return option
    end
end

--=====================================================================
-- Library API
--=====================================================================
function library:CreateWindow(title)
    local window = { title = tostring(title), options = {}, open = true, canInit = true, init = false, position = #self.windows }
    getFunctions(window)
    table.insert(library.windows, window)
    return window
end

function library:Init()
    self.base = self.base or self:Create("ScreenGui", { Name = tostring(math.random()) })
    if syn and syn.protect_gui then
        syn.protect_gui(self.base)
        self.base.Parent = game:GetService("CoreGui")
    elseif type(get_hidden_gui) == "function" then
        self.base.Parent = get_hidden_gui()
    elseif type(gethui) == "function" then
        self.base.Parent = gethui()
    else
        self.base.Parent = game:GetService("CoreGui")
    end

    self.cursor = self.cursor or self:Create("Frame", {
        ZIndex = 100,
        Size = UDim2.new(0, 5, 0, 5),
        Rotation = 45,
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        Parent = self.base,
    })

    for _, window in self.windows do
        if window.canInit and not window.init then
            window.init = true
            createOptionHolder(window.title, self.base, window)
            loadOptions(window)
        end
    end
end

function library:Close()
    self.open = not self.open
    if self.cursor then
        self.cursor.Visible = self.open
    end
    closeActivePopup()
    for _, window in self.windows do
        if window.main then
            window.main.Visible = self.open
        end
    end
end

-- recolors every accent-driven element live
function library:SetAccent(color)
    theme.accent = color
    if self.cursor then
        self.cursor.BackgroundColor3 = color
    end
    for _, object in self._accentObjects do
        object.BackgroundColor3 = color
    end
    for _, option in self.options do
        if option._refreshAccent then
            option:_refreshAccent()
        end
    end
end

-- optional key that toggles the whole menu (e.g. library:SetToggleKey("End"))
function library:SetToggleKey(keyName)
    self.toggleKey = keyName and tostring(keyName) or nil
end

--Config system --------------------------------------------------------
function library:GetConfig()
    local config = {}
    for flag, value in self.flags do
        if typeof(value) == "Color3" then
            config[flag] = { __color = true, value.R, value.G, value.B }
        else
            config[flag] = value
        end
    end
    return httpService:JSONEncode(config)
end

function library:LoadConfig(json)
    local ok, config = pcall(httpService.JSONDecode, httpService, json)
    if not ok or typeof(config) ~= "table" then return false end
    for flag, value in config do
        if typeof(value) == "table" and value.__color then
            value = Color3.new(value[1], value[2], value[3])
        end
        local option = self.options[flag]
        if option then
            if option.type == "toggle" and option.SetState then
                option:SetState(value)
            elseif (option.type == "slider" or option.type == "list" or option.type == "box") and option.SetValue then
                option:SetValue(value)
            elseif option.type == "color" and option.SetColor then
                option:SetColor(value)
            elseif option.type == "bind" and option.SetKey then
                option:SetKey(value)
            end
        else
            self.flags[flag] = value
        end
    end
    return true
end

--=====================================================================
-- Global input
--=====================================================================
inputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        -- close the active popup when clicking outside it (clicks on the
        -- popup's own anchor are handled by the anchor, which toggles)
        local popup = library.activePopup
        if popup and popup.popupHolder then
            local pos = Vector2.new(input.Position.X, input.Position.Y)
            local inPopup = within(pos, popup.popupHolder.AbsolutePosition, popup.popupHolder.AbsoluteSize)
            local inAnchor = popup.anchor and within(pos, popup.anchor.AbsolutePosition, popup.anchor.AbsoluteSize)
            if not inPopup and not inAnchor then
                popup:Close()
            end
        end
    elseif input.UserInputType == Enum.UserInputType.Keyboard then
        if library.toggleKey and input.KeyCode.Name == library.toggleKey and not inputService:GetFocusedTextBox() then
            library:Close()
        end
    end
end)

inputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and library.cursor then
        local mouse = inputService:GetMouseLocation() + Vector2.new(0, -36)
        library.cursor.Position = UDim2.new(0, mouse.X - 2, 0, mouse.Y - 2)
    end
    if input == dragInput and dragging and dragObject then
        local delta = input.Position - dragStart
        local newX = startPos.X.Offset + delta.X
        local newY = startPos.Y.Offset + delta.Y
        if library.base then
            local screen = library.base.AbsoluteSize
            newX = math.clamp(newX, 0, math.max(screen.X - dragObject.AbsoluteSize.X, 0))
            newY = math.clamp(newY, 0, math.max(screen.Y - HEADER_SIZE, 0))
        end
        dragObject.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
    end
end)

inputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

return library
