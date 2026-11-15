--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- ug-multicharacter config. Copied to config.lua in the resource folder on the first start: edit that file, never this one.
-- Updates never overwrite config.lua. A key you remove uses its default.
-- Coordinates are examples. Check them on your server and set your own.
-- Labels come from locales/<code>.json. Set label on a field, option or spawn point to override it.

return {
    -- Creation form. Types: 'text' (min, max letters), 'date' (YYYY-MM-DD, checked against ageRange), 'select' (options).
    -- Labels: fields.<name> and options.<name>.<value> in the locale file.
    fields = {
        {
            name = 'firstName',
            type = 'text',
            min = 2,
            max = 24,
        },
        {
            name = 'lastName',
            type = 'text',
            min = 2,
            max = 24,
        },
        {
            name = 'birthDate',
            type = 'date',
        },
        {
            name = 'sex',
            type = 'select',
            options = {
                {
                    value = 'male',
                },
                {
                    value = 'female',
                },
            },
        },
    },

    -- Allowed age, in years, for 'date' fields.
    ageRange = {
        min = 18,
        max = 90,
    },

    -- The character name, from field names in braces.
    nameFormat = '{firstName} {lastName}',

    -- The lineup, on the terrace of the Galileo Observatory with the city behind the characters.
    -- One slot per character, at least as many as maxCharacters in ug-core's config/characters.lua.
    -- animation: { dict = '...', name = '...', flag = 1 } or { scenario = '...' }.
    scene = {
        camera = {
            coords = vector3(-438.8, 1081.2, 353.3),
            rotation = vector3(-5.0, 0.0, 180.0),
            fov = 45.0,
        },
        slots = {
            {
                coords = vector4(-440.6, 1076.0, 352.36, 0.0),
                animation = {
                    scenario = 'WORLD_HUMAN_TOURIST_MOBILE',
                },
            },
            {
                coords = vector4(-439.4, 1076.2, 352.36, 0.0),
                animation = {
                    scenario = 'WORLD_HUMAN_BINOCULARS',
                },
            },
            {
                coords = vector4(-438.2, 1076.2, 352.36, 0.0),
                animation = {
                    scenario = 'WORLD_HUMAN_SMOKING',
                },
            },
            {
                coords = vector4(-437.0, 1076.0, 352.36, 0.0),
                animation = {
                    scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
                },
            },
        },
        -- Shown on empty slots.
        placeholder = {
            model = 'mp_m_freemode_01',
            animation = {
                scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
            },
        },
        time = {
            hour = 19,
            minute = 45,
        },
        weather = 'EXTRASUNNY',
    },

    spawn = {
        -- First spawn, and the fallback when a character has no saved position.
        default = vector4(195.17, -933.77, 30.69, 144.5),
        -- 'picker' lets new characters choose a spawn point, 'default' sends them to spawn.default.
        firstSpawn = 'picker',
        -- Spawn points players MAY choose. An empty list hides the picker: everyone spawns at their last location.
        -- Labels: spawns.<id> in the locale file.
        points = {
            {
                id = 'legion',
                coords = vector4(195.17, -933.77, 30.69, 144.5),
            },
            {
                id = 'sandy',
                coords = vector4(1853.86, 3685.0, 34.27, 210.0),
            },
            {
                id = 'paleto',
                coords = vector4(-448.4, 6008.2, 31.72, 225.0),
            },
        },
    },

    -- A private routing bucket while choosing, so other players do not see the scene.
    isolate = true,
    -- First bucket used when ug-core's sessions module is off.
    bucketBase = 5000,

    -- Players MAY delete characters, with this many ms between deletes.
    allowDelete = true,
    deleteCooldown = 10000,

    -- Command that sends a player back to the selection, such as 'logout'. false disables it.
    switchCommand = false,

    -- Models offered at creation while ug-appearance is not installed.
    appearance = {
        models = { 'mp_m_freemode_01', 'mp_f_freemode_01' },
    },

    -- Game sounds: move (another slot), select (play, create, spawn), back. { name, set }. A sound left out is silent.
    -- sounds = false turns them all off.
    sounds = true,
    soundEffects = {
        move = {
            name = 'NAV_LEFT_RIGHT',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
        select = {
            name = 'SELECT',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
        back = {
            name = 'BACK',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
    },

    -- Colors, radius, font and scale of the screens, over ug-lib's theme: { mode?, colors?, radius?, font?, scale? }.
    -- colors takes ug-lib's tokens and the accent colors: violet, indigo and blue (the brand gradient), then sky,
    -- emerald, amber, rose, fuchsia and teal (slots, details and spawn points). HSL triplets: '200 80% 55%'.
    -- Each accent's lighter and darker shades follow from the one color.
    theme = {},

    -- The selection screen. Keys you leave out keep their default.
    -- side: 'left' or 'right', where the character panel sits. slots: 'top' or 'bottom', the slot bar.
    -- hint: the keys line. initials: initials on the slot avatars. keyboard: arrows and Enter choose and play.
    -- animations = false keeps the screens still.
    layout = {
        side = 'left',
        slots = 'bottom',
        hint = true,
        initials = true,
        keyboard = true,
        animations = true,
    },

    -- Character details on the panel, in order: 'born', 'lastPlayed', 'location'. {} shows none.
    details = { 'born', 'lastPlayed', 'location' },

    -- Durations are in ms, distances and heights in meters, fov in degrees.
    -- Shots: { from = { coords, rotation, fov }, to = { ... }, duration, ease, fadeIn, fadeOut, letterbox }.
    -- ease: 'linear', 'inOut', 'in' or 'out'.
    cinematic = {
        -- true plays the intro over the scene, false starts at the lineup, or a list of your own shots.
        intro = true,
        -- false: players MUST watch the intro to the end.
        skippable = true,
        -- Reopening the selection (switch command): true plays a short intro, false fades straight in, or your own shots.
        reopen = true,
        -- true shows the server name during the intro, a string shows that text, false hides it.
        title = true,
        titleDelay = 1200,
        titleDuration = 3800,
        letterbox = true,
        -- A timecycle modifier while the scene is open, or false.
        timecycle = false,
        fadeOut = 600,
        fadeIn = 900,
        -- Hovering a character: the camera glides to their face.
        focus = {
            duration = 650,
            distance = 2.4,
            height = 0.75,
            fov = 38.0,
            ease = 'inOut',
        },
        -- Playing a character: a close push-in. animation = false skips the gesture.
        select = {
            duration = 1600,
            distance = 1.45,
            fov = 32.0,
            ease = 'out',
            animation = {
                dict = 'gestures@m@standing@casual',
                name = 'gesture_hello',
            },
        },
        -- Creating a character: a full-body shot of the new ped.
        create = {
            duration = 900,
            distance = 3.6,
            height = 0.15,
            fov = 42.0,
            ease = 'inOut',
        },
        -- Spawn picker: the camera orbits the hovered point. speed is in degrees per second, fade in ms between points.
        flyover = {
            radius = 55.0,
            height = 38.0,
            speed = 6.0,
            fov = 50.0,
            fade = 250,
        },
        -- Confirming a spawn: the camera dives toward the ground.
        dive = {
            duration = 2400,
            distance = 7.0,
            height = 2.5,
            fov = 45.0,
            ease = 'in',
        },
        -- After spawning: a shot behind the ped, held, then handed back to the gameplay camera.
        arrival = {
            distance = 3.2,
            height = 1.3,
            fov = 50.0,
            hold = 1400,
            handover = 1500,
        },
    },
}
