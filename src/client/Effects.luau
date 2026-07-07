-- Effects.luau
-- Juice: harvest/steal payout popups, toast notifications (success / error /
-- 🚨 alarm), server-wide announcements, click feedback, and the purple
-- screen tint while a Void Surge is active. Sounds are built-in rbxasset
-- files, no uploads needed.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local UI = require(script.Parent.UI)

local Effects = {}

local gui: ScreenGui
local toastContainer: Frame
local rng = Random.new()

local function makeSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local clickSound = makeSound("rbxasset://sounds/swoosh.wav", 0.3)
local successSound = makeSound("rbxasset://sounds/electronicpingshort.wav", 0.5)
local errorSound = makeSound("rbxasset://sounds/snap.mp3", 0.5)

-- ============================== POPUPS ==============================

function Effects.payoutPopup(value: number, mutationKey: string?)
	successSound.PlaybackSpeed = rng:NextNumber(0.95, 1.1)
	successSound:Play()

	local mutation = Config.getMutation(mutationKey)
	local popup = UI.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, rng:NextInteger(-100, 100), 0.55, rng:NextInteger(-20, 20)),
		Size = UDim2.fromOffset(320, mutation and 56 or 40),
		BackgroundTransparency = 1,
		Text = mutation and `{mutation.key}! +{Formulas.abbreviate(value)} 🪙` or `+{Formulas.abbreviate(value)} 🪙`,
		TextColor3 = mutation and mutation.color or UI.Palette.accent,
		Font = Enum.Font.FredokaOne,
		TextSize = mutation and 38 or 26,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})

	local tween = TweenService:Create(popup, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = popup.Position + UDim2.fromOffset(0, -100),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Connect(function()
		popup:Destroy()
	end)
	tween:Play()
end

-- Local feedback when you charge one of your crystals.
function Effects.chargePop()
	clickSound.PlaybackSpeed = rng:NextNumber(0.9, 1.2)
	clickSound:Play()

	local popup = UI.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, rng:NextInteger(-60, 60), 0.62, 0),
		Size = UDim2.fromOffset(140, 30),
		BackgroundTransparency = 1,
		Text = `⚡ +{Config.Charge.BoostPerClick}s`,
		TextColor3 = UI.Palette.primary,
		Font = Enum.Font.FredokaOne,
		TextSize = 22,
		TextStrokeTransparency = 0.4,
		Parent = gui,
	})
	local tween = TweenService:Create(popup, TweenInfo.new(0.6), {
		Position = popup.Position + UDim2.fromOffset(0, -50),
		TextTransparency = 1,
	})
	tween.Completed:Connect(function()
		popup:Destroy()
	end)
	tween:Play()
end

-- ============================== TOASTS ==============================

local KIND_STYLE = {
	success = { color = Color3.fromRGB(90, 210, 120), duration = 2.5 },
	error = { color = Color3.fromRGB(235, 87, 87), duration = 2.5 },
	alarm = { color = Color3.fromRGB(255, 60, 60), duration = 5 },
	announce = { color = Color3.fromRGB(168, 120, 255), duration = 4.5 },
}

function Effects.toast(kind: string, message: string)
	local style = KIND_STYLE[kind] or KIND_STYLE.success
	if kind == "error" or kind == "alarm" then
		errorSound:Play()
		if kind == "alarm" then
			task.delay(0.18, function()
				errorSound:Play()
			end)
		end
	else
		successSound:Play()
	end

	local toast = UI.create("Frame", {
		Size = UDim2.fromOffset(400, 46),
		BackgroundColor3 = style.color,
		BackgroundTransparency = 0.08,
		Parent = toastContainer,
	}, {
		UI.corner(12),
		UI.stroke(Color3.new(0, 0, 0), 2),
		UI.create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = message,
			TextColor3 = Color3.fromRGB(25, 22, 35),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
		}, {
			UI.create("UITextSizeConstraint", { MaxTextSize = 17 }),
			UI.padding(8),
		}),
	})

	task.delay(style.duration, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		local label = toast:FindFirstChildOfClass("TextLabel")
		if label then
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		fade.Completed:Connect(function()
			toast:Destroy()
		end)
		fade:Play()
	end)
end

-- ============================== VOID SURGE TINT ==============================

local function watchSurge()
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "VoidSurgeTint"
	correction.TintColor = Color3.fromRGB(255, 255, 255)
	correction.Parent = Lighting

	local function apply()
		local active = workspace:GetAttribute("VoidSurge") == true
		TweenService:Create(correction, TweenInfo.new(1.2), {
			TintColor = active and Color3.fromRGB(216, 180, 255) or Color3.fromRGB(255, 255, 255),
			Saturation = active and 0.15 or 0,
		}):Play()
	end
	workspace:GetAttributeChangedSignal("VoidSurge"):Connect(apply)
	apply()
end

-- ============================== START ==============================

function Effects.start()
	gui = UI.create("ScreenGui", {
		Name = "Effects",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	toastContainer = UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(400, 320),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Notify").OnClientEvent:Connect(Effects.toast)
	remotes:WaitForChild("Announce").OnClientEvent:Connect(function(message)
		Effects.toast("announce", message)
	end)
	remotes:WaitForChild("HarvestFx").OnClientEvent:Connect(Effects.payoutPopup)

	watchSurge()
end

return Effects
