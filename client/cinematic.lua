--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Shots, fades, letterbox and look. Every camera move of the resource goes through here.

---@class UgMc.Internal.Cinematic
local Cinematic = {}
UgMc.Internal.Cinematic = Cinematic

local Camera = UgMc.Internal.Camera
local Ease = UgMc.Enums.Ease
local Letterbox = UgMc.Enums.Letterbox

-- Bar heights as a share of the screen: 2.39:1 on a 16:9 screen during sequences, thin at rest.
local LETTERBOX_FULL = (1 - (16 / 9) / 2.39) / 2
local LETTERBOX_REST = 0.06
local LETTERBOX_MS = 700

---A camera move from one pose to another.
---@class UgMcShot
---@field from UgMcCameraPose
---@field to UgMcCameraPose
---@field duration integer ms
---@field ease? UgMcEase defaults to InOut
---@field fadeIn? boolean fade in from black as the shot starts
---@field fadeOut? boolean fade to black as the shot ends
---@field letterbox? boolean full bars during the shot, rest bars after

---A framing in front of or behind a ped.
---@class UgMcFraming
---@field duration? integer ms
---@field distance number meters
---@field height? number meters above the ped position
---@field fov number
---@field ease? UgMcEase

---@class UgMcSelectShot: UgMcFraming
---@field animation { dict: string, name: string }|false

---@class UgMcFlyover
---@field radius number
---@field height number
---@field speed number degrees per second
---@field fov number
---@field fade integer ms

---@class UgMcArrival: UgMcFraming
---@field hold integer ms
---@field handover integer ms

---The cinematic table of the config, as the server sends it. Durations in ms.
---@class UgMcCinematicSettings
---@field intro boolean|UgMcShot[]
---@field reopen boolean|UgMcShot[]
---@field skippable? boolean false: the intro MUST play to the end
---@field title string|false
---@field titleDelay integer
---@field titleDuration integer
---@field letterbox boolean
---@field timecycle string|false
---@field fadeOut integer
---@field fadeIn integer
---@field focus UgMcFraming
---@field select UgMcSelectShot
---@field create UgMcFraming
---@field flyover UgMcFlyover
---@field dive UgMcFraming
---@field arrival UgMcArrival

-- Fades only until the first Configure: the server always sends every key.
local FADES_ONLY = {
    letterbox = true,
    timecycle = false,
    fadeOut = 600,
    fadeIn = 900,
}

local settings = FADES_ONLY --[[@as UgMcCinematicSettings]]

---@param value UgMcCinematicSettings
function Cinematic.Configure(value)
    settings = value
end

---The settings of the open scene.
---@return UgMcCinematicSettings
function Cinematic.Get()
    return settings
end

-- Fades

---Fades the screen to black and waits until it is black.
---@param duration? integer ms, the configured fade out by default
function Cinematic.FadeOut(duration)
    if IsScreenFadedOut() then
        return
    end

    DoScreenFadeOut(duration or settings.fadeOut)

    while not IsScreenFadedOut() do
        Wait(0)
    end
end

---Fades in from black. Does not wait, so a shot can move while the picture appears.
---@param duration? integer ms, the configured fade in by default
function Cinematic.FadeIn(duration)
    DoScreenFadeIn(duration or settings.fadeIn)
end

-- Letterbox

local barHeight = 0.0
local barTarget = 0.0
local barFrom = 0.0
local barStart = 0
local barThread = false

---Bar height at a time, eased between the last height and the target.
---@param now integer
---@return number
function Cinematic.BarHeight(now)
    local t = (now - barStart) / LETTERBOX_MS

    return barFrom + (barTarget - barFrom) * Camera.Ease(Ease.InOut, t)
end

---Draws the bars every frame while they show.
local function drawBars()
    if barThread then
        return
    end

    barThread = true

    CreateThread(function()
        while barHeight > 0.0005 or barTarget > 0 do
            barHeight = Cinematic.BarHeight(GetGameTimer())

            DrawRect(0.5, barHeight / 2, 1.0, barHeight, 0, 0, 0, 255)
            DrawRect(0.5, 1 - barHeight / 2, 1.0, barHeight, 0, 0, 0, 255)
            Wait(0)
        end

        barHeight = 0.0
        barThread = false
    end)
end

---Slides the bars to full, rest or none.
---@param mode UgMcLetterbox
function Cinematic.Letterbox(mode)
    local target = 0.0

    if settings.letterbox then
        target = mode == Letterbox.Full and LETTERBOX_FULL or mode == Letterbox.Rest and LETTERBOX_REST or 0.0
    end

    if target == barTarget then
        return
    end

    barFrom = barHeight
    barTarget = target
    barStart = GetGameTimer()

    if target > 0 then
        drawBars()
    end
end

---@return number
function Cinematic.GetLetterboxTarget()
    return barTarget
end

-- Look

local lookActive = false

---Applies the configured timecycle modifier.
function Cinematic.StartLook()
    if settings.timecycle and not lookActive then
        SetTimecycleModifier(settings.timecycle)
        lookActive = true
    end
end

function Cinematic.StopLook()
    if lookActive then
        ClearTimecycleModifier()
        lookActive = false
    end
end

-- Shots

local sequence = 0

