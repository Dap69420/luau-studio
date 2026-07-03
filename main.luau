local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local httpRequest = request or http_request

-- ====================== STORAGE SETTINGS & CONFIG SYSTEM ======================
local BASE_FOLDER = "luau_studio"
local INDEX_FILE = BASE_FOLDER .. "/session_index.json"
local CONFIG_FILE = BASE_FOLDER .. "/config.json"

if makefolder then pcall(makefolder, BASE_FOLDER) end

local config = {
    apiKey = "",
    model = "openai/gpt-4o-mini",
    autoExecute = false,
}

local DEFAULT_MODELS = {
    "nvidia/llama-nemotron-rerank-vl-1b-v2:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "qwen/qwen-2.5-72b-instruct:free",
    "deepseek/deepseek-r1:free",
    "openai/gpt-4o-mini",
    "anthropic/claude-3-haiku",
    "google/gemini-2.5-flash",
    "openai/gpt-5.4-mini",
    "anthropic/claude-sonnet-4.5",
    "z-ai/glm-5.2",
    "openai/gpt-5.5",
    "anthropic/claude-opus-4.7-fast",
    "google/gemini-2.5-pro"
}
local availableModels = {unpack(DEFAULT_MODELS)}

local chatHistoryLog = {}
local currentSessionName = "default"
local masterSessionsList = {"default"}
local currentErrorLogSnapshot = ""
local isDrawingSessionData = false 

-- Background Architecture Context Tracker
local sessionGenStates = {} 

local OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
local SYSTEM_PROMPT = "You are an elite, specialized Roblox Luau developer tool with full environment awareness. You have access to the user's current code, past conversation, and real-time execution errors. Analyze their requests against this data. ALWAYS wrap executable code blocks strictly inside ```lua ... ``` tags. CRITICAL COMPLIANCE: You must ALWAYS output the ENTIRE, FULL, COMPLETE script inside your code block. NEVER provide partial snippets, modifications, or differential patches, as your response completely replaces the user's editor canvas entirely. Unchanged code must still be printed out completely."

local THEMES = {
    { name = "VS Dark", accent = Color3.fromRGB(0, 122, 204), bgPanel = Color3.fromRGB(30, 30, 30), bgElement = Color3.fromRGB(37, 37, 38), bgToggle = Color3.fromRGB(45, 45, 48) },
    { name = "Midnight", accent = Color3.fromRGB(110, 160, 255), bgPanel = Color3.fromRGB(9, 11, 16), bgElement = Color3.fromRGB(16, 20, 30), bgToggle = Color3.fromRGB(22, 28, 42) },
    { name = "Violet", accent = Color3.fromRGB(165, 110, 255), bgPanel = Color3.fromRGB(12, 9, 17), bgElement = Color3.fromRGB(22, 17, 31), bgToggle = Color3.fromRGB(31, 24, 43) },
    { name = "Emerald", accent = Color3.fromRGB(75, 210, 150), bgPanel = Color3.fromRGB(7, 12, 11), bgElement = Color3.fromRGB(14, 22, 20), bgToggle = Color3.fromRGB(20, 31, 28) },
}
local currentTheme = THEMES[1]

local function isReasoningModel(slug)
    local s = slug:lower()
    return string.find(s, "r1") or string.find(s, "reasoning") or string.find(s, "thinking") or string.find(s, "opus")
end

local function getModelDisplayName(slug)
    local prefix = isReasoningModel(slug) and "🧠 " or ""
    if string.find(slug, ":free") then
        return prefix .. "[FREE] " .. slug
    end
    local costMatrix = {
        ["openai/gpt-4o-mini"] = "⭐", ["anthropic/claude-3-haiku"] = "⭐", ["google/gemini-2.5-flash"] = "⭐",
        ["openai/gpt-5.4-mini"] = "⭐⭐", ["anthropic/claude-sonnet-4.5"] = "⭐⭐", ["z-ai/glm-5.2"] = "⭐⭐",
        ["openai/gpt-5.5"] = "⭐⭐⭐", ["anthropic/claude-opus-4.7-fast"] = "⭐⭐⭐", ["google/gemini-2.5-pro"] = "⭐⭐⭐"
    }
    return prefix .. (costMatrix[slug] or "⭐") .. " " .. slug
end

local function getSessionPaths(name)
    return BASE_FOLDER .. "/session_CODE_" .. name .. ".luau", 
           BASE_FOLDER .. "/session_CHAT_" .. name .. ".json",
           BASE_FOLDER .. "/session_ERR_" .. name .. ".log"
end

local function saveSettings()
    if writefile then
        local data = HttpService:JSONEncode({
            apiKey = config.apiKey, model = config.model, autoExecute = config.autoExecute,
            theme = currentTheme.name, availableModels = availableModels
        })
        pcall(writefile, CONFIG_FILE, data)
    end
end

-- ====================== TWEEN & UI HELPERS ======================
local function tween(obj, props, time, style, dir)
    return TweenService:Create(obj, TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
end
local function corner(parent, radius)
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius or 8) c.Parent = parent return c
end
local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke") s.Color = color or currentTheme.accent s.Thickness = thickness or 1.2 s.Transparency = transparency or 0.4 s.Parent = parent return s
end
local function makeDraggable(handle, target)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    handle.Active = true
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true dragStart = input.Position startPos = target.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    handle.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ====================== SYNTAX MARKUP HIGHLIGHTING ======================
local function highlightLuau(code)
    local clean = code:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    clean = clean:gsub("(%f[%d]%d+%.?%d*%f[%D])", '<font color="rgb(181,206,168)">%1</font>')
    local keywords = {"local", "function", "end", "if", "then", "else", "elseif", "for", "in", "while", "do", "return", "break", "nil", "true", "false", "and", "or", "not", "repeat", "until"}
    for _, kw in ipairs(keywords) do clean = clean:gsub("%f[%a]"..kw.."%f[%A]", '<font color="rgb(86,156,214)">'..kw..'</font>') end
    local builtins = {"game", "workspace", "script", "Instance", "Vector3", "CFrame", "Color3", "UDim2", "task", "math", "table", "string", "print", "warn", "pairs", "ipairs", "next", "tostring", "tonumber"}
    for _, bi in ipairs(builtins) do clean = clean:gsub("%f[%a]"..bi.."%f[%A]", '<font color="rgb(78,201,176)">'..bi..'</font>') end
    return clean
end

local function formatAIResponse(txt)
    local formatted = txt:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    formatted = formatted:gsub("###%s*(.-)\n", "<b><font color='rgb(255,255,255)'>%1</font></b>\n")
    formatted = formatted:gsub("##%s*(.-)\n", "<b><font color='rgb(255,255,255)'>%1</font></b>\n")
    formatted = formatted:gsub("#%s*(.-)\n", "<b><font color='rgb(255,255,255)'>%1</font></b>\n")
    formatted = formatted:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    formatted = formatted:gsub("\n%-%s*", "\n• ")
    formatted = formatted:gsub("^%-%s*", "• ")
    return formatted
end

-- ====================== MAIN CORE ENGINE FRAMES ======================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LuauStudioIDE" screenGui.ResetOnSpawn, screenGui.IgnoreGuiInset = false, true screenGui.Parent = playerGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size, toggleBtn.Position = UDim2.fromOffset(50, 50), UDim2.new(1, -70, 1, -120)
toggleBtn.BackgroundColor3 = currentTheme.bgToggle toggleBtn.Text, toggleBtn.Font, toggleBtn.TextSize, toggleBtn.TextColor3 = "</>", Enum.Font.Code, 18, Color3.fromRGB(240, 240, 240)
toggleBtn.Parent = screenGui corner(toggleBtn, 25) local toggleStroke = stroke(toggleBtn, currentTheme.accent, 1.5, 0.2)

local panel = Instance.new("Frame")
panel.Size, panel.Position = UDim2.fromOffset(920, 550), UDim2.new(0.5, -460, 0.5, -275)
panel.BackgroundColor3, panel.ClipsDescendants, panel.Visible = currentTheme.bgPanel, true, false panel.Parent = screenGui
corner(panel, 10) local panelStroke = stroke(panel, currentTheme.accent, 1.5, 0.3)

