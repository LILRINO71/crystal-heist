-- Formulas.luau
-- Pure functions shared by the server (authoritative math) and the client
-- (display). No state, no side effects.

local Config = require(script.Parent.Config)

local Formulas = {}

-- How grown is a crystal, 0..1. boost = accumulated charge seconds.
function Formulas.progress(plantedAt: number, boost: number, growTime: number, now: number): number
	local elapsed = (now - plantedAt) + boost
	return math.clamp(elapsed / math.max(growTime, 1), 0, 1)
end

function Formulas.secondsRemaining(plantedAt: number, boost: number, growTime: number, now: number): number
	return math.max(0, growTime - ((now - plantedAt) + boost))
end

function Formulas.harvestValue(shardValue: number, mutationMultiplier: number, hasDoubleCoins: boolean?): number
	local value = shardValue * mutationMultiplier
	if hasDoubleCoins then
		value *= 2
	end
	return math.floor(value + 0.5)
end

-- Roll a mutation at plant time. luckMultiplier scales every chance (VIP = 2).
-- Returns a mutation key or nil. Walks rarest-first so rare rolls win.
function Formulas.rollMutation(rng: Random, luckMultiplier: number): string?
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, mutation in Config.Mutations do
		cumulative += mutation.chance * luckMultiplier
		if roll < cumulative then
			return mutation.key
		end
	end
	return nil
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234567 -> "1.23M", 950 -> "950"
function Formulas.abbreviate(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 1000 ^ index
	local formatted
	if scaled >= 100 then
		formatted = string.format("%.0f", scaled)
	elseif scaled >= 10 then
		formatted = string.format("%.1f", scaled)
	else
		formatted = string.format("%.2f", scaled)
	end
	return formatted .. SUFFIXES[index + 1]
end

-- 40 -> "40s", 720 -> "12m", 36000 -> "10h"
function Formulas.formatTime(seconds: number): string
	seconds = math.floor(seconds)
	if seconds < 60 then
		return `{seconds}s`
	elseif seconds < 3600 then
		local minutes = seconds / 60
		return minutes % 1 == 0 and `{minutes}m` or string.format("%.1fm", minutes)
	end
	local hours = seconds / 3600
	return hours % 1 == 0 and `{hours}h` or string.format("%.1fh", hours)
end

return Formulas
