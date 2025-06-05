local DebugClient = false

local function DebugPrint(...)
    if DebugClient then
        print(...)
    end
end

local function IsTabletAvailable()
    return GetResourceState('tablet_ecr') == 'started'
end

local ClientAPI = {}

-- Funkcja do liczenia elementów w tablicy asocjacyjnej
function ClientAPI.TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Pobieranie konfiguracji
function ClientAPI.GetConfig()
    return Config
end

-- Tworzenie blipa dla Business Holding
function ClientAPI.CreateHoldingBlip()
    if not Config.Holding or not Config.Holding.coords or not Config.Holding.blip then
        DebugPrint("[esx_economyreworked] Błąd: Config.Holding jest niepoprawny lub brak danych!")
        return
    end
    local holding = Config.Holding
    local blip = AddBlipForCoord(holding.coords.x, holding.coords.y, holding.coords.z)
    SetBlipSprite(blip, holding.blip.sprite)
    SetBlipColour(blip, holding.blip.color)
    SetBlipScale(blip, holding.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(holding.blip.name)
    EndTextCommandSetBlipName(blip)
    return blip
end

-- Zarządzanie markerem dla Business Holding
function ClientAPI.HandleHoldingMarker()
    if not Config.Holding or not Config.Holding.coords then
        DebugPrint("[esx_economyreworked] Błąd: Config.Holding.coords nie istnieje!")
        return 1000
    end
    local holdingCoords = vector3(Config.Holding.coords.x, Config.Holding.coords.y, Config.Holding.coords.z)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local distance = #(coords - holdingCoords)

    if distance < 10.0 then
        DrawMarker(29, holdingCoords.x, holdingCoords.y, holdingCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 0.7, 1.1, 50, 200, 50, 100, false, true, 2, false, nil, nil, false)
        if distance < 3.0 then
            ESX.ShowHelpNotification(TranslateCap('press_to_open_holding'))
            if IsControlJustReleased(0, 38) then -- Klawisz E
                ClientAPI.OpenHoldingMenu()
            end
        end
        return 0
    elseif distance < 50.0 then
        return 500
    else
        return 1000
    end
end

-- Pobieranie biznesów z serwera
function ClientAPI.GetBusinesses(type, cb)
    if not ESX then
        DebugPrint("[esx_economyreworked] Błąd: ESX nie jest załadowany!")
        cb({})
        return
    end
    ESX.TriggerServerCallback('esx_economyreworked:getBusinesses', function(businesses)
        cb(businesses or {})
    end, type)
end

-- Pobieranie biznesów gracza
function ClientAPI.GetPlayerBusinesses(cb)
    if not ESX then
        DebugPrint("[esx_economyreworked] Błąd: ESX nie jest załadowany!")
        cb({})
        return
    end
    ESX.TriggerServerCallback('esx_economyreworked:getPlayerBusinesses', function(businesses)
        cb(businesses or {})
    end)
end

-- Pobieranie szczegółów biznesu
function ClientAPI.GetBusinessDetails(businessId, cb)
    if not ESX then
        DebugPrint("[esx_economyreworked] Błąd: ESX nie jest załadowany!")
        cb(nil)
        return
    end
    ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
        cb(business or nil)
    end, businessId)
end

-- Otwieranie menu Business Holding
function ClientAPI.OpenHoldingMenu()
    local elements = {}
    ClientAPI.GetBusinesses('shop', function(businesses)
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

        ESX.UI.Menu.CloseAll()
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
    end)
end

function ClientAPI.OpenInvoicesMenu(businessId, businessData)
    if IsTabletAvailable() then
        ESX.TriggerServerCallback('esx_economyreworked:getUnpaidInvoices', function(invoices)
            if not invoices or #invoices == 0 then
                ESX.ShowNotification(TranslateCap('no_unpaid_invoices'))
                TriggerEvent('economyreworked_tablet:openBusinessManagement', businessId, businessData)
                return
            end
            TriggerEvent('economyreworked_tablet:openInvoicesMenu', businessId, invoices, businessData)
        end, businessId)
    else
        ESX.TriggerServerCallback('esx_economyreworked:getUnpaidInvoices', function(invoices)
            if not invoices or #invoices == 0 then
                ESX.ShowNotification(TranslateCap('no_unpaid_invoices'))
                ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
                return
            end

            local elements = {}
            for _, invoice in ipairs(invoices) do
                table.insert(elements, {
                    label = TranslateCap('invoice_entry', invoice.id, ESX.Math.GroupDigits(invoice.amount), invoice.reason == '0' and TranslateCap('no_reason') or invoice.reason),
                    value = invoice.id,
                    amount = invoice.amount
                })
            end

            ESX.UI.Menu.CloseAll()
            ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'invoices_menu', {
                title = TranslateCap('invoices_menu'),
                align = 'bottom-right',
                elements = elements
            }, function(data, menu)
                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'confirm_pay_invoice_' .. data.current.value, {
                    title = TranslateCap('confirm_pay_invoice', ESX.Math.GroupDigits(data.current.amount)),
                    align = 'bottom-right',
                    elements = {
                        { label = TranslateCap('yes'), value = 'confirm' },
                        { label = TranslateCap('no'), value = 'cancel' }
                    }
                }, function(data2, menu2)
                    if data2.current.value == 'confirm' then
                        TriggerServerEvent('esx_economyreworked:payInvoice', businessId, data.current.value, data.current.amount)
                        menu2.close()
                        menu.close()
                    else
                        menu2.close()
                    end
                end, function(data2, menu2)
                    menu2.close()
                end)
            end, function(data, menu)
                menu.close()
                ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
            end)
        end, businessId)
    end
