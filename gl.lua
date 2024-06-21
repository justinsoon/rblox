local Fluent, SaveManager, InterfaceManager = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))(), loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))(), loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({Title = "Gym League - V5.0", SubTitle = "by EnVyP Hub", TabWidth = 160, Size = UDim2.fromOffset(680, 560), Acrylic = true, Theme = "Dark", MinimizeKey = Enum.KeyCode.LeftControl, TitleSize = 35, SubTitleSize = 30})
local Tabs = {
    Main = Window:AddTab({Title = "Main", Icon = "globe"}),
    Training = Window:AddTab({Title = "Training", Icon = "user"}),
    Workouts = Window:AddTab({Title = "Workouts", Icon = "bone"}),
    Shop = Window:AddTab({Title = "Shop", Icon = "shopping-cart"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
}
local Options = Fluent.Options or {}
local player = game:GetService("Players").LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local inCompetition = false
local webhookURL, webhookInterval, webhookEnabled, routineEnabled
local usingCurrentMachine, remainingTime = nil, 0

local function isInCompetition()
    return player.PlayerGui:FindFirstChild("Podium") and player.PlayerGui.Podium.Enabled
end

local function teleportToEquipment(equipment)
    if equipment and equipment:FindFirstChild("root") then
        player.Character.HumanoidRootPart.CFrame = equipment.root.CFrame
        wait(1)
    end
end

local function interactWithPrompt(prompt)
    if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        wait(prompt.HoldDuration + 0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end
end

local function useEquipment(equipment)
    local prompt = equipment:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled and prompt.HoldDuration > 0 then
        usingCurrentMachine = equipment.Name  -- Set current equipment
        while Options[equipment.Name .. "Enabled"].Value do  -- Ensure the toggle for the equipment is still on
            if (player.Character.HumanoidRootPart.Position - equipment.root.Position).Magnitude > 3 then
                teleportToEquipment(equipment)
            end
            interactWithPrompt(prompt)
            wait(prompt.HoldDuration + 0.1)
        end
        return true
    end
    return false
end

local function calculateRemainingTime(endTime)
    return math.max(0, math.floor(endTime - tick()))
end

local function handleRoutine(workoutOrder)
    while Options.routineEnabled.Value do
        for _, equipmentName in ipairs(workoutOrder) do
            local equipment = workspace.Equipments:FindFirstChild(equipmentName)
            if equipment then
                if not inCompetition and useEquipment(equipment) then
                    local startTime = tick()  -- Capture the start time
                    local duration = 300
                    local endTime = startTime + duration  -- Calculate end time once
                    while tick() < endTime and Options.routineEnabled.Value do
                        remainingTime = calculateRemainingTime(endTime)
                        updateWebhook(remainingTime, true)
                        wait(1)
                    end
                    remainingTime = 0
                end
            end
            wait(0.1)
        end
        wait(0.1)
    end
end

local function teleportBackToCurrentMachine()
    print("Attempting to teleport back to current machine...")
    if usingCurrentMachine then
        local equipment = workspace.Equipments:FindFirstChild(usingCurrentMachine)
        if equipment then
            print("Found equipment:", usingCurrentMachine)
            teleportToEquipment(equipment)
            useEquipment(equipment)
        else
            print("Equipment not found:", usingCurrentMachine)
        end
    else
        print("No current machine to teleport to.")
    end
end

local function onCompetitionToggle()
    inCompetition = isInCompetition()
    if not inCompetition then
        wait(1)  -- Add a short delay before teleporting back
        teleportBackToCurrentMachine()
    end
end

player.PlayerGui.Podium:GetPropertyChangedSignal("Enabled"):Connect(onCompetitionToggle)
onCompetitionToggle()

local function getStamina()
    local stamina = player.PlayerGui.Main.BottomCenter.Stamina.Title
    if stamina then
        local currentStamina, maxStamina = stamina.Text:match("^(%d+)/(%d+)$")
        return tonumber(currentStamina), tonumber(maxStamina)
    end
    return 0, 0
end

local function isStaminaMaxed()
    local currentStamina, maxStamina = getStamina()
    return currentStamina == maxStamina
end

local function getCurrentMachine()
    local indicator = workspace:FindFirstChild("equipmentIndicator")
    local part = indicator and indicator:FindFirstChild("indicator") and indicator.indicator:FindFirstChild("Part")
    local muscles = part and part:FindFirstChild("muscles")
    if muscles then
        local nameElement = muscles:FindFirstChild("Name")
        if nameElement and nameElement:IsA("TextLabel") or nameElement:IsA("TextBox") or nameElement:IsA("TextButton") then
            return nameElement.Text
        end
    end
    return "N/A"
end

local function sendWebhook(content)
    if webhookURL and webhookEnabled then
        http.request({
            Url = webhookURL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode({content = content})
        })
    end
end

local function formatNumber(number)
    local units = {
        [1e6] = "M", 
        [1e9] = "B", 
        [1e12] = "T", 
        [1e15] = "Qd", 
        [1e18] = "Qn", 
        [1e21] = "Z", 
        [1e24] = "Y", 
        [1e27] = "O", 
        [1e30] = "N"
    }
    for divisor, unit in pairs(units) do
        if number >= divisor then
            return string.format("%.2f", number / divisor) .. unit
        end
    end
    return tostring(number):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end

local function getStat(frame, name)
    local statFrame = frame:FindFirstChild(name)
    if statFrame then
        local frameElement = statFrame:FindFirstChild("Frame")
        if frameElement then
            local amount = frameElement:FindFirstChild("Amount")
            local percentage = frameElement:FindFirstChild("APercentage")
            if amount and percentage then
                local formattedAmount = amount.Text:sub(1, -3) .. " " .. amount.Text:sub(-2):gsub("^%l", string.upper)
                return formattedAmount, percentage.Text
            end
        end
    end
    return "N/A", "N/A"
end

local function updateWebhook(remainingTime, isRoutine)
    local stats = player.PlayerGui.Frames.Stats.Main.MuscleList.Stats
    local fullBodyStat = player.PlayerGui.Frames.Stats.Main.MuscleList.FullBody.Frame.APercentage.Text
    local currentStamina, maxStamina = getStamina()
    local cash = player.leaderstats.Cash.Value
    local inCompetition = isInCompetition()
    local statsText = ""
    local currentMachine = getCurrentMachine()

    for _, stat in ipairs({"Abs", "Back", "Biceps", "Calves", "Chest", "Forearm", "Legs", "Shoulder", "Triceps"}) do
        local amount, percentage = getStat(stats, stat)
        statsText = statsText .. string.format("\n> %s: `%s - (%s)`", stat, amount, percentage)
    end

    local staminaPercentage = (currentStamina / maxStamina) * 100
    local formattedCurrentStamina = formatNumber(tonumber(currentStamina)) -- Ensure numeric
    local formattedMaxStamina = formatNumber(tonumber(maxStamina)) -- Ensure numeric
    local formattedRemainingTime = tonumber(remainingTime) or 0 -- Ensure numeric

    local timeUntilNextMachine = isRoutine and string.format("%d seconds", formattedRemainingTime) or "N/A"

    local content = string.format(
        "> \n" ..
        "> 🏋️ **GYM LEAGUE - EnVyP Hub** 🏋️\n" ..
        "> \n" ..
        "> 💵 **Cash**: `$%s`\n" ..
        "> 🔋 **Stamina**: `%s/%s - (%.2f%%)`\n" ..
        "> 💪 **Total Body Stat**: `%s`\n" ..
        "> \n" ..
        "> [ Player Stats ]%s\n" ..
        "> \n" ..
        "> [ Status ]\n" ..
        "> 🏆 **In Competition**: `%s`\n" ..
        "> 🔧 **Current Equipment**: `%s`\n" ..
        "> ⏳ **Time Until Next Equipment**: `%s`",
        formatNumber(tonumber(cash)), -- Ensure numeric
        formattedCurrentStamina, 
        formattedMaxStamina, 
        staminaPercentage, 
        fullBodyStat, 
        statsText, 
        tostring(inCompetition), 
        currentMachine or "N/A", 
        timeUntilNextMachine
    )

    sendWebhook(content)
end

local itemPrices = {
    ["Chocolate Bar"] = 50,
    ["Chips"] = 90,
    ["Chicken Wings"] = 112,
    ["Master Drink"] = 127,
    ["Protein Bar"] = 150,
    ["Cheap Protein Powder"] = 180,
    ["Steak"] = 210,
    ["Rorate"] = 525,
    ["Cheap Body Oil"] = 525,
    ["Protein Shake"] = 750,
    ["Premium Body Oil"] = 1000,
    ["Protein Powder"] = 1500,
    ["Average Body Oil"] = 3750,
    ["Creatine Powder"] = 5250,
    ["Small Stamina Potion"] = 15000,
    ["Small Speed Potion"] = 15000,
    ["Small Power Potion"] = 15000,
    ["Small Pump Potion"] = 15000,
    ["Small Money Potion"] = 15000,
    ["Secret Beans"] = 18700,
    ["Angel Potion"] = 75000
}

local function buyItems(items, shouldContinue)
    while shouldContinue() do
        local cash = game:GetService("Players").LocalPlayer.leaderstats.Cash.Value
        for _, item in ipairs(items) do
            if not shouldContinue() then return end
            local price = itemPrices[item]
            if cash >= price then
                game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PowerUpsService.RF.Buy:InvokeServer(item)
                cash = cash - price
                wait(0.1)
            end
        end
        wait(2)
    end
end

local function changeTreadmillSpeed(value)
    for _ = 1, 4 do
        game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.EquipmentService.RF.ChangeSpeed:InvokeServer(value)
        wait(0.01)
    end
end

local function isOnTreadmill()
    for _, equipment in pairs(workspace.Equipments:GetChildren()) do
        if equipment.Name == "treadmill" then
            return true
        end
    end
    return false
end

local function usePurchasedItems()
    while Options.AutoUseItems.Value do
        for _, item in pairs(player.Backpack:GetChildren()) do
            if item:IsA("Tool") and item.Name ~= "Death Potion" then
                item.Parent = player.Character
                if item:FindFirstChild("Activate") then
                    item:Activate()
                else
                    player.Character.Humanoid:EquipTool(item)
                    item:Activate()
                end
                wait(0.1)
            end
        end
        wait(0.5)
    end
end

local function addMainTab()
    Tabs.Main:AddSection("Utilities")
    Tabs.Main:AddToggle("InstantMachine", {Title = "⚙️ Instant Machine", Default = false}):OnChanged(function()
        if Options.InstantMachine.Value then
            PromptButtonHoldBegan = game:GetService("ProximityPromptService").PromptButtonHoldBegan:Connect(function(prompt)
                fireproximityprompt(prompt)
            end)
        else
            if PromptButtonHoldBegan then
                PromptButtonHoldBegan:Disconnect()
                PromptButtonHoldBegan = nil
            end
        end
    end)
    Tabs.Main:AddToggle("AutoUseItems", {Title = "🎒 Auto Items", Default = false}):OnChanged(function()
        if Options.AutoUseItems.Value then spawn(usePurchasedItems) end
    end)
    Tabs.Main:AddSlider("WalkSpeed", {Title = "🚶‍♂️ Walk Speed", Default = 16, Min = 16, Max = 100, Rounding = 1}):OnChanged(function(Value)
        player.Character.Humanoid.WalkSpeed = Value
    end)
    Tabs.Main:AddSection("Actions")
    Tabs.Main:AddButton({Title = "🆘 Panic Button", Callback = function()
        for k in pairs(Options) do
            Options[k].Value = false
        end
        Fluent:Notify({Title = "Panic Button", Content = "All toggles have been stopped.", Duration = 5})
    end})
    Tabs.Main:AddButton({Title = "🔄 Reconnect Server", Callback = function()
        local TeleportService = game:GetService("TeleportService")
        local Players = game:GetService("Players")

        local placeId = game.PlaceId
        local jobId = game.JobId

        TeleportService:TeleportToPlaceInstance(placeId, jobId, Players.LocalPlayer)
    end})
    Tabs.Main:AddButton({Title = "🎟️ Redeem Codes", Callback = function()
        for _, code in ipairs({"5KLikes", "10KLikes", "1MVisits", "SORRY", "Release", "150KLikes", "100KActive", "20MVisits", "DEFLATION"}) do
            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.CodeService.RF.Redeem:InvokeServer(code)
        end
    end})
    Tabs.Main:AddButton({Title = "🎁 Get Daily Gift", Callback = function()
        game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.DailyService.RE.GetGift:FireServer()
    end})
end

local function addWebhookSettings()
    Tabs.Main:AddSection("Webhook Settings")
    Tabs.Main:AddInput("WebhookURL", {Title = "Webhook URL", Placeholder = "Enter webhook URL"}):OnChanged(function(Value)
        webhookURL = Value
    end)
    Tabs.Main:AddInput("WebhookInterval", {Title = "Webhook Interval (seconds)", Placeholder = "Enter interval", Text = "60", Numeric = true}):OnChanged(function(Value)
        webhookInterval = tonumber(Value) or 60
    end)
    Tabs.Main:AddToggle("EnableWebhook", {Title = "Enable Webhook", Default = false}):OnChanged(function(Value)
        webhookEnabled = Value
        if webhookEnabled then
            spawn(function()
                while webhookEnabled do
                    updateWebhook("None", remainingTime, false)
                    wait(webhookInterval)
                end
            end)
        end
    end)
end

local function addStats()
    Tabs.Main:AddSection("Stats")
    Tabs.Main:AddButton({Title = "📈 Get Character Stats", Callback = function()
        local stats = player.PlayerGui.Frames.Stats.Main.MuscleList.Stats
        local statsText = ""

        for _, stat in ipairs({"Abs", "Back", "Biceps", "Calves", "Chest", "Forearm", "Legs", "Shoulder", "Triceps"}) do
            local amount, percentage = getStat(stats, stat)
            statsText = statsText .. string.format("\n> %s: `%s - (%s)`", stat, amount, percentage)
        end

        if characterStatsParagraph then characterStatsParagraph:Destroy() end
        characterStatsParagraph = Tabs.Main:AddParagraph({Title = "Character Stats 📈", Content = statsText})
    end})
    Tabs.Main:AddButton({Title = "📋 Get Training Info", Callback = function()
        local workoutOrder = {"Push Up", "Pull Downs", "Dead Lifts", "Front Squat"}
        local currentMachine = getCurrentMachine()
        local content = string.format("Workout Plan: %s\nCurrent Machine: %s\nTime until next Machine: %d seconds", table.concat(workoutOrder, ", "), currentMachine, remainingTime)
        if trainingInfoParagraph then trainingInfoParagraph:Destroy() end
        trainingInfoParagraph = Tabs.Main:AddParagraph({Title = "Training Info 📋", Content = content})
    end})    
end

local function addTrainingTab()
    Tabs.Training:AddSection("Stamina Settings")
    Tabs.Training:AddInput("StaminaThreshold", {Title = "Stamina Threshold (%)", Default = "25", Numeric = true}):OnChanged(function(Value)
        staminaThresholdPercentage = tonumber(Value) or 0
    end)
    Tabs.Training:AddSection("Training Options")
    Tabs.Training:AddToggle("AutoTrain", {Title = "🚅 Auto Train", Default = false}):OnChanged(function()
        if Options.AutoTrain.Value then
            spawn(function()
                while Options.AutoTrain.Value do
                    local currentStamina, maxStamina = getStamina()
                    if currentStamina > (staminaThresholdPercentage / 100) * maxStamina then
                        local clickButton = player.PlayerGui.Main.RightCenter:FindFirstChild("click")
                        if clickButton and clickButton.Visible then
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.EquipmentService.RE.click:FireServer()
                        end
                    else
                        repeat wait(0.01) currentStamina, maxStamina = getStamina() until currentStamina >= (staminaThresholdPercentage / 100) * maxStamina
                    end
                    wait(0.1)
                end
            end)
        end
    end)
    Tabs.Training:AddToggle("AutoTrainMaxEnabled", {Title = "🚴‍♂️ Auto Train (Max Stamina)", Default = false}):OnChanged(function()
        if Options.AutoTrainMaxEnabled.Value then
            spawn(function()
                while Options.AutoTrainMaxEnabled.Value do
                    local currentStamina, maxStamina = getStamina()
                    if currentStamina > (staminaThresholdPercentage / 100) * maxStamina then
                        local clickButton = player.PlayerGui.Main.RightCenter:FindFirstChild("click")
                        if clickButton and clickButton.Visible then
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.EquipmentService.RE.click:FireServer()
                        end
                    else
                        repeat wait(0.01) until isStaminaMaxed()
                    end
                    wait(0.1)
                end
            end)
        end
    end)
    Tabs.Training:AddSection("Weight Options")
    Tabs.Training:AddToggle("AutoLoad", {Title = "🏋️‍♂️ Auto Weights", Default = false}):OnChanged(function()
        if Options.AutoLoad.Value then
            spawn(function()
                while Options.AutoLoad.Value do
                    for _, equipment in pairs(workspace.Equipments:GetChildren()) do
                        if not Options.AutoLoad.Value then break end
                        if equipment.Name ~= "treadmill" then
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.EquipmentService.RF.AutoLoad:InvokeServer()
                        end
                    end
                    wait(0.1)
                end
            end)
        end
    end)
    Tabs.Training:AddSection("Treadmill Options")
    Tabs.Training:AddToggle("AutoTreadmill", {Title = "🏃‍♂️ Auto Treadmill", Default = false}):OnChanged(function()
        if Options.AutoTreadmill.Value then
            spawn(function()
                while Options.AutoTreadmill.Value do
                    if isOnTreadmill() then
                        local currentStamina, maxStamina = getStamina()
                        local staminaThreshold = (staminaThresholdPercentage / 100) * maxStamina
                        if currentStamina < staminaThreshold then
                            changeTreadmillSpeed(false)
                            repeat wait(0.01) until isStaminaMaxed()
                        else
                            changeTreadmillSpeed(true)
                        end
                    end
                    wait(0.01)
                end
            end)
        end
    end)
    Tabs.Training:AddSection("Competition Options")
    Tabs.Training:AddToggle("AutoCompetition", {Title = "💪 Auto Flex", Default = false}):OnChanged(function()
        if Options.AutoCompetition.Value then
            spawn(function()
                while Options.AutoCompetition.Value do
                    local timeLabel = player.PlayerGui:FindFirstChild("Podium", true)
                    if timeLabel and timeLabel.Enabled then
                        local padding = timeLabel:FindFirstChild("padding", true)
                        local time = padding and padding:FindFirstChild("Time", true)
                        if time and time.Text and time.Text > "00:00" then
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PodiumService.RE.Event:FireServer()
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                        end
                    end
                    wait(0.01)
                end
            end)
        end
    end)
    Tabs.Training:AddToggle("AutoJoinCompetition", {Title = "🏆 Auto Competition", Default = false}):OnChanged(function()
        if Options.AutoJoinCompetition.Value then
            spawn(function()
                while Options.AutoJoinCompetition.Value do
                    local popup = player.PlayerGui.Main.BottomCenter:FindFirstChild("Popup")
                    if popup and popup.Visible then
                        local timerText = popup:FindFirstChild("Timer") and popup.Timer.Text
                        if timerText == "Starts in 1 sec" then
                            inCompetition = true
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.EquipmentService.RF.Leave:InvokeServer()
                            game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PodiumService.RF.Teleport:InvokeServer()
                            wait(5)
                        end
                    end
                    wait(0.1)
                end
            end)
        end
    end)
    Tabs.Training:AddToggle("FastExitCompetition", {Title = "🚪 Fast Exit Competition", Default = false}):OnChanged(function()
        if Options.FastExitCompetition.Value then
            spawn(function()
                while Options.FastExitCompetition.Value do
                    if isInCompetition() and not player.PlayerGui.Podium.padding.Bar.tip:FindFirstChild("Circle") then
                        local rewardsFrame = player.PlayerGui.Podium:FindFirstChild("RewardsFrame", true)
                        local winnersFrame = player.PlayerGui.Podium:FindFirstChild("winners", true)

                        local function clickButton(button)
                            local x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2
                            local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
                            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
                        end

                        if rewardsFrame then
                            local continueButton = rewardsFrame.CanvasGroup.Continue:FindFirstChild("TextLabel", true)
                            if continueButton then
                                wait(0.2)
                                clickButton(continueButton)
                            end
                        end
                    else
                        wait(0.1)
                    end
                end
            end)
        end
    end)
end

local function addWorkoutTab()
    local equipmentList = {
        {Name = "treadmill", Title = "Treadmill"},
        {Name = "benchpress", Title = "Bench Press"},
        {Name = "deadlift", Title = "Deadlift"},
        {Name = "pushup", Title = "Push Ups"},
        {Name = "barfix", Title = "Pull-Ups"},
        {Name = "pulldown", Title = "Lat Pull Down"},
        {Name = "pushpress", Title = "Push Press"},
        {Name = "chestpress", Title = "Chest Press"},
        {Name = "legpress", Title = "Leg Press"},
        {Name = "frontsquat", Title = "Front Squat"},
        {Name = "hammercurl", Title = "Hammer Curl"},
        {Name = "tricepscurl", Title = "Triceps Curl"},
        {Name = "crunch", Title = "Crunches"},
        {Name = "wristcurl", Title = "Wrist Curl"},
        {Name = "abs", Title = "Knee Raises"}
    }
    Tabs.Workouts:AddSection("Individual Equipment")
    for _, equipment in ipairs(equipmentList) do
        Options[equipment.Name .. "Enabled"] = Options[equipment.Name .. "Enabled"] or {Value = false}
        Tabs.Workouts:AddToggle(equipment.Name .. "Enabled", {Title = equipment.Title, Default = false}):OnChanged(function()
            if Options[equipment.Name .. "Enabled"].Value then
                spawn(function()
                    local equipmentObject = workspace.Equipments:FindFirstChild(equipment.Name)
                    if equipmentObject then
                        teleportToEquipment(equipmentObject)
                        useEquipment(equipmentObject)
                    end
                end)
            end
        end)
    end    

    Tabs.Workouts:AddSection("Workout Routines")
    local function handleWorkoutToggle(name, order)
        Tabs.Workouts:AddToggle(name, {Title = name:gsub("Workout", ""), Default = false}):OnChanged(function()
            Options.routineEnabled = Options[name]
            if Options.routineEnabled.Value then spawn(function() handleRoutine(order) end) end
        end)
    end

    handleWorkoutToggle("SimpleWorkout", {"pushup", "pulldown", "deadlift", "frontsquat"})
    handleWorkoutToggle("EfficientWorkout", {"pulldown", "benchpress", "frontsquat", "crunch", "hammercurl"})
    handleWorkoutToggle("EssentialWorkout", {"pulldown", "benchpress", "pushpress", "frontsquat", "legpress", "hammercurl", "tricepscurl", "wristcurl", "crunch"})
    handleWorkoutToggle("FullBodyWorkout", {"pulldown", "benchpress", "pushpress", "frontsquat", "legpress", "hammercurl", "tricepscurl", "abs", "deadlift", "chestpress", "crunch", "pushup", "wristcurl", "barfix"})
end

local function addShopTab()
    local powerUps = {"Chocolate Bar", "Chips", "Master Drink", "Chicken Wings", "Steak", "Cheap Protein Powder", "Protein Bar", "Rorate", "Cheap Body Oil", "Protein Shake", "Milk", "Protein Powder", "Creatine Powder", "Premium Body Oil", "Shiny Oil", "Small Stamina Potion", "Small Speed Potion", "Small Power Potion", "Random Potion", "Small Pump Potion", "Small Money Potion", "Secret Beans", "Death Potion"}
    local selectedPowerUp

    Tabs.Shop:AddSection("Item Selection")
    Tabs.Shop:AddDropdown("PowerUp", {Title = "🛍️ Gym Shop", Values = powerUps, Default = "Chocolate Bar"}):OnChanged(function(Value)
        selectedPowerUp = Value
    end)
    Tabs.Shop:AddButton({Title = "🛒 Purchase", Callback = function()
        game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PowerUpsService.RF.Buy:InvokeServer(selectedPowerUp)
    end})

    Tabs.Shop:AddSection("Auto Buy Options")
    Tabs.Shop:AddToggle("boostpowerups", {Title = "🛒 Auto Buy Boost Items", Default = false}):OnChanged(function(value)
        Options.boostpowerups.Value = value
        if value then
            spawn(function()
                buyItems({"Chocolate Bar", "Chips", "Master Drink", "Chicken Wings", "Steak", "Cheap Protein Powder", "Protein Bar", "Rorate", "Protein Shake", "Protein Powder", "Creatine Powder", "Small Stamina Potion", "Small Speed Potion", "Small Power Potion", "Small Pump Potion", "Secret Beans", "Angel Potion"}, function() return Options.boostpowerups.Value end)
            end)
        end
    end)
    Tabs.Shop:AddToggle("autoCashBuy", {Title = "💸 Auto Buy Cash Items", Default = false}):OnChanged(function(value)
        Options.autoCashBuy.Value = value
        while value do 
            local popup = player.PlayerGui.Main.BottomCenter:FindFirstChild("Popup")
            if popup and popup.Visible then
                spawn(function()
                    buyItems({"Cheap Body Oil", "Premium Body Oil", "Average Body Oil", "Small Money Potion"}, function() return Options.autoCashBuy.Value end)
                end)
            end
            wait(1)
        end
    end)
    Tabs.Shop:AddToggle("AutoBuyAura", {Title = "⭐ Auto Buy Aura", Default = false}):OnChanged(function()
        if Options.AutoBuyAura.Value then
            spawn(function()
                while Options.AutoBuyAura.Value do
                    game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.AuraService.RF.Buy:InvokeServer()
                    wait(1)
                end
            end)
        end
    end)
    Tabs.Shop:AddToggle("AutoBuyPose", {Title = "🧍‍♂️ Auto Buy Pose", Default = false}):OnChanged(function()
        if Options.AutoBuyPose.Value then
            spawn(function()
                while Options.AutoBuyPose.Value do
                    game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PoseService.RF.Buy:InvokeServer()
                    wait(1)
                end
            end)
        end
    end)
    Tabs.Shop:AddSection("Auto Cosmetics")
    Tabs.Shop:AddToggle("AutoAlter", {Title = "🔄 Auto Alter", Default = false}):OnChanged(function()
        if Options.AutoAlter.Value then
            spawn(function()
                while Options.AutoAlter.Value do
                    local textLabel = player.PlayerGui.Frames.Stats.Main.MuscleList.FullBody.Buy.TextLabel
                    if textLabel and textLabel.Visible and string.find(textLabel.Text, "Buy") then
                        game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.CharacterService.RF.NextAlter:InvokeServer()
                    end
                    wait(1)
                end
            end)
        end
    end)
    Tabs.Shop:AddToggle("AutoRollAura", {Title = "✨ Auto Roll Aura", Default = false}):OnChanged(function()
        if Options.AutoRollAura.Value then
            spawn(function()
                while Options.AutoRollAura.Value do
                    game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.AuraService.RF.Spin:InvokeServer()
                    wait(1)
                end
            end)
        end
    end)
    Tabs.Shop:AddToggle("AutoRollPose", {Title = "🤸 Auto Roll Pose", Default = false}):OnChanged(function()
        if Options.AutoRollPose.Value then
            spawn(function()
                while Options.AutoRollPose.Value do
                    game:GetService("ReplicatedStorage").common.packages._Index["sleitnick_knit@1.5.1"].knit.Services.PoseService.RF.Spin:InvokeServer()
                    wait(1)
                end
            end)
        end
    end)
end

addMainTab()
addWebhookSettings()
addStats()
addTrainingTab()
addWorkoutTab()
addShopTab()

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("GymLeague")
SaveManager:SetFolder("GymLeague/cfg")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)
Fluent:Notify({Title = "Gym League", Content = "The script has been loaded.", Duration = 8})
SaveManager:LoadAutoloadConfig()

spawn(function()
    while true do
        if Options.WalkSpeed then
            player.Character.Humanoid.WalkSpeed = Options.WalkSpeed.Value
        end
        wait(1)
    end
end)