--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- One scripted camera, moved every frame by this resource. Easing is computed here, not by the game, so every
-- move follows the same curves and the math is testable.

---@class UgMc.Internal.Camera
local Camera = {}
UgMc.Internal.Camera = Camera

local Ease = UgMc.Enums.Ease

---A camera position: where it stands, where it looks (pitch, roll, heading in degrees) and its field of view.
---@class UgMcCameraPose
---@field coords vector3
---@field rotation vector3
---@field fov number

---@type table<UgMcEase, fun(t: number): number>
local CURVES = {
    [Ease.Linear] = function(t)
        return t
    end,
    -- Cubic curves: a soft start and a long settle read as a camera operator, not a machine.
    [Ease.In] = function(t)
        return t * t * t
    end,
    [Ease.Out] = function(t)
        local inverse = 1 - t

        return 1 - inverse * inverse * inverse
    end,
    [Ease.InOut] = function(t)
        if t < 0.5 then
            return 4 * t * t * t
        end

        local inverse = -2 * t + 2

        return 1 - inverse * inverse * inverse / 2
    end,
}

---Eased progress from 0 to 1.
---@param ease UgMcEase?
---@param t number
---@return number
function Camera.Ease(ease, t)
    t = math.min(math.max(t, 0), 1)

    return (CURVES[ease or Ease.InOut] or CURVES[Ease.InOut])(t)
end

---@param a number
---@param b number
---@param t number
---@return number
local function lerp(a, b, t)
    return a + (b - a) * t
end

---Interpolates an angle in degrees along the shortest way round.
---@param a number
---@param b number
---@param t number
---@return number
function Camera.LerpAngle(a, b, t)
    local delta = (b - a + 180) % 360 - 180

    return a + delta * t
end

---The pose at eased progress `t` between two poses.
---@param from UgMcCameraPose
---@param to UgMcCameraPose
---@param t number already eased
---@return UgMcCameraPose
function Camera.Mix(from, to, t)
    return {
        coords = vector3(lerp(from.coords.x, to.coords.x, t), lerp(from.coords.y, to.coords.y, t), lerp(from.coords.z, to.coords.z, t)),
        rotation = vector3(
            Camera.LerpAngle(from.rotation.x, to.rotation.x, t),
            Camera.LerpAngle(from.rotation.y, to.rotation.y, t),
            Camera.LerpAngle(from.rotation.z, to.rotation.z, t)
        ),
        fov = lerp(from.fov, to.fov, t),
    }
end

---Rotation that looks from `from` at `target`, in the game's convention: pitch up is positive, heading 0 looks north.
---@param from vector3
---@param target vector3
---@return vector3
function Camera.LookAt(from, target)
    local dx, dy, dz = target.x - from.x, target.y - from.y, target.z - from.z
    local flat = math.sqrt(dx * dx + dy * dy)

    return vector3(math.deg(math.atan(dz, flat)), 0.0, math.deg(math.atan(-dx, dy)))
end

---Unit vector a heading in degrees faces, on the ground plane.
---@param heading number
---@return number x
---@return number y
function Camera.Forward(heading)
    local radians = math.rad(heading)

    return -math.sin(radians), math.cos(radians)
end

---@type integer?
local handle = nil

---@type UgMcCameraPose?
local current = nil

---Moves the camera to a pose, creating and rendering it the first time.
---@param pose UgMcCameraPose
function Camera.Set(pose)
    local coords, rotation = pose.coords, pose.rotation

    if not handle then
        handle = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z, rotation.x, rotation.y, rotation.z, pose.fov, false, 2)
        SetCamActive(handle, true)
        RenderScriptCams(true, false, 0, true, true)
    else
        SetCamCoord(handle, coords.x, coords.y, coords.z)
        SetCamRot(handle, rotation.x, rotation.y, rotation.z, 2)
        SetCamFov(handle, pose.fov)
    end

    current = pose
end

---Renders the camera again after another resource released script cameras, such as the appearance editor.
function Camera.Resume()
    if handle then
        SetCamActive(handle, true)
        RenderScriptCams(true, false, 0, true, true)
    end
end

---The pose the camera shows now, nil without a camera.
---@return UgMcCameraPose?
function Camera.Get()
    return current
end

---Gives the view back to the game camera, eased over `duration` ms, and destroys the scripted camera.
---@param duration? integer 0 or nil cuts at once
function Camera.Release(duration)
    if not handle then
        return
    end

    RenderScriptCams(false, (duration or 0) > 0, duration or 0, true, true)
    DestroyCam(handle, false)
    handle = nil
    current = nil
end
