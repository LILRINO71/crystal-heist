-- Data.luau
-- Player data: loading with retries, session cache, leaderstats, autosave,
-- and graceful fallback to in-memory data when DataStores are unavailable
-- (which is normal in unpublished Studio playtests).
--
-- Profile shape (crystals is keyed by tostring(slot) because DataStores
-- reject sparse numeric-keyed tables):
--   { version, coins, totalEarned, grown, stolen, unlockedSlots, turretTier,
--     shieldUntil, tutorialSeen,
--     crystals = { ["3"] = { shard, plantedAt, boost, mutation? } } }

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DATASTORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 60
local LOAD_RETRIES = 3

local Data = {}

local profiles = {} -- [Player] = profile table
local store = nil -- nil when DataStores are unavailable
local loadedCallbacks = {} -- fired as (player, profile) once a profile is ready

local function defaultProfile()
	return {
		version = 1,
		coins = Config.StartingCoins,
		totalEarned = 0,
		grown = 0,
		stolen = 0,
		unlockedSlots = Config.Plot.StartSlots,
		turretTier = 0,
		shieldUntil = 0,
		tutorialSeen = false,
		crystals = {},
	}
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- Push the profile into leaderstats and attributes (both replicate to clients).
function Data.sync(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	stats.Coins.Value = profile.coins
	stats.Grown.Value = profile.grown
	stats.Stolen.Value = profile.stolen
	player:SetAttribute("TutorialSeen", profile.tutorialSeen)
	player:SetAttribute("UnlockedSlots", profile.unlockedSlots)
	player:SetAttribute("TurretTier", profile.turretTier)
end

local function loadProfile(player: Player)
	local data
	if store then
		for attempt = 1, LOAD_RETRIES do
			local ok, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if ok then
				data = result
				break
			end
			warn(`[Data] Load attempt {attempt} failed for {player.Name}: {result}`)
			task.wait(2 ^ attempt)
		end
	end
	data = data or defaultProfile()
	-- Fill in any fields added since this profile was saved.
	for key, value in defaultProfile() do
		if data[key] == nil then
			data[key] = value
		end
	end
	return data
end

local function saveProfile(player: Player)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function()
			return profile
		end)
	end)
	if not ok then
		warn(`[Data] Save failed for {player.Name}: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not player.Parent then
		return -- left while loading
	end
	profiles[player] = profile

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, statName in { "Coins", "Grown", "Stolen" } do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Parent = stats
	end
	stats.Parent = player

	Data.sync(player)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

-- ============================== PUBLIC API ==============================

function Data.get(player: Player)
	return profiles[player]
end

-- Register for "profile is ready" (replays for profiles already loaded).
function Data.onLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Coins from purchases/gifts; does NOT count toward the earnings leaderboard.
function Data.addCoins(player: Player, amount: number)
	local profile = profiles[player]
	if profile then
		profile.coins += amount
		Data.sync(player)
	end
end

-- Coins from harvesting your own crystals.
function Data.recordHarvest(player: Player, value: number)
	local profile = profiles[player]
	if profile then
		profile.coins += value
		profile.totalEarned += value
		profile.grown += 1
		Data.sync(player)
	end
end

-- Coins from banking a stolen crystal at the Black Market.
function Data.recordSteal(player: Player, value: number)
	local profile = profiles[player]
	if profile then
		profile.coins += value
		profile.totalEarned += value
		profile.stolen += 1
		Data.sync(player)
	end
end

function Data.trySpendCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.coins < amount then
		return false
	end
	profile.coins -= amount
	Data.sync(player)
	return true
end

function Data.setTutorialSeen(player: Player)
	local profile = profiles[player]
	if profile then
		profile.tutorialSeen = true
		Data.sync(player)
	end
end

function Data.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStores unavailable — using in-memory data. "
			.. "This is expected in unpublished Studio playtests.")
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveProfile(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				saveProfile(player)
			end
		end
	end)
end

return Data
