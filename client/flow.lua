--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The client side of the flow: open the scene, follow the page's intents, take the player into the world.

---@class UgMc.Internal.Flow
local Flow = {}
UgMc.Internal.Flow = Flow

local Camera = UgMc.Internal.Camera
local Cinematic = UgMc.Internal.Cinematic
local Scene = UgMc.Internal.Scene
local Nui = UgMc.Internal.Nui
local Picker = UgMc.Internal.Picker
local Appearance = UgMc.Internal.Appearance
local Enums = UgMc.Enums
local Action = Enums.NuiAction
local Screen = Enums.Screen

local RESOURCE = GetCurrentResourceName()
local COLLISION_TIMEOUT = 5000
-- Time for the server to see the new position before Arrived.
local SYNC_DELAY = 400
local SOUND_MOVE, SOUND_SELECT, SOUND_BACK = Enums.Sound.Move, Enums.Sound.Select, Enums.Sound.Back

---@type table? the List answer while the scene is open
local data = nil
---@type UgMcScreen?
local screen = nil
local selected = 1
local skipRequested = false
local openedAt = 0
---@type integer? the empty slot being created
local creating = nil
-- A create or delete waits on the server.
local working = false
---@type { index: integer, appearance: table }? the look made in ug-appearance for the slot being created
local made = nil
---@type { slot: UgMcSlot, options: UgMcSpawnOption[], current: string }? the open spawn picker
local picking = nil
local REFRESH_FADE_MS = 250

---Plays one of the owner's sounds, while `sounds` is on. A sound the owner left out is silent.
---@param name UgMcSound
local function sound(name)
    local effect = data and data.sounds and data.soundEffects and data.soundEffects[name]

    if effect then
        PlaySoundFrontend(-1, effect.name, effect.set, true)
    end
end

---@param message string
---@param ... any
local function log(message, ...)
    print(('[ug-multicharacter] ' .. message):format(...))
end

---Calls a server callback. Answers the server's table, or `{ ok = false, error }` when ug-core refused it.
---@param name string
---@param ... any
---@return table
local function call(name, ...)
    local ok, value, errorCode = UgCore.Callback.Await(RESOURCE .. ':' .. name, ...)

    if not ok or type(value) ~= 'table' then
        return {
            ok = false,
            error = errorCode or UgCore.Enums.Errors.InternalError,
        }
    end

    return value
end

---@param value UgMcScreen?
local function show(value)
    screen = value
    Nui.Send(Action.Screen, {
        screen = value,
    })
end

---@param visible boolean
local function showUi(visible)
    Nui.Send(Action.Visible, {
        visible = visible,
    })
end

---What a card shows: no ids, no raw data.
---@return table[]
local function slotViews()
    local views = {}

    for index = 1, Scene.Count() do
        local slot = Scene.Slot(index)
        local character = slot and slot.character
        local view = {}

        if character then
            local street = nil
            local position = character.position

            if position then
                local hash = GetStreetNameAtCoord(position.x, position.y, position.z)

                street = hash and GetStreetNameFromHashKey(hash) or nil
            end

            view.character = {
                name = character.name,
                birthDate = character.data and character.data.birthDate or nil,
                lastPlayed = character.lastPlayed,
                street = street ~= '' and street or nil,
                deathState = character.deathState,
            }
        end

        views[index] = view
    end

    return views
end

---Glides to a slot without blocking.
---@param index integer
function Flow.Focus(index)
    local slot = Scene.Slot(index)

    if not slot then
        return
    end

    if index ~= selected then
        sound(SOUND_MOVE)
    end

    selected = index

    CreateThread(function()
        local focus = Cinematic.Get().focus

        Cinematic.Play({ Cinematic.GlideTo(Cinematic.Focus(slot.coords, focus), focus.duration, focus.ease) })
    end)
end

---Places the player at the destination once collision is there.
---@param destination vector4
local function place(destination)
    local ped = PlayerPedId()

    -- After SetPlayerModel the ped is new: freeze it before it can fall through unloaded ground.
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(destination.x, destination.y, destination.z)
    SetEntityCoordsNoOffset(ped, destination.x, destination.y, destination.z, false, false, false)
    SetEntityHeading(ped, destination.w)

    local deadline = GetGameTimer() + COLLISION_TIMEOUT

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Wait(0)
    end

    Wait(SYNC_DELAY)
end

---Gives the player the character's model, and its look when ug-appearance runs.
---@param character table
local function dress(character)
    local appearance = data and data.appearances and data.appearances[character.id]
    local model = Appearance.ModelOf(character, appearance)

    if model and UgLib.Streaming.Model(model, 5000) then
        SetPlayerModel(PlayerId(), joaat(model))
        SetPedDefaultComponentVariation(PlayerPedId())
        UgLib.Streaming.Release(UgLib.Enums.Asset.Model, model)
        Appearance.Dress(PlayerPedId(), appearance)
    end
