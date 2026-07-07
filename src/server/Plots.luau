-- Plots.luau
-- The heart of the game. Builds the 8 player plots, assigns them on join,
-- rebuilds saved crystals, and runs the whole crystal lifecycle:
--
--   plant (remote, costs coins, mutation rolled secretly)
--     -> grow (real time via os.time timestamps, so it works offline too)
--     -> charge (click a growing crystal to shave seconds off)
--     -> ready (neon + sparkles + value billboard)
--     -> harvest (click; pays coins, rare mutations announced to everyone)
--
-- Ready crystals on SOMEONE ELSE'S plot can be stolen: that click is handed
-- to the Heist module via the steal handler. Plots also owns the defensive
-- layer: plot shields (join/pity/purchased) and the Guard Turret.
--
-- Clicks arrive through per-pedestal ClickDetectors CONNECTED ON THE SERVER,
-- so charging/harvesting/stealing can't be spoofed at all. Planting needs a
-- shard choice, so it comes through a remote and is fully re-validated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local PLOT_RING_RADIUS = 120
local PLOT_SIZE = 48
local GROWTH_TICK = 3
local CLICK_RANGE = 45

-- Pedestal grid: 4 columns x 3 rows, row-major, front row (toward hub) last.
local SLOT_XS = { -16.5, -5.5, 5.5, 16.5 }
local SLOT_ZS = { 14, 0, -14 } -- +Z is away from the hub (plots face the hub)

local Plots = {}

local Data, Monetization, Events
local rng = Random.new()
local stealHandler = nil -- set by Heist via Plots.setStealHandler

-- plots[index] = { platform, cframe, pedestals = {slot -> Part},
--                  billboards = {slot -> TextLabel}, nameplate = TextLabel,
--                  shieldDome = Part, turret = Model?, folder = Folder,
--                  owner = Player?, crystals = {slot -> runtime},
--                  carried = {slot -> true} }
-- runtime = { model, ready = bool, lastCharge = number }
local plots = {}
local plotOfPlayer = {} -- [Player] = plot index
local lastTeleport = {} -- [Player] = os.clock() of last home teleport

-- ============================== HELPERS ==============================

local function remotes()
	return ReplicatedStorage.Remotes
end

local function notify(player: Player, kind: string, message: string)
	remotes().Notify:FireClient(player, kind, message)
end

local function slotOffset(slot: number): Vector3
	local column = (slot - 1) % 4 + 1
	local row = math.floor((slot - 1) / 4) + 1
	return Vector3.new(SLOT_XS[column], 0, SLOT_ZS[row])
end

local function crystalOf(profile, slot: number)
	return profile.crystals[tostring(slot)]
end

local function growTimeOf(saved): number
	local shard = Config.getShard(saved.shard)
	return shard and shard.growTime or 60
end

local function progressOf(saved): number
	return Formulas.progress(saved.plantedAt, saved.boost, growTimeOf(saved), os.time())
end

-- ============================== CRYSTAL VISUALS ==============================

local function buildCrystalModel(pedestal: Part, shardKey: string): Model?
	local shard, shardIndex = Config.getShard(shardKey)
	if not shard then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Crystal"

	local scale = 1 + (shardIndex :: number) * 0.12
	local top = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2, 0)
	local shapeRng = Random.new(pedestal.Position.X * 31 + pedestal.Position.Z * 7)

	local function spike(size: Vector3, cframe: CFrame)
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = cframe
		part.Color = shard.color
		part.Material = Enum.Material.Glass
		part.Transparency = 0.15
		part.Reflectance = 0.15
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- clicks pass through to the pedestal's ClickDetector
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	-- Tall center spike (diamond cross-section), four tilted satellites.
	local centerHeight = 6.5 * scale
	local center = spike(
		Vector3.new(2 * scale, centerHeight, 2 * scale),
		CFrame.new(top + Vector3.new(0, centerHeight / 2, 0)) * CFrame.Angles(0, math.rad(45), 0)
	)
	for i = 1, 4 do
		local angle = math.rad(90 * i + shapeRng:NextNumber(-15, 15))
		local tilt = math.rad(shapeRng:NextNumber(18, 32))
		local height = shapeRng:NextNumber(2.8, 4.2) * scale
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 1.7 * scale
		spike(
			Vector3.new(1.1 * scale, height, 1.1 * scale),
			CFrame.new(top + out + Vector3.new(0, height / 2 - 0.3, 0))
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(0, math.rad(45), tilt)
		)
	end

	model.PrimaryPart = center
	-- Pivot at the base so ScaleTo makes crystals grow upward out of the pedestal.
	model.WorldPivot = CFrame.new(top)
	model.Parent = pedestal

	return model
