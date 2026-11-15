--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The lineup: one local ped per slot, the world around it, and the hidden player.

---@class UgMc.Internal.Scene
local Scene = {}
UgMc.Internal.Scene = Scene

local Appearance = UgMc.Internal.Appearance
local Streaming = UgLib.Streaming
local Animation = UgLib.Animation

local MODEL_TIMEOUT = 5000
-- Empty slots show a faint figure, not a character.
local PLACEHOLDER_ALPHA = 110

---@class UgMcSlot
---@field index integer
---@field ped integer
---@field coords vector4
---@field character? table the character from List, nil for an empty slot

---@type UgMcSlot[]
local slots = {}
---@type table<string, boolean> models loaded for the scene
local models = {}
local open = false
---@type table? the scene config of the open lineup
local sceneConfig = nil

---@param model string
---@return boolean
local function load(model)
    if Streaming.Model(model, MODEL_TIMEOUT) then
        models[model] = true

        return true
    end

    return false
end

---@param ped integer
---@param animation table `{ dict, name, flag? }` or `{ scenario }`
local function animate(ped, animation)
    if animation.scenario then
        Animation.Scenario(ped, animation.scenario)
    else
        Animation.Play(ped, animation.dict, animation.name, {
            flag = animation.flag or 1,
        })
    end
end

---@param model string
---@param coords vector4
---@return integer ped
local function spawn(model, coords)
    local ped = CreatePed(4, joaat(model), coords.x, coords.y, coords.z - 1.0, coords.w, false, true)

    SetPedDefaultComponentVariation(ped)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)

    return ped
end

---Hides and freezes the player near the scene, so the area streams in around them.
---@param camera { coords: vector3 }
local function hidePlayer(camera)
    local ped = PlayerPedId()

    SetEntityCoordsNoOffset(ped, camera.coords.x, camera.coords.y, camera.coords.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
end

---Streams the world around the scene camera. The hidden ped alone is not enough: anything that moves it,
---such as a spawn on first join, would leave the lineup in low-detail textures.
function Scene.FocusStreaming()
    if open and sceneConfig then
        local coords = sceneConfig.camera.coords

        SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    end
end

---Shows the player again, still frozen until the flow lets go.
function Scene.ShowPlayer()
    local ped = PlayerPedId()

    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
end

---Puts the scene's clock, weather and streaming focus back, such as after the appearance editor changed them.
function Scene.RestoreWorld()
    if not open or not sceneConfig then
        return
    end

    Scene.FocusStreaming()
    NetworkOverrideClockTime(sceneConfig.time.hour, sceneConfig.time.minute, 0)
    SetWeatherTypeNowPersist(sceneConfig.weather)
    SetOverrideWeather(sceneConfig.weather)
end

---Builds the lineup from the List answer. MUST run in a thread.
---@param data table with `appearances` by character id when ug-appearance runs
function Scene.Open(data)
    Scene.Close()
    open = true

    local scene = data.scene
    local appearances = data.appearances or {}

    sceneConfig = scene
    hidePlayer(scene.camera)
    Scene.RestoreWorld()

    for index = 1, data.slots do
        local slot = scene.slots[index]
        local character = data.characters[index]
        local appearance = character and appearances[character.id]
        local model = character and Appearance.ModelOf(character, appearance) or scene.placeholder.model
        local placeholder = character == nil

        if not load(model) then
            model, placeholder = scene.placeholder.model, true
            load(model)
        end

        local ped = spawn(model, slot.coords)

        if placeholder then
            SetEntityAlpha(ped, PLACEHOLDER_ALPHA, false)
            animate(ped, scene.placeholder.animation)
        else
            Appearance.Dress(ped, appearance)
            animate(ped, slot.animation)
        end

        slots[index] = {
            index = index,
            ped = ped,
            coords = slot.coords,
            character = character,
        }
    end

    CreateThread(function()
        while open do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

---Replaces an empty slot's ped: a chosen model at full opacity, or the placeholder again. MUST run in a thread.
---@param index integer
---@param model? string nil puts the placeholder back
function Scene.Preview(index, model)
    local slot = slots[index]

    if not slot or slot.character or not sceneConfig then
        return
    end

    local placeholder = model == nil or not load(model)
    local shown = placeholder and sceneConfig.placeholder.model or model --[[@as string]]

    if DoesEntityExist(slot.ped) then
        DeletePed(slot.ped)
    end

    slot.ped = spawn(shown, slot.coords)

    if placeholder then
        SetEntityAlpha(slot.ped, PLACEHOLDER_ALPHA, false)
    end

    animate(slot.ped, sceneConfig.placeholder.animation)
end

---@param index integer
---@return UgMcSlot?
function Scene.Slot(index)
    return slots[index]
end

---@return integer
function Scene.Count()
    return #slots
end

---@return boolean
function Scene.IsOpen()
    return open
end

---Removes the lineup and gives the world back its clock and weather. The player stays hidden.
function Scene.Close()
    for _, slot in ipairs(slots) do
        if DoesEntityExist(slot.ped) then
            DeletePed(slot.ped)
        end
    end

    for model in pairs(models) do
        Streaming.Release(UgLib.Enums.Asset.Model, model)
    end

    slots, models = {}, {}

    if open then
        ClearFocus()
        NetworkClearClockTimeOverride()
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        open = false
    end
end
