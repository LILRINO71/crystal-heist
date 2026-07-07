-- Monetization.luau
-- Gamepass ownership (cached per player, exposed as attributes for the UI)
-- and developer product receipt processing. All grants happen server-side.
-- Products with type "coins" are granted here; other types (instantGrow,
-- shield, ...) are routed to handlers registered by gameplay modules.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Monetization = {}

local ownership = {} -- [Player] = { [passKey] = boolean }
local handledReceipts = {} -- [PurchaseId] = true, session-level dedupe
local productHandlers = {} -- [productType] = (player, product) -> ()
local Data

-- Speedy Boots: applied on every spawn and the moment the pass is bought.
-- Never touches a thief mid-carry (Heist owns the WalkSpeed while carrying).
local function applyWalkSpeed(player: Player)
	if player:GetAttribute("CarryingFromUserId") ~= nil then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Monetization.ownsPass(player, "SpeedyBoots") and Config.Heist.SpeedyBootsWalkSpeed
			or Config.Heist.BaseWalkSpeed
	end
end

local function refreshPasses(player: Player)
	local owned = {}
	for key, passId in Config.GamePasses do
		local owns = false
		if passId ~= 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			owns = ok and result == true
		end
		owned[key] = owns
		player:SetAttribute("Owns" .. key, owns)
	end
	ownership[player] = owned
	applyWalkSpeed(player)
end

local function processReceipt(receiptInfo)
	if handledReceipts[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not Data.get(player) then
		-- Player left or their data hasn't loaded; Roblox will retry later.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	for _, product in Config.DevProducts do
		if product.id == receiptInfo.ProductId then
			if product.type == "coins" then
				Data.addCoins(player, product.amount)
			else
				local handler = productHandlers[product.type]
				if not handler then
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				handler(player, product)
			end
			handledReceipts[receiptInfo.PurchaseId] = true
			local notify = ReplicatedStorage.Remotes:FindFirstChild("Notify")
			if notify then
				notify:FireClient(player, "success", `Purchased {product.label}!`)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	warn(`[Monetization] Receipt for unknown product id {receiptInfo.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ============================== PUBLIC API ==============================

function Monetization.ownsPass(player: Player, passKey: string): boolean
	local owned = ownership[player]
	return owned ~= nil and owned[passKey] == true
end

function Monetization.setProductHandler(productType: string, handler: (Player, any) -> ())
	productHandlers[productType] = handler
end

function Monetization.start(dataService)
	Data = dataService

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(applyWalkSpeed, player)
		end)
		task.spawn(refreshPasses, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ownership[player] = nil
	end)

	-- Update the cache instantly when a pass is bought in-game.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, id in Config.GamePasses do
			if id == passId then
				local owned = ownership[player]
				if owned then
					owned[key] = true
				end
				player:SetAttribute("Owns" .. key, true)
				applyWalkSpeed(player)
				local notify = ReplicatedStorage.Remotes:FindFirstChild("Notify")
				if notify then
					notify:FireClient(player, "success", `{Config.GamePassInfo[key].title} unlocked!`)
				end
			end
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt
end

return Monetization
