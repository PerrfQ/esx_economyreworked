ESX = exports['es_extended']:getSharedObject()
local businessCache = {}
local DebugServer = false -- Domyślnie debugowanie wyłączone

-- Funkcja debugująca
local function DebugPrint(...)
    if DebugServer then
        print(...)
    end
end

-- Komenda /debugserver
ESX.RegisterCommand('debugserver', 'admin', function(xPlayer, args, showError)
    DebugServer = not DebugServer
    xPlayer.showNotification(DebugServer and 'Debugowanie serwera włączone' or 'Debugowanie serwera wyłączone')
    DebugPrint(string.format('[esx_economyreworked] Debugowanie serwera %s przez gracza %s', DebugServer and 'włączone' or 'wyłączone', xPlayer.identifier))
end, false, {help = 'Włącza/wyłącza debugowanie serwera dla esx_economyreworked'})

-- Inicjalizacja cache biznesów
Citizen.CreateThread(function()
    local result = MySQL.query.await('SELECT id, type, owner, stock, funds, blocked_until, price, auto_renew, UNIX_TIMESTAMP(lease_expiry) as lease_expiry FROM businesses')
    if not result then
        DebugPrint('[esx_economyreworked] Błąd: Nie udało się pobrać danych z tabeli businesses!')
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
            auto_renew = row.auto_renew == 1,
            lease_expiry = row.lease_expiry or 0 -- Zapisujemy lease_expiry jako timestamp (w sekundach) lub 0, jeśli NULL
        }
        DebugPrint(string.format('[esx_economyreworked] Załadowano biznes ID %d: type=%s, owner=%s, stock=%d, funds=%d, price=%d, lease_expiry=%s', 
            row.id, row.type, row.owner or 'nil', row.stock or 0, row.funds or 0, row.price or 0, tostring(row.lease_expiry)))
    end

    if not next(businessCache) then
        DebugPrint('[esx_economyreworked] Ostrzeżenie: businessCache jest pusty! Sprawdź, czy tabela businesses zawiera rekordy.')
    else
        DebugPrint(string.format('[esx_economyreworked] Załadowano %d biznesów do businessCache.', tableCount(businessCache)))
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
                    DebugPrint(string.format('[esx_economyreworked] Biznes ID %d ma brakującą cenę (price)!', id))
                    business.price = 0
                end
                if not configBusiness.name then
                    DebugPrint(string.format('[esx_economyreworked] Biznes ID %d ma brakującą nazwę (name) w Config.Businesses!', id))
                    configBusiness.name = "Nieznany Sklep"
                end
                if not configBusiness.coords then
                    DebugPrint(string.format('[esx_economyreworked] Biznes ID %d ma brakujące koordynaty (coords) w Config.Businesses!', id))
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
                DebugPrint(string.format('[esx_economyreworked] Brak configu dla biznesu ID %d w Config.Businesses!', id))
            end
        end
    end
    DebugPrint(string.format('[esx_economyreworked] getBusinesses: Zwracam %d biznesów dla typu %s', #businesses, type))
    cb(businesses)
end)

-- Callback dla pobierania biznesów gracza
ESX.RegisterServerCallback('esx_economyreworked:getPlayerBusinesses', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local businesses = {}

    DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Szukam biznesów dla gracza %s (identifier: %s)", xPlayer.getName(), xPlayer.identifier))
    DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Liczba biznesów w businessCache: %d", tableCount(businessCache)))

    for id, business in pairs(businessCache) do
        DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Sprawdzam biznes ID %d: owner=%s", id, business.owner or "nil"))
        if business.owner == xPlayer.identifier then
            local configBusiness = nil
            for _, config in ipairs(Config.Businesses) do
                if config.businessId == id then
                    configBusiness = config
                    break
                end
            end
            if configBusiness then
                DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Znaleziono biznes ID %d: %s", id, configBusiness.name or "Nieznany Biznes"))
                table.insert(businesses, {
                    id = id,
                    name = configBusiness.name or "Nieznany Biznes"
                })
            else
                DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Brak configu dla biznesu ID %d w Config.Businesses!", id))
            end
        end
    end

    DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Zwracam %d biznesów dla gracza", #businesses))
    cb(businesses)
end)

-- Callback dla szczegółów biznesu
ESX.RegisterServerCallback('esx_economyreworked:getBusinessDetails', function(source, cb, businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    local business = businessCache[businessId]

    if not business then
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Biznes ID %d nie istnieje w businessCache!", businessId))
        cb(nil)
        return
    end

    if business.owner ~= xPlayer.identifier then
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Gracz %s nie jest właścicielem biznesu ID %d!", xPlayer.identifier, businessId))
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
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Brak configu dla biznesu ID %d w Config.Businesses!", businessId))
        cb(nil)
        return
    end

    local result = MySQL.query.await('SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds, auto_renew FROM businesses WHERE id = ?', { businessId })
    if result and result[1] then
        -- Obliczanie dni pozostałych na serwerze
        local leaseExpiry = result[1].lease_expiry or 0
        local daysRemaining = leaseExpiry > 0 and math.ceil((leaseExpiry - os.time()) / (24 * 60 * 60)) or 0
        if daysRemaining < 0 then daysRemaining = 0 end

        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Zwrócono szczegóły biznesu ID %d: funds=%d, auto_renew=%s, lease_expiry=%s, daysRemaining=%d", 
            businessId, result[1].funds or 0, tostring(result[1].auto_renew == 1), tostring(leaseExpiry), daysRemaining))
        cb({
            id = businessId,
            name = configBusiness.name,
            funds = result[1].funds or 0,
            leaseExpiry = leaseExpiry,
            auto_renew = result[1].auto_renew == 1,
            daysRemaining = daysRemaining -- Nowe pole
        })
    else
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych!", businessId))
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
    businessCache[businessId].lease_expiry = os.time() + (7 * 24 * 60 * 60) -- 7 dni w sekundach
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

RegisterServerEvent('esx_economyreworked:toggleAutoRenew')
AddEventHandler('esx_economyreworked:toggleAutoRenew', function(businessId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: xPlayer jest nil dla source %s w toggleAutoRenew", tostring(source)))
        return
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Biznes ID %d nie istnieje lub gracz %s nie jest jego właścicielem", businessId, xPlayer.identifier))
        return
    end

    local newAutoRenew = not business.auto_renew
    MySQL.query.await('UPDATE businesses SET auto_renew = ? WHERE id = ?', { newAutoRenew, businessId })
    businessCache[businessId].auto_renew = newAutoRenew
    xPlayer.showNotification(newAutoRenew and TranslateCap('auto_renew') or TranslateCap('auto_renew_off'))
    DebugPrint(string.format("[esx_economyreworked] Zaktualizowano auto_renew dla biznesu ID %d na %s dla gracza %s", businessId, tostring(newAutoRenew), xPlayer.identifier))

    -- Pobieramy zaktualizowane dane biznesu, ale używamy newAutoRenew dla auto_renew
    local result = MySQL.query.await('SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds FROM businesses WHERE id = ?', { businessId })
    if result and result[1] then
        local leaseExpiry = result[1].lease_expiry or 0
        local daysRemaining = leaseExpiry > 0 and math.ceil((leaseExpiry - os.time()) / (24 * 60 * 60)) or 0
        if daysRemaining < 0 then daysRemaining = 0 end

        local configBusiness = nil
        for _, config in ipairs(Config.Businesses) do
            if config.businessId == businessId then
                configBusiness = config
                break
            end
        end

        if configBusiness then
            local businessData = {
                id = businessId,
                name = configBusiness.name,
                funds = result[1].funds or 0,
                leaseExpiry = leaseExpiry,
                auto_renew = newAutoRenew, -- Używamy newAutoRenew zamiast result[1].auto_renew
                daysRemaining = daysRemaining
            }
            TriggerClientEvent('esx_economyreworked:updateBusinessDetails', xPlayer.source, businessData)
            DebugPrint(string.format("[esx_economyreworked] Wysłano updateBusinessDetails dla biznesu ID %d do gracza %s, auto_renew=%s", businessId, xPlayer.identifier, tostring(businessData.auto_renew)))
        else
            DebugPrint(string.format("[esx_economyreworked] Błąd: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
        end
    else
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych", businessId))
    end
end)

-- Wpłata na konto biznesu
RegisterServerEvent('esx_economyreworked:depositToBusiness')
AddEventHandler('esx_economyreworked:depositToBusiness', function(businessId, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        DebugPrint("[esx_economyreworked] Błąd: xPlayer jest nil dla source " .. tostring(source))
        return
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint("[esx_economyreworked] Błąd: Biznes ID " .. businessId .. " nie istnieje w businessCache")
        return
    end

    if business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint("[esx_economyreworked] Błąd: Gracz " .. xPlayer.identifier .. " nie jest właścicielem biznesu ID " .. businessId)
        return
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return
    end

    if xPlayer.getAccount('bank').money < amount then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return
    end

    xPlayer.removeAccountMoney('bank', amount)
    MySQL.query.await('UPDATE businesses SET funds = funds + ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = (businessCache[businessId].funds or 0) + amount
    xPlayer.showNotification(TranslateCap('deposited_to_business', ESX.Math.GroupDigits(amount)))

    -- Aktualizujemy dane biznesu dla klienta
    local result = MySQL.query.await('SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds FROM businesses WHERE id = ?', { businessId })
    if result and result[1] then
        local leaseExpiry = result[1].lease_expiry or 0
        local daysRemaining = leaseExpiry > 0 and math.ceil((leaseExpiry - os.time()) / (24 * 60 * 60)) or 0
        if daysRemaining < 0 then daysRemaining = 0 end

        local configBusiness = nil
        for _, config in ipairs(Config.Businesses) do
            if config.businessId == businessId then
                configBusiness = config
                break
            end
        end

        if configBusiness then
            local businessData = {
                id = businessId,
                name = configBusiness.name,
                funds = result[1].funds or 0,
                leaseExpiry = leaseExpiry,
                auto_renew = business.auto_renew,
                daysRemaining = daysRemaining
            }
            TriggerClientEvent('esx_economyreworked:updateBusinessDetails', xPlayer.source, businessData)
            DebugPrint(string.format("[esx_economyreworked] Wysłano updateBusinessDetails po wpłacie dla biznesu ID %d do gracza %s, funds=%d", businessId, xPlayer.identifier, businessData.funds))
        else
            DebugPrint(string.format("[esx_economyreworked] Błąd: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
        end
    else
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych", businessId))
    end
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
    local businessFunds = business.funds or 0 -- Fundusze biznesu
    local totalPayout = sellPrice + businessFunds -- Całkowita kwota dla gracza

    MySQL.query.await('UPDATE businesses SET owner = NULL, lease_expiry = NULL, funds = 0, stock = 0 WHERE id = ?', { businessId })
    businessCache[businessId].owner = nil
    businessCache[businessId].funds = 0
    businessCache[businessId].stock = 0
    businessCache[businessId].lease_expiry = 0
    xPlayer.addAccountMoney('bank', totalPayout) -- Wypłacamy sumę graczowi
    xPlayer.showNotification(TranslateCap('business_sold', ESX.Math.GroupDigits(totalPayout)))
    TriggerClientEvent('esx_shops:refreshBlips', -1)
end)

-- Wypłata gotówki na konto bankowe właściciela
RegisterServerEvent('esx_economyreworked:withdrawToPlayer')
AddEventHandler('esx_economyreworked:withdrawToPlayer', function(businessId, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        DebugPrint("[esx_economyreworked] Błąd: xPlayer jest nil dla source " .. tostring(source))
        return
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint("[esx_economyreworked] Błąd: Biznes ID " .. businessId .. " nie istnieje w businessCache")
        return
    end

    if business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint("[esx_economyreworked] Błąd: Gracz " .. xPlayer.identifier .. " nie jest właścicielem biznesu ID " .. businessId)
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

    MySQL.query.await('UPDATE businesses SET funds = funds - ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - amount
    xPlayer.addAccountMoney('bank', amount)
    xPlayer.showNotification(TranslateCap('withdrawn_to_owner', ESX.Math.GroupDigits(amount)))

    -- Aktualizujemy dane biznesu dla klienta
    local result = MySQL.query.await('SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds FROM businesses WHERE id = ?', { businessId })
    if result and result[1] then
        local leaseExpiry = result[1].lease_expiry or 0
        local daysRemaining = leaseExpiry > 0 and math.ceil((leaseExpiry - os.time()) / (24 * 60 * 60)) or 0
        if daysRemaining < 0 then daysRemaining = 0 end

        local configBusiness = nil
        for _, config in ipairs(Config.Businesses) do
            if config.businessId == businessId then
                configBusiness = config
                break
            end
        end

        if configBusiness then
            local businessData = {
                id = businessId,
                name = configBusiness.name,
                funds = result[1].funds or 0,
                leaseExpiry = leaseExpiry,
                auto_renew = business.auto_renew,
                daysRemaining = daysRemaining
            }
            TriggerClientEvent('esx_economyreworked:updateBusinessDetails', xPlayer.source, businessData)
            DebugPrint(string.format("[esx_economyreworked] Wysłano updateBusinessDetails po wypłacie dla biznesu ID %d do gracza %s, funds=%d", businessId, xPlayer.identifier, businessData.funds))
        else
            DebugPrint(string.format("[esx_economyreworked] Błąd: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
        end
    else
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych", businessId))
    end
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
    targetPlayer.addAccountMoney('bank', amount)
    xPlayer.showNotification(TranslateCap('transferred_to_player', ESX.Math.GroupDigits(amount), playerId))
    targetPlayer.showNotification(TranslateCap('received_from_business', ESX.Math.GroupDigits(amount)))
end)