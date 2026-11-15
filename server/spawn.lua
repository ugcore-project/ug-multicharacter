--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Play and Arrived. The server picks the destination, the client places itself, the server checks, then loads.

---@class UgMc.Internal.Spawn
local Spawn = {}
UgMc.Internal.Spawn = Spawn

local Config = UgMc.Internal.Config
local State = UgMc.Internal.State
local Schema = UgCore.Schema
local Errors = UgCore.Enums.Errors
local Enums = UgMc.Enums
local Logger = UgCore.Logger

-- The player MUST stand this close to the destination, in meters, read from the ped on the server.
local ARRIVAL_DISTANCE = 10.0
-- Failed arrival checks before a kick. The first failure retries the placement.
local MAX_ATTEMPTS = 2

---Where a character goes. Downed and dead characters always go back to where they were.
---@param character UgCharacter
---@param spawnId string `last` or a configured spawn point id
---@return boolean ok
---@return vector4? destination
---@return UgErrorCode? errorCode
function Spawn.Resolve(character, spawnId)
    local spawn = Config.Get().spawn
    local last = character.position or spawn.default
    local alive = character.deathState == UgCore.Enums.DeathState.Alive

    if not alive or spawnId == Enums.SpawnId.Last then
        return true, last, nil
    end

    if character.position == nil and spawn.firstSpawn == Enums.FirstSpawn.Default then
        return true, spawn.default, nil
    end

    for _, point in ipairs(spawn.points) do
        if point.id == spawnId then
            return true, point.coords, nil
        end
    end

    return false, nil, Errors.InvalidArgs
end

---@param source integer
---@param characterId integer
---@return UgCharacter? character
---@return UgErrorCode? errorCode
local function owned(source, characterId)
    local ok, characters, errorCode = UgCore.Characters.GetAll(source)

    if not ok or not characters then
        return nil, errorCode or Errors.InternalError
    end

    for _, character in ipairs(characters) do
        if character.id == characterId then
            return character, nil
        end
    end

    return nil, Errors.NotFound
end

---Chooses a character and a spawn. Answers the destination the client MUST go to.
---@param source integer
---@param characterId integer
---@param spawnId string
---@return table
function Spawn.Play(source, characterId, spawnId)
    local flow = State.Get(source)

    if not flow or flow.phase ~= Enums.Phase.Selecting then
        return {
            ok = false,
            error = Errors.NoPermission,
        }
    end

    return State.Exclusive(flow, function()
        local character, errorCode = owned(source, characterId)

        if not character then
            return {
                ok = false,
                error = errorCode,
            }
        end

        local ok, destination, resolveError = Spawn.Resolve(character, spawnId)

        if not ok or not destination then
            return {
                ok = false,
                error = resolveError,
            }
        end

        flow.phase = Enums.Phase.Placing
        flow.pending = {
            characterId = characterId,
            destination = destination,
            attempts = 0,
        }

        return {
            ok = true,
            destination = destination,
            deathState = character.deathState,
        }
    end)
end

---The client says it stands at the destination. The server checks the ped, then loads the character.
---@param source integer
---@return table
function Spawn.Arrived(source)
    local flow = State.Get(source)
    local pending = flow and flow.pending

    if not flow or flow.phase ~= Enums.Phase.Placing or not pending then
        return {
            ok = false,
            error = Errors.NoPermission,
        }
    end

    return State.Exclusive(flow, function()
        local destination = pending.destination

        if not UgCore.Guard.IsNear(source, vector3(destination.x, destination.y, destination.z), ARRIVAL_DISTANCE) then
            pending.attempts = pending.attempts + 1
            UgCore.Guard.Flag(source, UgCore.Enums.Violations.OutOfRange, 'ug-multicharacter arrival')

            if pending.attempts >= MAX_ATTEMPTS then
                Logger.Warn('Player %d never reached the spawn of character %d. Kicked.', source, pending.characterId)
                State.Close(source)
                UgCore.Players.Kick(source)

                return {
                    ok = false,
                    error = Errors.NoPermission,
                }
            end

            return {
                ok = false,
                error = Errors.InvalidArgs,
                retry = true,
                destination = destination,
            }
        end

        -- The character loads in the default bucket, where the world is.
        State.Release(source)

        local ok, errorCode = UgCore.Characters.Load(source, pending.characterId)

        if not ok then
            flow.phase = Enums.Phase.Selecting
            flow.pending = nil
            State.Isolate(source)

            return {
                ok = false,
                error = errorCode or Errors.InternalError,
            }
        end

        Logger.Debug('player %d loaded character %d.', source, pending.characterId)
        State.Close(source)

        return {
            ok = true,
        }
    end)
end

---Registers the callbacks. Runs once after a clean boot.
function Spawn.Register()
    local Callback = UgCore.Callback

    Callback.Register('Play', {
        schema = Schema.Define({
            Schema.Integer({
                min = 1,
                max = 2147483647,
            }),
            Schema.String({
                min = 1,
                max = 32,
                pattern = '^[%w_%-]+$',
            }),
        }),
        rate = {
            max = 3,
            per = 10000,
        },
    }, Spawn.Play)

    Callback.Register('Arrived', {
        schema = Schema.Define({}),
        rate = {
            max = 3,
            per = 10000,
        },
    }, Spawn.Arrived)
end
