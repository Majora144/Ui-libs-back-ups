local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Majora144/Ui-libs-back-ups/refs/heads/main/uwuwarerew/main.lua", true))()

--[[
    library.theme = {
        accent       = Color3.fromRGB(255, 65, 65),   -- main highlight color
        window       = Color3.fromRGB(20, 20, 20),    -- window body
        header       = Color3.fromRGB(10, 10, 10),    -- window title bar
        folderHeader = Color3.fromRGB(14, 14, 14),    -- folder title bar
        control      = Color3.fromRGB(35, 35, 35),    -- buttons / tracks / tags
        controlHover = Color3.fromRGB(55, 55, 55),    -- hover state
        popup        = Color3.fromRGB(28, 28, 28),    -- dropdown / color picker
        rowHover     = Color3.fromRGB(40, 40, 40),    -- dropdown row hover
        dark         = Color3.fromRGB(20, 20, 20),    -- checkbox / picker buttons
        border       = Color3.fromRGB(45, 45, 45),    -- outlines
        text         = Color3.fromRGB(255, 255, 255),
        subtext      = Color3.fromRGB(150, 150, 150), -- list titles / labels
        disabled     = Color3.fromRGB(100, 100, 100),
        font         = Enum.Font.Gotham,
        fontBold     = Enum.Font.GothamBold,
    }


--[[
    window:SetTitle(newTitle)   -- rename the window at any time
    window:SetOpen(true/false)  -- expand / collapse from code
]]

local window = library:CreateWindow("example")

--[[
    window:AddFolder(title) -> folder
      * collapsible section inside a window (starts CLOSED)
      * a folder has every Add* method a window has
      * folder:SetTitle / folder:SetOpen work like the window versions
]]

local folder = window:AddFolder("main")

--[[
    option:SetText("new text")  -- update it later
    option.Text = "new text"    -- old-style assignment also still works
]]

local label = folder:AddLabel({ text = "general" })



folder:AddDivider({})

--[[
    option:SetState(true/false)         -- set from code (fires callback)
    option:SetState(true/false, true)   -- second arg = silent (no callback)
    option:SetText("new text")
]]

local toggle = folder:AddToggle({
    text = "enabled",
    state = false,
    flag = "example_enabled",
    callback = function(state)
        print("toggle is now:", state)
    end,
})

--[[
   parent:AddButton({
        text     = "button",
        flag     = "my_button",
        callback = function() end,
    }) -> option
]]

folder:AddButton({
    text = "click me",
    callback = function()
        print("clicked")
    end,
})

--[[
   =====================================================================
    parent:AddBind({
        text     = "keybind",
        key      = "RightShift",  -- key name, or "None" for unbound
        hold     = false,         -- true = callback repeats while held,
                                  --        then callback(true) on release
        flag     = "my_bind",
        callback = function() end,
    }) -> option

    option:SetKey("F")            -- set from code (string or Enum.KeyCode)
]]

folder:AddBind({
    text = "toggle menu",
    key = "RightShift",
    flag = "menu_bind",
    callback = function()
        library:Close()
    end,
})

--[[
    parent:AddSlider({
        text     = "slider",
        min      = 0,
        max      = 100,
        value    = 50,       -- initial value (clamped to min/max)
        float    = 1,        -- STEP SIZE: 1 = whole numbers,
                             -- 0.1 = one decimal, 0.01 = two decimals...
        flag     = "my_slider",
        callback = function(value) end,
    }) -> option

    option:SetValue(75)           -- set from code (snapped + clamped)
]]

local slider = folder:AddSlider({
    text = "speed",
    min = 0,
    max = 100,
    value = 50,
    float = 1,
    flag = "example_speed",
    callback = function(value)
        print("speed:", value)
    end,
})

--[[
    parent:AddList({
        text     = "list",
        values   = { "One", "Two", "Three" },
        value    = "One",     -- initial selection (defaults to values[1])
        flag     = "my_list",
        callback = function(value) end,
    }) -> option

    option:SetValue("Two")              -- select from code
    option:AddValue("Four")             -- append a new entry
    option:RemoveValue("Four")          -- remove an entry
    option:SetValues({ "A", "B", "C" }) -- replace the whole list
]]

local list = folder:AddList({
    text = "mode",
    values = { "Corner", "Full" },
    value = "Corner",
    flag = "example_mode",
    callback = function(value)
        print("mode:", value)
    end,
})

--[[
    parent:AddBox({
        text     = "box",
        value    = "",        -- initial text
        flag     = "my_box",
        callback = function(value, enterPressed) end,
    }) -> option

    option:SetValue("text")       -- set from code
]]

folder:AddBox({
    text = "player name",
    flag = "example_name",
    callback = function(value, enterPressed)
        print("typed:", value, "confirmed:", enterPressed)
    end,
})

--[[
    parent:AddColor({
        text     = "color",
        color    = Color3.fromRGB(255, 65, 65),   -- initial color
        flag     = "my_color",
        callback = function(color) end,
    }) -> option

    option:SetColor(Color3.fromRGB(0, 255, 0))   -- set from code
]]

local color = folder:AddColor({
    text = "accent color",
    color = Color3.fromRGB(255, 65, 65),
    flag = "example_color",
    callback = function(c)
        print("color picked:", c)
    end,
})

--[[

        if library.flags["example_enabled"] then ... end
        local speed = library.flags["example_speed"]
]]

--[[

    library:Init()

    library:Close()

    library:SetToggleKey("End")

    library:SetAccent(Color3.fromRGB(0, 170, 255))

    library:LoadConfig(json) -> true/false

    Example save/load with executor file functions:
]]

local CONFIG_FILE = "my_config.json"

folder:AddButton({
    text = "save config",
    callback = function()
        if writefile then
            writefile(CONFIG_FILE, library:GetConfig())
            print("config saved")
        end
    end,
})

folder:AddButton({
    text = "load config",
    callback = function()
        if readfile and isfile and isfile(CONFIG_FILE) then
            library:LoadConfig(readfile(CONFIG_FILE))
            print("config loaded")
        end
    end,
})


library:SetToggleKey("End")
library:Init()
