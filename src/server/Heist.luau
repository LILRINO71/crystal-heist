-- Heist.luau
-- The stealing layer. A thief clicks a READY crystal on someone else's plot:
-- the crystal pops onto their head, they're slowed and marked red for the
-- whole server, and they must reach the Black Market pad at the hub to bank
-- a fraction of its value. Until then the victim can click the thief to zap
-- the crystal straight back onto its pedestal (a ClickDetector is welded to
-- the thief, so range and targeting are enforced by the engine, not a remote).
-- Guard Turrets auto-zap thieves who are still inside the victim's plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local Heist = {}

local Data, Monetization, Events, Plots

-- carries[thief] = { victim, plotIndex, slot, shard, mutation, orb, highlight,
--                    clicker, startedAt, connections = {...} }
local carries = {}
local stealCooldownUntil = {} -- [Player] = os.clock()
local lastTurretZap = {} -- [plotIndex] = os.clock()

local function remotes()
	return ReplicatedStorage.Remotes
end

local function notify(player: Player, kind: string, message: string)
	remotes().Notify:FireClient(player, kind, message)
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function beamFx(from: Vector3, to: Vector3, color: Color3)
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(0.4, 0.4, math.max((from - to).Magnitude, 0.5))
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Parent = workspace
	Debris:AddItem(beam, 0.15)
end

-- Remove all carry visuals/state from the thief (shared by every ending).
local function cleanupCarry(thief: Player)
	local carry = carries[thief]
	if not carry then
		return
	end
	carries[thief] = nil

	for _, connection in carry.connections do
		connection:Disconnect()
	end
	if carry.orb then
		carry.orb:Destroy()
	end
	if carry.highlight then
		carry.highlight:Destroy()
	end
	if carry.clicker then
		carry.clicker:Destroy()
	end
	thief:SetAttribute("CarryingFromUserId", nil)

	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.Heist.BaseWalkSpeed
	end
end

-- The crystal returns to its pedestal (zap, turret, timeout, death).
local function dropCarry(thief: Player, reason: string)
	local carry = carries[thief]
	if not carry then
		return
	end
	cleanupCarry(thief)
	stealCooldownUntil[thief] = os.clock() + Config.Heist.StealCooldown

	-- Only restore if the victim still owns that plot (they may have left).
	if Plots.getOwner(carry.plotIndex) == carry.victim then
		Plots.endCarryRestore(carry.plotIndex, carry.slot)
	end

	if reason == "zap" then
		notify(thief, "error", "⚡ Zapped! The crystal snapped back to its pedestal.")
		notify(carry.victim, "success", `You zapped {thief.DisplayName}! Your crystal is back.`)
	elseif reason == "turret" then
		notify(thief, "error", "🗼 The Guard Turret zapped you! Escape the plot faster next time.")
		notify(carry.victim, "success", `Your turret zapped {thief.DisplayName}!`)
	elseif reason == "timeout" then
		notify(thief, "error", "The crystal wriggled free and returned home!")
	end
end

-- The thief reached the Black Market: pay them, the victim loses the crystal.
local function bankCarry(thief: Player)
	local carry = carries[thief]
	if not carry then
		return
	end
	cleanupCarry(thief)

	local shard = Config.getShard(carry.shard)
	local mutation = Config.getMutation(carry.mutation)
	local fraction = math.min(
		Events.payoutFraction()
			+ (Monetization.ownsPass(thief, "MasterThief") and Config.Heist.MasterThiefBonus or 0),
		1
	)
	local fullValue = Formulas.harvestValue(
		shard.value,
		mutation and mutation.multiplier or 1,
		Monetization.ownsPass(thief, "DoubleCoins")
	)
	local payout = math.floor(fullValue * fraction)

	Data.recordSteal(thief, payout)
	remotes().HarvestFx:FireClient(thief, payout, carry.mutation)
	notify(thief, "success", `💰 Banked the stolen {shard.name} for {Formulas.abbreviate(payout)} coins!`)

	if Plots.getOwner(carry.plotIndex) == carry.victim then
		Plots.endCarryConsume(carry.plotIndex, carry.slot)
		Plots.addShield(carry.victim, Config.Heist.ShieldAfterTheft)
		notify(
			carry.victim,
			"alarm",
			`💔 {thief.DisplayName} banked your {shard.name}! Your plot is shielded for {Config.Heist.ShieldAfterTheft}s.`
		)
	end

	if mutation and mutation.announce then
		remotes().Announce:FireAllClients(
			`🏴 {thief.DisplayName} stole a {mutation.key} {shard.name} from {carry.victim.DisplayName}!`
		)
	end
end

-- ============================== STARTING A STEAL ==============================

