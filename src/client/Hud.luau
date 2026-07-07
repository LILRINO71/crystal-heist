-- Hud.luau
-- The always-visible interface: stat pills (Coins / Grown / Stolen), the
-- HARVEST ALL button, and the menu buttons (Shop, How to Play).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local UI = require(script.Parent.UI)

local Hud = {}

local player = Players.LocalPlayer

local function statPill(parent: Frame, order: number, emoji: string, statName: string)
	local label = UI.create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = emoji .. " 0",
		TextColor3 = UI.Palette.text,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
	}, {
		UI.create("UITextSizeConstraint", { MaxTextSize = 22 }),
	})

	UI.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(150, 44),
		BackgroundColor3 = UI.Palette.panel,
		BackgroundTransparency = 0.15,
		Parent = parent,
	}, {
		UI.corner(22),
		UI.stroke(UI.Palette.panelLight, 2),
		label,
	})

	-- leaderstats can arrive after the HUD; bind whenever it shows up.
	task.spawn(function()
		local value = player:WaitForChild("leaderstats"):WaitForChild(statName)
		local function update()
			label.Text = `{emoji} {Formulas.abbreviate(value.Value)}`
		end
		value.Changed:Connect(update)
		update()
	end)
end

function Hud.start()
	local gui = UI.create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- ============================== STAT BAR ==============================
	local bar = UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(480, 44),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})
	statPill(bar, 1, "🪙", "Coins")
	statPill(bar, 2, "💎", "Grown")
	statPill(bar, 3, "🏴", "Stolen")

	-- ============================== HARVEST ALL ==============================
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	UI.button({
		Text = "✨ HARVEST ALL",
		Size = UDim2.fromOffset(210, 56),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Color = UI.Palette.accent,
		MaxTextSize = 24,
		CornerRadius = 16,
		Parent = gui,
	}).Activated:Connect(function()
		remotes:WaitForChild("HarvestAll"):FireServer()
	end)

	-- ============================== MENU BUTTONS ==============================
	local menu = UI.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(130, 160),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	UI.button({
		Text = "🛒 Shop",
		Size = UDim2.fromOffset(130, 46),
		LayoutOrder = 1,
		Color = UI.Palette.panelLight,
		TextColor = UI.Palette.text,
		Parent = menu,
	}).Activated:Connect(function()
		UI.toggleWindow("Shop")
	end)

	UI.button({
		Text = "❓ How to Play",
		Size = UDim2.fromOffset(130, 46),
		LayoutOrder = 2,
		Color = UI.Palette.panelLight,
		TextColor = UI.Palette.text,
		Parent = menu,
	}).Activated:Connect(function()
		UI.toggleWindow("HowToPlay")
	end)
end

return Hud
