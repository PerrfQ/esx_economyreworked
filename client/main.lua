-- main.lua (klient)
ESX = exports['es_extended']:getSharedObject()
local DebugClient = true

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

-- Inicjalizacja
Citizen.CreateThread(function()
    exports.esx_economyreworked:CreateHoldingBlip()
    while true do
        Citizen.Wait(exports.esx_economyreworked:HandleHoldingMarker())
    end
end)

-- Wywołanie OpenManageMenu po naciśnięciu F7
Citizen.CreateThread(function()
    while true do
        if IsControlJustReleased(0, 168) then -- F7
            exports.esx_economyreworked:OpenManageMenu()
        end
        Citizen.Wait(0)
    end
end)

-- Event do aktualizacji danych biznesu
RegisterNetEvent('esx_economyreworked:updateBusinessDetails')
AddEventHandler('esx_economyreworked:updateBusinessDetails', function(business)
    if not business then
        DebugPrint("[esx_economyreworked] Błąd: Otrzymano nil w updateBusinessDetails")
        return
    end
    exports.esx_economyreworked:OpenBusinessManagementMenu(business.id, business)
end)