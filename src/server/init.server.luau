-- Server entry point. Creates the remotes, then wires services together in
-- dependency order. Services receive their dependencies explicitly instead of
-- requiring each other, which keeps the graph flat and easy to follow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in { "Plant", "HarvestAll", "BuyTurret", "TutorialDone", "Notify", "Announce", "HarvestFx" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
end
remotes.Parent = ReplicatedStorage

local Data = require(script.Data)
local Monetization = require(script.Monetization)
local Events = require(script.Events)
local MapBuilder = require(script.MapBuilder)
local Plots = require(script.Plots)
local Heist = require(script.Heist)
local GlobalLeaderboard = require(script.GlobalLeaderboard)

local mapHandles = MapBuilder.build()

Data.start()
Monetization.start(Data)
Events.start()
Plots.start(Data, Monetization, Events)
Heist.start(Data, Monetization, Events, Plots, mapHandles.bankPad)
Plots.setStealHandler(Heist.tryStartSteal)
GlobalLeaderboard.start(Data, mapHandles.leaderboardPart)

print("[Server] Crystal Heist ready 💎🏴")