end

---The last part: fade in behind the player, then hand the view to the game camera.
---@param destination vector4
local function arrive(destination)
    local arrival = Cinematic.Get().arrival

    Nui.Send(Action.Close)
    Scene.ShowPlayer()
    Camera.Set(Cinematic.Behind(destination, arrival, 0.6))
    Cinematic.FadeIn()
    Wait(arrival.hold)
    Cinematic.Letterbox(Enums.Letterbox.None)
    Camera.Release(arrival.handover)
    Wait(arrival.handover)
    Cinematic.StopLook()
    FreezeEntityPosition(PlayerPedId(), false)
    data, screen = nil, nil
    log('Character loaded in %d ms.', GetGameTimer() - openedAt)
end

---Back to the lineup after a refusal.
---@param reason any
local function recover(reason)
    log('Could not play: %s.', tostring(reason))
    data, screen = nil, nil

    CreateThread(function()
        Flow.Open(true)
    end)
end

---The chosen character waves while the camera pushes in, then black. MUST run in a thread.
---@param slot UgMcSlot
local function selectShot(slot)
    show(Screen.Busy)
    showUi(false)
    SetNuiFocus(false, false)

    local shot = Cinematic.Get().select

    -- The default gesture MUST be verified on a live server.
    if shot.animation then
        UgLib.Animation.Play(slot.ped, shot.animation.dict, shot.animation.name, {
            flag = 48,
            duration = 2000,
        })
    end

    Cinematic.Play({ Cinematic.GlideTo(Cinematic.Focus(slot.coords, shot), shot.duration, shot.ease) })
    Cinematic.Letterbox(Enums.Letterbox.Full)
    Cinematic.FadeOut()
end

---Asks the server for the destination and takes the player there. MUST run in a thread.
---@param slot UgMcSlot
---@param spawnId string
---@param fromPicker boolean the camera is over the place: dive instead of cutting
local function play(slot, spawnId, fromPicker)
    show(Screen.Busy)
    showUi(false)
    SetNuiFocus(false, false)
    picking = nil

    local result = call('Play', slot.character.id, spawnId)

    if result.ok and fromPicker then
        Picker.Dive(result.destination)
    end

    Picker.Stop()
    Cinematic.FadeOut()
    Scene.Close()

    if not result.ok then
        return recover(result.error)
    end

    dress(slot.character)

    local destination = result.destination

    while true do
        place(destination)

        local arrived = call('Arrived')

        if arrived.ok then
            return arrive(destination)
        end

        if not arrived.retry then
            return recover(arrived.error)
        end

        destination = arrived.destination
    end
end

Nui.On(Enums.NuiCallback.Skip, function()
    -- An intro the owner made unskippable ignores the page.
    if screen == Screen.Intro and Cinematic.Get().skippable ~= false then
        skipRequested = true
    end
end)

Nui.On(Enums.NuiCallback.Hover, function(index)
    if screen == Screen.Select and index ~= selected then
        Flow.Focus(index)
    end
end)

---Sends the form the page shows, and what Lua lets the page send back.
---@param result table the List answer
local function sendForm(result)
    Nui.SetForm(result.fields, result.appearance.models)
    Nui.SetLook(result)
    Nui.Send(Action.Form, {
        fields = Nui.LabelFields(result.fields),
        ageRange = result.ageRange,
        models = result.appearance.models,
        allowDelete = result.allowDelete,
    })
end

---Rebuilds the lineup from a fresh List, behind a short fade, and focuses a slot. MUST run in a thread.
---@param focus integer|fun(result: table): integer
local function refresh(focus)
    local result = call('List')

    if not result.ok then
        log('Could not refresh: %s.', tostring(result.error))

        return
    end

    result.appearances = Appearance.Fetch(result.characters)
    Cinematic.FadeOut(REFRESH_FADE_MS)
    data = result
    Scene.Open(result)
    sendForm(result)
    Nui.Send(Action.Open, {
        slots = slotViews(),
    })

    selected = math.min(math.max(type(focus) == 'function' and focus(result) or focus --[[@as integer]], 1), Scene.Count())

    local slot = Scene.Slot(selected)

    if slot then
        Camera.Set(Cinematic.Focus(slot.coords, Cinematic.Get().focus))
    end

    show(Screen.Select)
    Nui.Send(Action.Focus, {
        index = selected,
    })
    Cinematic.FadeIn(REFRESH_FADE_MS * 2)
end