end

local function decorateReadyCrystal(runtime, saved)
	local model = runtime.model
	local center = model and model.PrimaryPart
	if not center then
		return
	end
	local shard = Config.getShard(saved.shard)
	local mutation = Config.getMutation(saved.mutation)
	local auraColor = mutation and mutation.color or shard.color

	center.Material = Enum.Material.Neon
	center.Transparency = 0

	local light = Instance.new("PointLight")
	light.Color = auraColor
	light.Brightness = 2
	light.Range = 14
	light.Parent = center

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = auraColor
	sparkles.Parent = center

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(10, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	gui.MaxDistance = 200
	gui.AlwaysOnTop = true -- never clips into the crystal
	local value = Formulas.harvestValue(shard.value, mutation and mutation.multiplier or 1, false)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = mutation and `✨ {mutation.key} READY! ~{Formulas.abbreviate(value)} 🪙`
		or `✨ READY! ~{Formulas.abbreviate(value)} 🪙`
	label.TextColor3 = auraColor
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = center
end

-- ============================== PEDESTAL STATE ==============================

local function setPedestalState(plotIndex: number, slot: number, state: string)
	local plot = plots[plotIndex]
	local pedestal = plot.pedestals[slot]
	local billboard = plot.billboards[slot]
	pedestal:SetAttribute("State", state)

	local gui = billboard.Parent :: BillboardGui
	if state == "Empty" then
		gui.Enabled = true
		billboard.Text = "➕ Plant"
		billboard.TextColor3 = Color3.fromRGB(160, 240, 190)
	elseif state == "NextUnlock" then
		local profile = plot.owner and Data.get(plot.owner)
		local cost = profile and Config.Plot.SlotCosts[profile.unlockedSlots + 1] or 0
		gui.Enabled = true
		billboard.Text = `🔒 {Formulas.abbreviate(cost)} 🪙`
		billboard.TextColor3 = Color3.fromRGB(255, 200, 60)
	elseif state == "Locked" then
		gui.Enabled = true
		billboard.Text = "🔒"
		billboard.TextColor3 = Color3.fromRGB(150, 150, 165)
	elseif state == "Raided" then
		gui.Enabled = true
		billboard.Text = "🚨 STOLEN!"
		billboard.TextColor3 = Color3.fromRGB(255, 90, 90)
	else -- Growing / Ready / Idle: the crystal (or nothing) speaks for itself
		gui.Enabled = false
	end
end

-- Recompute every pedestal's state from the owner's profile.
local function refreshPedestals(plotIndex: number)
	local plot = plots[plotIndex]
	local owner = plot.owner
	local profile = owner and Data.get(owner)
	for slot = 1, Config.Plot.MaxSlots do
		if not profile then
			setPedestalState(plotIndex, slot, "Idle")
		elseif plot.carried[slot] then
			setPedestalState(plotIndex, slot, "Raided")
		elseif crystalOf(profile, slot) then
			local runtime = plot.crystals[slot]
			setPedestalState(plotIndex, slot, runtime and runtime.ready and "Ready" or "Growing")
		elseif slot <= profile.unlockedSlots then
			setPedestalState(plotIndex, slot, "Empty")
		elseif slot == profile.unlockedSlots + 1 then
			setPedestalState(plotIndex, slot, "NextUnlock")
		else
			setPedestalState(plotIndex, slot, "Locked")
		end
	end
end

-- ============================== LIFECYCLE ==============================

local function updateCrystal(plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	local owner = plot.owner
	local profile = owner and Data.get(owner)
	local saved = profile and crystalOf(profile, slot)
	local runtime = plot.crystals[slot]
	if not saved or not runtime or not runtime.model then
		return
	end

	local progress = progressOf(saved)
	if runtime.ready then
		return
	end
	runtime.model:ScaleTo(0.15 + 0.85 * progress)
	if progress >= 1 then
		runtime.ready = true
		decorateReadyCrystal(runtime, saved)
		setPedestalState(plotIndex, slot, "Ready")
	end
end

local function spawnCrystal(plotIndex: number, slot: number, saved)
	local plot = plots[plotIndex]
	local model = buildCrystalModel(plot.pedestals[slot], saved.shard)
	if not model then
		return
	end
	plot.crystals[slot] = { model = model, ready = false, lastCharge = 0 }
	updateCrystal(plotIndex, slot)
end

local function removeCrystalModel(plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	local runtime = plot.crystals[slot]
	if runtime and runtime.model then
		runtime.model:Destroy()
	end
	plot.crystals[slot] = nil
end

local function harvest(player: Player, plotIndex: number, slot: number): number?
	local profile = Data.get(player)
	local saved = profile and crystalOf(profile, slot)
	if not saved or progressOf(saved) < 1 then
		return nil
	end

	local shard = Config.getShard(saved.shard)
	local mutation = Config.getMutation(saved.mutation)
	local value = Formulas.harvestValue(
		shard.value,
		mutation and mutation.multiplier or 1,
		Monetization.ownsPass(player, "DoubleCoins")
	)

	if mutation then
		profile.mutationCounts[saved.mutation] = (profile.mutationCounts[saved.mutation] or 0) + 1
	end
	Data.recordHarvest(player, value)
	removeCrystalModel(plotIndex, slot)
	profile.crystals[tostring(slot)] = nil
	setPedestalState(plotIndex, slot, "Empty")

	remotes().HarvestFx:FireClient(player, value, saved.mutation)
	if mutation and mutation.announce then
		remotes().Announce:FireAllClients(
			`🌟 {player.DisplayName} grew a {mutation.key} {shard.name} worth {Formulas.abbreviate(value)} coins!`
		)
	end
	return value
end

local function charge(player: Player, plotIndex: number, slot: number)
	local profile = Data.get(player)
	local saved = profile and crystalOf(profile, slot)
	local runtime = plots[plotIndex].crystals[slot]
	if not saved or not runtime or runtime.ready then
		return
	end
	local now = os.clock()
	if now - runtime.lastCharge < Config.Charge.ClickCooldown * 0.9 then
		return
	end
	runtime.lastCharge = now
	saved.boost += Config.Charge.BoostPerClick
	updateCrystal(plotIndex, slot)
end

local function tryUnlockSlot(player: Player, plotIndex: number)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local nextSlot = profile.unlockedSlots + 1
	local cost = Config.Plot.SlotCosts[nextSlot]
	if not cost then
		return
	end
	if not Data.trySpendCoins(player, cost) then
		notify(player, "error", `Unlocking pedestal {nextSlot} costs {Formulas.abbreviate(cost)} coins!`)
		return
	end
	profile.unlockedSlots = nextSlot
	Data.sync(player)
	refreshPedestals(plotIndex)
	notify(player, "success", `Pedestal {nextSlot} unlocked! 🔓`)
end

local function onPedestalClick(player: Player, plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	local owner = plot.owner

	-- Clicking a READY crystal on someone else's plot is a steal attempt.
	if owner and owner ~= player then
		local runtime = plot.crystals[slot]
		if runtime and runtime.ready and stealHandler then
			stealHandler(player, plotIndex, slot)
		end
		return
	end
	if owner ~= player then
		return
	end

	local profile = Data.get(player)
	if not profile then
		return
	end

	if plot.carried[slot] then
		return -- being stolen right now; chase the thief instead!
	elseif crystalOf(profile, slot) then
		local runtime = plot.crystals[slot]
		if runtime and runtime.ready then
			harvest(player, plotIndex, slot)
		else
			charge(player, plotIndex, slot)
		end
	elseif slot > profile.unlockedSlots then
		tryUnlockSlot(player, plotIndex)
	end
	-- Empty + unlocked: the client opens the plant menu on its own click handler.
end

-- ============================== PLANTING (remote) ==============================

local function onPlant(player: Player, slot: any, shardKey: any)
	if type(slot) ~= "number" or slot % 1 ~= 0 or type(shardKey) ~= "string" then
		return
	end
	local plotIndex = plotOfPlayer[player]
	local profile = Data.get(player)
	if not plotIndex or not profile then
		return
	end
	if slot < 1 or slot > profile.unlockedSlots or crystalOf(profile, slot) then
		return
	end
	local shard = Config.getShard(shardKey)
	if not shard then
		return
	end
	if shard.vipOnly and not Monetization.ownsPass(player, "Lucky") then
		notify(player, "error", "Rainbow Shards need the Lucky gamepass! 🌈")
		return
	end
	if not Data.trySpendCoins(player, shard.cost) then
		notify(player, "error", `{shard.name} costs {Formulas.abbreviate(shard.cost)} coins!`)
		return
	end

	local luck = (Monetization.ownsPass(player, "Lucky") and 2 or 1) * Events.luckMultiplier()
	if profile.luckPlants > 0 then
		luck *= profile.luckMult
		profile.luckPlants -= 1
		Data.sync(player)
	end
	local saved = {
		shard = shardKey,
		plantedAt = os.time(),
		boost = 0,
		mutation = Formulas.rollMutation(rng, luck),
	}
	profile.crystals[tostring(slot)] = saved
	spawnCrystal(plotIndex, slot, saved)
	setPedestalState(plotIndex, slot, "Growing")
end

-- ============================== SHIELDS ==============================

function Plots.isShielded(plotIndex: number): boolean
	local plot = plots[plotIndex]
	local profile = plot and plot.owner and Data.get(plot.owner)
	return profile ~= nil and profile.shieldUntil > os.time()
end

function Plots.addShield(player: Player, seconds: number)
	local profile = Data.get(player)
	local plotIndex = plotOfPlayer[player]
	if not profile then
		return
	end
	profile.shieldUntil = math.max(profile.shieldUntil, os.time()) + seconds
	Data.sync(player)
	if plotIndex then
		plots[plotIndex].shieldDome.Transparency = 0.75
	end
end

-- ============================== TURRETS ==============================

local function buildTurret(plotIndex: number, tier: number)
	local plot = plots[plotIndex]
	if plot.turret then
		plot.turret:Destroy()
		plot.turret = nil
	end
	if tier < 1 then
		return
	end

	local tierColors = {
		Color3.fromRGB(205, 130, 70), -- bronze
		Color3.fromRGB(210, 215, 225), -- silver
		Color3.fromRGB(150, 90, 255), -- void
	}
	local color = tierColors[math.min(tier, #tierColors)]

	local model = Instance.new("Model")
	model.Name = "GuardTurret"

	local base = Instance.new("Part")
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(1.2, 5, 5)
	base.CFrame = plot.cframe * CFrame.new(20, 1.1, 20) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(70, 62, 92)
	base.Material = Enum.Material.Metal
	base.Anchored = true
	base.Parent = model

	local pole = Instance.new("Part")
	pole.Size = Vector3.new(1, 8, 1)
	pole.CFrame = plot.cframe * CFrame.new(20, 5.5, 20)
	pole.Color = Color3.fromRGB(70, 62, 92)
	pole.Material = Enum.Material.Metal
	pole.Anchored = true
	pole.Parent = model

	local orb = Instance.new("Part")
	orb.Name = "Orb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.6, 2.6, 2.6)
	orb.CFrame = plot.cframe * CFrame.new(20, 10.5, 20)
	orb.Color = color
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.Parent = model

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Parent = orb

	model.PrimaryPart = orb
	model.Parent = plot.folder
	plot.turret = model
end

local function onBuyTurret(player: Player)
	local profile = Data.get(player)
	local plotIndex = plotOfPlayer[player]
	if not profile or not plotIndex then
		return
	end
	local nextTier = profile.turretTier + 1
	local cost = Config.Turret.Costs[nextTier]
	if not cost then
		notify(player, "error", "Your Guard Turret is already max tier!")
		return
	end
	if not Data.trySpendCoins(player, cost) then
		notify(player, "error", `Turret tier {nextTier} costs {Formulas.abbreviate(cost)} coins!`)
		return
	end
	profile.turretTier = nextTier
	Data.sync(player)
	buildTurret(plotIndex, nextTier)
	notify(player, "success", `🗼 Guard Turret tier {nextTier} built! Thieves beware.`)
end

-- Zap visual: a brief neon beam from the turret orb to the target.
function Plots.fireTurretBeam(plotIndex: number, targetPosition: Vector3)
	local plot = plots[plotIndex]
	local turret = plot and plot.turret
	local orb = turret and turret.PrimaryPart
	if not orb then
		return
	end
	local from = orb.Position
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(0.4, 0.4, (from - targetPosition).Magnitude)
	beam.CFrame = CFrame.lookAt((from + targetPosition) / 2, targetPosition)
	beam.Color = orb.Color
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Parent = workspace
	Debris:AddItem(beam, 0.15)
end

-- ============================== PUBLIC API (used by Heist) ==============================

function Plots.getOwner(plotIndex: number): Player?
	local plot = plots[plotIndex]
	return plot and plot.owner
end

function Plots.getPlotIndexOf(player: Player): number?
	return plotOfPlayer[player]
end

function Plots.getSaved(owner: Player, slot: number)
	local profile = Data.get(owner)
	return profile and crystalOf(profile, slot)
end

function Plots.getTurretTier(plotIndex: number): number
	local plot = plots[plotIndex]
	local profile = plot and plot.owner and Data.get(plot.owner)
	return profile and profile.turretTier or 0
end

function Plots.plotContains(plotIndex: number, position: Vector3): boolean
	local plot = plots[plotIndex]
	if not plot then
		return false
	end
	local localPos = plot.cframe:PointToObjectSpace(position)
	return math.abs(localPos.X) <= PLOT_SIZE / 2 + 4
		and math.abs(localPos.Z) <= PLOT_SIZE / 2 + 4
		and math.abs(localPos.Y) < 40
end

-- A thief picked the crystal up: hide the model, mark the pedestal raided.
function Plots.beginCarry(plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	removeCrystalModel(plotIndex, slot)
	plot.carried[slot] = true
	setPedestalState(plotIndex, slot, "Raided")
end

-- The carry ended with the crystal returning (zap/drop/timeout/thief left).
function Plots.endCarryRestore(plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	plot.carried[slot] = nil
	local owner = plot.owner
	local saved = owner and Plots.getSaved(owner, slot)
	if saved then
		spawnCrystal(plotIndex, slot, saved)
		refreshPedestals(plotIndex)
	else
		setPedestalState(plotIndex, slot, owner and "Empty" or "Idle")
	end
end

-- The carry ended with the thief banking it: the owner loses the crystal.
function Plots.endCarryConsume(plotIndex: number, slot: number)
	local plot = plots[plotIndex]
	plot.carried[slot] = nil
	local owner = plot.owner
	local profile = owner and Data.get(owner)
	if profile then
		profile.crystals[tostring(slot)] = nil
	end
	refreshPedestals(plotIndex)
end

function Plots.setStealHandler(handler: (Player, number, number) -> ())
	stealHandler = handler
end

-- ============================== PLOT ASSIGNMENT ==============================

local function assignPlot(player: Player, profile)
	local plotIndex
	for index, plot in plots do
		if plot.owner == nil then
			plotIndex = index
			break
		end
	end
	if not plotIndex then
		notify(player, "error", "All plots are taken in this server — try another one!")
		return
	end

	local plot = plots[plotIndex]
	plot.owner = player
	plotOfPlayer[player] = plotIndex
	plot.platform:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("PlotIndex", plotIndex)
	plot.nameplate.Text = `💎 {player.DisplayName}'s Crystals`

	-- Fresh-spawn protection so nobody gets robbed while loading in.
	profile.shieldUntil = math.max(profile.shieldUntil, os.time() + Config.Heist.JoinShield)
	Data.sync(player)

	if profile.turretTier > 0 then
		buildTurret(plotIndex, profile.turretTier)
	end

	-- Rebuild saved crystals; count how many finished while they were away.
	local readyCount = 0
	for slotKey, saved in profile.crystals do
		local slot = tonumber(slotKey)
		if slot then
			spawnCrystal(plotIndex, slot, saved)
			if progressOf(saved) >= 1 then
				readyCount += 1
			end
		end
	end
	refreshPedestals(plotIndex)

	if readyCount > 0 then
		notify(player, "success", `✨ {readyCount} crystal{readyCount == 1 and "" or "s"} finished growing while you were away!`)
	end
end

local function releasePlot(player: Player)
	local plotIndex = plotOfPlayer[player]
	if not plotIndex then
		return
	end
	local plot = plots[plotIndex]
	for slot in plot.crystals do
		removeCrystalModel(plotIndex, slot)
	end
	plot.crystals = {}
	plot.carried = {}
	plot.owner = nil
	plot.platform:SetAttribute("OwnerUserId", nil)
	plot.nameplate.Text = "🌱 Unclaimed Plot"
	if plot.turret then
		plot.turret:Destroy()
		plot.turret = nil
	end
	plot.shieldDome.Transparency = 1
	plotOfPlayer[player] = nil
	lastTeleport[player] = nil
	refreshPedestals(plotIndex)
end

-- ============================== WORLD BUILDING ==============================

local function buildPlot(index: number, parent: Folder)
	local angle = math.rad((index - 1) * (360 / Config.Plot.Count))
	local position = Vector3.new(math.cos(angle) * PLOT_RING_RADIUS, 0.5, math.sin(angle) * PLOT_RING_RADIUS)
	local cframe = CFrame.lookAt(position, Vector3.new(0, 0.5, 0)) -- -Z faces the hub

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder.Parent = parent

	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE)
	platform.CFrame = cframe
	platform.Color = Color3.fromRGB(86, 66, 116)
	platform.Material = Enum.Material.Slate
	platform.Anchored = true
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.Parent = folder

	-- Low fence posts + rails around the plot (decorative; hub side stays open).
	for _, side in { -1, 1 } do
		for _, axis in { "X", "Z" } do
			if axis == "X" and side == -1 then
				continue -- the hub-facing side, where the path arrives
			end
			local rail = Instance.new("Part")
			rail.Anchored = true
			rail.Material = Enum.Material.Wood
			rail.Color = Color3.fromRGB(124, 92, 70)
			if axis == "X" then
				rail.Size = Vector3.new(PLOT_SIZE, 1, 0.8)
				rail.CFrame = cframe * CFrame.new(0, 1.6, side * (PLOT_SIZE / 2 - 0.4))
			else
				rail.Size = Vector3.new(0.8, 1, PLOT_SIZE - 16)
				rail.CFrame = cframe * CFrame.new(side * (PLOT_SIZE / 2 - 0.4), 1.6, 8)
			end
			rail.Parent = folder
		end
	end

	-- Nameplate post at the front of the plot.
	local post = Instance.new("Part")
	post.Size = Vector3.new(0.8, 7, 0.8)
	post.CFrame = cframe * CFrame.new(-14, 4, -(PLOT_SIZE / 2 - 2))
	post.Color = Color3.fromRGB(124, 92, 70)
	post.Material = Enum.Material.Wood
	post.Anchored = true
	post.Parent = folder

	local nameGui = Instance.new("BillboardGui")
	nameGui.Size = UDim2.fromScale(14, 3)
	nameGui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	nameGui.MaxDistance = 250
	nameGui.AlwaysOnTop = true
	local nameplate = Instance.new("TextLabel")
	nameplate.Size = UDim2.fromScale(1, 1)
	nameplate.BackgroundTransparency = 1
	nameplate.Text = "🌱 Unclaimed Plot"
	nameplate.TextColor3 = Color3.fromRGB(240, 243, 250)
	nameplate.TextScaled = true
	nameplate.Font = Enum.Font.FredokaOne
	nameplate.TextStrokeTransparency = 0.4
	nameplate.Parent = nameGui
	nameGui.Parent = post

	-- Shield dome (invisible until a shield is active).
	local dome = Instance.new("Part")
	dome.Name = "ShieldDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(70, 70, 70)
	dome.CFrame = cframe
	dome.Color = Color3.fromRGB(120, 220, 255)
	dome.Material = Enum.Material.ForceField
	dome.Transparency = 1
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.Parent = folder

	local pedestals = {}
	local billboards = {}
	for slot = 1, Config.Plot.MaxSlots do
		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal" .. slot
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.Size = Vector3.new(1.6, 6.5, 6.5) -- X is height for cylinders
		pedestal.CFrame = cframe * CFrame.new(slotOffset(slot) + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pedestal.Color = Color3.fromRGB(120, 108, 148)
		pedestal.Material = Enum.Material.Marble
		pedestal.Anchored = true
		pedestal:SetAttribute("Slot", slot)
		pedestal:SetAttribute("PlotIndex", index)
		pedestal:SetAttribute("State", "Idle")
		pedestal.Parent = folder

		local clicker = Instance.new("ClickDetector")
		clicker.MaxActivationDistance = CLICK_RANGE
		clicker.Parent = pedestal
		clicker.MouseClick:Connect(function(clickingPlayer)
			onPedestalClick(clickingPlayer, index, slot)
		end)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(6, 1.8)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
		gui.MaxDistance = 120
		gui.AlwaysOnTop = true -- never clips into the pedestal
		gui.Enabled = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = ""
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextStrokeTransparency = 0.5
		label.Parent = gui
		gui.Parent = pedestal

		pedestals[slot] = pedestal
		billboards[slot] = label
	end

	plots[index] = {
		platform = platform,
		cframe = cframe,
		pedestals = pedestals,
		billboards = billboards,
		nameplate = nameplate,
		shieldDome = dome,
		turret = nil,
		folder = folder,
		owner = nil,
		crystals = {},
		carried = {},
	}
end

-- ============================== START ==============================

function Plots.start(dataService, monetizationService, eventsService)
	Data = dataService
	Monetization = monetizationService
	Events = eventsService

	local container = Instance.new("Folder")
	container.Name = "Plots"
	for index = 1, Config.Plot.Count do
		buildPlot(index, container)
	end
	container.Parent = workspace

	Data.onLoaded(assignPlot)
	Players.PlayerRemoving:Connect(releasePlot)

	remotes().Plant.OnServerEvent:Connect(onPlant)
	remotes().BuyTurret.OnServerEvent:Connect(onBuyTurret)

	remotes().HarvestAll.OnServerEvent:Connect(function(player)
		local plotIndex = plotOfPlayer[player]
		local profile = Data.get(player)
		if not plotIndex or not profile then
			return
		end
		local total, count = 0, 0
		for slot = 1, Config.Plot.MaxSlots do
			local runtime = plots[plotIndex].crystals[slot]
			if runtime and runtime.ready then
				local value = harvest(player, plotIndex, slot)
				if value then
					total += value
					count += 1
				end
			end
		end
		if count > 1 then
			notify(player, "success", `Harvested {count} crystals for {Formulas.abbreviate(total)} coins! 🪙`)
		elseif count == 0 then
			notify(player, "error", "No crystals are ready yet!")
		end
	end)

	remotes().TutorialDone.OnServerEvent:Connect(function(player)
		Data.setTutorialSeen(player)
	end)

	-- Coin-purchased plot shield: protect your crystals with money.
	remotes().BuyShield.OnServerEvent:Connect(function(player)
		local profile = Data.get(player)
		if not profile then
			return
		end
		if profile.shieldUntil - os.time() >= Config.Shield.MaxRemaining then
			notify(player, "error", "Your shield is already stacked to the max!")
			return
		end
		if not Data.trySpendCoins(player, Config.Shield.CoinCost) then
			notify(player, "error", `A shield costs {Formulas.abbreviate(Config.Shield.CoinCost)} coins!`)
			return
		end
		Plots.addShield(player, Config.Shield.Duration)
		notify(player, "success", `🛡️ Plot shielded for {Config.Shield.Duration / 60} more minutes!`)
	end)

	-- Coin-purchased luck potion: better mutation odds on your next plants.
	remotes().BuyPotion.OnServerEvent:Connect(function(player)
		local profile = Data.get(player)
		if not profile then
			return
		end
		local potion = Config.Potions.Luck
		if profile.luckPlants > 0 and profile.luckMult > potion.multiplier then
			notify(player, "error", "A stronger potion is still active!")
			return
		end
		if profile.luckPlants >= potion.maxPlants then
			notify(player, "error", `Potions are stacked to the max ({potion.maxPlants} plants)!`)
			return
		end
		if not Data.trySpendCoins(player, potion.cost) then
			notify(player, "error", `The Luck Potion costs {Formulas.abbreviate(potion.cost)} coins!`)
			return
		end
		if profile.luckMult ~= potion.multiplier then
			profile.luckPlants = 0 -- switching strength resets the stack
		end
		profile.luckMult = potion.multiplier
		profile.luckPlants = math.min(profile.luckPlants + potion.plants, potion.maxPlants)
		Data.sync(player)
		notify(player, "success", `🧪 {potion.multiplier}x mutation luck for your next {profile.luckPlants} plants!`)
	end)

	-- Teleport back to your plot (blocked while carrying stolen loot!).
	remotes().TeleportHome.OnServerEvent:Connect(function(player)
		local plotIndex = plotOfPlayer[player]
		local character = player.Character
		if not plotIndex or not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end
		if player:GetAttribute("CarryingFromUserId") ~= nil then
			notify(player, "error", "No teleporting with stolen goods! 🏃")
			return
		end
		local now = os.clock()
		if now - (lastTeleport[player] or 0) < 5 then
			return
		end
		lastTeleport[player] = now
		character:PivotTo(plots[plotIndex].cframe * CFrame.new(0, 4, -20))
	end)

	-- Growth heartbeat: advance visuals, flip finished crystals to Ready,
	-- and keep shield domes in sync with their timers.
	task.spawn(function()
		while true do
			task.wait(GROWTH_TICK)
			for plotIndex, plot in plots do
				if plot.owner then
					for slot in plot.crystals do
						updateCrystal(plotIndex, slot)
					end
					plot.shieldDome.Transparency = Plots.isShielded(plotIndex) and 0.75 or 1
				end
			end
		end
	end)

	-- Auto Charge gamepass: hands-free charging for every growing crystal.
	task.spawn(function()
		while true do
			task.wait(Config.Charge.AutoChargeInterval)
			for player, plotIndex in plotOfPlayer do
				if Monetization.ownsPass(player, "AutoCharge") then
					local profile = Data.get(player)
					if profile then
						for slotKey, saved in profile.crystals do
							local slot = tonumber(slotKey)
							local runtime = plots[plotIndex].crystals[slot]
							if runtime and not runtime.ready then
								saved.boost += Config.Charge.BoostPerClick
								updateCrystal(plotIndex, slot)
							end
						end
					end
				end
			end
		end
	end)

	-- Instant Grow dev product: finish every growing crystal right now.
	Monetization.setProductHandler("instantGrow", function(player)
		local plotIndex = plotOfPlayer[player]
		local profile = Data.get(player)
		if not plotIndex or not profile then
			return
		end
		for slotKey, saved in profile.crystals do
			saved.boost += growTimeOf(saved) -- guarantees progress >= 1
			updateCrystal(plotIndex, tonumber(slotKey))
		end
	end)

	-- Plot Shield dev product.
	Monetization.setProductHandler("shield", function(player, product)
		Plots.addShield(player, product.amount)
	end)

	-- Super Luck Potion dev product.
	Monetization.setProductHandler("superLuck", function(player)
		local profile = Data.get(player)
		if not profile then
			return
		end
		local potion = Config.Potions.SuperLuck
		if profile.luckMult ~= potion.multiplier then
			profile.luckPlants = 0 -- switching strength resets the stack
		end
		profile.luckMult = potion.multiplier
		profile.luckPlants += potion.plants
		Data.sync(player)
	end)
end

return Plots
