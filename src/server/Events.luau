-- Events.luau
-- The Void Surge: a random server-wide frenzy window where mutation odds
-- triple and heists pay out more. Announced to everyone; the client reads
-- the workspace "VoidSurge" attribute to tint the world purple.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Events = {}

local surgeActive = false
local rng = Random.new()

function Events.isSurgeActive(): boolean
	return surgeActive
end

-- Multiplier applied to mutation odds when planting.
function Events.luckMultiplier(): number
	return surgeActive and Config.Surge.LuckMultiplier or 1
end

-- Fraction of a stolen crystal's value the thief banks.
function Events.payoutFraction(): number
	return surgeActive and Config.Surge.SurgePayoutFraction or Config.Heist.PayoutFraction
end

function Events.start()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Surge.MinGap, Config.Surge.MaxGap))

			surgeActive = true
			workspace:SetAttribute("VoidSurge", true)
			ReplicatedStorage.Remotes.Announce:FireAllClients(
				`🌌 VOID SURGE! {Config.Surge.LuckMultiplier}x mutation luck and juiced heist payouts for {Config.Surge.Duration} seconds!`
			)

			task.wait(Config.Surge.Duration)

			surgeActive = false
			workspace:SetAttribute("VoidSurge", false)
			ReplicatedStorage.Remotes.Announce:FireAllClients("The Void Surge fades away...")
		end
	end)
end

return Events
