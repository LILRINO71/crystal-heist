-- Instructions.luau
-- The "How to Play" window. Auto-opens the first time a player ever joins
-- (tracked in their save data via the TutorialSeen attribute) and can be
-- reopened any time from the HUD's ❓ button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.UI)

local Instructions = {}

local player = Players.LocalPlayer

local STEPS = {
	{ emoji = "💎", title = "GROW", text = "Click a ➕ pedestal on YOUR plot to plant a shard. Crystals grow in real time — even while you're offline!" },
	{ emoji = "⚡", title = "CHARGE", text = "Click your growing crystals to speed them up. More clicks = faster money." },
	{ emoji = "✨", title = "HARVEST", text = "Sparkling crystals are READY — click them (or HARVEST ALL) for coins. Rare mutations pay up to 300x!" },
	{ emoji = "🏴", title = "STEAL", text = "See a sparkling crystal on someone ELSE'S plot? Click it and SPRINT to the Black Market to bank half its value. You'll be slowed and marked red!" },
	{ emoji = "🛡️", title = "DEFEND", text = "Harvest fast! Click thieves to zap your crystal back, or buy a Guard Turret / coin Shield in the Shop's Defense tab." },
	{ emoji = "🌌", title = "VOID SURGE", text = "When the sky turns purple: 3x mutation luck and juiced heist payouts. GO CRAZY." },
}

function Instructions.build()
	local content = UI.window("HowToPlay", "❓ How to Play", UDim2.fromOffset(500, 470))

	local list = UI.create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -58),
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

	for index, step in STEPS do
		local rowFrame = UI.create("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, 62),
			BackgroundColor3 = UI.Palette.panelLight,
			Parent = list,
		}, { UI.corner(10) })

		UI.create("TextLabel", {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(46, 62),
			BackgroundTransparency = 1,
			Text = step.emoji,
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			Parent = rowFrame,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 30 }) })

		UI.create("TextLabel", {
			Position = UDim2.fromOffset(60, 6),
			Size = UDim2.new(1, -70, 0, 20),
			BackgroundTransparency = 1,
			Text = step.title,
			TextColor3 = UI.Palette.accent,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = rowFrame,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 17 }) })

		UI.create("TextLabel", {
			Position = UDim2.fromOffset(60, 26),
			Size = UDim2.new(1, -70, 0, 32),
			BackgroundTransparency = 1,
			Text = step.text,
			TextColor3 = UI.Palette.text,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = rowFrame,
		}, { UI.create("UITextSizeConstraint", { MaxTextSize = 13 }) })
	end

	local gotIt = UI.button({
		Text = "LET'S GET RICH 💎",
		Size = UDim2.fromOffset(240, 46),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		MaxTextSize = 22,
		Parent = content,
	})
	gotIt.Activated:Connect(function()
		ReplicatedStorage.Remotes.TutorialDone:FireServer()
		UI.toggleWindow("HowToPlay")
	end)

	-- Auto-open on a player's very first visit.
	task.spawn(function()
		-- TutorialSeen is set by the server once the profile loads.
		while player:GetAttribute("TutorialSeen") == nil do
			player.AttributeChanged:Wait()
		end
		if player:GetAttribute("TutorialSeen") == false then
			UI.openWindow("HowToPlay")
		end
	end)
end

return Instructions
