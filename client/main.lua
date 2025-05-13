ESX = exports['es_extended']:getSharedObject()

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

function OpenBusinessManagementMenu(businessId)
    ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
        if not business then
            ESX.ShowNotification(TranslateCap('business_not_found'))
            return
        end

        local daysRemaining = business.leaseExpiry and math.ceil((business.leaseExpiry - os.time()) / (24 * 60 * 60)) or 0
        if daysRemaining < 0 then daysRemaining = 0 end

        local elements = {
            { label = TranslateCap('business_name', business.name or "Nieznany Biznes"), unselectable = true },
            { label = TranslateCap('days_paid', daysRemaining), unselectable = true },
            { label = TranslateCap('business_funds', ESX.Math.GroupDigits(business.funds or 0)), unselectable = true },
            { label = TranslateCap('toggle_auto_renew', business.auto_renew and TranslateCap('on') or TranslateCap('off')), value = "toggle_auto_renew" },
            { label = TranslateCap('pay_arrears'), value = "pay_arrears" }, -- TODO
            { label = TranslateCap('sell_business'), value = "sell_business" },
            { label = TranslateCap('withdraw_to_player'), value = "withdraw_to_player" },
            { label = TranslateCap('transfer_to_player'), value = "transfer_to_player" },
            { label = TranslateCap('pay_invoices'), value = "pay_invoices" }, -- TODO
            { label = TranslateCap('issue_order'), value = "issue_order" } -- TODO
        }

        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'manage_business', {
            title = TranslateCap('manage_menu'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            if data.current.value == "toggle_auto_renew" then
                TriggerServerEvent('esx_economyreworked:toggleAutoRenew', businessId)
                menu.close()
                OpenBusinessManagementMenu(businessId)
            elseif data.current.value == "pay_arrears" then
                ESX.ShowNotification(TranslateCap('todo'))
            elseif data.current.value == "sell_business" then
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'confirm_sell', {
                    title = TranslateCap('confirm_sell', business.name or "Nieznany Biznes")
                }, function(data2, menu2)
                    if data2.value == "yes" then
                        TriggerServerEvent('esx_economyreworked:sellBusiness', businessId)
                        menu2.close()
                        menu.close()
                    else
                        menu2.close()
                    end
                end, function(data2, menu2)
                    menu2.close()
                end, "yes")
            elseif data.current.value == "withdraw_to_player" then
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'withdraw_amount', {
                    title = TranslateCap('withdraw_amount')
                }, function(data2, menu2)
                    local amount = tonumber(data2.value)
                    if amount and amount > 0 then
                        ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'withdraw_player_id', {
                            title = TranslateCap('withdraw_player_id')
                        }, function(data3, menu3)
                            local playerId = tonumber(data3.value)
                            if playerId then
                                TriggerServerEvent('esx_economyreworked:withdrawToPlayer', businessId, playerId, amount)
                                menu3.close()
                                menu2.close()
                                menu.close()
                            else
                                ESX.ShowNotification(TranslateCap('invalid_player_id'))
                            end
                        end, function(data3, menu3)
                            menu3.close()
                        end)
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                    end
                end, function(data2, menu2)
                    menu2.close()
                end)
            elseif data.current.value == "transfer_to_player" then
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_amount', {
                    title = TranslateCap('transfer_amount')
                }, function(data2, menu2)
                    local amount = tonumber(data2.value)
                    if amount and amount > 0 then
                        ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_player_id', {
                            title = TranslateCap('transfer_player_id')
                        }, function(data3, menu3)
                            local playerId = tonumber(data3.value)
                            if playerId then
                                TriggerServerEvent('esx_economyreworked:transferToPlayer', businessId, playerId, amount)
                                menu3.close()
                                menu2.close()
                                menu.close()
                            else
                                ESX.ShowNotification(TranslateCap('invalid_player_id'))
                            end
                        end, function(data3, menu3)
                            menu3.close()
                        end)
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
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
    end, businessId)
end

-- Odświeżanie blipów po wykupie
RegisterNetEvent('esx_shops:refreshBlips')
AddEventHandler('esx_shops:refreshBlips', function()
    -- Kod odświeżania blipów przeniesiony do esx_shops/client/main.lua
    -- Wywołanie odświeżania w esx_shops
    TriggerEvent('esx_shops:refreshBlips')
end)