---Plays shots one after another. MUST run in a thread.
---@param shots UgMcShot[]
---@param skip? fun(): boolean checked every frame; true jumps to the end pose of the last shot
---@return boolean finished false when skipped or interrupted by another sequence
function Cinematic.Play(shots, skip)
    sequence = sequence + 1

    local id = sequence

    for _, shot in ipairs(shots) do
        if shot.letterbox ~= nil then
            Cinematic.Letterbox(shot.letterbox and Letterbox.Full or Letterbox.Rest)
        end

        Camera.Set(shot.from)

        if shot.fadeIn then
            Cinematic.FadeIn()
        end

        local start = GetGameTimer()
        local fadingOut = false

        while true do
            if id ~= sequence then
                return false
            end

            if skip and skip() then
                Camera.Set(shots[#shots].to)

                return false
            end

            local elapsed = GetGameTimer() - start
            local t = math.min(elapsed / shot.duration, 1)

            Camera.Set(Camera.Mix(shot.from, shot.to, Camera.Ease(shot.ease, t)))

            if shot.fadeOut and not fadingOut and shot.duration - elapsed <= settings.fadeOut then
                fadingOut = true
                DoScreenFadeOut(settings.fadeOut)
            end

            if t >= 1 then
                break
            end

            Wait(0)
        end

        if shot.fadeOut then
            Cinematic.FadeOut()
        end
    end

    return true
end

---Stops any running sequence where it is.
function Cinematic.Interrupt()
    sequence = sequence + 1
end

---A glide from wherever the camera is to a pose.
---@param to UgMcCameraPose
---@param duration integer ms
---@param ease? UgMcEase
---@return UgMcShot
function Cinematic.GlideTo(to, duration, ease)
    return {
        from = Camera.Get() or to,
        to = to,
        duration = duration,
        ease = ease or Ease.InOut,
    }
end

-- Shot builders

---@param pose UgMcCameraPose
---@param forward number meters along the camera heading
---@param up number meters
---@param pitch number degrees added to the pitch
---@param fov? number
---@return UgMcCameraPose
local function offset(pose, forward, up, pitch, fov)
    local x, y = Camera.Forward(pose.rotation.z)

    return {
        coords = vector3(pose.coords.x + x * forward, pose.coords.y + y * forward, pose.coords.z + up),
        rotation = vector3(pose.rotation.x + pitch, pose.rotation.y, pose.rotation.z),
        fov = fov or pose.fov,
    }
end

---The default intro: high and wide behind the rest camera, then a long descent onto the lineup.
---@param rest UgMcCameraPose
---@return UgMcShot[]
function Cinematic.Intro(rest)
    local establishing = offset(rest, -90.0, 55.0, -24.0, rest.fov + 15.0)
    local approach = offset(rest, -18.0, 9.0, -14.0, rest.fov + 5.0)

    return {
        {
            from = establishing,
            to = offset(establishing, 25.0, -12.0, 4.0),
            duration = 3500,
            ease = Ease.Out,
            fadeIn = true,
            letterbox = true,
        },
        {
            from = offset(establishing, 25.0, -12.0, 4.0),
            to = approach,
            duration = 2600,
            ease = Ease.InOut,
        },
        {
            from = approach,
            to = rest,
            duration = 2200,
            ease = Ease.Out,
            letterbox = false,
        },
    }
end

---A short intro for reopening: a pull back onto the rest shot.
---@param rest UgMcCameraPose
---@return UgMcShot[]
function Cinematic.ShortIntro(rest)
    return {
        {
            from = offset(rest, 2.5, 0.4, -2.0, rest.fov - 8.0),
            to = rest,
            duration = 1800,
            ease = Ease.Out,
            fadeIn = true,
            letterbox = false,
        },
    }
end

---Frames a ped from the front, looking at the chest.
---@param ped vector4 ped position and heading
---@param framing UgMcFraming height defaults to 0.75
---@return UgMcCameraPose
function Cinematic.Focus(ped, framing)
    local x, y = Camera.Forward(ped.w)
    local target = vector3(ped.x, ped.y, ped.z + 0.55)
    local coords = vector3(ped.x + x * framing.distance, ped.y + y * framing.distance, ped.z + (framing.height or 0.75))

    return {
        coords = coords,
        rotation = Camera.LookAt(coords, target),
        fov = framing.fov,
    }
end

---Head to toe from the front, for creation.
---@param ped vector4 ped position and heading
---@param framing UgMcFraming
---@return UgMcCameraPose
function Cinematic.FullBody(ped, framing)
    local x, y = Camera.Forward(ped.w)
    local coords = vector3(ped.x + x * framing.distance, ped.y + y * framing.distance, ped.z + (framing.height or 0.0))

    return {
        coords = coords,
        rotation = Camera.LookAt(coords, vector3(ped.x, ped.y, ped.z - 0.1)),
        fov = framing.fov,
    }
end

---Behind and above a player standing at `position`, looking at `look` meters above it.
---@param position vector4
---@param framing UgMcFraming
---@param look number
---@return UgMcCameraPose
function Cinematic.Behind(position, framing, look)
    local x, y = Camera.Forward(position.w)
    local coords = vector3(position.x - x * framing.distance, position.y - y * framing.distance, position.z + (framing.height or 0.0))

    return {
        coords = coords,
        rotation = Camera.LookAt(coords, vector3(position.x, position.y, position.z + look)),
        fov = framing.fov,
    }
end

---Puts every effect back: camera, fades, bars and look.
function Cinematic.Reset()
    Cinematic.Interrupt()
    Camera.Release(0)
    Cinematic.StopLook()
    barTarget, barHeight = 0.0, 0.0

    if IsScreenFadedOut() or IsScreenFadingOut() then
        DoScreenFadeIn(0)
    end
end
