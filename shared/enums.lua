--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---Every magic value of this resource. Code and config samples MUST use these.
---@class UgMc.Enums
UgMc.Enums = {}

---Camera easing of a shot.
---@enum UgMcEase
UgMc.Enums.Ease = {
    Linear = 'linear',
    InOut = 'inOut',
    In = 'in',
    Out = 'out',
}

---Creation form field types.
---@enum UgMcFieldType
UgMc.Enums.FieldType = {
    Text = 'text',
    Date = 'date',
    Select = 'select',
}

---Where a new character spawns.
---@enum UgMcFirstSpawn
UgMc.Enums.FirstSpawn = {
    Picker = 'picker',
    Default = 'default',
}

---Spawn choices that are not owner spawn points.
---@enum UgMcSpawnId
UgMc.Enums.SpawnId = {
    Last = 'last',
}

---Where a player is in the flow.
---@enum UgMcPhase
UgMc.Enums.Phase = {
    Selecting = 'selecting',
    Placing = 'placing',
}

---Letterbox bars: full during sequences, thin at rest, or none.
---@enum UgMcLetterbox
UgMc.Enums.Letterbox = {
    Full = 'full',
    Rest = 'rest',
    None = 'none',
}

---Where the character panel sits. MUST match web/src/types/protocol.ts.
---@enum UgMcSide
UgMc.Enums.Side = {
    Left = 'left',
    Right = 'right',
}

---Where the slot bar sits. MUST match web/src/types/protocol.ts.
---@enum UgMcPlace
UgMc.Enums.Place = {
    Top = 'top',
    Bottom = 'bottom',
}

---Character details the panel shows. MUST match web/src/types/protocol.ts.
---@enum UgMcDetail
UgMc.Enums.Detail = {
    Born = 'born',
    LastPlayed = 'lastPlayed',
    Location = 'location',
}

---Sounds of the selection.
---@enum UgMcSound
UgMc.Enums.Sound = {
    Move = 'move',
    Select = 'select',
    Back = 'back',
}

---Messages Lua sends to the page. MUST match web/src/types/protocol.ts.
---@enum UgMcNuiAction
UgMc.Enums.NuiAction = {
    Config = 'config',
    Open = 'open',
    Focus = 'focus',
    Screen = 'screen',
    Title = 'title',
    Visible = 'visible',
    Close = 'close',
    Form = 'form',
    Result = 'result',
    Spawns = 'spawns',
}

---Callbacks the page posts. MUST match web/src/types/protocol.ts.
---@enum UgMcNuiCallback
UgMc.Enums.NuiCallback = {
    Ready = 'ready',
    Hover = 'hover',
    Select = 'select',
    Skip = 'skip',
    Model = 'model',
    Submit = 'submit',
    Cancel = 'cancel',
    Delete = 'delete',
    SpawnHover = 'spawnHover',
    SpawnChoose = 'spawnChoose',
}

---What the page shows. MUST match web/src/types/protocol.ts.
---@enum UgMcScreen
UgMc.Enums.Screen = {
    Intro = 'intro',
    Select = 'select',
    Create = 'create',
    Spawn = 'spawn',
    Busy = 'busy',
}

---What a result message reports. MUST match web/src/types/protocol.ts.
---@enum UgMcResultKind
UgMc.Enums.ResultKind = {
    Create = 'create',
    Delete = 'delete',
}