end

-- Otwieranie menu menedżera
function ClientAPI.OpenManageMenu(businessId)
    if IsTabletAvailable() then
        ESX.TriggerServerCallback('esx_economyreworked:getPlayerBusinesses', function(businesses)
            if not businesses or #businesses == 0 then
                ESX.ShowNotification(TranslateCap('no_businesses'))
                return
            end
            if businessId then
                for _, business in ipairs(businesses) do
                    if business.id == businessId then
                        ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(businessData)
                            TriggerEvent('economyreworked_tablet:openBusinessManagement', businessId, businessData)
                        end, businessId)
                        return
                    end
                end
                ESX.ShowNotification(TranslateCap('business_not_found'))
                return
            end
            TriggerEvent('economyreworked_tablet:openTablet', businesses)
        end)
    else
        ClientAPI.GetPlayerBusinesses(function(businesses)
            if not businesses or #businesses == 0 then
                ESX.ShowNotification(TranslateCap('no_businesses'))
                return
            end
            
            if businessId then
                for _, business in ipairs(businesses) do
                    if business.id == businessId then
                        ClientAPI.OpenBusinessManagementMenu(businessId)
                        return
                    end
                end
                ESX.ShowNotification(TranslateCap('business_not_found'))
                return
            end

            if #businesses == 1 then
                ClientAPI.OpenBusinessManagementMenu(businesses[1].id)
                return
            end

            local elements = {}
            for _, business in ipairs(businesses) do
                table.insert(elements, {
                    label = business.name or "Nieznany Biznes",
                    value = business.id
                })
            end

            ESX.UI.Menu.CloseAll()
            ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'select_business', {
                title = TranslateCap('select_business'),
                align = 'bottom-right',
                elements = elements
            }, function(data, menu)
                ClientAPI.OpenBusinessManagementMenu(data.current.value)
                menu.close()
            end, function(data, menu)
                menu.close()
            end)
        end)
    end
end

-- Otwieranie menu zarządzania biznesem
local lastOutOfServicesNotification = 0

function ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
    if IsTabletAvailable() then
        if not businessData then
            ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
                if not business then
                    ESX.ShowNotification(TranslateCap('business_not_found'))
                    return
                end
                TriggerEvent('economyreworked_tablet:openBusinessManagement', businessId, business)
            end, businessId)
            return
        end
        if businessData.stock == 0 then
            local currentTime = GetGameTimer()
            if currentTime - lastOutOfServicesNotification > 5000 then
                ESX.ShowNotification(TranslateCap('out_of_services'))
                lastOutOfServicesNotification = currentTime
            end
        end
        TriggerEvent('economyreworked_tablet:openBusinessManagement', businessId, businessData)
    else
        if businessData then
            if not businessData.id then
                DebugPrint("[esx_economyreworked] Błąd: Brak id w businessData dla businessId=" .. businessId)
                ESX.ShowNotification(TranslateCap('invalid_business_data'))
                return
            end

            businessData.name = businessData.name or "Nieznany Biznes"
            businessData.funds = businessData.funds or 0
            businessData.stock = businessData.stock or 0
            businessData.daysRemaining = businessData.daysRemaining or 0
            businessData.auto_renew = businessData.auto_renew or false
            businessData.products = businessData.products or {}

            DebugPrint(string.format("[esx_economyreworked] OpenBusinessManagementMenu: Biznes ID %d, stock=%d", businessId, businessData.stock))
            local businessType = businessData.type or 'shop'
            if businessData.stock == 0 then
                local currentTime = GetGameTimer()
                if currentTime - lastOutOfServicesNotification > 5000 then
                    ESX.ShowNotification(TranslateCap('out_of_services'))
                    lastOutOfServicesNotification = currentTime
                end
            end

            local elements = {
                { label = TranslateCap('business_name', businessData.name), unselectable = true },
                { label = TranslateCap('days_paid', businessData.daysRemaining), unselectable = true },
                { label = TranslateCap('business_funds', ESX.Math.GroupDigits(businessData.funds)), unselectable = true },
                { label = TranslateCap('manage_stock'), value = "manage_stock" },
                { label = TranslateCap('manage_services'), value = "manage_services" },
                { label = TranslateCap('toggle_auto_renew', businessData.auto_renew and TranslateCap('on') or TranslateCap('off')), value = "toggle_auto_renew" },
                { label = TranslateCap('sell_business'), value = "sell_business" },
                { label = TranslateCap('deposit_to_business'), value = "deposit_to_business" },
                { label = TranslateCap('withdraw_to_player'), value = "withdraw_to_player" },
                { label = TranslateCap('pay_invoices'), value = "pay_invoices" }
            }

            ESX.UI.Menu.CloseAll()
            ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'manage_business', {
                title = TranslateCap('manage_menu'),
                align = 'bottom-right',
                elements = elements
            }, function(data, menu)
                if data.current.value == "manage_services" then
                    ESX.ShowNotification(TranslateCap('todo'))
                elseif data.current.value == "toggle_auto_renew" then
                    TriggerServerEvent('esx_economyreworked:toggleAutoRenew', businessId)
                    menu.close()
                elseif data.current.value == "pay_arrears" then
                    ESX.ShowNotification(TranslateCap('todo'))
                elseif data.current.value == "sell_business" then
                    ESX.UI.Menu.CloseAll()
                    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'confirm_sell', {
                        title = TranslateCap('confirm_sell', businessData.name),
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
                            ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
                        end
                    end, function(data2, menu2)
                        menu2.close()
                        ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
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
                        ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
                    end, function(data2, menu2)
                        menu2.close()
                        ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
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
                        ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
                    end, function(data2, menu2)
                        menu2.close()
                        ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
                    end)
                elseif data.current.value == "manage_stock" then
                    ClientAPI.OpenStockManagementMenu(businessId, businessData)
                elseif data.current.value == "pay_invoices" then
                    ClientAPI.OpenInvoicesMenu(businessId, businessData)
                end
            end, function(data, menu)
                menu.close()
            end)
        else
            ClientAPI.GetBusinessDetails(businessId, function(business)
                if not business then
                    DebugPrint("[esx_economyreworked] Błąd: Nie znaleziono biznesu dla ID " .. businessId)
                    ESX.ShowNotification(TranslateCap('business_not_found'))
                    return
                end
                ClientAPI.OpenBusinessManagementMenu(businessId, business)
            end)
        end
    end
end

-- Otwieranie menu zarządzania zapasami
function ClientAPI.OpenStockManagementMenu(businessId, businessData)
    if IsTabletAvailable() then
        TriggerEvent('economyreworked_tablet:openStockManagement', businessId, businessData)
    else
        local elements = {
            { label = TranslateCap('stock_amount', businessData.stock or 0), unselectable = true },
            { label = TranslateCap('order_delivery'), value = "order_delivery" },
            { label = TranslateCap('manage_products'), value = "manage_products" }
        }

        ESX.UI.Menu.CloseAll()
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'stock_management', {
            title = TranslateCap('stock_management'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            if data.current.value == "order_delivery" then
                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'delivery_amount', {
                    title = TranslateCap('enter_delivery_amount')
                }, function(data2, menu2)
                    local units = tonumber(data2.value)
                    if units and units > 0 then
                        ESX.UI.Menu.CloseAll()
                        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'delivery_type', {
                            title = TranslateCap('select_delivery_type'),
                            align = 'bottom-right',
                            elements = {
                                { label = TranslateCap('standard_delivery'), value = 'standard' },
                                { label = TranslateCap('instant_delivery', ESX.Math.GroupDigits(units * Config.BaseResourceCost * Config.InstantDeliveryMultiplier)), value = 'instant' }
                            }
                        }, function(data3, menu3)
                            if data3.current.value == 'standard' then
                                ESX.UI.Menu.CloseAll()
                                ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'set_buy_price', {
                                    title = TranslateCap('set_buy_price')
                                }, function(data4, menu4)
                                    local buyPrice = tonumber(data4.value)
                                    if buyPrice and buyPrice > 0 then
                                        TriggerServerEvent('esx_economyreworked:orderDelivery', businessId, 'standard', units, buyPrice)
                                        ESX.UI.Menu.CloseAll()
                                    else
                                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                                        menu4.close()
                                        ClientAPI.OpenStockManagementMenu(businessId, businessData)
                                    end
                                end, function(data4, menu4)
                                    menu4.close()
                                    ClientAPI.OpenStockManagementMenu(businessId, businessData)
                                end)
                            else -- instant
                                TriggerServerEvent('esx_economyreworked:orderDelivery', businessId, 'instant', units, nil)
                                menu3.close()
                                ClientAPI.OpenStockManagementMenu(businessId, businessData)
                            end
                        end, function(data3, menu3)
                            menu3.close()
                            ClientAPI.OpenStockManagementMenu(businessId, businessData)
                        end)
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                        menu2.close()
                        ClientAPI.OpenStockManagementMenu(businessId, businessData)
                    end
                end, function(data2, menu2)
                    menu2.close()
                    ClientAPI.OpenStockManagementMenu(businessId, businessData)
                end)
            elseif data.current.value == "manage_products" then
                ClientAPI.OpenProductsMenu(businessId, businessData)
            end
        end, function(data, menu)
            menu.close()
            ClientAPI.OpenBusinessManagementMenu(businessId, businessData)
        end)
    end