local titleBar = Instance.new("TextLabel")
titleBar.Size, titleBar.Position = UDim2.new(1, -100, 0, 35), UDim2.fromOffset(15, 0)
titleBar.BackgroundTransparency, titleBar.Text = 1, "LUAU STUDIO IDE v1.5.0  ⠿"
titleBar.Font, titleBar.TextSize, titleBar.TextColor3, titleBar.TextXAlignment = Enum.Font.GothamBold, 13, Color3.fromRGB(160, 165, 180), Enum.TextXAlignment.Left
titleBar.Parent = panel makeDraggable(titleBar, panel)

local tabRow = Instance.new("Frame")
tabRow.Size, tabRow.Position = UDim2.fromOffset(410, 30), UDim2.new(1, -425, 0, 5)
tabRow.BackgroundTransparency = 1 tabRow.Parent = panel
local tabLayout = Instance.new("UIListLayout") tabLayout.FillDirection, tabLayout.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 6) tabLayout.Parent = tabRow

local function makeTabButton(text)
    local btn = Instance.new("TextButton") btn.Size = UDim2.fromOffset(95, 25) btn.BackgroundColor3 = currentTheme.bgPanel
    btn.Font, btn.TextSize, btn.TextColor3 = Enum.Font.GothamBold, 11, Color3.fromRGB(140, 145, 160) btn.Text = text btn.Parent = tabRow corner(btn, 4) return btn
end
local editorTabBtn = makeTabButton("Workspace") editorTabBtn.BackgroundColor3, editorTabBtn.TextColor3 = currentTheme.bgElement, Color3.fromRGB(255, 255, 255)
local sessionsTabBtn = makeTabButton("Sessions")
local settingsTabBtn = makeTabButton("Settings")
local docsTabBtn = makeTabButton("Docs")

local workspaceFrame = Instance.new("Frame") workspaceFrame.Size, workspaceFrame.Position, workspaceFrame.BackgroundTransparency = UDim2.new(1, -20, 1, -50), UDim2.fromOffset(10, 40), 1 workspaceFrame.Parent = panel
local sessionsFrame = Instance.new("Frame") sessionsFrame.Size, sessionsFrame.Position, sessionsFrame.BackgroundTransparency, sessionsFrame.Visible = UDim2.new(1, -20, 1, -50), UDim2.fromOffset(10, 40), 1, false sessionsFrame.Parent = panel
local settingsFrame = Instance.new("Frame") settingsFrame.Size, settingsFrame.Position, settingsFrame.BackgroundTransparency, settingsFrame.Visible = UDim2.new(0.58, 0, 1, -50), UDim2.fromOffset(10, 40), 1, false settingsFrame.Parent = panel
local docsFrame = Instance.new("ScrollingFrame") docsFrame.Size, docsFrame.Position, docsFrame.BackgroundTransparency, docsFrame.Visible = UDim2.new(1, -20, 1, -50), UDim2.fromOffset(10, 40), 1, false docsFrame.ScrollBarThickness = 4 docsFrame.Parent = panel

-- CONFIRMATION OVERLAY POPUP MODAL
local confirmOverlay = Instance.new("Frame")
confirmOverlay.Size = UDim2.fromScale(1, 1) confirmOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 18) confirmOverlay.BackgroundTransparency = 0.4
confirmOverlay.ZIndex = 500 confirmOverlay.Visible = false confirmOverlay.Parent = panel

local confirmBox = Instance.new("Frame")
confirmBox.Size = UDim2.fromOffset(360, 140) confirmBox.Position = UDim2.new(0.5, -180, 0.5, -70) confirmBox.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
confirmBox.ZIndex = 501 confirmBox.Parent = confirmOverlay corner(confirmBox, 8) stroke(confirmBox, Color3.fromRGB(240, 90, 90), 1.5, 0.2)

local confirmTitle = Instance.new("TextLabel")
confirmTitle.Size = UDim2.new(1, -20, 0, 50) confirmTitle.Position = UDim2.fromOffset(10, 10) confirmTitle.BackgroundTransparency = 1
confirmTitle.Text = "Are you sure you want to stop and abandon the current AI token iteration generation loop?"
confirmTitle.Font, confirmTitle.TextSize, confirmTitle.TextColor3, confirmTitle.TextWrapped = Enum.Font.GothamMedium, 12, Color3.fromRGB(230, 230, 235), true
confirmTitle.ZIndex = 502 confirmTitle.Parent = confirmBox

local yesConfirmBtn = Instance.new("TextButton")
yesConfirmBtn.Size = UDim2.fromOffset(140, 32) yesConfirmBtn.Position = UDim2.fromOffset(25, 85) yesConfirmBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
yesConfirmBtn.Text, yesConfirmBtn.Font, yesConfirmBtn.TextSize, yesConfirmBtn.TextColor3 = "Yes, Abort Pipeline", Enum.Font.GothamBold, 11, Color3.fromRGB(255, 255, 255)
yesConfirmBtn.ZIndex = 502 yesConfirmBtn.Parent = confirmBox corner(yesConfirmBtn, 6)

local noConfirmBtn = Instance.new("TextButton")
noConfirmBtn.Size = UDim2.fromOffset(140, 32) noConfirmBtn.Position = UDimOffset = UDim2.fromOffset(195, 85) noConfirmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
noConfirmBtn.Text, noConfirmBtn.Font, noConfirmBtn.TextSize, noConfirmBtn.TextColor3 = "No, Keep Waiting", Enum.Font.GothamBold, 11, Color3.fromRGB(220, 220, 225)
noConfirmBtn.ZIndex = 502 noConfirmBtn.Parent = confirmBox corner(noConfirmBtn, 6)

-- ====================== CODE EDITOR FRAMEWORK ======================
local editorFrame = Instance.new("Frame") editorFrame.Size, editorFrame.Position, editorFrame.BackgroundColor3 = UDim2.new(0.58, 0, 0.63, 0), UDim2.fromOffset(0, 0), currentTheme.bgElement editorFrame.Parent = workspaceFrame corner(editorFrame, 6) stroke(editorFrame, Color3.fromRGB(45, 45, 48), 1, 0.3)
local editorHeader = Instance.new("TextLabel") editorHeader.Size, editorHeader.Position = UDim2.new(1, -160, 0, 24), UDim2.fromOffset(10, 2) editorHeader.BackgroundTransparency, editorHeader.Text = 1, "📄 main.luau" editorHeader.Font, editorHeader.TextSize, editorHeader.TextColor3, editorHeader.TextXAlignment = Enum.Font.GothamMedium, 11, Color3.fromRGB(130, 135, 145), Enum.TextXAlignment.Left editorHeader.Parent = editorFrame
local runCodeBtn = Instance.new("TextButton") runCodeBtn.Size, runCodeBtn.Position, runCodeBtn.BackgroundColor3 = UDim2.fromOffset(65, 18), UDim2.new(1, -75, 0, 4), currentTheme.accent runCodeBtn.Text, runCodeBtn.Font, runCodeBtn.TextSize, runCodeBtn.TextColor3 = "▶ Run", Enum.Font.GothamBold, 10, Color3.fromRGB(255, 255, 255) runCodeBtn.Parent = editorFrame corner(runCodeBtn, 4)
local undoCodeBtn = Instance.new("TextButton") undoCodeBtn.Size, undoCodeBtn.Position, undoCodeBtn.BackgroundColor3 = UDim2.fromOffset(65, 18), UDim2.new(1, -145, 0, 4), Color3.fromRGB(60, 62, 68) undoCodeBtn.Text, undoCodeBtn.Font, undoCodeBtn.TextSize, undoCodeBtn.TextColor3 = "⟲ Undo", Enum.Font.GothamBold, 10, Color3.fromRGB(220, 220, 225) undoCodeBtn.Visible = false undoCodeBtn.Parent = editorFrame corner(undoCodeBtn, 4)

