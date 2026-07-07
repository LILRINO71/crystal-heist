-- ShopUi.luau
-- Shop window with three tabs: Shards (info — planting happens at your
-- pedestals), Defense (Guard Turret tiers + Plot Shield), and Robux
-- (gamepasses + dev products). All purchases are validated server-side.
-- Clicking the Shard Shop stall at the hub also opens this window.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local UI = require(script.Parent.UI)

local ShopUi = {}

local player = Players.LocalPlayer

local function scrollList(parent: Frame): ScrollingFrame
	return UI.create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function row(parent: ScrollingFrame, order: number, height: number): Frame
	return UI.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = UI.Palette.panelLight,
		Parent = parent,
	}, { UI.corner(10) })
end

local function titleLabel(parent: Frame, text: string, color: Color3, position: UDim2, size: UDim2, maxSize: number)
	return UI.create("TextLabel", {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, { UI.create("UITextSizeConstraint", { MaxTextSize = maxSize }) })
end

local function subLabel(parent: Frame, text: string, position: UDim2, size: UDim2, maxSize: number)
	return UI.create("TextLabel", {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UI.Palette.subtext,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, { UI.create("UITextSizeConstraint", { MaxTextSize = maxSize }) })
end

-- ============================== SHARDS TAB ==============================

local function buildShardsTab(parent: Frame)
	local list = scrollList(parent)

	UI.create("TextLabel", {
		LayoutOrder = 0,
		Size = UDim2.new(1, -8, 0, 34),
		BackgroundTransparency = 1,
		Text = "Walk to YOUR plot and click a ➕ pedestal to plant!",
		TextColor3 = UI.Palette.accent,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Parent = list,
	}, { UI.create("UITextSizeConstraint", { MaxTextSize = 15 }) })

	for index, shard in Config.Shards do
		local container = row(list, index, 60)
		UI.create("Frame", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = shard.color,
			Parent = container,
		}, { UI.corner(8) })
		titleLabel(
			container,
			shard.name .. (shard.vipOnly and " 🌈 (Lucky pass)" or ""),
			UI.Palette.text,
			UDim2.fromOffset(60, 6),
			UDim2.new(1, -70, 0, 26),
			18
		)
		subLabel(
			container,
			`🪙 {Formulas.abbreviate(shard.cost)}  •  ⏳ {Formulas.formatTime(shard.growTime)}  •  💰 sells ~{Formulas.abbreviate(shard.value)}`,
			UDim2.fromOffset(60, 34),
			UDim2.new(1, -70, 0, 20),
			14
		)
	end
end

-- ============================== DEFENSE TAB ==============================

local function buildDefenseTab(parent: Frame)
	local list = scrollList(parent)

	UI.create("TextLabel", {
		LayoutOrder = 0,
		Size = UDim2.new(1, -8, 0, 48),
		BackgroundTransparency = 1,
		Text = "Thieves can grab your ✨ READY crystals! Harvest fast, click thieves to zap them, or automate it:",
		TextColor3 = UI.Palette.subtext,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
		Parent = list,
	}, { UI.create("UITextSizeConstraint", { MaxTextSize = 14 }) })

	-- Guard Turret card.
	local turretRow = row(list, 1, 76)
	local turretTitle = titleLabel(turretRow, "🗼 Guard Turret", UI.Palette.primary, UDim2.fromOffset(12, 8), UDim2.new(1, -140, 0, 26), 20)
	local turretDesc = subLabel(turretRow, "", UDim2.fromOffset(12, 38), UDim2.new(1, -140, 0, 32), 13)
	turretDesc.TextWrapped = true

	local turretButton = UI.button({
		Text = "BUY",
		Size = UDim2.fromOffset(104, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Parent = turretRow,
	})
	turretButton.Activated:Connect(function()
		ReplicatedStorage.Remotes.BuyTurret:FireServer()
	end)

	local function refreshTurret()
		local tier = player:GetAttribute("TurretTier") or 0
		local nextCost = Config.Turret.Costs[tier + 1]
		turretTitle.Text = tier > 0 and `🗼 Guard Turret — Tier {tier}` or "🗼 Guard Turret"
		if nextCost then
			local interval = Config.Turret.Intervals[tier + 1]
			turretDesc.Text = `Auto-zaps thieves still on your plot every {interval}s. Tier {tier + 1}: {Formulas.abbreviate(nextCost)} 🪙`
			turretButton.Text = "BUY"
			turretButton.BackgroundColor3 = UI.Palette.accent
			turretButton.Active = true
		else
			turretDesc.Text = "Maximum tier! Your plot is a fortress."
			turretButton.Text = "MAX"
			turretButton.BackgroundColor3 = UI.Palette.locked
			turretButton.Active = false
		end
	end
	player:GetAttributeChangedSignal("TurretTier"):Connect(refreshTurret)
	refreshTurret()

	-- Plot Shield product (only shown once its ID is configured).
	for _, product in Config.DevProducts do
		if product.type == "shield" and product.id ~= 0 then
			local shieldRow = row(list, 2, 64)
			titleLabel(shieldRow, "🛡️ " .. product.label, UI.Palette.text, UDim2.fromOffset(12, 8), UDim2.new(1, -140, 0, 26), 18)
			subLabel(shieldRow, "Robux. Total steal immunity while it lasts.", UDim2.fromOffset(12, 36), UDim2.new(1, -140, 0, 20), 13)
			UI.button({
				Text = "BUY",
				Size = UDim2.fromOffset(104, 40),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Color = UI.Palette.good,
				Parent = shieldRow,
			}).Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.id)
			end)
		end
	end