---Opens creation on an empty slot: a preview body and a full-body shot.
---@param index integer
local function startCreate(index)
    local slot = Scene.Slot(index)

    if not slot or not data then
        return
    end

    sound(SOUND_SELECT)

    creating, selected, made = index, index, nil
    show(Screen.Create)

    CreateThread(function()
        Scene.Preview(index, data.appearance.models[1])
        local create = Cinematic.Get().create

        Cinematic.Play({ Cinematic.GlideTo(Cinematic.FullBody(slot.coords, create), create.duration, create.ease) })
    end)
end

---@param options UgMcSpawnOption[]
---@param id string
---@return UgMcSpawnOption?
local function optionOf(options, id)
    for _, option in ipairs(options) do
        if option.id == id then
            return option
        end
    end

    return nil
end

---Plays a character: straight in when it has one place to go, through the picker otherwise. MUST run in a thread.
---@param slot UgMcSlot
local function choose(slot)
    if not data then
        return
    end

    local options = Picker.Options(slot.character, data.spawn, Nui.Label)

    sound(SOUND_SELECT)
    selectShot(slot)

    if #options == 1 then
        return play(slot, options[1].id, false)
    end

    picking = {
        slot = slot,
        options = options,
        current = options[1].id,
    }

    local views = {}
    local ids = {}

    for index, option in ipairs(options) do
        views[index] = {
            id = option.id,
            label = option.label,
            street = option.street,
        }
        ids[index] = option.id
    end

    Nui.SetSpawns(ids)
    Nui.Send(Action.Spawns, {
        options = views,
        focus = options[1].id,
    })
    show(Screen.Spawn)
    Cinematic.Letterbox(Enums.Letterbox.Rest)
    showUi(true)
    SetNuiFocus(true, true)
    Picker.Fly(options[1])
end

Nui.On(Enums.NuiCallback.Select, function(index)
    if screen ~= Screen.Select or working then
        return
    end

    local slot = Scene.Slot(index)

    if not slot then
        return
    end

    if not slot.character then
        return startCreate(index)
    end

    CreateThread(function()
        choose(slot)
    end)
end)

Nui.On(Enums.NuiCallback.SpawnHover, function(id)
    local option = picking and optionOf(picking.options, id)

    if screen ~= Screen.Spawn or not picking or not option or id == picking.current then
        return
    end

    picking.current = id
    sound(SOUND_MOVE)

    CreateThread(function()
        Picker.Fly(option)
    end)
end)

Nui.On(Enums.NuiCallback.SpawnChoose, function(id)
    if screen ~= Screen.Spawn or not picking then
        return
    end

    local slot = picking.slot

    CreateThread(function()
        play(slot, id, true)
    end)
end)

---Back from the picker to the lineup.
local function leavePicker()
    local slot = picking and picking.slot

    sound(SOUND_BACK)

    picking = nil
    show(Screen.Busy)

    CreateThread(function()
        Cinematic.FadeOut(REFRESH_FADE_MS)
        Picker.Stop()

        if slot then
            Camera.Set(Cinematic.Focus(slot.coords, Cinematic.Get().focus))
        end

        show(Screen.Select)
        Nui.Send(Action.Focus, {
            index = selected,
        })
        Cinematic.FadeIn(REFRESH_FADE_MS * 2)
    end)
end

Nui.On(Enums.NuiCallback.Model, function(model)
    if screen == Screen.Create and creating and not working then
        local index = creating

        made = nil

        CreateThread(function()
            Scene.Preview(index, model)
        end)
    end
end)

Nui.On(Enums.NuiCallback.Cancel, function()
    if screen == Screen.Spawn and picking then
        return leavePicker()
    end

    if screen ~= Screen.Create or working or not creating then
        return
    end

    local index = creating

    sound(SOUND_BACK)
    creating, made = nil, nil
    show(Screen.Select)

    CreateThread(function()
        Scene.Preview(index)
    end)

    Flow.Focus(index)
end)

---Opens the ug-appearance creator on the slot's preview ped, then gives the scene back. MUST run in a thread.
---The look is kept for the slot, so a refused create does not ask for it again.
---@param index integer
---@return table? appearance nil when the player cancelled
local function design(index)
    local slot = Scene.Slot(index)

    if not slot or not data then
        return nil
    end

    if made and made.index == index then
        return made.appearance
    end

    -- The page stays on the form, hidden, so the typed values survive.
    showUi(false)
    SetNuiFocus(false, false)

    local appearance = Appearance.Create(slot.ped, data.appearance.models)
    local create = Cinematic.Get().create

    Camera.Resume()
    Scene.RestoreWorld()
    Camera.Set(Cinematic.FullBody(slot.coords, create))

    if appearance then
        made = {
            index = index,
            appearance = appearance,
        }

        -- The editor dressed a ped of its own: the slot shows the result until the lineup refreshes.
        Scene.Preview(index, appearance.model)

        local shown = Scene.Slot(index)

        if shown then
            Appearance.Dress(shown.ped, appearance)
        end
    end

    showUi(true)
    SetNuiFocus(true, true)

    return appearance