local codeScroll = Instance.new("ScrollingFrame") codeScroll.Size, codeScroll.Position = UDim2.new(1, -16, 1, -34), UDim2.fromOffset(8, 28) codeScroll.BackgroundTransparency, codeScroll.ScrollBarThickness = 1, 4 codeScroll.Parent = editorFrame
local lineNumbersLabel = Instance.new("TextLabel") lineNumbersLabel.Size = UDim2.new(0, 32, 1, 0) lineNumbersLabel.BackgroundTransparency, lineNumbersLabel.Text, lineNumbersLabel.Font, lineNumbersLabel.TextSize = 1, "1", Enum.Font.Code, 12 lineNumbersLabel.TextColor3, lineNumbersLabel.TextXAlignment, lineNumbersLabel.TextYAlignment = Color3.fromRGB(90, 95, 105), Enum.TextXAlignment.Right, Enum.TextYAlignment.Top lineNumbersLabel.Parent = codeScroll
local textDisplayLabel = Instance.new("TextLabel") textDisplayLabel.Position, textDisplayLabel.Size = UDim2.fromOffset(42, 0), UDim2.new(1, -42, 1, 0) textDisplayLabel.BackgroundTransparency, textDisplayLabel.RichText = 1, true textDisplayLabel.Text, textDisplayLabel.Font, textDisplayLabel.TextSize = "", Enum.Font.Code, 12 textDisplayLabel.TextColor3, textDisplayLabel.TextXAlignment, textDisplayLabel.TextYAlignment = Color3.fromRGB(220, 220, 220), Enum.TextXAlignment.Left, Enum.TextYAlignment.Top textDisplayLabel.ZIndex = 1 textDisplayLabel.Parent = codeScroll
local codeTextBox = Instance.new("TextBox") codeTextBox.Position, codeTextBox.Size = UDim2.fromOffset(42, 0), UDim2.new(1, -42, 1, 0) codeTextBox.BackgroundTransparency, codeTextBox.ClearTextOnFocus, codeTextBox.MultiLine = 1, false, true codeTextBox.Text, codeTextBox.Font, codeTextBox.TextSize = "", Enum.Font.Code, 12 codeTextBox.TextColor3, codeTextBox.TextTransparency = Color3.fromRGB(255, 255, 255), 1 codeTextBox.TextXAlignment, codeTextBox.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top codeTextBox.ZIndex = 2 codeTextBox.Parent = codeScroll
local cursorLine = Instance.new("Frame") cursorLine.BackgroundColor3, cursorLine.BorderSizePixel, cursorLine.Size, cursorLine.Visible, cursorLine.ZIndex = Color3.fromRGB(240, 240, 240), 0, UDim2.fromOffset(2, 14), false, 3 cursorLine.Parent = codeScroll

