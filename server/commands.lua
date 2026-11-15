--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The owner's switch command and the `ugmc` console command.

---@class UgMc.Internal.Commands
local Commands = {}
UgMc.Internal.Commands = Commands

local Config = UgMc.Internal.Config
local State = UgMc.Internal.State
local Logger = UgCore.Logger

local OPEN_EVENT = GetCurrentResourceName() .. ':Open'

---Saves and unloads the character, then sends the player back to the scene.
---@param source integer
---@return boolean ok
function Commands.Reopen(source)
    local player = UgCore.Players.Get(source)

    if not player then
        return false
    end

    if player.characterId then
        local ok, errorCode = UgCore.Characters.Unload(source)

        if not ok then
            Logger.Warn('Could not unload player %d: %s', source, tostring(errorCode))

            return false
        end
    end

    UgCore.Network.TriggerClient(source, OPEN_EVENT)

    return true
end

---@param args string[]
local function console(args)
    local subcommand = args[1]

    if subcommand == 'status' then
        local count = 0

        for source, flow in pairs(State.GetAll()) do
            count = count + 1
            print(('  player %d: %s for %d s%s'):format(
                source,
                flow.phase,
                (GetGameTimer() - flow.since) // 1000,
                flow.pending and (', character %d'):format(flow.pending.characterId) or ''
            ))
        end

        print(('ug-multicharacter: %d player(s) in the scene.'):format(count))

        return
    end

    if subcommand == 'reopen' then
        local target = math.tointeger(tonumber(args[2]))

        if not target or not UgCore.Players.Get(target) then
            print('Usage: ugmc reopen <player id>')

            return
        end

        CreateThread(function()
            print(Commands.Reopen(target) and ('Player %d is back in the scene.'):format(target) or ('Could not reopen the scene for player %d.'):format(target))
        end)

        return
    end

    print('Usage: ugmc status | ugmc reopen <player id>')
end

---Registers the commands. Runs once after a clean boot.
function Commands.Register()
    -- Console only: players never reach it.
    RegisterCommand('ugmc', function(source, args)
        if source == 0 then
            console(args)
        end
    end, true)

    local name = Config.Get().switchCommand

    if name then
        RegisterCommand(name, function(source)
            if source > 0 and not State.Get(source) then
                CreateThread(function()
                    Commands.Reopen(source)
                end)
            end
        end, false)
    end
end
