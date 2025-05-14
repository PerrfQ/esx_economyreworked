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

        ESX.UI.Menu.CloseAll()
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'holding_menu', {
            title = TranslateCap('holding_menu'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            TriggerServerEvent('esx_economyreworked:buyBusiness', data.current.value)
            menu.close()
        end, function(data, menu)
            menu.close() -- Główne menu zamyka wszystko
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

        ESX.UI.Menu.CloseAll()
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'select_business', {
            title = TranslateCap('select_business'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            OpenBusinessManagementMenu(data.current.value)
            menu.close()
        end, function(data, menu)
            menu.close() -- Główne menu zamyka wszystko
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
            { label = TranslateCap('manage_stock'), value = "manage_stock" },
            { label = TranslateCap('toggle_auto_renew', businessData.auto_renew and TranslateCap('on') or TranslateCap('off')), value = "toggle_auto_renew" },
            { label = TranslateCap('pay_arrears'), value = "pay_arrears" },
            { label = TranslateCap('sell_business'), value = "sell_business" },
            { label = TranslateCap('deposit_to_business'), value = "deposit_to_business" },
            { label = TranslateCap('withdraw_to_player'), value = "withdraw_to_player" },
            { label = TranslateCap('transfer_to_player'), value = "transfer_to_player" },
            { label = TranslateCap('pay_invoices'), value = "pay_invoices" }
        }

        ESX.UI.Menu.CloseAll()
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'manage_business', {
            title = TranslateCap('manage_menu'),
            align = 'bottom-right',
            elements = elements
        }, function(data, menu)
            if data.current.value == "toggle_auto_renew" then
                DebugPrint(string.format("[esx_economyreworked] Wywołano toggle_auto_renew dla biznesu ID %d", businessId))
                TriggerServerEvent('esx_economyreworked:toggleAutoRenew', businessId)
                menu.close()
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
                        OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end
                end, function(data2, menu2)
                    menu2.close()
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
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
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                end, function(data2, menu2)
                    menu2.close()
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
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
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                end, function(data2, menu2)
                    menu2.close()
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
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
                            OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                        end, function(data3, menu3)
                            menu3.close()
                            ESX.UI.Menu.CloseAll()
                            ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_amount', {
                                title = TranslateCap('transfer_amount')
                            }, function(data4, menu4)
                                local amount2 = tonumber(data4.value)
                                if amount2 and amount2 > 0 then
                                    ESX.UI.Menu.CloseAll()
                                    ESX.UI.Menu.Open('dialog', GetCurrentResourceName(), 'transfer_player_id', {
                                        title = TranslateCap('transfer_player_id')
                                    }, function(data5, menu5)
                                        local playerId2 = tonumber(data5.value)
                                        if playerId2 then
                                            TriggerServerEvent('esx_economyreworked:transferToPlayer', businessId, playerId2, amount2)
                                            ESX.UI.Menu.CloseAll()
                                        else
                                            ESX.ShowNotification(TranslateCap('invalid_player_id'))
                                        end
                                        menu5.close()
                                        OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                                    end, function(data5, menu5)
                                        menu5.close()
                                        OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                                    end)
                                else
                                    ESX.ShowNotification(TranslateCap('invalid_amount'))
                                    menu4.close()
                                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                                end
                            end, function(data4, menu4)
                                menu4.close()
                                OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                            end)
                        end)
                    else
                        ESX.ShowNotification(TranslateCap('invalid_amount'))
                        menu2.close()
                        OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end
                end, function(data2, menu2)
                    menu2.close()
                    OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                end)
            elseif data.current.value == "manage_stock" then
                OpenStockManagementMenu(businessId, businessData)
            elseif data.current.value == "pay_invoices" then
                ESX.ShowNotification(TranslateCap('todo'))
            end
        end, function(data, menu)
            menu.close() -- Główne menu zamyka wszystko
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

function OpenStockManagementMenu(businessId, businessData)
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
                            { label = TranslateCap('instant_delivery', ESX.Math.GroupDigits(units * Config.BaseResourceCost * 3)), value = 'instant' }
                        }
                    }, function(data3, menu3)
                        TriggerServerEvent('esx_economyreworked:orderDelivery', businessId, data3.current.value, units)
                        menu3.close()
                        OpenStockManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end, function(data3, menu3)
                        menu3.close()
                        OpenStockManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end)
                else
                    ESX.ShowNotification(TranslateCap('invalid_amount'))
                    menu2.close()
                    OpenStockManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                end
            end, function(data2, menu2)
                menu2.close()
                OpenStockManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
            end)
        elseif data.current.value == "manage_products" then
            OpenProductsMenu(businessId, businessData)
        end
    end, function(data, menu)
        menu.close()
        OpenBusinessManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
    end)
end

function OpenProductsMenu(businessId, businessData)
    ESX.TriggerServerCallback('esx_economyreworked:getBusinessDetails', function(business)
        if not business then
            ESX.ShowNotification(TranslateCap('business_not_found'))
            return
        end

        local elements = {}
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
            local product = business.products and business.products[productName] or { enabled = true, price = Config.Services.shop[productName].price }
            local stockCost = nil
            for _, service in ipairs(Config.Services.shop) do
                if service.name == productName then
                    stockCost = service.stockCost
                    break
                end
            end

            ESX.UI.Menu.CloseAll()
            ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'product_details_' .. productName, {
                title = TranslateCap('product_details', productName),
                align = 'bottom-right',
                elements = {
                    { label = TranslateCap('toggle_product', product.enabled and TranslateCap('on') or TranslateCap('off')), value = "toggle_product" },
                    { label = TranslateCap('set_price'), value = "set_price" },
                    { label = TranslateCap('stock_cost', stockCost or 0), unselectable = true }
                }
            }, function(data2, menu2)
                if data2.current.value == "toggle_product" then
                    local newEnabled = not product.enabled
                    TriggerServerEvent('esx_economyreworked:setProductDetails', businessId, productName, newEnabled, product.price)
                    menu2.close()
                    OpenProductsMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
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
                        OpenProductsMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end, function(data3, menu3)
                        menu3.close()
                        OpenProductsMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
                    end)
                end
            end, function(data2, menu2)
                menu2.close()
                OpenProductsMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
            end)
        end, function(data, menu)
            menu.close()
            OpenStockManagementMenu(businessId, businessData) -- Cofamy do nadrzędnego menu
        end)
    end, businessId)
end