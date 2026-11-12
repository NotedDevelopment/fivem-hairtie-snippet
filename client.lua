local config = {
    command = 'hairtie',
    duration = 2000,
    anim = { dict = 'clothingtie', clip = 'check_out_a', flag = 49 },
    checkLoop = false,
    hair = {
        [`mp_m_freemode_01`] = { drawable = 7, texture = 0 },
        [`mp_f_freemode_01`] = { drawable = 4, texture = 0 },
    },
}

local savedHair

local function notify(description, ntype)
    lib.notify({
        title = 'Hair Tie',
        description = description,
        type = ntype or 'inform'
    })
end

local function kvpKey()
    local citizenid = QBX.PlayerData and QBX.PlayerData.citizenid
    return citizenid and 'hairtie:' .. citizenid
end

local function getSettings()
    local key = kvpKey()
    local raw = key and GetResourceKvpString(key)
    if not raw then return {} end
    if raw == 'on' then return { hat = true } end

    local ok, settings = pcall(json.decode, raw)
    return ok and type(settings) == 'table' and settings or {}
end

local function saveSettings(settings)
    local key = kvpKey()
    if not key then return end
    if settings.hat or settings.mask or settings.always then
        SetResourceKvp(key, json.encode(settings))
    else
        DeleteResourceKvp(key)
    end
end

local function isOn(settings)
    return settings.hat or settings.mask or settings.always or false
end

local function wantsTie(ped, settings)
    return settings.always
        or (settings.hat and GetPedPropIndex(ped, 0) ~= -1)
        or (settings.mask and GetPedDrawableVariation(ped, 1) ~= 0)
end

local function update(ped)
    local tie = config.hair[GetEntityModel(ped)]
    if not tie then return end

    local tied = GetPedDrawableVariation(ped, 2) == tie.drawable and GetPedTextureVariation(ped, 2) == tie.texture
    if wantsTie(ped, getSettings()) then
        if tied then return end
        savedHair = { GetPedDrawableVariation(ped, 2), GetPedTextureVariation(ped, 2) }
        SetPedComponentVariation(ped, 2, tie.drawable, tie.texture, 0)
    elseif tied and savedHair then
        SetPedComponentVariation(ped, 2, savedHair[1], savedHair[2], 0)
        savedHair = nil
    end
end

exports('checkHairTie', function()
    update(cache.ped)
end)

local looping = false

local function startLoop()
    if not config.checkLoop or looping then return end
    looping = true
    CreateThread(function()
        while LocalPlayer.state.isLoggedIn and isOn(getSettings()) do
            if not IsNuiFocused() then update(cache.ped) end
            Wait(1000)
        end
        looping = false
    end)
end

lib.onCache('ped', function(value)
    SetTimeout(1000, function()
        if cache.ped == value then update(value) end
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    savedHair = nil
    SetTimeout(5000, function()
        update(cache.ped)
        startLoop()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    savedHair = nil
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    update(cache.ped)
    startLoop()
end)

RegisterCommand(config.command, function()
    if not config.hair[GetEntityModel(cache.ped)] then
        notify("This character can't use a hair tie", 'error')
        return
    end
    if not kvpKey() or lib.progressActive() then return end

    local old = getSettings()
    local input = lib.inputDialog('Hair Tie', {
        { type = 'checkbox', label = 'When wearing a hat', checked = old.hat == true },
        { type = 'checkbox', label = 'When wearing a mask', checked = old.mask == true },
        { type = 'checkbox', label = 'All the time', checked = old.always == true },
    })
    if not input then return end

    local settings = { hat = input[1] == true, mask = input[2] == true, always = input[3] == true }
    local wasOn, nowOn = isOn(old), isOn(settings)

    if wasOn ~= nowOn and not lib.progressBar({
        duration = config.duration,
        label = nowOn and 'Putting on a hair tie' or 'Taking off your hair tie',
        canCancel = true,
        disable = { combat = true },
        anim = config.anim,
    }) then return end

    saveSettings(settings)
    update(cache.ped)
    if nowOn then startLoop() end

    if not nowOn then
        notify('Hair tie off')
    elseif wasOn then
        notify('Hair tie updated')
    else
        notify('Hair tie on')
    end
end, false)

TriggerEvent('chat:addSuggestion', '/' .. config.command, 'Choose when to tie your hair up')