function Heist.tryStartSteal(thief: Player, plotIndex: number, slot: number)
	if carries[thief] then
		notify(thief, "error", "You're already carrying a crystal!")
		return
	end
	if os.clock() < (stealCooldownUntil[thief] or 0) then
		notify(thief, "error", "You're too shaky to steal again yet... ⏳")
		return
	end
	local victim = Plots.getOwner(plotIndex)
	if not victim or victim == thief then
		return
	end
	if Plots.isShielded(plotIndex) then
		notify(thief, "error", "🛡️ This plot is shielded!")
		return
	end
	local saved = Plots.getSaved(victim, slot)
	if not saved then
		return
	end

	local character = thief.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or humanoid.Health <= 0 then
		return
	end

	local shard = Config.getShard(saved.shard)

	-- Take the crystal off the pedestal and onto the thief's head.
	Plots.beginCarry(plotIndex, slot)

	local orb = Instance.new("Part")
	orb.Name = "StolenCrystal"
	orb.Size = Vector3.new(2, 3, 2)
	orb.CFrame = head.CFrame * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.rad(45), 0)
	orb.Color = shard.color
	orb.Material = Enum.Material.Neon
	orb.CanCollide = false
	orb.Massless = true
	orb.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = orb
	weld.Part1 = head
	weld.Parent = orb
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = shard.color
	sparkles.Parent = orb

	-- Marked red for the whole server: everyone can see who the thief is.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 70, 70)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(255, 70, 70)
	highlight.Parent = character

	-- The victim zaps by clicking the thief; the engine enforces the range.
	-- Parented to the character MODEL so clicking any body part counts.
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = Config.Heist.ZapRange
	clicker.Parent = character

	humanoid.WalkSpeed = Monetization.ownsPass(thief, "MasterThief") and Config.Heist.CarryWalkSpeedMasterThief
		or Config.Heist.CarryWalkSpeed
	thief:SetAttribute("CarryingFromUserId", victim.UserId)

	local connections = {}
	table.insert(connections, clicker.MouseClick:Connect(function(clickingPlayer)
		local carry = carries[thief]
		if carry and clickingPlayer == carry.victim then
			local thiefRoot = characterRoot(thief)
			local victimRoot = characterRoot(clickingPlayer)
			if thiefRoot and victimRoot then
				beamFx(victimRoot.Position, thiefRoot.Position, Color3.fromRGB(120, 220, 255))
			end
			dropCarry(thief, "zap")
		end
	end))
	table.insert(connections, humanoid.Died:Connect(function()
		dropCarry(thief, "died")
	end))
	table.insert(connections, thief.CharacterRemoving:Connect(function()
		dropCarry(thief, "died")
	end))

	carries[thief] = {
		victim = victim,
		plotIndex = plotIndex,
		slot = slot,
		shard = saved.shard,
		mutation = saved.mutation,
		orb = orb,
		highlight = highlight,
		clicker = clicker,
		startedAt = os.clock(),
		connections = connections,
	}

	notify(thief, "success", `You grabbed a {shard.name}! Sprint it to the Black Market! 🏃`)
	notify(victim, "alarm", `🚨 {thief.DisplayName} is stealing your {shard.name}! Click them to zap it back!`)
end

-- ============================== START ==============================

function Heist.start(dataService, monetizationService, eventsService, plotsService, bankPad: BasePart)
	Data = dataService
	Monetization = monetizationService
	Events = eventsService
	Plots = plotsService

	-- Banking: step on the Black Market pad while carrying.
	bankPad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and carries[player] then
			bankCarry(player)
		end
	end)

	-- Turret enforcement + carry timeout, twice a second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for thief, carry in carries do
				if now - carry.startedAt > Config.Heist.CarryTimeout then
					dropCarry(thief, "timeout")
					continue
				end
				local root = characterRoot(thief)
				if root and Plots.plotContains(carry.plotIndex, root.Position) then
					local tier = Plots.getTurretTier(carry.plotIndex)
					if tier > 0 then
						local interval = Config.Turret.Intervals[math.min(tier, #Config.Turret.Intervals)]
						if now - (lastTurretZap[carry.plotIndex] or 0) >= interval then
							lastTurretZap[carry.plotIndex] = now
							Plots.fireTurretBeam(carry.plotIndex, root.Position)
							dropCarry(thief, "turret")
						end
					end
				end
			end
		end
	end)

	-- Thief or victim leaving ends the carry cleanly.
	Players.PlayerRemoving:Connect(function(player)
		if carries[player] then
			dropCarry(player, "left")
		end
		for thief, carry in carries do
			if carry.victim == player then
				-- Victim left: their plot despawns, so the loot just fizzles.
				cleanupCarry(thief)
				notify(thief, "error", "The crystal's owner left — the loot vanished!")
			end
		end
		stealCooldownUntil[player] = nil
	end)
end

return Heist
