-- Config.luau
-- Every tunable number in the game: economy, shards, mutations, plots,
-- heists, defense, events, monetization. Change values here and the map,
-- shop, UI and formulas follow.

local Config = {}

Config.GameName = "Crystal Heist"
Config.StartingCoins = 50

-- ============================== PLOTS ==============================

Config.Plot = {
	Count = 8, -- plots arranged in a ring around the hub
	MaxSlots = 12, -- pedestals per plot
	StartSlots = 4,
	-- Cost to unlock each pedestal beyond the starting four.
	SlotCosts = {
		[5] = 400,
		[6] = 2_000,
		[7] = 8_000,
		[8] = 30_000,
		[9] = 120_000,
		[10] = 500_000,
		[11] = 2_000_000,
		[12] = 10_000_000,
	},
}

-- ============================== SHARDS (the "seeds") ==============================
-- Later shards: bigger payouts per cycle but much longer growth. Fast cycles
-- reward active players (charging); long cycles reward coming back later.

Config.Shards = {
	{ key = "Quartz", name = "Quartz Shard", cost = 10, growTime = 40, value = 22, color = Color3.fromRGB(245, 228, 240) },
	{ key = "Amethyst", name = "Amethyst Shard", cost = 60, growTime = 120, value = 150, color = Color3.fromRGB(170, 120, 230) },
	{ key = "Emerald", name = "Emerald Shard", cost = 300, growTime = 300, value = 850, color = Color3.fromRGB(80, 220, 130) },
	{ key = "Sapphire", name = "Sapphire Shard", cost = 1_500, growTime = 720, value = 4_800, color = Color3.fromRGB(70, 140, 255) },
	{ key = "Ruby", name = "Ruby Shard", cost = 8_000, growTime = 1_800, value = 28_000, color = Color3.fromRGB(255, 80, 90) },
	{ key = "Rainbow", name = "Rainbow Shard", cost = 25_000, growTime = 2_700, value = 220_000, color = Color3.fromRGB(255, 130, 200), vipOnly = true },
	{ key = "Obsidian", name = "Obsidian Shard", cost = 40_000, growTime = 5_400, value = 160_000, color = Color3.fromRGB(70, 58, 92) },
	{ key = "Starlight", name = "Starlight Shard", cost = 200_000, growTime = 14_400, value = 900_000, color = Color3.fromRGB(140, 240, 255) },
	{ key = "Voidstone", name = "Voidstone Shard", cost = 1_000_000, growTime = 36_000, value = 5_200_000, color = Color3.fromRGB(120, 40, 200) },
}

function Config.getShard(key: string)
	for index, shard in Config.Shards do
		if shard.key == key then
			return shard, index
		end
	end
	return nil, nil
end

-- ============================== MUTATIONS ==============================
-- Rolled secretly when a shard is planted, revealed when the crystal matures.
-- Ordered rarest-first; roll walks down the list. Chances are per-plant.

Config.Mutations = {
	{ key = "Celestial", chance = 0.0004, multiplier = 300, color = Color3.fromRGB(150, 245, 255), announce = true },
	{ key = "Prismatic", chance = 0.0035, multiplier = 60, color = Color3.fromRGB(255, 120, 255), announce = true },
	{ key = "Golden", chance = 0.02, multiplier = 12, color = Color3.fromRGB(255, 200, 50), announce = false },
	{ key = "Shiny", chance = 0.08, multiplier = 3, color = Color3.fromRGB(255, 255, 255), announce = false },
}

function Config.getMutation(key: string?)
	if not key then
		return nil
	end
	for _, mutation in Config.Mutations do
		if mutation.key == key then
			return mutation
		end
	end
	return nil
end

-- ============================== CHARGING ==============================
-- Clicking a growing crystal "charges" it: shaves seconds off its growth.
-- This is the active-play layer on top of the idle timers.

Config.Charge = {
	BoostPerClick = 6, -- seconds of growth added per click
	ClickCooldown = 2, -- per-crystal, enforced server-side
	AutoChargeInterval = 8, -- Auto Charge gamepass tick (applies BoostPerClick to every crystal)
}

-- ============================== PROTECTION & POTIONS ==============================
-- Coin-purchasable defense and luck: money protects your crystals, money
-- juices your mutation odds.

Config.Shield = {
	CoinCost = 2_500,
	Duration = 300, -- 5 minutes per purchase
	MaxRemaining = 600, -- can't stack a coin shield beyond 10 minutes
}

