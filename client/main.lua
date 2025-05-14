ESX = exports['es_extended']:getSharedObject()
local DebugClient = false -- Domyślnie debugowanie wyłączone

-- Funkcja debugująca
function DebugPrint(...)
    if DebugClient then
        print(...)
    end
end

-- Komenda /debugclient
RegisterCommand('debugclient', function(source, args, rawCommand)
    local xPlayer = ESX.GetPlayerData()
    if xPlayer and xPlayer.group == 'admin' then
        DebugClient = not DebugClient
        ESX.ShowNotification(DebugClient and 'Debugowanie klienta włączone' or 'Debugowanie klienta wyłączone')
        DebugPrint(string.format('[esx_economyreworked] Debugowanie klienta %s', DebugClient and 'włączone' or 'wyłączone'))
    else
        ESX.ShowNotification('Nie masz uprawnień do tej komendy!')
    end
end, false)

-- Tworzenie blipa dla Business Holding
Citizen.CreateThread(function()
    local holding = Config.Holding
    local blip = AddBlipForCoord(holding.coords.x, holding.coords.y, holding.coords.z)
    SetBlipSprite(blip, holding.blip.sprite)
    SetBlipColour(blip, holding.blip.color)
    SetBlipScale(blip, holding.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(holding.blip.name)
    EndTextCommandSetBlipName(blip)
end)

-- Cache'owanie stałych koordynatów
local holdingCoords = vector3(Config.Holding.coords.x, Config.Holding.coords.y, Config.Holding.coords.z)

-- Funkcja do sprawdzania i rysowania markera
local function HandleHoldingMarker()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local distance = #(coords - holdingCoords)

    if distance < 10.0 then
        -- Rysuj marker tylko w bliskim zasięgu
        DrawMarker(29, holdingCoords.x, holdingCoords.y, holdingCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 0.7, 1.1, 50, 200, 50, 100, false, true, 2, false, nil, nil, false)
        if distance < 3.0 then
            -- Pokazuj powiadomienie i sprawdzaj klawisz tylko w bardzo bliskim zasięgu
            ESX.ShowHelpNotification(TranslateCap('press_to_open_holding'))
            if IsControlJustReleased(0, 38) then -- Klawisz E
                OpenHoldingMenu()
            end
        end
        return 0 -- Krótki czas oczekiwania w bliskim zasięgu
    elseif distance < 50.0 then
        return 500 -- Średni czas oczekiwania w większym zasięgu
    else
        return 1000 -- Długi czas oczekiwania, gdy daleko
    end
end

-- Główne zdarzenie z dynamicznym czekaniem
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(HandleHoldingMarker())
    end
end)

-- Wywołanie OpenManageMenu po naciśnięciu F7
CreateThread(function()
    while true do
        if IsControlJustReleased(0, 168) then -- F7
            OpenManageMenu() -- Nie przekazujemy businessId, menu pokaże listę biznesów
        end
        Wait(0)
    end
end)

-- Event do aktualizacji danych biznesu
RegisterNetEvent('esx_economyreworked:updateBusinessDetails')
AddEventHandler('esx_economyreworked:updateBusinessDetails', function(business)
    if not business then
        DebugPrint("[esx_economyreworked] Błąd: Otrzymano nil w updateBusinessDetails")
        return
    end
    DebugPrint(string.format("[esx_economyreworked] Otrzymano updateBusinessDetails: id=%d, name=%s, auto_renew=%s", business.id, business.name or "nil", tostring(business.auto_renew)))
    OpenBusinessManagementMenu(business.id, business)
end)