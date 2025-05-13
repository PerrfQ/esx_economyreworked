ESX = exports['es_extended']:getSharedObject()
local businessCache = {}

-- Inicjalizacja cache biznesów
Citizen.CreateThread(function()
    local result = MySQL.query.await('SELECT id, type, owner, stock, funds, blocked_until, price, auto_renew FROM businesses WHERE type = ?', { 'shop' })
    if not result then
        print('[esx_economyreworked] Błąd: Nie udało się pobrać danych z tabeli businesses!')
        return
    end

    for _, row in ipairs(result) do
        businessCache[row.id] = {
            type = row.type,
            owner = row.owner,
            stock = row.stock or 0,
            funds = row.funds or 0,
            blocked_until = row.blocked_until,
            price = row.price or 0,
            auto_renew = row.auto_renew or false
        }
        print(string.format('[esx_economyreworked] Załadowano biznes ID %d: type=%s, owner=%s, stock=%d, funds=%d, price=%d', 
            row.id, row.type, row.owner or 'nil', row.stock or 0, row.funds or 0, row.price or 0))
    end

    if not next(businessCache) then
        print('[esx_economyreworked] Ostrzeżenie: businessCache jest pusty! Sprawdź, czy tabela businesses zawiera rekordy.')
    else
        print(string.format('[esx_economyreworked] Załadowano %d biznesów do businessCache.', tableCount(businessCache)))
    end
end)

-- Funkcja pomocnicza do liczenia elementów w tablicy
function tableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Export konfiguracji dla esx_shops
exports('getConfig', function()
    return Config
end)