local lastCodeBeforeAI = ""
local function updateCursor()
    local text = codeTextBox.Text local pos = codeTextBox.CursorPosition if pos == -1 or not codeTextBox:IsFocused() then cursorLine.Visible = false return end
    local textUpToCursor = string.sub(text, 1, pos - 1) local lines = string.split(textUpToCursor, "\n") local currentLineText = lines[#lines] or ""
    local sizeBeforeCursor = TextService:GetTextSize(currentLineText, codeTextBox.TextSize, codeTextBox.Font, Vector2.new(99999, 99999))
    local dummySize = TextService:GetTextSize("Y", codeTextBox.TextSize, codeTextBox.Font, Vector2.new(99999, 99999))
    cursorLine.Position = UDim2.fromOffset(sizeBeforeCursor.X + 42, (#lines - 1) * dummySize.Y) cursorLine.Size = UDim2.fromOffset(2, dummySize.Y)
end

local saveActiveWorkspaceSession
codeTextBox:GetPropertyChangedSignal("Text"):Connect(function()
    textDisplayLabel.Text = highlightLuau(codeTextBox.Text)
    if saveActiveWorkspaceSession and not isDrawingSessionData then saveActiveWorkspaceSession() end
    local lines = string.split(codeTextBox.Text, "\n") local numbersFormat = {} for i = 1, #lines do table.insert(numbersFormat, tostring(i)) end lineNumbersLabel.Text = table.concat(numbersFormat, "\n")
    local tBounds = TextService:GetTextSize(codeTextBox.Text, codeTextBox.TextSize, codeTextBox.Font, Vector2.new(codeScroll.AbsoluteSize.X - 50, 99999))
    local targetSize = UDim2.new(0, tBounds.X + 90, 0, tBounds.Y + 30) codeScroll.CanvasSize = targetSize
    textDisplayLabel.Size, codeTextBox.Size, lineNumbersLabel.Size = UDim2.new(0, tBounds.X + 50, 0, tBounds.Y + 30), UDim2.new(0, tBounds.X + 50, 0, tBounds.Y + 30), UDim2.new(0, 32, 0, tBounds.Y + 30)
    updateCursor()
end)
codeTextBox:GetPropertyChangedSignal("CursorPosition"):Connect(updateCursor) codeTextBox.Focused:Connect(updateCursor) codeTextBox.FocusLost:Connect(updateCursor)
task.spawn(function() while true do if codeTextBox:IsFocused() then cursorLine.Visible = not cursorLine.Visible else cursorLine.Visible = false end task.wait(0.5) end end)

-- ====================== OUTPUT CONSOLE SYSTEM ======================
local consoleFrame = Instance.new("Frame") consoleFrame.Size, consoleFrame.Position, consoleFrame.BackgroundColor3 = UDim2.new(0.58, 0, 0.33, 0), UDim2.new(0, 0, 0.67, 0), Color3.fromRGB(20, 20, 20) consoleFrame.Parent = workspaceFrame corner(consoleFrame, 6) stroke(consoleFrame, Color3.fromRGB(35, 35, 35), 1, 0.3)
local consoleHeader = Instance.new("TextLabel") consoleHeader.Size, consoleHeader.Position = UDim2.new(1, 0, 0, 22), UDim2.fromOffset(10, 2) consoleHeader.BackgroundTransparency, consoleHeader.Text = 1, "🛠️ OUTPUT CONSOLE" consoleHeader.Font, consoleHeader.TextSize, consoleHeader.TextColor3, consoleHeader.TextXAlignment = Enum.Font.GothamBold, 10, Color3.fromRGB(110, 115, 125), Enum.TextXAlignment.Left consoleHeader.Parent = consoleFrame
local clearConsoleBtn = Instance.new("TextButton") clearConsoleBtn.Size, clearConsoleBtn.Position, clearConsoleBtn.BackgroundTransparency = UDim2.fromOffset(50, 16), UDim2.new(1, -60, 0, 3), 1 clearConsoleBtn.Text, clearConsoleBtn.Font, clearConsoleBtn.TextSize, clearConsoleBtn.TextColor3 = "Clear", Enum.Font.GothamMedium, 10, Color3.fromRGB(140, 140, 140) clearConsoleBtn.Parent = consoleFrame
local consoleScroll = Instance.new("ScrollingFrame") consoleScroll.Size, consoleScroll.Position = UDim2.new(1, -16, 1, -30), UDim2.fromOffset(8, 24) consoleScroll.BackgroundTransparency, consoleScroll.ScrollBarThickness = 1, 4 consoleScroll.Parent = consoleFrame
local consoleLayout = Instance.new("UIListLayout") consoleLayout.Padding, consoleLayout.SortOrder = UDim.new(0, 4), Enum.SortOrder.LayoutOrder consoleLayout.Parent = consoleScroll

local function writeToConsole(text, color, isError)
    local logLabel = Instance.new("TextLabel") logLabel.BackgroundTransparency, logLabel.Text, logLabel.Font, logLabel.TextSize, logLabel.TextColor3 = 1, text, Enum.Font.Code, 11, color or Color3.fromRGB(210, 215, 225) logLabel.TextWrapped, logLabel.TextXAlignment = true, Enum.TextXAlignment.Left
    local txtBounds = TextService:GetTextSize(text, logLabel.TextSize, logLabel.Font, Vector2.new(consoleScroll.AbsoluteSize.X - 10, 9999)) logLabel.Size = UDim2.new(1, -6, 0, txtBounds.Y + 2) logLabel.Parent = consoleScroll
    consoleScroll.CanvasSize = UDim2.new(0, 0, 0, consoleLayout.AbsoluteContentSize.Y + 10) consoleScroll.CanvasPosition = Vector2.new(0, consoleScroll.CanvasSize.Y.Offset)
    if isError then
        currentErrorLogSnapshot = currentErrorLogSnapshot .. text .. "\n"
        if saveActiveWorkspaceSession and not isDrawingSessionData then saveActiveWorkspaceSession() end
    end
end
clearConsoleBtn.MouseButton1Click:Connect(function() for _, child in ipairs(consoleScroll:GetChildren()) do if child:IsA("TextLabel") then child:Destroy() end end consoleScroll.CanvasSize = UDim2.new(0,0,0,0) currentErrorLogSnapshot = "" if saveActiveWorkspaceSession and not isDrawingSessionData then saveActiveWorkspaceSession() end end)

-- ====================== AI ASSISTANT PANEL FRAMEWORK ======================
local chatFrame = Instance.new("Frame") chatFrame.Size, chatFrame.Position, chatFrame.BackgroundColor3 = UDim2.new(0.4, 0, 1, 0), UDim2.new(0.6, 0, 0, 0), currentTheme.bgElement chatFrame.Parent = workspaceFrame corner(chatFrame, 6) stroke(chatFrame, Color3.fromRGB(45, 45, 48), 1, 0.3)
local chatHeader = Instance.new("TextLabel") chatHeader.Size, chatHeader.Position = UDim2.new(1, 0, 0, 22), UDim2.fromOffset(12, 4) chatHeader.BackgroundTransparency, chatHeader.Text = 1, "🤖 AI ASSISTANT CHAT" chatHeader.Font, chatHeader.TextSize, chatHeader.TextColor3, chatHeader.TextXAlignment = Enum.Font.GothamBold, 11, Color3.fromRGB(140, 145, 160), Enum.TextXAlignment.Left chatHeader.Parent = chatFrame

local chatActiveModelLabel = Instance.new("TextLabel") chatActiveModelLabel.Size, chatActiveModelLabel.Position, chatActiveModelLabel.BackgroundTransparency = UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 24), 1 chatActiveModelLabel.Font, chatActiveModelLabel.TextSize, chatActiveModelLabel.TextColor3, chatActiveModelLabel.TextXAlignment = Enum.Font.GothamBold, 10, Color3.fromRGB(90, 150, 240), Enum.TextXAlignment.Left chatActiveModelLabel.Text = "Active Model: [Loading...]" chatActiveModelLabel.Parent = chatFrame
local chatScroll = Instance.new("ScrollingFrame") chatScroll.BackgroundTransparency, chatScroll.ScrollBarThickness = 1, 4 chatScroll.Parent = chatFrame
local chatLayout = Instance.new("UIListLayout") chatLayout.Padding, chatLayout.SortOrder = UDim.new(0, 8), Enum.SortOrder.LayoutOrder chatLayout.Parent = chatScroll

local promptBox = Instance.new("TextBox") promptBox.PlaceholderText, promptBox.Text = "Ask AI to generate or tweak scripts...", "" promptBox.Font, promptBox.TextSize, promptBox.TextColor3, promptBox.ClearTextOnFocus = Enum.Font.Gotham, 11, Color3.fromRGB(230, 235, 245), false promptBox.MultiLine, promptBox.TextWrapped, promptBox.ClipsDescendants = true, true, true promptBox.Parent = chatFrame corner(promptBox, 6) local promptStroke = stroke(promptBox, Color3.fromRGB(60, 60, 65), 1, 0.3)
local generateBtn = Instance.new("TextButton") generateBtn.Text, generateBtn.Font, generateBtn.TextSize, generateBtn.TextColor3 = "Send", Enum.Font.GothamBold, 12, Color3.fromRGB(255, 255, 255) generateBtn.Parent = chatFrame corner(generateBtn, 6)

local function recalculatePromptInputBounds()
    local text = promptBox.Text local frameWidth = chatFrame.AbsoluteSize.X - 95 local baseBounds = TextService:GetTextSize(text, promptBox.TextSize, promptBox.Font, Vector2.new(frameWidth - 12, 9999))
    local targetHeight = math.clamp(baseBounds.Y + 16, 42, 120)
    promptBox.Size = UDim2.new(1, -85, 0, targetHeight) promptBox.Position = UDim2.new(0, 8, 1, -(targetHeight + 8))
    generateBtn.Size = UDim2.fromOffset(70, targetHeight) generateBtn.Position = UDim2.new(1, -74, 1, -(targetHeight + 8))
    chatScroll.Size = UDim2.new(1, -16, 1, -(targetHeight + 54)) chatScroll.Position = UDimOffset = UDim2.fromOffset(8, 42)
end
promptBox:GetPropertyChangedSignal("Text"):Connect(recalculatePromptInputBounds) chatFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalculatePromptInputBounds) recalculatePromptInputBounds()

local function getSessionState(sName)
    if not sessionGenStates[sName] then
        sessionGenStates[sName] = { isThinking = false, abortTriggered = false, history = {}, errors = "" }
    end
    return sessionGenStates[sName]
end

local function drawActiveChatUIElementsFromLog()
    for _, child in ipairs(chatScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    chatScroll.CanvasSize = UDim2.new(0,0,0,0)
    local state = getSessionState(currentSessionName)
    
    for _, entry in ipairs(state.history) do
        local f = Instance.new("Frame") f.BackgroundTransparency = 1
        local l = Instance.new("TextLabel") l.Size = UDim2.new(1, 0, 1, 0) l.BackgroundTransparency, l.Font, l.TextSize = 1, Enum.Font.Gotham, 12 l.TextColor3, l.TextWrapped, l.TextXAlignment, l.TextYAlignment = Color3.new(entry.color[1], entry.color[2], entry.color[3]), true, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
        if entry.isAI then l.RichText = true l.Text = formatAIResponse(entry.text) else l.Text = entry.text end l.Parent = f
        local bounds = TextService:GetTextSize(entry.text, l.TextSize, l.Font, Vector2.new(chatScroll.AbsoluteSize.X - 16, 9999)) f.Size = UDim2.new(1, -6, 0, bounds.Y + 8) f.Parent = chatScroll
    end
    
    -- Recover active progress indicator UI if switching back to a processing engine session
    if state.isThinking then
        local thinkingFrame = Instance.new("Frame") thinkingFrame.Name = "ThinkingIndicatorFrame" thinkingFrame.BackgroundTransparency = 1 thinkingFrame.Size = UDim2.new(1, -6, 0, 24)
        local thinkingLabel = Instance.new("TextLabel") thinkingLabel.Size = UDim2.new(1, 0, 1, 0) thinkingLabel.BackgroundTransparency, thinkingLabel.Font, thinkingLabel.TextSize = 1, Enum.Font.GothamItalic, 12 thinkingLabel.TextColor3, thinkingLabel.TextXAlignment = Color3.fromRGB(160, 165, 175), Enum.TextXAlignment.Left
        thinkingLabel.Text = isReasoningModel(config.model) and "🧠 AI reasoning engine deep thinking..." or "🤖 AI is thinking..."
        thinkingLabel.Parent = thinkingFrame thinkingFrame.Parent = chatScroll
        
        task.spawn(function()
            local dots = {"", ".", "..", "..."} local idx = 1
            while state.isThinking and thinkingFrame.Parent ~= nil do
                local base = isReasoningModel(config.model) and "🧠 AI reasoning engine deep thinking" or "🤖 AI is thinking"
                thinkingLabel.Text = base .. dots[idx]
                idx = (idx % 4) + 1 task.wait(0.4)
            end
        end)
    end
    chatScroll.CanvasSize = UDim2.new(0, 0, 0, chatLayout.AbsoluteContentSize.Y + 15)
    chatScroll.CanvasPosition = Vector2.new(0, chatScroll.CanvasSize.Y.Offset)
end

local function appendChatLog(text, color, isAI, targetSession)
    local sName = targetSession or currentSessionName
    local state = getSessionState(sName)
    color = color or Color3.fromRGB(220, 225, 235)
    
    table.insert(state.history, {text = text, isAI = isAI, color = {color.R, color.G, color.B}})
    if sName == currentSessionName then
        drawActiveChatUIElementsFromLog()
    end
    if saveActiveWorkspaceSession and not isDrawingSessionData then saveActiveWorkspaceSession() end
end

local function refreshSendButtonVisuals()
    local curState = getSessionState(currentSessionName)
    if curState.isThinking then
        generateBtn.Text = "🛑 STOP"
        generateBtn.BackgroundColor3 = Color3.fromRGB(190, 55, 55)
    else
        generateBtn.Text = "Send"
        generateBtn.BackgroundColor3 = currentTheme.accent
    end
end

-- ====================== SESSIONS MANAGEMENT LAYOUT ======================
local sessionCreationBox = Instance.new("TextBox") sessionCreationBox.Size, sessionCreationBox.Position, sessionCreationBox.BackgroundColor3 = UDim2.new(0.6, 0, 0, 36), UDim2.fromOffset(5, 5), currentTheme.bgElement sessionCreationBox.PlaceholderText, sessionCreationBox.Text = "Type new session label name...", "" sessionCreationBox.Font, sessionCreationBox.TextSize, sessionCreationBox.TextColor3 = Enum.Font.Gotham, 12, Color3.fromRGB(230, 235, 245) sessionCreationBox.Parent = sessionsFrame corner(sessionCreationBox, 6) stroke(sessionCreationBox, Color3.fromRGB(55, 55, 60), 1, 0.3)
local createSessionBtn = Instance.new("TextButton") createSessionBtn.Size, createSessionBtn.Position, createSessionBtn.BackgroundColor3 = UDim2.new(0.38, -10, 0, 36), UDim2.new(0.6, 10, 0, 5), currentTheme.accent createSessionBtn.Text, createSessionBtn.Font, createSessionBtn.TextSize, createSessionBtn.TextColor3 = "＋ Create Session", Enum.Font.GothamBold, 12, Color3.fromRGB(255, 255, 255) createSessionBtn.Parent = sessionsFrame corner(createSessionBtn, 6)
local sessionsScroll = Instance.new("ScrollingFrame") sessionsScroll.Size, sessionsScroll.Position = UDim2.new(1, -10, 1, -55), UDim2.fromOffset(5, 50) sessionsScroll.BackgroundTransparency, sessionsScroll.ScrollBarThickness = 1, 4 sessionsScroll.Parent = sessionsFrame
local sessionsLayout = Instance.new("UIListLayout") sessionsLayout.Padding = UDim.new(0, 6) sessionsLayout.Parent = sessionsScroll

local loadSessionDataTarget
local function renderSessionsListMenu()
    for _, child in ipairs(sessionsScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for _, sName do ipairs(masterSessionsList) do
        local entryRow = Instance.new("Frame") entryRow.Size, entryRow.BackgroundColor3 = UDim2.new(1, -6, 0, 40), currentTheme.bgElement entryRow.Parent = sessionsScroll corner(entryRow, 6)
        local state = getSessionState(sName)
        local thinkingLabel = state.isThinking and " ⏳ [AI Processing]" or ""
        local indicator = (sName == currentSessionName) and " 🟢 [Active]" or thinkingLabel
        
        local nameTitle = Instance.new("TextLabel") nameTitle.Size, nameTitle.Position, nameTitle.BackgroundTransparency = UDim2.new(0.6, 0, 1, 0), UDim2.fromOffset(12, 0), 1 nameTitle.Text = sName .. indicator nameTitle.Font = (sName == currentSessionName) and Enum.Font.GothamBold or Enum.Font.GothamMedium nameTitle.TextSize, nameTitle.TextColor3, nameTitle.TextXAlignment = 12, Color3.fromRGB(230, 235, 245), Enum.TextXAlignment.Left nameTitle.Parent = entryRow
        local switchBtn = Instance.new("TextButton") switchBtn.Size, switchBtn.Position = UDim2.fromOffset(100, 24), UDim2.new(1, -112, 0, 8) switchBtn.BackgroundColor3 = (sName == currentSessionName) and Color3.fromRGB(45, 55, 50) or currentTheme.bgPanel switchBtn.Text = (sName == currentSessionName) and "Loaded" or "Open Workspace" switchBtn.Font, switchBtn.TextSize, switchBtn.TextColor3 = Enum.Font.GothamBold, 10, (sName == currentSessionName) and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(200, 205, 215) switchBtn.Parent = entryRow corner(switchBtn, 4)
        
        if sName ~= currentSessionName then switchBtn.MouseButton1Click:Connect(function() loadSessionDataTarget(sName, false) end) end
    end
    sessionsScroll.CanvasSize = UDim2.new(0, 0, 0, sessionsLayout.AbsoluteContentSize.Y + 10)
end

saveActiveWorkspaceSession = function()
    if not writefile or isDrawingSessionData then return end
    local codePath, chatPath, errPath = getSessionPaths(currentSessionName)
    pcall(writefile, codePath, codeTextBox.Text)
    local state = getSessionState(currentSessionName)
    pcall(writefile, chatPath, HttpService:JSONEncode(state.history))
    pcall(writefile, errPath, currentErrorLogSnapshot)
end

loadSessionDataTarget = function(name, skipSave)
    if not skipSave then saveActiveWorkspaceSession() end
    currentSessionName = name
    if writefile then pcall(writefile, INDEX_FILE, HttpService:JSONEncode({current = currentSessionName, sessions = masterSessionsList})) end
    
    isDrawingSessionData = true
    local state = getSessionState(name)
    undoCodeBtn.Visible = false
    
    local codePath, _, errPath = getSessionPaths(name)
    if isfile and readfile and isfile(codePath) then
        local _, codeData = pcall(readfile, codePath) codeTextBox.Text = codeData or ""
    else
        codeTextBox.Text = "-- Welcome to session [" .. name .. "]\nprint(\"Hello world!\")"
    end
    
    if isfile and readfile and isfile(errPath) then
        local _, errData = pcall(readfile, errPath) currentErrorLogSnapshot = errData or ""
        if currentErrorLogSnapshot ~= "" then writeToConsole("📋 Restored session fault-log history:\n" .. currentErrorLogSnapshot, Color3.fromRGB(240, 115, 115), false) end
    else
        currentErrorLogSnapshot = ""
    end
    
    drawActiveChatUIElementsFromLog()
    isDrawingSessionData = false
    editorHeader.Text = "📄 " .. name .. "::workspace.luau"
    refreshSendButtonVisuals()
    renderSessionsListMenu()
    recalculatePromptInputBounds()
end

createSessionBtn.MouseButton1Click:Connect(function()
    local rawName = sessionCreationBox.Text:gsub("[^%w%s%-]", ""):gsub("^%s*", ""):gsub("%s*$", "") if rawName == "" then return end
    for _, name in ipairs(masterSessionsList) do if name:lower() == rawName:lower() then return end end
    table.insert(masterSessionsList, rawName) sessionCreationBox.Text = "" loadSessionDataTarget(rawName, false)
end)

-- ====================== SETTINGS PANEL FRAMEWORK ======================
local function addSettingLabel(text, yOffset)
    local lbl = Instance.new("TextLabel") lbl.Size, lbl.Position = UDim2.new(1, 0, 0, 20), UDim2.fromOffset(5, yOffset) lbl.BackgroundTransparency, lbl.Text = 1, text lbl.Font, lbl.TextSize, lbl.TextColor3, lbl.TextXAlignment = Enum.Font.GothamMedium, 12, Color3.fromRGB(160, 165, 175), Enum.TextXAlignment.Left lbl.Parent = settingsFrame return lbl
end
addSettingLabel("OpenRouter Bearer Token Key (Saved)", 0)
local apiField = Instance.new("TextBox") apiField.Size, apiField.Position, apiField.BackgroundColor3 = UDim2.new(1, -10, 0, 34), UDim2.fromOffset(5, 22), currentTheme.bgElement apiField.PlaceholderText, apiField.Text, apiField.Font, apiField.TextSize, apiField.TextColor3, apiField.ClearTextOnFocus = "sk-or-...", config.apiKey, Enum.Font.Code, 11, Color3.fromRGB(210, 215, 230), false apiField.Parent = settingsFrame corner(apiField, 6)
apiField.FocusLost:Connect(function() config.apiKey = apiField.Text saveSettings() end)

addSettingLabel("Active LLM Core Endpoint Model", 68)
local modelDropdownBtn = Instance.new("TextButton") modelDropdownBtn.Size, modelDropdownBtn.Position, modelDropdownBtn.BackgroundColor3 = UDim2.new(1, -10, 0, 34), UDim2.fromOffset(5, 90), currentTheme.bgElement modelDropdownBtn.Text = getModelDisplayName(config.model) modelDropdownBtn.Font, modelDropdownBtn.TextSize, modelDropdownBtn.TextColor3 = Enum.Font.Gotham, 12, Color3.fromRGB(210, 215, 230) modelDropdownBtn.Parent = settingsFrame corner(modelDropdownBtn, 6) local modelDropdownStroke = stroke(modelDropdownBtn, Color3.fromRGB(55, 55, 60), 1, 0.3)
local dropdownContainer = Instance.new("Frame") dropdownContainer.Size, dropdownContainer.Position, dropdownContainer.BackgroundColor3 = UDim2.new(1, -10, 0, 220), UDim2.fromOffset(5, 126), currentTheme.bgElement dropdownContainer.ZIndex, dropdownContainer.Visible = 10, false dropdownContainer.Parent = settingsFrame corner(dropdownContainer, 6) local dropdownContainerStroke = stroke(dropdownContainer, currentTheme.accent, 1, 0.3)
local dropdownScroll = Instance.new("ScrollingFrame") dropdownScroll.Size, dropdownScroll.Position = UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 0) dropdownScroll.BackgroundTransparency, dropdownScroll.ScrollBarThickness, dropdownScroll.ZIndex = 1, 4, 10 dropdownScroll.Parent = dropdownContainer
local dropdownLayout = Instance.new("UIListLayout") dropdownLayout.Padding = UDim.new(0, 2) dropdownLayout.Parent = dropdownScroll
local addModelFrame = Instance.new("Frame") addModelFrame.Size, addModelFrame.Position, addModelFrame.BackgroundColor3 = UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 1, -34), currentTheme.bgPanel addModelFrame.ZIndex = 10 addModelFrame.Parent = dropdownContainer corner(addModelFrame, 6)
local addModelInput = Instance.new("TextBox") addModelInput.Size, addModelInput.Position, addModelInput.BackgroundTransparency = UDim2.new(1, -45, 1, -4), UDim2.fromOffset(6, 2), 1 addModelInput.PlaceholderText, addModelInput.Text = "Custom model router string...", "" addModelInput.Font, addModelInput.TextSize, addModelInput.TextColor3, addModelInput.ClearTextOnFocus = Enum.Font.Code, 11, Color3.fromRGB(190, 195, 205), false addModelInput.ZIndex = 10 addModelInput.Parent = addModelFrame
local addModelBtn = Instance.new("TextButton") addModelBtn.Size, addModelBtn.Position, addModelBtn.BackgroundColor3 = UDim2.fromOffset(28, 26), UDim2.new(1, -32, 0, 4), currentTheme.accent addModelBtn.Text, addModelBtn.Font, addModelBtn.TextSize, addModelBtn.TextColor3 = "＋", Enum.Font.GothamBold, 14, Color3.fromRGB(255, 255, 255) addModelBtn.ZIndex = 10 addModelBtn.Parent = addModelFrame corner(addModelBtn, 4)

local function renderModelDropdown()
    for _, child in ipairs(dropdownScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for _, mName in ipairs(availableModels) do
        local row = Instance.new("Frame") row.Size, row.BackgroundTransparency, row.ZIndex = UDim2.new(1, -6, 0, 28), 1, 10 row.Parent = dropdownScroll
        local selectBtn = Instance.new("TextButton") selectBtn.Size = (table.find(DEFAULT_MODELS, mName)) and UDim2.new(1, 0, 1, 0) or UDim2.new(1, -30, 1, 0) selectBtn.BackgroundTransparency = 1 selectBtn.Text = "  " .. getModelDisplayName(mName) selectBtn.Font = (config.model == mName) and Enum.Font.GothamBold or Enum.Font.Gotham selectBtn.TextSize = 11 selectBtn.TextColor3 = (config.model == mName) and currentTheme.accent or Color3.fromRGB(210, 215, 225) selectBtn.TextXAlignment = Enum.TextXAlignment.Left selectBtn.ZIndex = 10 selectBtn.Parent = row
        
        selectBtn.MouseButton1Click:Connect(function()
            config.model = mName modelDropdownBtn.Text = getModelDisplayName(mName)
            chatActiveModelLabel.Text = "Active Model: " .. getModelDisplayName(mName)
            dropdownContainer.Visible = false saveSettings() renderModelDropdown()
        end)
        if not table.find(DEFAULT_MODELS, mName) then
            local delBtn = Instance.new("TextButton") delBtn.Size, delBtn.Position = UDim2.fromOffset(22, 22), UDim2.new(1, -26, 0, 3) delBtn.BackgroundColor3 = Color3.fromRGB(75, 35, 35) delBtn.Text, delBtn.Font, delBtn.TextSize, delBtn.TextColor3 = "❌", Enum.Font.GothamBold, 9, Color3.fromRGB(255, 120, 120) delBtn.ZIndex = 10 delBtn.Parent = row corner(delBtn, 4)
            delBtn.MouseButton1Click:Connect(function()
                local idx = table.find(availableModels, mName) if idx then table.remove(availableModels, idx) if config.model == mName then config.model = DEFAULT_MODELS[1] modelDropdownBtn.Text = getModelDisplayName(config.model) chatActiveModelLabel.Text = "Active Model: " .. getModelDisplayName(config.model) end saveSettings() renderModelDropdown() end
            end)
        end
    end
    dropdownScroll.CanvasSize = UDim2.new(0, 0, 0, dropdownLayout.AbsoluteContentSize.Y + 6)
end
modelDropdownBtn.MouseButton1Click:Connect(function() dropdownContainer.Visible = not dropdownContainer.Visible if dropdownContainer.Visible then renderModelDropdown() end end)
addModelBtn.MouseButton1Click:Connect(function() local rawModelName = addModelInput.Text:gsub("^%s*", ""):gsub("%s*$", "") if rawModelName == "" or table.find(availableModels, rawModelName) then return end table.insert(availableModels, rawModelName) addModelInput.Text = "" saveSettings() renderModelDropdown() end)

addSettingLabel("Runtime Logic Rules Execution Trigger", 138)
local autoExecToggle = Instance.new("TextButton") autoExecToggle.Size, autoExecToggle.Position = UDim2.fromOffset(140, 28), UDim2.fromOffset(5, 160) autoExecToggle.Parent = settingsFrame corner(autoExecToggle, 6)
local function refreshToggleUI()
    if config.autoExecute then autoExecToggle.BackgroundColor3, autoExecToggle.Text = currentTheme.accent, "Auto-Execute: ON" autoExecToggle.TextColor3 = Color3.fromRGB(255, 255, 255) else autoExecToggle.BackgroundColor3, autoExecToggle.Text = Color3.fromRGB(50, 50, 55), "Auto-Execute: OFF" autoExecToggle.TextColor3 = Color3.fromRGB(180, 185, 195) end
end
autoExecToggle.MouseButton1Click:Connect(function() config.autoExecute = not config.autoExecute refreshToggleUI() saveSettings() end)

addSettingLabel("Active Interface Color Palette System Theme", 205)
local themeSwatches = Instance.new("Frame") themeSwatches.Size, themeSwatches.Position, themeSwatches.BackgroundTransparency = UDim2.new(1, 0, 0, 35), UDim2.fromOffset(5, 228), 1 themeSwatches.Parent = settingsFrame
local swatchLayout = Instance.new("UIListLayout") swatchLayout.FillDirection, swatchLayout.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 10) swatchLayout.Parent = themeSwatches

local function applyTheme(theme)
    currentTheme = theme panel.BackgroundColor3 = theme.bgPanel panelStroke.Color = theme.accent toggleBtn.BackgroundColor3 = theme.bgToggle toggleStroke.Color = theme.accent editorFrame.BackgroundColor3 = theme.bgElement chatFrame.BackgroundColor3 = theme.bgElement promptBox.BackgroundColor3 = theme.bgPanel
    refreshSendButtonVisuals() runCodeBtn.BackgroundColor3 = theme.accent apiField.BackgroundColor3 = theme.bgElement modelDropdownBtn.BackgroundColor3 = theme.bgElement dropdownContainer.BackgroundColor3 = theme.bgElement dropdownContainerStroke.Color = theme.accent addModelFrame.BackgroundColor3 = theme.bgPanel addModelBtn.BackgroundColor3 = theme.accent sessionCreationBox.BackgroundColor3 = theme.bgElement createSessionBtn.BackgroundColor3 = theme.accent refreshToggleUI()
end
for _, th in ipairs(THEMES) do
    local sw = Instance.new("TextButton") sw.Size, sw.BackgroundColor3, sw.Text = UDim2.fromOffset(75, 26), th.accent, th.name sw.Font, sw.TextSize, sw.TextColor3 = Enum.Font.GothamBold, 10, Color3.fromRGB(255,255,255) sw.Parent = themeSwatches sw.MouseButton1Click:Connect(function() applyTheme(th) saveSettings() end)
end

-- ====================== DOCUMENTATION DOCS PAGE LAYER ======================
local docsLayout = Instance.new("UIListLayout") docsLayout.Padding = UDim.new(0, 14) docsLayout.Parent = docsFrame
local function addDocSection(title, rawBody)
    local frame = Instance.new("Frame") frame.Size = UDim2.new(1, -12, 0, 40) frame.BackgroundColor3 = currentTheme.bgElement frame.Parent = docsFrame corner(frame, 6)
    local tLbl = Instance.new("TextLabel") tLbl.Size = UDim2.new(1, -20, 0, 24) tLbl.Position = UDim2.fromOffset(10, 6) tLbl.BackgroundTransparency = 1 tLbl.Text = "📌 " .. title tLbl.Font, tLbl.TextSize, tLbl.TextColor3, tLbl.TextXAlignment = Enum.Font.GothamBold, 13, Color3.fromRGB(255, 255, 255), Enum.TextXAlignment.Left tLbl.Parent = frame
    local bLbl = Instance.new("TextLabel") tLbl.BackgroundTransparency = 1 bLbl.BackgroundTransparency = 1 bLbl.Text = rawBody bLbl.Font, bLbl.TextSize, bLbl.TextColor3, bLbl.TextWrapped, bLbl.TextXAlignment = Enum.Font.Gotham, 11, Color3.fromRGB(190, 195, 205), true, Enum.TextXAlignment.Left bLbl.Parent = frame
    local size = TextService:GetTextSize(rawBody, bLbl.TextSize, bLbl.Font, Vector2.new(panel.AbsoluteSize.X - 50, 9999))
    bLbl.Size = UDim2.new(1, -20, 0, size.Y + 10) bLbl.Position = UDim2.fromOffset(10, 30) frame.Size = UDim2.new(1, -12, 0, size.Y + 45)
end

local function buildDocumentationText()
    for _, c in ipairs(docsFrame:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    addDocSection("How the Studio IDE Operates", "This workspace integrates an automated scripting canvas directly with OpenRouter's massive neural endpoint pipeline. You can modify scripts locally inside the code container viewport, evaluate performance errors securely with the output terminal monitor, and pass full structural system instructions to models.")
    addDocSection("Dynamic Generation Background Threading", "You can close the panel layout or shift workspace context across distinct parallel tracks inside the 'Sessions' directory page seamlessly. If an active generation is executing, its background processing thread won't halt or throw anomalies when jumping instances.")
    addDocSection("Understanding Configuration System Identifiers", "• 🧠 Brain Icon Badge: Signifies highly complex logic models (e.g. deep-reasoning variants like DeepSeek-R1, Anthropic Opus). These endpoints process deep strategic chains before writing characters, making them inherently slower but structurally accurate.\n• ⭐ Star Rating system: Indicates base financial computation processing categories:\n  - [FREE]: Fully subsidized open infrastructure endpoints.\n  - ⭐ Tier: Low-latency efficient setups (e.g., GPT-4o-Mini).\n  - ⭐⭐ Tier: Balanced mid-tier frontier models.\n  - ⭐⭐⭐ Tier: Costly, heavy performance enterprise systems.")
    addDocSection("Registering Custom OpenRouter API Model Strings", "To employ model strings not packaged natively within the default environment listings:\n1. Open the 'Settings' profile layout panel view.\n2. Expand the Core Endpoint Model selection popup scrollbox frame.\n3. Input your target model identifier tag into the custom prompt textbox line located exactly at the footer container row (e.g. 'deepseek/deepseek-chat').\n4. Tap the '＋' button to seamlessly inject it to your local environment array profiles.")
    docsFrame.CanvasSize = UDim2.new(0, 0, 0, docsLayout.AbsoluteContentSize.Y + 20)
end

-- ====================== TAB NAVIGATION ROUTINES ======================
local function deactivateAllTabs()
    workspaceFrame.Visible, sessionsFrame.Visible, settingsFrame.Visible, docsFrame.Visible = false, false, false, false
    editorTabBtn.BackgroundColor3, editorTabBtn.TextColor3 = currentTheme.bgPanel, Color3.fromRGB(140, 145, 160)
    sessionsTabBtn.BackgroundColor3, sessionsTabBtn.TextColor3 = currentTheme.bgPanel, Color3.fromRGB(140, 145, 160)
    settingsTabBtn.BackgroundColor3, settingsTabBtn.TextColor3 = currentTheme.bgPanel, Color3.fromRGB(140, 145, 160)
    docsTabBtn.BackgroundColor3, docsTabBtn.TextColor3 = currentTheme.bgPanel, Color3.fromRGB(140, 145, 160)
    dropdownContainer.Visible = false
end
editorTabBtn.MouseButton1Click:Connect(function() deactivateAllTabs() workspaceFrame.Visible = true editorTabBtn.BackgroundColor3, editorTabBtn.TextColor3 = currentTheme.bgElement, Color3.fromRGB(255, 255, 255) end)
sessionsTabBtn.MouseButton1Click:Connect(function() deactivateAllTabs() sessionsFrame.Visible = true sessionsTabBtn.BackgroundColor3, sessionsTabBtn.TextColor3 = currentTheme.bgElement, Color3.fromRGB(255, 255, 255) renderSessionsListMenu() end)
settingsTabBtn.MouseButton1Click:Connect(function() deactivateAllTabs() settingsFrame.Visible = true settingsTabBtn.BackgroundColor3, settingsTabBtn.TextColor3 = currentTheme.bgElement, Color3.fromRGB(255, 255, 255) end)
docsTabBtn.MouseButton1Click:Connect(function() deactivateAllTabs() docsFrame.Visible = true docsTabBtn.BackgroundColor3, docsTabBtn.TextColor3 = currentTheme.bgElement, docsTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255) buildDocumentationText() end)

-- ====================== RUNTIME COMPILATION DRIVER ======================
local function executeWorkspaceScript(code)
    local chunk, compErr = loadstring(code) if not chunk then writeToConsole("❌ Compilation Fault:\n" .. tostring(compErr), Color3.fromRGB(255, 110, 110), true) return end
    local customEnv = setmetatable({}, { __index = getfenv() })
    customEnv.print = function(...) local args, parsed = { ... }, {} for i, v in ipairs(args) do parsed[i] = tostring(v) end writeToConsole(table.concat(parsed, "  "), Color3.fromRGB(230, 230, 230), false) end
    customEnv.warn = function(...) local args, parsed = { ... }, {} for i, v in ipairs(args) do parsed[i] = tostring(v) end writeToConsole("⚠️ " .. table.concat(parsed, "  "), Color3.fromRGB(255, 175, 80), false) end
    setfenv(chunk, customEnv)
    writeToConsole("⚡ Executing active runtime thread...", Color3.fromRGB(90, 165, 255), false)
    local success, runErr = pcall(chunk) if not success then writeToConsole("❌ Runtime Exception: " .. tostring(runErr), Color3.fromRGB(255, 95, 110), true) else writeToConsole("✅ Context Evaluation Complete [Success]", Color3.fromRGB(100, 255, 140), false) end
end
runCodeBtn.MouseButton1Click:Connect(function() executeWorkspaceScript(codeTextBox.Text) end)
undoCodeBtn.MouseButton1Click:Connect(function() if lastCodeBeforeAI ~= "" then codeTextBox.Text = lastCodeBeforeAI undoCodeBtn.Visible = false writeToConsole("⟲ System: Rolled back canvas to structural pre-AI generation history.", Color3.fromRGB(255, 200, 100), false) end end)

-- ====================== PIPELINE CONTEXT WRAPPING & PACKAGING ENGINE ======================
generateBtn.MouseButton1Click:Connect(function()
    local state = getSessionState(currentSessionName)
    
    -- "STOP" PIPELINE GENERATION ACTION ROUTINE
    if state.isThinking then
        confirmOverlay.Visible = true
        
        local connectionYes, connectionNo
        local function clearTempConnections()
            connectionYes:Disconnect() connectionNo:Disconnect() confirmOverlay.Visible = false
        end
        
        connectionYes = yesConfirmBtn.MouseButton1Click:Connect(function()
            state.abortTriggered = true clearTempConnections()
        end)
        connectionNo = noConfirmBtn.MouseButton1Click:Connect(function()
            clearTempConnections()
        end)
        return
    end
    
    local inputPrompt = promptBox.Text if inputPrompt == "" then return end
    if config.apiKey == "" then appendChatLog("⚠️ System Error: Missing valid Token Key inside Settings profile layout.", Color3.fromRGB(255, 105, 105), false) return end

    state.isThinking = true state.abortTriggered = false
    refreshSendButtonVisuals() renderSessionsListMenu()
    promptBox.Text = "" recalculatePromptInputBounds()

    local activeGenerationSession = currentSessionName
    appendChatLog("💡 Query: " .. inputPrompt, Color3.fromRGB(130, 180, 255), false, activeGenerationSession)

    task.spawn(function()
        local codeContextSnapshot = codeTextBox.Text
        local contextualSystemMessage = SYSTEM_PROMPT .. "\n\n[CURRENT_WORKSPACE_CANVAS_CODE]\n" .. codeContextSnapshot .. "\n\n"
        if currentErrorLogSnapshot ~= "" then contextualSystemMessage = contextualSystemMessage .. "[REALTIME_RUNTIME_CONSOLE_ERRORS]\n" .. currentErrorLogSnapshot .. "\n\n" end
        
        local compiledMessages = {{ role = "system", content = contextualSystemMessage }}
        for _, rawHistory in ipairs(state.history) do
            table.insert(compiledMessages, { role = rawHistory.isAI and "assistant" or "user", content = rawHistory.text })
        end
        table.insert(compiledMessages, { role = "user", content = inputPrompt })

        local payload = { model = config.model, messages = compiledMessages }
        local startTime = os.clock()
        local requestComplete, httpSuccess, responseBodyData = false, false, nil

        task.spawn(function()
            local requestSuccess, response = pcall(function()
                return httpRequest({
                    Url = OPENROUTER_ENDPOINT, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.apiKey, ["HTTP-Referer"] = "https://roblox.com", ["X-Title"] = "Luau IDE Workspace" },
                    Body = HttpService:JSONEncode(payload)
                })
            end)
            httpSuccess = requestSuccess and response ~= nil responseBodyData = response requestComplete = true
        end)

        while not requestComplete and not state.abortTriggered do task.wait(0.5) end

        state.isThinking = false
        if currentSessionName == activeGenerationSession then refreshSendButtonVisuals() renderSessionsListMenu() end

        if state.abortTriggered then
            appendChatLog("🛑 Generation Aborted: The operation was terminated locally by the developer. (Note: Tokens processing on remote endpoint may still draw account balance credit equivalents)", Color3.fromRGB(240, 120, 120), false, activeGenerationSession)
            return
        end

        local timeTaken = os.clock() - startTime
        if httpSuccess and responseBodyData.StatusCode == 200 then
            local jsonSuccess, decoded = pcall(function() return HttpService:JSONDecode(responseBodyData.Body) end)
            if jsonSuccess and decoded.choices and decoded.choices[1] then
                local messageData = decoded.choices[1].message
                local rawThinking = messageData.reasoning or messageData.reasoning_content
                if rawThinking and rawThinking ~= "" then
                    appendChatLog("💭 **[AI Thinking Process]:**\n" .. rawThinking, Color3.fromRGB(155, 158, 165), true, activeGenerationSession)
                end

                local aiOutput = messageData.content or ""
                local narrative = aiOutput:gsub("```lua(.-)```", ""):gsub("^%s*", ""):gsub("%s*$", "")
                if narrative ~= "" then appendChatLog(narrative, nil, true, activeGenerationSession) end
                
                local isolatedCode = aiOutput:match("```lua(.-)```")
                if isolatedCode then
                    local cleanCode = isolatedCode:gsub("^%s*", ""):gsub("%s*$", "")
                    
                    if currentSessionName == activeGenerationSession then
                        lastCodeBeforeAI = codeTextBox.Text undoCodeBtn.Visible = true codeTextBox.Text = cleanCode
                        writeToConsole(string.format("📥 System: Contextual code updates applied safely to canvas. (Time: %.2fs)", timeTaken), Color3.fromRGB(100, 220, 255), false)
                        if config.autoExecute then executeWorkspaceScript(cleanCode) end
                    else
                        local targetPaths, _, _ = getSessionPaths(activeGenerationSession)
                        pcall(writefile, targetPaths, cleanCode)
                        writeToConsole(string.format("📥 Background System: Thread generation finalized and written quietly into storage session disk profile map for [%s].", activeGenerationSession), Color3.fromRGB(130, 230, 160), false)
                    end
                end
                appendChatLog(string.format("🕒 Task resolved in %.2f seconds.", timeTaken), Color3.fromRGB(120, 210, 145), false, activeGenerationSession)
            else
                appendChatLog("⚠️ Parsing Failure: Structural failure reading JSON payload content.", Color3.fromRGB(255, 100, 100), false, activeGenerationSession)
            end
        else
            appendChatLog("❌ Server Pipeline Rejected Request. Status: " .. (responseBodyData and tostring(responseBodyData.StatusCode) or "Link Error"), Color3.fromRGB(255, 90, 110), false, activeGenerationSession)
        end
    end)
end)