end

Nui.On(Enums.NuiCallback.Submit, function(submission)
    if screen ~= Screen.Create or working or not creating then
        return
    end

    working = true

    local index = creating

    CreateThread(function()
        if Appearance.Enabled() then
            local appearance = design(index)

            if not appearance or creating ~= index then
                Nui.Send(Action.Result, {
                    kind = Enums.ResultKind.Create,
                    ok = false,
                })
                working = false

                return
            end

            submission.model = appearance.model
        end

        local result = call('Create', submission)

        Nui.Send(Action.Result, {
            kind = Enums.ResultKind.Create,
            ok = result.ok == true,
            error = result.error,
        })

        if result.ok then
            creating, made = nil, nil
            refresh(function(list)
                for index, character in ipairs(list.characters) do
                    if character.id == result.characterId then
                        return index
                    end
                end

                return #list.characters
            end)
        end

        working = false
    end)
end)

Nui.On(Enums.NuiCallback.Delete, function(index)
    local slot = Scene.Slot(index)

    if screen ~= Screen.Select or working or not slot or not slot.character then
        return
    end

    working = true

    CreateThread(function()
        local result = call('Delete', slot.character.id)

        Nui.Send(Action.Result, {
            kind = Enums.ResultKind.Delete,
            ok = result.ok == true,
            error = result.error,
        })

        if result.ok then
            refresh(index)
        end

        working = false
    end)
end)

---Shows the title card for a while during the intro.
---@param title string|false
local function titleCard(title)
    if not title then
        return
    end

    CreateThread(function()
        Wait(Cinematic.Get().titleDelay)

        if screen == Screen.Intro then
            Nui.Send(Action.Title, {
                text = title,
                visible = true,
            })
            Wait(Cinematic.Get().titleDuration)
        end

        Nui.Send(Action.Title, {
            text = title,
            visible = false,
        })
    end)
end

---Opens the scene. MUST run in a thread.
---@param short? boolean the short intro, when coming back from the world or an error
function Flow.Open(short)
    if data then
        return
    end

    openedAt = GetGameTimer()
    Cinematic.FadeOut(0)

    local result = call('List')

    if not result.ok then
        log('Scene not opened: %s.', tostring(result.error))
        Cinematic.FadeIn()

        return
    end

    result.appearances = Appearance.Fetch(result.characters)
    data = result
    skipRequested, creating, working, made = false, nil, false, nil
    Cinematic.Configure(result.cinematic)
    Scene.Open(result)
    Cinematic.StartLook()
    sendForm(result)
    Nui.Send(Action.Open, {
        slots = slotViews(),
    })
    show(Screen.Intro)
    showUi(false)
    -- Keyboard only during the intro: Enter and Escape reach the page to skip it, the cursor stays hidden.
    SetNuiFocus(true, false)
    log('Scene opened in %d ms.', GetGameTimer() - openedAt)

    local rest = result.scene.camera
    -- true builds the default shots, a table is the owner's shots, false cuts straight to the lineup.
    local intro = result.cinematic[short and 'reopen' or 'intro']
    local shots = intro == true and (short and Cinematic.ShortIntro(rest) or Cinematic.Intro(rest))
        or type(intro) == 'table' and intro
        or {}

    if not short then
        titleCard(result.cinematic.title)
    end

    if #shots > 0 then
        local finished = Cinematic.Play(shots, function()
            return skipRequested
        end)

        if not finished then
            Cinematic.FadeIn(300)
        end
    else
        Camera.Set(rest)
        Cinematic.FadeIn()
    end

    Nui.Send(Action.Title, {
        text = '',
        visible = false,
    })
    Cinematic.Letterbox(Enums.Letterbox.Rest)
    selected = 1
    show(Screen.Select)
    showUi(true)
    SetNuiFocus(true, true)
    Nui.Send(Action.Focus, {
        index = selected,
    })
    Flow.Focus(selected)
end

---@return boolean
function Flow.IsOpen()
    return data ~= nil
end

---Puts everything back, such as when the resource stops.
function Flow.Reset()
    data, screen, picking, made = nil, nil, nil, nil
    Picker.Stop()
    SetNuiFocus(false, false)
    Nui.Send(Action.Close)
    Scene.Close()
    Cinematic.Reset()
    Scene.ShowPlayer()
    FreezeEntityPosition(PlayerPedId(), false)
end
