-- main.lua (klient)
ESX = exports['es_extended']:getSharedObject()
local DebugClient = false

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
-- Wywołanie menu lub tabletu po naciśnięciu F7
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if IsControlJustReleased(0, 168) then -- F7
            if GetResourceState('economyreworked_tablet') == 'started' then
                -- Otwieranie tabletu
                ESX.TriggerServerCallback('esx_economyreworked:getPlayerBusinesses', function(businesses)
                    if not businesses or #businesses == 0 then
                        ESX.ShowNotification(TranslateCap('no_businesses'))
                        return
                    end
                    TriggerEvent('economyreworked_tablet:openTablet', businesses)
                end)
            else
                -- Otwieranie natywnego menu
                exports.esx_economyreworked:OpenManageMenu()
            end
        end
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