-- ====================== CONTROLS TOGGLES / WINDOW DRAGS ======================
local isWindowVisible = false
local function setIDEWindowState(state)
    isWindowVisible = state
    if isWindowVisible then
        panel.Visible = true panel.BackgroundTransparency = 1 panel.Size = UDim2.fromOffset(920, 0)
        tween(panel, { BackgroundTransparency = 0.02, Size = UDim2.fromOffset(920, 550) }, 0.25, Enum.EasingStyle.Back):Play()
    else
        dropdownContainer.Visible = false local hideTween = tween(panel, { Size = UDim2.fromOffset(920, 0), BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quad) hideTween:Play()
        hideTween.Completed:Connect(function() if not isWindowVisible then panel.Visible = false end end)
    end
end

local isDraggingToggle, toggleDragStart, startTogglePos = false, nil, nil
toggleBtn.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDraggingToggle = true toggleDragStart = input.Position startTogglePos = toggleBtn.Position end end)
UserInputService.InputChanged:Connect(function(input) if isDraggingToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then local delta = input.Position - toggleDragStart toggleBtn.Position = UDim2.new(startTogglePos.X.Scale, startTogglePos.X.Offset + delta.X, startTogglePos.Y.Scale, startTogglePos.Y.Offset + delta.Y) end end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if isDraggingToggle then isDraggingToggle = false if toggleDragStart then local moveDelta = (input.Position - toggleDragStart).Magnitude if moveDelta < 6 then setIDEWindowState(not isWindowVisible) end end toggleDragStart = nil end
    end
end)