end

-- ============================== ROBUX TAB ==============================

local function buildRobuxTab(parent: Frame)
	local list = scrollList(parent)
	local order = 0
	local anyVisible = false

	local passOrder = { "DoubleCoins", "AutoCharge", "Lucky", "MasterThief" }
	for _, key in passOrder do
		local passId = Config.GamePasses[key]
		if passId == 0 then
			continue
		end
		anyVisible = true
		order += 1
		local info = Config.GamePassInfo[key]
		local container = row(list, order, 64)

		titleLabel(container, "👑 " .. info.title, UI.Palette.accent, UDim2.fromOffset(12, 8), UDim2.new(1, -130, 0, 26), 19)
		subLabel(container, info.desc, UDim2.fromOffset(12, 36), UDim2.new(1, -130, 0, 20), 13)

		local buyButton = UI.button({
			Text = "BUY",
			Size = UDim2.fromOffset(96, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Color = UI.Palette.good,
			Parent = container,
		})
		local function refreshOwned()
			if player:GetAttribute("Owns" .. key) == true then
				buyButton.Text = "OWNED"
				buyButton.BackgroundColor3 = UI.Palette.locked
				buyButton.Active = false
			end
		end
		buyButton.Activated:Connect(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		player:GetAttributeChangedSignal("Owns" .. key):Connect(refreshOwned)
		refreshOwned()
	end

	for _, product in Config.DevProducts do
		if product.id == 0 or product.type == "shield" then
			continue -- shield lives in the Defense tab
		end
		anyVisible = true
		order += 1
		local container = row(list, order, 56)
		titleLabel(container, product.label, UI.Palette.text, UDim2.fromOffset(12, 0), UDim2.new(1, -130, 1, 0), 18)
		UI.button({
			Text = "BUY",
			Size = UDim2.fromOffset(96, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Color = UI.Palette.good,
			Parent = container,
		}).Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(player, product.id)
		end)
	end

	if not anyVisible then
		UI.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 80),
			BackgroundTransparency = 1,
			Text = "Robux shop coming soon! 👀",
			TextColor3 = UI.Palette.subtext,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			Parent = list,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 22 }) })
	end
end

-- ============================== WINDOW ==============================

function ShopUi.build()
	local content = UI.window("Shop", "🛒 Shop", UDim2.fromOffset(500, 460))

	local tabBar = UI.create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = content,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
		}),
	})

	local pages = UI.create("Frame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		Parent = content,
	})

	local pageFrames = {}
	local tabButtons = {}
	local tabs = {
		{ key = "Shards", label = "💎 Shards", build = buildShardsTab },
		{ key = "Defense", label = "🛡️ Defense", build = buildDefenseTab },
		{ key = "Robux", label = "👑 Robux", build = buildRobuxTab },
	}

	local function selectTab(selectedKey: string)
		for key, frame in pageFrames do
			frame.Visible = key == selectedKey
			local button = tabButtons[key]
			button.BackgroundColor3 = key == selectedKey and UI.Palette.accent or UI.Palette.panelLight
			button.TextColor3 = key == selectedKey and Color3.fromRGB(28, 24, 40) or UI.Palette.text
		end
	end

	for i, tab in tabs do
		local frame = UI.create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = i == 1,
			Parent = pages,
		})
		tab.build(frame)
		pageFrames[tab.key] = frame

		local button = UI.button({
			Text = tab.label,
			Size = UDim2.fromOffset(140, 40),
			LayoutOrder = i,
			Color = i == 1 and UI.Palette.accent or UI.Palette.panelLight,
			TextColor = i == 1 and Color3.fromRGB(28, 24, 40) or UI.Palette.text,
			Parent = tabBar,
		})
		button.Activated:Connect(function()
			selectTab(tab.key)
		end)
		tabButtons[tab.key] = button
	end

	-- Clicking the Shard Shop stall at the hub opens this window too.
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		if not map then
			return
		end
		for _, descendant in map:GetDescendants() do
			if descendant:GetAttribute("OpensShop") then
				local clicker = descendant:FindFirstChildOfClass("ClickDetector")
				if clicker then
					clicker.MouseClick:Connect(function()
						UI.openWindow("Shop")
					end)
				end
			end
		end
	end)
end

return ShopUi
