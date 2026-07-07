-- MapBuilder.luau
-- Builds the whole world from code at server start: the twilight meadow, the
-- central hub (fountain, Black Market, Shard Shop, leaderboard obelisk),
-- stone paths out to every plot, a decorated environment ring (boulders,
-- wild crystals, glowshrooms, trees) and a tall rock border + invisible
-- walls so nobody parkours out of the map. Plots themselves are built by
-- Plots.luau; everything else lives here.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GROUND_RADIUS = 260
local BORDER_RADIUS = 246
local ENV_INNER, ENV_OUTER = 150, 235 -- decoration ring (outside the plots)

local MapBuilder = {}

local rng = Random.new(20260707)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			p[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function billboard(adornee: BasePart, text: string, color: Color3, offsetY: number, size: UDim2)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = adornee
	gui.Size = size
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 300
	gui.AlwaysOnTop = true -- text never clips into geometry

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	gui.Parent = adornee
	return gui
end

-- A market stall: counter, two posts, slanted canopy, sign.
local function buildStall(parent: Folder, cframe: CFrame, canopyColor: Color3, signText: string, signColor: Color3): Part
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(10, 3.4, 3),
		CFrame = cframe * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(96, 74, 56),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = cframe * CFrame.new(side * 4.6, 4.5, -1),
			Color = Color3.fromRGB(76, 58, 44),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	part({
		Name = "Canopy",
		Size = Vector3.new(12, 0.6, 6),
		CFrame = cframe * CFrame.new(0, 9.2, -0.4) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = canopyColor,
		Material = Enum.Material.Fabric,
		Parent = parent,
	})
	billboard(counter, signText, signColor, 10.5, UDim2.fromScale(16, 3.2))
	return counter
end

local function buildHub(parent: Folder): (BasePart, BasePart)
	-- Stone plaza.
	part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 80, 80),
		CFrame = CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(104, 96, 128),
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})

	-- Fountain: stacked basins with a glowing core.
	local basinSizes = { { 18, 2.4 }, { 11, 2 }, { 5.5, 1.8 } }
	local y = 1.2
	for _, basin in basinSizes do
		local diameter, height = basin[1], basin[2]
		part({
			Name = "FountainBasin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(0, y + height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 108, 148),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		y += height
	end
	local core = part({
		Name = "FountainCore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(0, y + 2.4, 0),
		Color = Color3.fromRGB(150, 120, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	local coreLight = Instance.new("PointLight")
	coreLight.Color = core.Color
	coreLight.Brightness = 3
	coreLight.Range = 30
	coreLight.Parent = core
	local coreSparkles = Instance.new("Sparkles")
	coreSparkles.SparkleColor = core.Color
	coreSparkles.Parent = core

	-- Black Market stall + the banking pad in front of it.
	local marketCFrame = CFrame.new(0, 1.2, -30) * CFrame.Angles(0, math.rad(180), 0)
	buildStall(parent, marketCFrame, Color3.fromRGB(45, 40, 58), "🏴 BLACK MARKET", Color3.fromRGB(255, 110, 110))
	local bankPad = part({
		Name = "BankPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 12, 12),
		CFrame = CFrame.new(0, 1.4, -22) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 90, 90),
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	billboard(bankPad, "Bank stolen crystals here! 💰", Color3.fromRGB(255, 170, 170), 4, UDim2.fromScale(14, 2.4))

	-- Shard Shop stall: clicking the counter opens the shop UI (client-side).
	local shopCFrame = CFrame.new(0, 1.2, 30)
	local shopCounter = buildStall(parent, shopCFrame, Color3.fromRGB(90, 60, 140), "💎 SHARD SHOP", Color3.fromRGB(200, 160, 255))
	shopCounter:SetAttribute("OpensShop", true)
	local shopClicker = Instance.new("ClickDetector")
	shopClicker.MaxActivationDistance = 30
	shopClicker.Parent = shopCounter

	-- Leaderboard obelisk.
	local obelisk = part({
		Name = "LeaderboardObelisk",
		Size = Vector3.new(16, 22, 2.5),
		CFrame = CFrame.new(34, 12.2, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(40, 34, 62),
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	-- Spawn on the plaza.
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(-24, 1.7, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(220, 214, 240)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = parent

	return obelisk, bankPad
end

local function buildEnvironment(parent: Folder)
	-- Scatter positions in the ring between the plots and the border.
	local function ringPosition(): (Vector3, number)
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(ENV_INNER, ENV_OUTER)
		return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), angle
	end

	-- Boulders.
	for _ = 1, 26 do
		local position = ringPosition()
		local size = rng:NextNumber(4, 13)
		part({
			Name = "Boulder",
			Shape = rng:NextNumber() < 0.5 and Enum.PartType.Ball or Enum.PartType.Block,
			Size = Vector3.new(size, size * rng:NextNumber(0.6, 1), size * rng:NextNumber(0.7, 1.1)),
			CFrame = CFrame.new(position + Vector3.new(0, size * 0.3, 0))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
			Color = Color3.fromRGB(88, 82, 104),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	-- Wild crystal outcrops (flavor only, not harvestable).
	for _ = 1, 16 do
		local position = ringPosition()
		local shard = Config.Shards[rng:NextInteger(1, 5)]
		for i = 1, rng:NextInteger(2, 3) do
			local height = rng:NextNumber(3, 7)
			local spike = part({
				Name = "WildCrystal",
				Size = Vector3.new(1.4, height, 1.4),
				CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-2, 2), height / 2 - 0.5, rng:NextNumber(-2, 2)))
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6.28), rng:NextNumber(-0.35, 0.35)),
				Color = shard.color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = parent,
			})
			if i == 1 then
				local light = Instance.new("PointLight")
				light.Color = shard.color
				light.Brightness = 1
				light.Range = 12
				light.Parent = spike
			end
		end
	end

	-- Glowshrooms.
	for _ = 1, 12 do
		local position = ringPosition()
		local stemHeight = rng:NextNumber(2, 5)
		part({
			Name = "ShroomStem",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(stemHeight, 1.2, 1.2),
			CFrame = CFrame.new(position + Vector3.new(0, stemHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(220, 210, 190),
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		local cap = part({
			Name = "ShroomCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.4, 2.2, 3.4),
			CFrame = CFrame.new(position + Vector3.new(0, stemHeight + 0.6, 0)),
			Color = Color3.fromRGB(110, 240, 210),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Color = cap.Color
		light.Brightness = 1.2
		light.Range = 14
		light.Parent = cap
	end

	-- Twilight trees.
	for _ = 1, 10 do
		local position = ringPosition()
		local trunkHeight = rng:NextNumber(7, 12)
		part({
			Name = "TreeTrunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(trunkHeight, 2.2, 2.2),
			CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(84, 64, 58),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for i = 1, 2 do
			local puff = rng:NextNumber(6, 9) - (i - 1) * 2
			part({
				Name = "TreeFoliage",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(puff, puff * 0.8, puff),
				CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1), trunkHeight + (i - 1) * 2.5, rng:NextNumber(-1, 1))),
				Color = Color3.fromRGB(58, 92, 110),
				Material = Enum.Material.Grass,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
end

local function buildBorder(parent: Folder)
	-- Chunky rock ring so the map has a horizon...
	local segments = 22
	for i = 1, segments do
		local angle = math.rad((i - 1) * (360 / segments) + rng:NextNumber(-4, 4))
		local height = rng:NextNumber(34, 64)
		local width = 2 * math.pi * BORDER_RADIUS / segments + 14
		part({
			Name = "BorderRock",
			Size = Vector3.new(width, height, rng:NextNumber(10, 18)),
			CFrame = CFrame.new(math.cos(angle) * BORDER_RADIUS, height / 2 - rng:NextNumber(2, 6), math.sin(angle) * BORDER_RADIUS)
				* CFrame.Angles(0, -angle + math.rad(90), 0)
				* CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.05, 0.05)),
			Color = Color3.fromRGB(70, 64, 88),
			Material = Enum.Material.Rock,
			Parent = parent,
		})
	end
	-- ...and a 200-stud invisible wall above it so NOBODY parkours out.
	for i = 1, 12 do
		local angle = math.rad((i - 1) * 30)
		part({
			Name = "InvisibleWall",
			Size = Vector3.new(2 * math.pi * (BORDER_RADIUS + 6) / 12 + 10, 200, 4),
			CFrame = CFrame.new(math.cos(angle) * (BORDER_RADIUS + 6), 100, math.sin(angle) * (BORDER_RADIUS + 6))
				* CFrame.Angles(0, -angle + math.rad(90), 0),
			Transparency = 1,
			Parent = parent,
		})
	end
end

function MapBuilder.build()
	local map = Instance.new("Folder")
	map.Name = "Map"

	-- The ground: a twilight meadow disc.
	part({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, GROUND_RADIUS * 2, GROUND_RADIUS * 2),
		CFrame = CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(64, 96, 82),
		Material = Enum.Material.Grass,
		Parent = map,
	})

	local obelisk, bankPad = buildHub(map)
	buildEnvironment(map)
	buildBorder(map)

	-- Stone paths from the plaza out to each plot.
	for index = 1, Config.Plot.Count do
		local angle = math.rad((index - 1) * (360 / Config.Plot.Count))
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = direction * 41
		local to = direction * 95
		part({
			Name = "Path",
			Size = Vector3.new(7, 0.4, (to - from).Magnitude),
			CFrame = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 0.2, 0), to + Vector3.new(0, 0.2, 0)),
			Color = Color3.fromRGB(104, 96, 128),
			Material = Enum.Material.Cobblestone,
			Parent = map,
		})
	end

	-- Atmosphere: purple dusk with a soft glow.
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Color = Color3.fromRGB(150, 130, 200)
	atmosphere.Decay = Color3.fromRGB(80, 60, 140)
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 28
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	map.Parent = workspace

	return { leaderboardPart = obelisk, bankPad = bankPad }
end

return MapBuilder