Config.Potions = {
	Luck = { cost = 5_000, multiplier = 3, plants = 10, maxPlants = 30 }, -- coins
	SuperLuck = { multiplier = 10, plants = 10 }, -- Robux dev product
}

-- ============================== HEISTS ==============================
-- Only READY crystals can be stolen. The thief carries the crystal over
-- their head (slowed + marked red for everyone) and must reach the Black
-- Market at the hub to bank a fraction of its value. The victim can chase
-- and click the thief to zap the crystal back onto its pedestal.

Config.Heist = {
	PayoutFraction = 0.5, -- thief banks this share of the crystal's value
	MasterThiefBonus = 0.25, -- Master Thief gamepass adds this to the fraction
	BaseWalkSpeed = 16,
	SpeedyBootsWalkSpeed = 22, -- with the Speedy Boots gamepass
	CarrySpeedBootsBonus = 3, -- Speedy Boots bonus while carrying
	CarryWalkSpeed = 11, -- slowed while carrying
	CarryWalkSpeedMasterThief = 13,
	CarryTimeout = 60, -- seconds before a carried crystal returns on its own
	ZapRange = 35, -- victim must be this close to zap the thief
	StealCooldown = 20, -- seconds a zapped/dropped thief must wait to steal again
	ShieldAfterTheft = 120, -- pity shield on the victim's plot after a successful steal
	JoinShield = 60, -- shield when a player spawns in
}

-- ============================== DEFENSE ==============================
-- A Guard Turret auto-zaps thieves who are still inside your plot with the
-- loot. Escape the plot before it fires and you're clear of the turret.

Config.Turret = {
	Costs = { 5_000, 75_000, 1_500_000 }, -- tier 1..3
	Intervals = { 6, 4, 2.5 }, -- seconds between zaps per tier
}

-- ============================== VOID SURGE EVENTS ==============================
-- Random server-wide frenzy windows: mutations and heists both spike.

Config.Surge = {
	MinGap = 480, -- seconds between surges (random in range)
	MaxGap = 720,
	Duration = 90,
	LuckMultiplier = 3, -- mutation odds multiplier while active
	SurgePayoutFraction = 0.75, -- replaces Heist.PayoutFraction while active
}

-- ============================== MONETIZATION ==============================
-- Fill the IDs in from the Creator Dashboard after publishing
-- (Creator Dashboard -> your experience -> Monetization -> Passes / Developer Products).
-- IDs of 0 hide the item; the game runs fine without them.

Config.GamePasses = {
	DoubleCoins = 0, -- suggested price: 199 R$
	AutoCharge = 0, -- suggested price: 349 R$
	Lucky = 0, -- suggested price: 499 R$
	MasterThief = 0, -- suggested price: 449 R$
	SpeedyBoots = 0, -- suggested price: 299 R$
}

Config.GamePassInfo = {
	DoubleCoins = { title = "2x Coins", desc = "Every harvest pays double, forever." },
	AutoCharge = { title = "Auto Charge", desc = "Your crystals charge themselves while you play." },
	Lucky = { title = "Lucky (VIP)", desc = "2x mutation odds + the exclusive Rainbow Shard." },
	MasterThief = { title = "Master Thief", desc = "Bank +25% more from heists and carry loot faster." },
	SpeedyBoots = { title = "Speedy Boots", desc = "+40% run speed forever. Escape with the loot — or chase thieves down." },
}

Config.DevProducts = {
	{ key = "SmallCoins", id = 0, type = "coins", amount = 5_000, label = "5K Coins" }, -- suggested: 49 R$
	{ key = "MediumCoins", id = 0, type = "coins", amount = 40_000, label = "40K Coins" }, -- suggested: 199 R$
	{ key = "LargeCoins", id = 0, type = "coins", amount = 300_000, label = "300K Coins" }, -- suggested: 799 R$
	{ key = "InstantGrow", id = 0, type = "instantGrow", amount = 0, label = "⚡ Instant Grow (finish ALL your crystals)" }, -- suggested: 99 R$
	{ key = "Shield30", id = 0, type = "shield", amount = 1_800, label = "🛡️ Plot Shield (30 minutes)" }, -- suggested: 79 R$
	{ key = "SuperLuckPotion", id = 0, type = "superLuck", amount = 0, label = "🧪 Super Luck Potion (10x luck, next 10 plants)" }, -- suggested: 149 R$
}

return Config