-- Callback dla pobierania biznesów
ESX.RegisterServerCallback('esx_economyreworked:getBusinesses', function(source, cb, type)
    local businesses = {}
    for id, business in pairs(businessCache) do
        if business.type == type then
            local configBusiness = nil
            for _, config in ipairs(Config.Businesses) do
                if config.businessId == id then
                    configBusiness = config
                    break
                end
            end
            if configBusiness then
                -- Upewniamy się, że wszystkie pola są zdefiniowane
                if not business.price then
                    print(string.format('[esx_economyreworked] Biznes ID %d ma brakującą cenę (price)!', id))
                    business.price = 0
                end
                if not configBusiness.name then
                    print(string.format('[esx_economyreworked] Biznes ID %d ma brakującą nazwę (name) w Config.Businesses!', id))
                    configBusiness.name = "Nieznany Sklep"
                end
                if not configBusiness.coords then
                    print(string.format('[esx_economyreworked] Biznes ID %d ma brakujące koordynaty (coords) w Config.Businesses!', id))
                    configBusiness.coords = { x = 0.0, y = 0.0, z = 0.0 }
                end
                table.insert(businesses, {
                    id = id,
                    owner = business.owner,
                    price = business.price,
                    blocked_until = business.blocked_until,
                    name = configBusiness.name,
                    coords = configBusiness.coords
                })
            else
                print(string.format('[esx_economyreworked] Brak configu dla biznesu ID %d w Config.Businesses!', id))
            end
        end
    end
    print(string.format('[esx_economyreworked] getBusinesses: Zwracam %d biznesów dla typu %s', #businesses, type))
    cb(businesses)
end)

-- Callback dla pobierania biznesów gracza
ESX.RegisterServerCallback('esx_economyreworked:getPlayerBusinesses', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local businesses = {}

    for id, business in pairs(businessCache) do
        if business.owner == xPlayer.identifier then
            local configBusiness = nil
            for _, config in ipairs(Config.Businesses) do
                if config.businessId == id then
                    configBusiness = config
                    break
                end
            end
            if configBusiness then
                table.insert(businesses, {
                    id = id,
                    name = configBusiness.name or "Nieznany Biznes"
                })
            end
        end
    end

    cb(businesses)
end)

-- Callback dla szczegółów biznesu
ESX.RegisterServerCallback('esx_economyreworked:getBusinessDetails', function(source, cb, businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business then
        cb(nil)
        return
    end

    if business.owner ~= xPlayer.identifier then
        cb(nil)
        return
    end

    local configBusiness = nil
    for _, config in ipairs(Config.Businesses) do
        if config.businessId == businessId then
            configBusiness = config
            break
        end
    end

    if not configBusiness then
        cb(nil)
        return
    end

    local result = MySQL.query.await('SELECT lease_expiry, funds, auto_renew FROM businesses WHERE id = ?', { businessId })
    if result and result[1] then
        cb({
            id = businessId,
            name = configBusiness.name,
            funds = result[1].funds or 0,
            leaseExpiry = result[1].lease_expiry and os.time({year = result[1].lease_expiry.year, month = result[1].lease_expiry.month, day = result[1].lease_expiry.day, hour = result[1].lease_expiry.hour, min = result[1].lease_expiry.min, sec = result[1].lease_expiry.sec}) or 0,
            auto_renew = result[1].auto_renew == 1
        })
    else
        cb(nil)
    end
end)

-- Wykup biznesu
RegisterServerEvent('esx_economyreworked:buyBusiness')
AddEventHandler('esx_economyreworked:buyBusiness', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        return
    end

    if business.owner then
        xPlayer.showNotification(TranslateCap('business_already_owned'))
        return
    end

    if xPlayer.getMoney() < business.price then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return
    end

    xPlayer.removeMoney(business.price)
    MySQL.query.await('UPDATE businesses SET owner = ?, lease_expiry = DATE_ADD(NOW(), INTERVAL 7 DAY) WHERE id = ?', { xPlayer.identifier, businessId })
    businessCache[businessId].owner = xPlayer.identifier
    xPlayer.showNotification(TranslateCap('service_performed'))
    TriggerClientEvent('esx_shops:refreshBlips', -1)
end)

-- Sprzedaż produktu
RegisterServerEvent('esx_economyreworked:performService')
AddEventHandler('esx_economyreworked:performService', function(businessId, serviceName, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]
    local service = nil

    for _, s in ipairs(Config.Services[business.type]) do
        if s.name == serviceName then
            service = s
            break
        end
    end

    if not service then
        xPlayer.showNotification(TranslateCap('invalid_product'))
        return
    end

    local isNPC = business.owner == nil
    local price = isNPC and math.floor(service.price * Config.NPCMargin) or service.price
    local totalPrice = price * amount
    local stockCost = service.stockCost * amount

    if business.stock < stockCost and not isNPC then
        xPlayer.showNotification(TranslateCap('out_of_stock'))
        return
    end

    if xPlayer.getMoney() < totalPrice then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return
    end

    xPlayer.removeMoney(totalPrice)
    if not isNPC then
        MySQL.query.await('UPDATE businesses SET stock = stock - ?, funds = funds + ? WHERE id = ?', { stockCost, totalPrice, businessId })
        businessCache[businessId].stock = businessCache[businessId].stock - stockCost
        businessCache[businessId].funds = businessCache[businessId].funds + totalPrice
    end

    xPlayer.showNotification(TranslateCap('service_performed'))
end)

-- Zamówienie dostawy
RegisterServerEvent('esx_economyreworked:orderDelivery')
AddEventHandler('esx_economyreworked:orderDelivery', function(businessId, deliveryType)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    local cost = deliveryType == 'instant' and Config.BaseDeliveryCost * 2 or Config.BaseDeliveryCost
    if business.funds < cost then
        xPlayer.showNotification(TranslateCap('not_enough_funds'))
        return
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ?, stock = stock + ? WHERE id = ?', { cost, Config.DeliveryUnits, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - cost
    businessCache[businessId].stock = businessCache[businessId].stock + Config.DeliveryUnits
    MySQL.query.await('INSERT INTO deliveries (business_id, units, cost, type) VALUES (?, ?, ?, ?)', { businessId, Config.DeliveryUnits, cost, deliveryType })
    xPlayer.showNotification(TranslateCap('order_delivery'))
end)

-- Wystawienie faktury
RegisterServerEvent('esx_economyreworked:issueInvoice')
AddEventHandler('esx_economyreworked:issueInvoice', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    local invoiceCount = MySQL.query.await('SELECT COUNT(*) as count FROM invoices WHERE business_id = ? AND DATE(created_at) = CURDATE()', { businessId })[1].count
    if invoiceCount >= 5 then
        xPlayer.showNotification(TranslateCap('invoice_limit_reached'))
        return
    end

    MySQL.query.await('INSERT INTO invoices (business_id, amount, is_fictitious) VALUES (?, ?, ?)', { businessId, 1000, false })
    xPlayer.showNotification(TranslateCap('issue_invoice'))
end)

-- Tymczasowe dodawanie zasobów
RegisterServerEvent('esx_economyreworked:addStock')
AddEventHandler('esx_economyreworked:addStock', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    MySQL.query.await('UPDATE businesses SET stock = stock + ? WHERE id = ?', { Config.DeliveryUnits, businessId })
    businessCache[businessId].stock = businessCache[businessId].stock + Config.DeliveryUnits
    xPlayer.showNotification(TranslateCap('add_stock'))
end)

-- Auto-opłacanie
RegisterServerEvent('esx_economyreworked:toggleAutoRenew')
AddEventHandler('esx_economyreworked:toggleAutoRenew', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    local newAutoRenew = not business.auto_renew
    MySQL.query.await('UPDATE businesses SET auto_renew = ? WHERE id = ?', { newAutoRenew, businessId })
    businessCache[businessId].auto_renew = newAutoRenew
    xPlayer.showNotification(newAutoRenew and TranslateCap('auto_renew') or TranslateCap('auto_renew_off'))
end)

-- Sprzedaż biznesu
RegisterServerEvent('esx_economyreworked:sellBusiness')
AddEventHandler('esx_economyreworked:sellBusiness', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    local sellPrice = math.floor(business.price * 0.5) -- 50% ceny zakupu
    MySQL.query.await('UPDATE businesses SET owner = NULL, lease_expiry = NULL, funds = funds + ?, stock = 0 WHERE id = ?', { sellPrice, businessId })
    businessCache[businessId].owner = nil
    businessCache[businessId].funds = (businessCache[businessId].funds or 0) + sellPrice
    businessCache[businessId].stock = 0
    xPlayer.showNotification(TranslateCap('business_sold', ESX.Math.GroupDigits(sellPrice)))
    TriggerClientEvent('esx_shops:refreshBlips', -1)
end)

-- Wypłata gotówki na konto bankowe gracza
RegisterServerEvent('esx_economyreworked:withdrawToPlayer')
AddEventHandler('esx_economyreworked:withdrawToPlayer', function(businessId, playerId, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return
    end

    if business.funds < amount then
        xPlayer.showNotification(TranslateCap('not_enough_funds'))
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(playerId)
    if not targetPlayer then
        xPlayer.showNotification(TranslateCap('player_not_online'))
        return
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - amount
    targetPlayer.addAccountMoney('bank', amount)
    xPlayer.showNotification(TranslateCap('withdrawn_to_player', ESX.Math.GroupDigits(amount), playerId))
    targetPlayer.showNotification(TranslateCap('received_from_business', ESX.Math.GroupDigits(amount)))
end)

-- Przelew gotówki na konto innego gracza
RegisterServerEvent('esx_economyreworked:transferToPlayer')
AddEventHandler('esx_economyreworked:transferToPlayer', function(businessId, playerId, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return
    end

    if business.funds < amount then
        xPlayer.showNotification(TranslateCap('not_enough_funds'))
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(playerId)
    if not targetPlayer then
        xPlayer.showNotification(TranslateCap('player_not_online'))
        return
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - amount
    targetPlayer.addMoney(amount)
    xPlayer.showNotification(TranslateCap('transferred_to_player', ESX.Math.GroupDigits(amount), playerId))
    targetPlayer.showNotification(TranslateCap('received_from_business', ESX.Math.GroupDigits(amount)))
end)

-- Podatki tygodniowe (5% od funds)
Citizen.CreateThread(function()
    while true do
        for id, business in pairs(businessCache) do
            if business.owner and business.funds > 0 then
                local tax = math.floor(business.funds * Config.WeeklyFundsTax)
                MySQL.query.await('UPDATE businesses SET funds = funds - ?, pending_fees = pending_fees + ? WHERE id = ?', { tax, tax, id })
                businessCache[id].funds = businessCache[id].funds - tax
                businessCache[id].pending_fees = (businessCache[id].pending_fees or 0) + tax
                MySQL.query.await('UPDATE treasury SET funds = funds + ? WHERE job_name = ?', { tax, 'treasury' })
            end
        end
        Citizen.Wait(7 * 24 * 60 * 60 * 1000) -- 7 dni
    end
end)

-- Wykrywanie sklepów-duchów
Citizen.CreateThread(function()
    while true do
        for id, business in pairs(businessCache) do
            if business.owner then
                local instantDeliveries = MySQL.query.await('SELECT COUNT(*) as count FROM deliveries WHERE business_id = ? AND type = ? AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)', 
                    { id, 'instant' })[1].count
                local invoicesWithoutDeliveries = MySQL.query.await('SELECT COUNT(*) as count FROM invoices WHERE business_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY) AND NOT EXISTS (SELECT 1 FROM deliveries WHERE business_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY))', 
                    { id, id })[1].count

                if instantDeliveries > 3 or invoicesWithoutDeliveries > 0 then
                    MySQL.query.await('UPDATE businesses SET blocked_until = DATE_ADD(NOW(), INTERVAL 7 DAY) WHERE id = ?', { id })
                    businessCache[id].blocked_until = os.time() + 7 * 24 * 60 * 60
                    TriggerClientEvent('esx_shops:refreshBlips', -1)
                end
            end
        end
        Citizen.Wait(24 * 60 * 60 * 1000) -- 24 godziny
    end
end)