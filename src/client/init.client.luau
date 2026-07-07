-- Client entry point: waits for the server's remotes, then boots every
-- controller. Windows (Shop, PlantMenu, HowToPlay) register themselves with
-- the UI window manager; the HUD's buttons toggle them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")
ReplicatedStorage:WaitForChild("Shared")

local Effects = require(script.Effects)
local ShopUi = require(script.ShopUi)
local PlantMenu = require(script.PlantMenu)
local Instructions = require(script.Instructions)
local Hud = require(script.Hud)

Effects.start()
ShopUi.build()
PlantMenu.build()
Instructions.build()
Hud.start()
