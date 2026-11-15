--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The spawn picker's camera work: which places a character MAY pick, an aerial orbit over each, and the dive.
-- The server still decides the destination: these options only shape what the player sees.

---@class UgMc.Internal.Picker
local Picker = {}
UgMc.Internal.Picker = Picker

local Camera = UgMc.Internal.Camera
local Cinematic = UgMc.Internal.Cinematic
local Scene = UgMc.Internal.Scene
local Enums = UgMc.Enums

-- Time for the area under the new camera to stream before the picture comes back.
local STREAM_MS = 400

---@class UgMcSpawnOption
---@field id string `last` or a spawn point id
---@field label string
---@field coords vector4
---@field street? string
---@field camera? UgMcCameraPose the owner's flyover pose, a slow orbit otherwise

---The locale label of a spawn point, or its id when the locale has none.
---@param id string
---@param label fun(key: string): string
---@return string
local function labelOf(id, label)
    local key = 'spawns.' .. id
    local text = label(key)

    return text ~= key and text or id
end

---@param position table|vector4|nil
---@return string?
local function streetOf(position)
    if not position then
        return nil
    end

    local hash = GetStreetNameAtCoord(position.x, position.y, position.z)
    local name = hash and GetStreetNameFromHashKey(hash) or nil

    return name ~= '' and name or nil
end

---Places a character MAY pick, in the order the page lists them. One option means there is nothing to pick.
---@param character table from List
---@param spawn { points: table[], firstSpawn: string, default: vector4 }
---@param label fun(key: string): string
---@return UgMcSpawnOption[]
function Picker.Options(character, spawn, label)
    local position = character.position
    local last = {
        id = Enums.SpawnId.Last,
        label = label(position and 'page.lastLocation' or 'page.firstLocation'),
        coords = position and vector4(position.x, position.y, position.z, 0.0) or spawn.default,
        street = streetOf(position),
    }

    -- Downed and dead characters go back where they were; new ones MAY be sent to the default spawn.
    if character.deathState ~= UgCore.Enums.DeathState.Alive then
        return { last }
    end

    if not position and spawn.firstSpawn == Enums.FirstSpawn.Default then
        return { last }
    end

    local options = { last }

    for _, point in ipairs(spawn.points) do
        options[#options + 1] = {
            id = point.id,
            label = point.label or labelOf(point.id, label),
            coords = point.coords,
            camera = point.camera,
        }
    end

    return options
end

---The orbit pose at an angle, looking at the place.
---@param coords vector4
---@param angle number degrees
---@return UgMcCameraPose
function Picker.Orbit(coords, angle)
    local flyover = Cinematic.Get().flyover
    local radians = math.rad(angle)
    local at = vector3(coords.x + math.cos(radians) * flyover.radius, coords.y + math.sin(radians) * flyover.radius, coords.z + flyover.height)

    return {
        coords = at,
        rotation = Camera.LookAt(at, vector3(coords.x, coords.y, coords.z + 2.0)),
        fov = flyover.fov,
    }
end

local flight = 0
local focused = false

---Stops the orbit. Streaming goes back to the lineup while it is open, to the player otherwise.
function Picker.Stop()
    flight = flight + 1

    if focused then
        focused = false

        if Scene.IsOpen() then
            Scene.FocusStreaming()
        else
            ClearFocus()
        end
    end
end

---Cuts to a place: fade, move the camera and streaming there, fade back in, then orbit. MUST run in a thread.
---@param option UgMcSpawnOption
function Picker.Fly(option)
    flight = flight + 1

    local id = flight
    local flyover = Cinematic.Get().flyover

    Cinematic.FadeOut(flyover.fade)

    if id ~= flight then
        return
    end

    SetFocusPosAndVel(option.coords.x, option.coords.y, option.coords.z, 0.0, 0.0, 0.0)
    focused = true
    Camera.Set(option.camera or Picker.Orbit(option.coords, 0))
    Wait(STREAM_MS)
    Cinematic.FadeIn(flyover.fade * 2)

    if option.camera then
        return
    end

    local angle, last = 0, GetGameTimer()

    while id == flight do
        local now = GetGameTimer()

        angle = angle + (now - last) / 1000 * flyover.speed
        last = now
        Camera.Set(Picker.Orbit(option.coords, angle))
        Wait(0)
    end
end

---From the orbit down to a low shot behind the destination, ending in black. MUST run in a thread.
---@param destination vector4
function Picker.Dive(destination)
    flight = flight + 1
    SetFocusPosAndVel(destination.x, destination.y, destination.z, 0.0, 0.0, 0.0)
    focused = true

    local dive = Cinematic.Get().dive

    Cinematic.Play({
        {
            from = Camera.Get() or Picker.Orbit(destination, 0),
            to = Cinematic.Behind(destination, dive, 0.8),
            duration = dive.duration,
            ease = dive.ease,
            fadeOut = true,
            letterbox = true,
        },
    })
end