end

-- Otwieranie menu produktów
function ClientAPI.OpenProductsMenu(businessId, businessData)
    if IsTabletAvailable() then
        ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
            if not business then
                ESX.ShowNotification(TranslateCap('business_not_found'))
                return
            end
            TriggerEvent('economyreworked_tablet:openProductsManagement', businessId, business.products, businessData)
        end, businessId)
    else
        ClientAPI.GetBusinessDetails(businessId, function(business)
            if not business then
                ESX.ShowNotification(TranslateCap('business_not_found'))
                return
            end

            local elements = {}
            if not Config.Services or not Config.Services.shop then
                DebugPrint("[esx_economyreworked] Błąd: Config.Services.shop nie istnieje!")
                ESX.ShowNotification(TranslateCap('error_fetching_businesses'))
                return
            end

            for _, service in ipairs(Config.Services.shop) do
                local product = business.products and business.products[service.name] or { enabled = true, price = service.price }
                table.insert(elements, {
                    label = TranslateCap('product_entry', service.label, product.enabled and TranslateCap('on') or TranslateCap('off'), ESX.Math.GroupDigits(product.price), service.stockCost),
                    value = service.name
                })
            end

            ESX.UI.Menu.CloseAll()
            ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'products_management', {
                title = TranslateCap('products_management'),
                align = 'bottom-right',
                elements = elements
            }, function(data, menu)
                local productName = data.current.value
                local product = business.products and business.products[productName] or { enabled = true, price = 0 }
                local stockCost = nil
                local defaultPrice = nil
                for _, service in ipairs(Config.Services.shop) do
                    if service.name == productName then
                        stockCost = service.stockCost
                        defaultPrice = service.price
                        break
                    end
                end
                if not stockCost then
                    DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono produktu %s w Config.Services.shop!", productName))
                    ESX.ShowNotification(TranslateCap('invalid_product'))
                    return
                end
                product.price = product.price or defaultPrice or 0

                ESX.UI.Menu.CloseAll()
                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'product_details_' .. productName, {
                    title = TranslateCap('product_details', productName),
                    align = 'bottom-right',
                    elements = {
                        { label = TranslateCap('toggle_product', product.enabled and TranslateCap('on') or TranslateCap('off')), value = "toggle_product" },
                        { label = TranslateCap('set_price'), value = "set_price" },
                        { label = TranslateCap('stock_cost', stockCost), unselectable = true }
                    }
                }, function(data2, menu2)
                    if data2.current.value == "toggle_product" then
                        local newEnabled = not product.enabled
                        TriggerServerEvent('esx_economyreworked:setProductDetails', businessId, productName, newEnabled, product.price)
                        menu2.close()
                        ClientAPI.OpenProductsMenu(businessId, businessData)
                    elseif data2.current.value == "set_price" then
                        ESX.UI.Menu.CloseAll()
                        ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'set_product_price_' .. productName, {
                            title = TranslateCap('set_product_price')
                        }, function(data3, menu3)
                            local newPrice = tonumber(data3.value)
                            if newPrice and newPrice > 0 then
                                TriggerServerEvent('esx_economyreworked:setProductDetails', businessId, productName, product.enabled, newPrice)
                                ESX.UI.Menu.CloseAll()
                            else
                                ESX.ShowNotification(TranslateCap('invalid_amount'))
                            end
                            menu3.close()
                            ClientAPI.OpenProductsMenu(businessId, businessData)
                        end, function(data3, menu3)
                            menu3.close()
                            ClientAPI.OpenProductsMenu(businessId, businessData)
                        end)
                    end
                end, function(data2, menu2)
                    menu2.close()
                    ClientAPI.OpenProductsMenu(businessId, businessData)
                end)
            end, function(data, menu)
                menu.close()
                ClientAPI.OpenStockManagementMenu(businessId, businessData)
            end)
        end)
    end
end

-- Eksport konfiguracji usług
function ClientAPI.GetShopServices()
    return Config.Services.shop
end

-- Rejestracja eksportów
for funcName, func in pairs(ClientAPI) do
    exports(funcName, func)
    DebugPrint(string.format("[esx_economyreworked] Zarejestrowano eksport klienta: %s", funcName))
end