-- ====================== SYSTEM INITIALIZER PIPELINE BOOTSTRAP ======================
local function initializeMasterSystem()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local success, content = pcall(readfile, CONFIG_FILE)
        if success then
            local jsonSuccess, data = pcall(function() return HttpService:JSONDecode(content) end)
            if jsonSuccess and data then
                config.apiKey = data.apiKey or config.apiKey config.model = data.model or config.model config.autoExecute = data.autoExecute or false
                apiField.Text = config.apiKey modelDropdownBtn.Text = getModelDisplayName(config.model)
                if data.availableModels and type(data.availableModels) == "table" then availableModels = data.availableModels end
                if data.theme then for _, th in ipairs(THEMES) do if th.name == data.theme then currentTheme = th break end end end
            end
        end
    end
    applyTheme(currentTheme) chatActiveModelLabel.Text = "Active Model: " .. getModelDisplayName(config.model)
    
    if isfile and readfile and isfile(INDEX_FILE) then
        local success, content = pcall(readfile, INDEX_FILE)
        if success then
            local jsonSuccess, indexedData = pcall(function() return HttpService:JSONDecode(content) end)
            if jsonSuccess and indexedData then
                masterSessionsList = indexedData.sessions or {"default"} currentSessionName = indexedData.current or "default"
            end
        end
    end
    
    -- Warm up session memory log snapshots structures from physical workspace files sequentially
    for _, sName in ipairs(masterSessionsList) do
        local state = getSessionState(sName)
        local _, chatPath, _ = getSessionPaths(sName)
        if isfile and readfile and isfile(chatPath) then
            local _, chatData = pcall(readfile, chatPath)
            local parsedSuccess, logParsed = pcall(function() return HttpService:JSONDecode(chatData) end)
            if parsedSuccess and type(logParsed) == "table" then state.history = logParsed end
        end
    end
    
    loadSessionDataTarget(currentSessionName, true)
end

initializeMasterSystem()
