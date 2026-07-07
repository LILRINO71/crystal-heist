-- PlantMenu.luau
-- Client-side pedestal interactions on YOUR plot. ClickDetector events also
-- fire on the client, so we listen locally: an empty pedestal opens the
-- shard-picking menu (planting needs a choice, so it goes through the Plant
-- remote); a growing crystal gives instant charge feedback (the server
-- handles the actual charge through its own ClickDetector connection).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local UI = require(script.Parent.UI)
local Effects = require(script.Parent.Effects)

local PlantMenu = {}

local player = Players.LocalPlayer
local selectedSlot = nil
local rowButtons = {} -- [shardKey] = { button, row }

local function coins(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins")
	return value and value.Value or 0
end

-- ============================== THE MENU ==============================

local function buildWindow()
	local content = UI.window("PlantMenu", "🌱 Plant a Shard", UDim2.fromOffset(480, 440))

	local list = UI.create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for index, shard in Config.Shards do
		local row = UI.create("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, 64),
			BackgroundColor3 = UI.Palette.panelLight,
			Parent = list,
		}, { UI.corner(10) })

		UI.create("Frame", {
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = shard.color,
			Parent = row,
		}, { UI.corner(8) })

		UI.create("TextLabel", {
			Position = UDim2.fromOffset(60, 8),
			Size = UDim2.new(1, -190, 0, 26),
			BackgroundTransparency = 1,
			Text = shard.name .. (shard.vipOnly and " 🌈 (Lucky pass)" or ""),
			TextColor3 = UI.Palette.text,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 19 }) })

		UI.create("TextLabel", {
			Position = UDim2.fromOffset(60, 36),
			Size = UDim2.new(1, -190, 0, 20),
			BackgroundTransparency = 1,
			Text = `🪙 {Formulas.abbreviate(shard.cost)}  •  ⏳ {Formulas.formatTime(shard.growTime)}  •  💰 {Formulas.abbreviate(shard.value)}`,
			TextColor3 = UI.Palette.subtext,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 14 }) })

		local plantButton = UI.button({
			Text = "PLANT",
			Size = UDim2.fromOffset(100, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Parent = row,
		})
		plantButton.Activated:Connect(function()
			if selectedSlot then
				ReplicatedStorage.Remotes.Plant:FireServer(selectedSlot, shard.key)
				UI.toggleWindow("PlantMenu") -- close after planting
			end
		end)
		rowButtons[shard.key] = plantButton
	end
end

-- Refresh affordability / VIP lock colors each time the menu opens.
local function refreshRows()
	local balance = coins()
	for key, button in rowButtons do
		local shard = Config.getShard(key)
		local vipLocked = shard.vipOnly and player:GetAttribute("OwnsLucky") ~= true
		if vipLocked then
			button.Text = "🔒 VIP"
			button.BackgroundColor3 = UI.Palette.locked
		elseif balance < shard.cost then
			button.Text = "PLANT"
			button.BackgroundColor3 = UI.Palette.locked
		else
			button.Text = "PLANT"
			button.BackgroundColor3 = UI.Palette.accent
		end
	end
end

-- ============================== PEDESTAL CLICKS ==============================

local function hookPedestal(pedestal: Instance)
	if not pedestal:IsA("BasePart") or not pedestal.Name:match("^Pedestal") then
		return
	end
	local clicker = pedestal:FindFirstChildOfClass("ClickDetector")
	if not clicker then
		return
	end
	clicker.MouseClick:Connect(function()
		-- This local connection fires only for OUR clicks.
		if pedestal:GetAttribute("PlotIndex") ~= player:GetAttribute("PlotIndex") then
			return
		end
		local state = pedestal:GetAttribute("State")
		if state == "Empty" then
			selectedSlot = pedestal:GetAttribute("Slot")
			refreshRows()
			UI.openWindow("PlantMenu")
		elseif state == "Growing" then
			Effects.chargePop()
		end
	end)
end

function PlantMenu.build()
	buildWindow()

	task.spawn(function()
		local container = workspace:WaitForChild("Plots", 30)
		if not container then
			return
		end
		for _, descendant in container:GetDescendants() do
			hookPedestal(descendant)
		end
		container.DescendantAdded:Connect(hookPedestal)
	end)
end

return PlantMenu
