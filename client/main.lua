ESX = exports['es_extended']:getSharedObject()
local DebugClient = false -- Domyślnie debugowanie wyłączone

-- Funkcja debugująca
local function DebugPrint(...)
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

Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        local holdingCoords = vector3(Config.Holding.coords.x, Config.Holding.coords.y, Config.Holding.coords.z)
        local distance = #(coords - holdingCoords)

        if distance < 10.0 then
            DrawMarker(29, holdingCoords.x, holdingCoords.y, holdingCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 0.7, 1.1, 50, 200, 50, 100, false, true, 2, false, nil, nil, false)
            if distance < 3.0 then
                ESX.ShowHelpNotification(TranslateCap('press_to_open_holding'))
                if IsControlJustReleased(0, 38) then
                    OpenHoldingMenu()
                end
            end
        end
        Citizen.Wait(distance < 10.0 and 0 or 500)
    end
end)

-- Menu Business Holding
function OpenHoldingMenu()
    local elements = {}
    ESX.TriggerServerCallback('esx_economyreworked:getBusinesses', function(businesses)
        if businesses then
            for _, business in ipairs(businesses) do
                if not business.owner then
                    local name = business.name or "Nieznany Sklep"
                    local price = business.price and tonumber(business.price) or 0
                    local formattedPrice = ESX.Math.GroupDigits(price) or "0"
                    table.insert(elements, {
                        label = TranslateCap('buy_business', name, formattedPrice),
                        value = business.id
                    })
                end
            end
        else
            ESX.ShowNotification(TranslateCap('error_fetching_businesses'))
        end

        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'holding_menu', {
            title = TranslateCap('holding_menu'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            TriggerServerEvent('esx_economyreworked:buyBusiness', data.current.value)
            menu.close()
        end, function(data, menu)
            menu.close()
        end)
    end, 'shop')
end

-- Menu menedżera
function OpenManageMenu(businessId)
    ESX.TriggerServerCallback('esx_economyreworked:getPlayerBusinesses', function(businesses)
        if not businesses or #businesses == 0 then
            ESX.ShowNotification(TranslateCap('no_businesses'))
            return
        end
        
        -- Jeśli businessId jest podany, otwórz bezpośrednio menu tego biznesu
        if businessId then
            for _, business in ipairs(businesses) do
                if business.id == businessId then
                    OpenBusinessManagementMenu(businessId)
                    return
                end
            end
            ESX.ShowNotification(TranslateCap('business_not_found'))
            return
        end

        -- Jeśli gracz ma tylko jeden biznes, od razu otwórz menu zarządzania
        if #businesses == 1 then
            OpenBusinessManagementMenu(businesses[1].id)
            return
        end

        -- Menu wyboru biznesu
        local elements = {}
        for _, business in ipairs(businesses) do
            table.insert(elements, {
                label = business.name or "Nieznany Biznes",
                value = business.id
            })
        end

        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'select_business', {
            title = TranslateCap('select_business'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            OpenBusinessManagementMenu(data.current.value)
            menu.close()
        end, function(data, menu)
            menu.close()
        end)
    end)
end

function OpenBusinessManagementMenu(businessId, businessData)
    DebugPrint(string.format("[esx_economyreworked] Otwieram OpenBusinessManagementMenu dla biznesu ID %d, businessData=%s", businessId, businessData and "dostępne" or "brak"))

    -- Jeśli mamy dane z eventu, użyj ich bezpośrednio
    if businessData then
        DebugPrint(string.format("[esx_economyreworked] Używam danych z businessData: id=%d, name=%s, auto_renew=%s", businessData.id, businessData.name or "nil", tostring(businessData.auto_renew)))
        local elements = {
            { label = TranslateCap('business_name', businessData.name or "Nieznany Biznes"), unselectable = true },
            { label = TranslateCap('days_paid', businessData.daysRemaining or 0), unselectable = true },
            { label = TranslateCap('business_funds', ESX.Math.GroupDigits(businessData.funds or 0)), unselectable = true },
            { label = TranslateCap('toggle_auto_renew', businessData.auto_renew and TranslateCap('on') or TranslateCap('off')), value = "toggle_auto_renew" },
            { label = TranslateCap('pay_arrears'), value = "pay_arrears" },
            { label = TranslateCap('sell_business'), value = "sell_business" },
            { label = TranslateCap('deposit_to_business'), value = "deposit_to_business" },
            { label = TranslateCap('withdraw_to_player'), value = "withdraw_to_player" },
            { label = TranslateCap('transfer_to_player'), value = "transfer_to_player" },
            { label = TranslateCap('pay_invoices'), value = "pay_invoices" },
            { label = TranslateCap('issue_order'), value = "issue_order" }
        }

        ESX.UI.Menu.CloseAll() -- Zamykamy wszystkie otwarte menu
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'manage_business', {
            title = TranslateCap('manage_menu'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            if data.current.value == "toggle_auto_renew" then
                DebugPrint(string.format("[esx_economyreworked] Wywołano toggle_auto_renew dla biznesu ID %d", businessId))
                TriggerServerEvent('esx_economyreworked:toggleAutoRenew', businessId)
                menu.close()
                -- Czekamy na updateBusinessDetails od serwera
            elseif data.current.value == "pay_arrears" then
                ESX.ShowNotification(TranslateCap('todo'))
            elseif data.current.value == "sell_business" then
                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'confirm_sell', {
                    title = TranslateCap('confirm_sell', businessData.name or "Nieznany Biznes"),
                    align = 'bottom-right',
                    elements = {
                        { label = TranslateCap('yes'), value = 'confirm' },
                        { label = TranslateCap('no'), value = 'cancel' }
                    }
                }, function(data2, menu2)
                    if data2.current.value == 'confirm' then
                        TriggerServerEvent('esx_economyreworked:sellBusiness', businessId)
                        menu2.close()
                        menu.close()
                    else
                        menu2.close()
                    end
                end, function(data2, menu2)
                    menu2.close()
                end)
            elseif data.current.value == "deposit_to_business" then
                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'deposit_amount', {
                    title = TranslateCap('deposit_amount')
                }, function(data2, menu2)
                    local amount = tonumber(data2.value)
                    if amount and amount > 0 then
                        TriggerServerEvent('esx_economyreworked:depositToBusiness', businessId, amount)
                        ESX.UI.Menu.CloseAll()
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                    end
                    menu2.close()
                    menu.close()
                end, function(data2, menu2)
                    menu2.close()
                end)
            elseif data.current.value == "withdraw_to_player" then
                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'withdraw_amount', {
                    title = TranslateCap('withdraw_amount')
                }, function(data2, menu2)
                    local amount = tonumber(data2.value)
                    if amount and amount > 0 then
                        TriggerServerEvent('esx_economyreworked:withdrawToPlayer', businessId, amount)
                        ESX.UI.Menu.CloseAll()
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                    end
                    menu2.close()
                    menu.close()
                end, function(data2, menu2)
                    menu2.close()
                end)
            elseif data.current.value == "transfer_to_player" then
                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_amount', {
                    title = TranslateCap('transfer_amount')
                }, function(data2, menu2)
                    local amount = tonumber(data2.value)
                    if amount and amount > 0 then
                        ESX.UI.Menu.CloseAll()
                        ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_player_id', {
                            title = TranslateCap('transfer_player_id')
                        }, function(data3, menu3)
                            local playerId = tonumber(data3.value)
                            if playerId then
                                TriggerServerEvent('esx_economyreworked:transferToPlayer', businessId, playerId, amount)
                                ESX.UI.Menu.CloseAll()
                            else
                                ESX.ShowNotification(TranslateCap('invalid_player_id'))
                            end
                            menu3.close()
                            menu2.close()
                            menu.close()
                        end, function(data3, menu3)
                            menu3.close()
                        end)
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                        menu2.close()
                    end
                end, function(data2, menu2)
                    menu2.close()
                end)
            elseif data.current.value == "pay_invoices" then
                ESX.ShowNotification(TranslateCap('todo'))
            elseif data.current.value == "issue_order" then
                ESX.ShowNotification(TranslateCap('todo'))
            end
        end, function(data, menu)
            menu.close()
        end)
    else
        -- Jeśli nie mamy danych, pobieramy je z serwera
        DebugPrint(string.format("[esx_economyreworked] Pobieram dane biznesu ID %d z serwera", businessId))
        ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
            if not business then
                ESX.ShowNotification(TranslateCap('business_not_found'))
                DebugPrint(string.format("[esx_economyreworked] Błąd: Dane biznesu ID %d nie zostały zwrócone", businessId))
                return
            end
            DebugPrint(string.format("[esx_economyreworked] Otrzymano dane biznesu ID %d: name=%s, auto_renew=%s", businessId, business.name or "nil", tostring(business.auto_renew)))
            OpenBusinessManagementMenu(businessId, business)
        end, businessId)
    end
end

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

-- Wywołanie OpenManageMenu po naciśnięciu F7
CreateThread(function()
    while true do
        if IsControlJustReleased(0, 168) then -- F7
            OpenManageMenu() -- Nie przekazujemy businessId, menu pokaże listę biznesów
        end
        Wait(0)
    end
end)
