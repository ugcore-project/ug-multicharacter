--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Players in the selection scene: their flow and their private routing bucket.

---@class UgMc.Internal.State
local State = {}
UgMc.Internal.State = State

local Config = UgMc.Internal.Config
local Logger = UgCore.Logger
local Phase = UgMc.Enums.Phase

---@class UgMcPending
---@field characterId integer
---@field destination vector4
---@field attempts integer failed arrival checks

---@class UgMcFlow
---@field phase UgMcPhase
---@field busy boolean a request that waits on the database is running
---@field sessionId? integer ug-core session while isolated through the sessions module
---@field bucket? integer routing bucket while isolated without it
---@field pending? UgMcPending
---@field lastDelete integer GetGameTimer of the last delete, 0 before any
---@field since integer GetGameTimer when the scene opened

---@type table<integer, UgMcFlow>
local flows = {}

---Puts the player in a private routing bucket, when the owner wants it.
---@param source integer
---@param flow UgMcFlow
local function isolate(source, flow)
    if not Config.Get().isolate then
        return
    end

    if UgCore.Modules.IsEnabled('sessions') then
        local ok, sessionId, errorCode = UgCore.Sessions.Create({
            name = ('ug-multicharacter %d'):format(source),
        })

        if ok and sessionId then
            local joined, joinError = UgCore.Sessions.Join(source, sessionId)

            if joined then
                flow.sessionId = sessionId

                return
            end

            errorCode = joinError
            UgCore.Sessions.Destroy(sessionId)
        end

        Logger.Warn('Could not isolate player %d: %s. They share the default bucket while choosing.', source, tostring(errorCode))

        return
    end

    flow.bucket = Config.Get().bucketBase + source
    SetPlayerRoutingBucket(tostring(source), flow.bucket)
end

---Back to the default bucket.
---@param source integer
---@param flow UgMcFlow
local function release(source, flow)
    if flow.sessionId then
        UgCore.Sessions.Leave(source)
        flow.sessionId = nil
    elseif flow.bucket then
        SetPlayerRoutingBucket(tostring(source), 0)
        flow.bucket = nil
    end
end

---Starts a flow, or returns the running one.
---@param source integer
---@return UgMcFlow
function State.Open(source)
    local flow = flows[source]

    if flow then
        return flow
    end

    flow = {
        phase = Phase.Selecting,
        busy = false,
        lastDelete = 0,
        since = GetGameTimer(),
    }
    flows[source] = flow
    isolate(source, flow)

    return flow
end

---@param source integer
---@return UgMcFlow?
function State.Get(source)
    return flows[source]
end

---Ends the flow and gives the player back the default bucket.
---@param source integer
function State.Close(source)
    local flow = flows[source]

    if flow then
        release(source, flow)
        flows[source] = nil
    end
end

---Leaves the private bucket while the flow stays open, right before the character loads in the world.
---@param source integer
function State.Release(source)
    local flow = flows[source]

    if flow then
        release(source, flow)
    end
end

---Back into the private bucket, such as after a load failed.
---@param source integer
function State.Isolate(source)
    local flow = flows[source]

    if flow and not flow.sessionId and not flow.bucket then
        isolate(source, flow)
    end
end

---Runs `fn` while the flow is marked busy. A second request during it is refused.
---@param flow UgMcFlow
---@param fn fun(): table
---@return table result
function State.Exclusive(flow, fn)
    if flow.busy then
        return {
            ok = false,
            error = UgCore.Enums.Errors.RateLimited,
        }
    end

    flow.busy = true

    local ok, result = pcall(fn)

    flow.busy = false

    if not ok then
        error(result, 0)
    end

    return result
end

---@return table<integer, UgMcFlow>
function State.GetAll()
    return flows
end

AddEventHandler('playerDropped', function()
    local dropped = math.tointeger(tonumber(source))

    -- The sessions module removes dropped players from their session itself.
    if dropped then
        flows[dropped] = nil
    end
end)
