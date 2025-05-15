local DebugServer = true
isProductsSynced = false
isFrameworkReady = false

local function DebugPrint(...)
    if DebugServer then
        print(...)
    end
end

local API = {}

-- Funkcja do liczenia elementów w tablicy asocjacyjnej
function API.TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Pobieranie konfiguracji
function API.GetConfig()
    return Config
end

-- Funkcja pomocnicza do aktualizacji danych biznesu dla klienta
function API.UpdateBusinessDetails(playerId, businessId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono biznesu ID %d w businessCache", businessId))
        xPlayer.showNotification(TranslateCap('invalid_business'))
        return false
    end

    local success, result = pcall(MySQL.query.await, 'SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds, stock, auto_renew FROM businesses WHERE id = ?', { businessId })
    if not success or not result or not result[1] then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych: %s", businessId, tostring(result)))
        xPlayer.showNotification(TranslateCap('database_error'))
        return false
    end

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

    if not configBusiness then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
        xPlayer.showNotification(TranslateCap('invalid_business'))
        return false
    end

    local businessData = {
        id = businessId,
        name = configBusiness.name or "Nieznany Biznes",
        funds = result[1].funds or 0,
        stock = result[1].stock or 0,
        type = business.type or "shop",
        leaseExpiry = leaseExpiry,
        auto_renew = result[1].auto_renew == 1,
        daysRemaining = daysRemaining,
        products = business.products or {},
        owner = business.owner or nil,
        price = business.price or 0
    }

    TriggerClientEvent('esx_economyreworked:updateBusinessDetails', playerId, businessData)
    return true
end

function API.SyncBusinessProducts()
    if not isBusinessCacheReady then
        DebugPrint("[esx_economyreworked] SyncBusinessProducts: businessCache nie jest jeszcze gotowy!")
        return false
    end

    local config = exports.esx_economyreworked:GetConfig()
    if not config or not config.Services or not config.Services.shop then
        DebugPrint("[esx_economyreworked] Błąd: Config.Services.shop jest nil lub nieprawidłowy!")
        isProductsSynced = true
        isFrameworkReady = true
        return false
    end

    -- Pobierz wszystkie biznesy
    local success, businesses = pcall(MySQL.query.await, 'SELECT id, type FROM businesses')
    if not success or not businesses then
        DebugPrint("[esx_economyreworked] Błąd: Nie udało się pobrać biznesów z bazy danych")
        isProductsSynced = true
        isFrameworkReady = true
        return false
    end

    local success = true
    for _, biz in ipairs(businesses) do
        local businessId = biz.id
        if not businessId then
            DebugPrint("[esx_economyreworked] Ostrzeżenie: Pominięto biznes z id=nil")
            success = false
            goto continue
        end
        local businessType = biz.type or 'shop'
        local configProducts = config.Services[businessType] or {}

        -- Pobierz istniejące produkty
        local existingProducts = MySQL.query.await('SELECT product_name FROM business_products WHERE business_id = ?', { businessId }) or {}
        local existingProductNames = {}
        for _, prod in ipairs(existingProducts) do
            if prod.product_name then
                existingProductNames[prod.product_name] = true
            end
        end

        -- Dodaj nowe produkty pojedynczo
        for i, configProd in ipairs(configProducts) do
            if not configProd or type(configProd) ~= 'table' or not configProd.name or not configProd.price or configProd.name == "" then
                DebugPrint(string.format("[esx_economyreworked] Ostrzeżenie: Pominięto nieprawidłowy produkt w Config.Services dla biznesu ID %d, indeks %d: %s", 
                    businessId, i, json.encode(configProd or {})))
                success = false
                goto continueProd
            end
            if not existingProductNames[configProd.name] then
                local query = 'INSERT INTO business_products (business_id, product_name, enabled, price) VALUES (?, ?, ?, ?)'
                local params = { businessId, configProd.name, 0, configProd.price }
                DebugPrint(string.format("[esx_economyreworked] SyncBusinessProducts: Wykonuję INSERT dla produktu %s, biznes ID %d: %s", 
                    configProd.name, businessId, json.encode(params)))
                local insertSuccess = MySQL.query.await(query, params)
                if not insertSuccess then
                    DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się dodać produktu %s dla biznesu ID %d", configProd.name, businessId))
                    success = false
                end
            end
            existingProductNames[configProd.name] = nil
            ::continueProd::
        end

        -- Usuń niepotrzebne produkty pojedynczo
        for productName in pairs(existingProductNames) do
            if productName then
                local query = 'DELETE FROM business_products WHERE business_id = ? AND product_name = ?'
                local params = { businessId, productName }
                DebugPrint(string.format("[esx_economyreworked] SyncBusinessProducts: Wykonuję DELETE dla produktu %s, biznes ID %d: %s", 
                    productName, businessId, json.encode(params)))
                local deleteSuccess = MySQL.query.await(query, params)
                if not deleteSuccess then
                    DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się usunąć produktu %s dla biznesu ID %d", productName, businessId))
                    success = false
                end
            end
        end
        ::continue::
    end

    isProductsSynced = true
    isFrameworkReady = true
    DebugPrint(string.format("[esx_economyreworked] SyncBusinessProducts: Synchronizacja zakończona, sukces=%s", tostring(success)))
    return success
end

-- Eksport do czekania na gotowość frameworku
function API.WaitForFrameworkReady()
    local attempts = 0
    while not isFrameworkReady do
        attempts = attempts + 1
        DebugPrint(string.format("[esx_economyreworked] WaitForFrameworkReady: Czekam na gotowość frameworku (próba %d)", attempts))
        Citizen.Wait(1000)
        if attempts >= 60 then
            DebugPrint("[esx_economyreworked] Błąd: Framework nie osiągnął gotowości po 60 próbach!")
            return false
        end
    end
    return true
end


-- Wykup biznesu
function API.BuyBusiness(businessId, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono biznesu ID %d", businessId))
        return false
    end

    if business.owner then
        xPlayer.showNotification(TranslateCap('business_already_owned'))
        return false
    end

    if business.price <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_business_price'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Biznes ID %d ma nieprawidłową cenę %d", businessId, business.price))
        return false
    end

    if xPlayer.getMoney() < business.price then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return false
    end

    xPlayer.removeMoney(business.price)
    MySQL.query.await('UPDATE businesses SET owner = ?, lease_expiry = DATE_ADD(NOW(), INTERVAL 7 DAY) WHERE id = ?', { xPlayer.identifier, businessId })
    businessCache[businessId].owner = xPlayer.identifier
    businessCache[businessId].lease_expiry = os.time() + (7 * 24 * 60 * 60)
    xPlayer.showNotification(TranslateCap('service_performed'))
    if GetResourceState('esx_shops') == 'started' then
        TriggerClientEvent('esx_shops:refreshBlips', -1)
    else
        DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips")
    end
    DebugPrint(string.format("[esx_economyreworked] Gracz %s kupił biznes ID %d za %d", xPlayer.identifier, businessId, business.price))
    return true
end

-- Sprzedaż produktu
function API.PerformService(businessId, serviceName, amount, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono biznesu ID %d", businessId))
        return false
    end

    local services = Config.Services[business.type]
    if not services then
        xPlayer.showNotification(TranslateCap('invalid_business_type'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Typ biznesu %s nie istnieje w Config.Services", business.type))
        return false
    end

    local service = nil
    for _, s in ipairs(services) do
        if s.name == serviceName then
            service = s
            break
        end
    end

    if not service then
        xPlayer.showNotification(TranslateCap('invalid_product'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono produktu %s dla biznesu ID %d", serviceName, businessId))
        return false
    end

    local isNPC = business.owner == nil
    local product = business.products and business.products[serviceName]
    if not isNPC and (not product or not product.enabled) then
        xPlayer.showNotification(TranslateCap('invalid_product'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Produkt %s nie jest włączony lub nie istnieje dla biznesu ID %d", serviceName, businessId))
        return false
    end

    local price = isNPC and math.floor(service.price * Config.NPCMargin) or (product and product.price or service.price)
    local totalPrice = price * amount
    local stockCost = service.stockCost * amount

    if not isNPC and business.stock < stockCost then
        xPlayer.showNotification(TranslateCap('out_of_stock'))
        return false
    end

    if xPlayer.getMoney() < totalPrice then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return false
    end

    xPlayer.removeMoney(totalPrice)
    if not isNPC then
        MySQL.query.await('UPDATE businesses SET stock = stock - ?, funds = funds + ? WHERE id = ?', { stockCost, totalPrice, businessId })
        businessCache[businessId].stock = businessCache[businessId].stock - stockCost
        businessCache[businessId].funds = businessCache[businessId].funds + totalPrice
        if GetResourceState('esx_shops') == 'started' then
            TriggerClientEvent('esx_shops:refreshBlips', -1)
        else
            DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips")
        end
    end
    xPlayer.showNotification(TranslateCap('service_performed'))
    DebugPrint(string.format("[esx_economyreworked] Gracz %s kupił %d x %s w biznesie ID %d za %d", xPlayer.identifier, amount, serviceName, businessId, totalPrice))
    return true
end

-- Wpłata na konto biznesu
function API.DepositToBusiness(businessId, amount, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono biznesu ID %d", businessId))
        return false
    end

    if business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return false
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    if xPlayer.getAccount('bank').money < amount then
        xPlayer.showNotification(TranslateCap('not_enough_money'))
        return false
    end

    xPlayer.removeAccountMoney('bank', amount)
    MySQL.query.await('UPDATE businesses SET funds = funds + ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = (businessCache[businessId].funds or 0) + amount
    xPlayer.showNotification(TranslateCap('deposited_to_business', ESX.Math.GroupDigits(amount)))
    API.UpdateBusinessDetails(playerId, businessId)
    DebugPrint(string.format("[esx_economyreworked] Gracz %s wpłacił %d do biznesu ID %d", xPlayer.identifier, amount, businessId))
    return true
end

-- Sprzedaż biznesu
function API.SellBusiness(businessId, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    local sellPrice = math.floor(business.price * 0.5)
    local businessFunds = business.funds or 0
    local totalPayout = sellPrice + businessFunds

    MySQL.query.await('UPDATE businesses SET owner = NULL, lease_expiry = NULL, funds = 0, stock = 0 WHERE id = ?', { businessId })
    businessCache[businessId].owner = nil
    businessCache[businessId].funds = 0
    businessCache[businessId].stock = 0
    businessCache[businessId].lease_expiry = 0
    xPlayer.addAccountMoney('bank', totalPayout)
    xPlayer.showNotification(TranslateCap('business_sold', ESX.Math.GroupDigits(totalPayout)))
    if GetResourceState('esx_shops') == 'started' then
        TriggerClientEvent('esx_shops:refreshBlips', -1)
    else
        DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips")
    end
    DebugPrint(string.format("[esx_economyreworked] Gracz %s sprzedał biznes ID %d za %d", xPlayer.identifier, businessId, totalPayout))
    return true
end

-- Wypłata gotówki na konto właściciela
function API.WithdrawToPlayer(businessId, amount, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business then
        xPlayer.showNotification(TranslateCap('invalid_business'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono biznesu ID %d", businessId))
        return false
    end

    if business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        return false
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    if business.funds < amount then
        xPlayer.showNotification(TranslateCap('not_enough_funds'))
        return false
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - amount
    xPlayer.addAccountMoney('bank', amount)
    xPlayer.showNotification(TranslateCap('withdrawn_to_owner', ESX.Math.GroupDigits(amount)))
    API.UpdateBusinessDetails(playerId, businessId)
    DebugPrint(string.format("[esx_economyreworked] Gracz %s wypłacił %d z biznesu ID %d", xPlayer.identifier, amount, businessId))
    return true
end

-- Przelew gotówki na konto innego gracza
function API.TransferToPlayer(businessId, targetPlayerId, amount, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    if business.funds < amount then
        xPlayer.showNotification(TranslateCap('not_enough_funds'))
        return false
    end

    local targetPlayer = ESX.GetPlayerFromId(targetPlayerId)
    if not targetPlayer then
        xPlayer.showNotification(TranslateCap('player_not_online'))
        return false
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ? WHERE id = ?', { amount, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - amount
    targetPlayer.addAccountMoney('bank', amount)
    xPlayer.showNotification(TranslateCap('trans ligado_to_player', ESX.Math.GroupDigits(amount), targetPlayerId))
    targetPlayer.showNotification(TranslateCap('received_from_business', ESX.Math.GroupDigits(amount)))
    API.UpdateBusinessDetails(playerId, businessId)
    DebugPrint(string.format("[esx_economyreworked] Gracz %s przelał %d z biznesu ID %d graczowi ID %d", xPlayer.identifier, amount, businessId, targetPlayerId))
    return true
end

-- Zamówienie dostawy
function API.OrderDelivery(businessId, deliveryType, units, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    if not units or units <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    local maxStock = 10000
    if businessCache[businessId].stock + units > maxStock then
        xPlayer.showNotification(TranslateCap('stock_limit_reached'))
        return false
    end

    if deliveryType == 'instant' then
        local cost = units * Config.BaseResourceCost * 3
        if business.funds < cost then
            xPlayer.showNotification(TranslateCap('not_enough_funds'))
            return false
        end

        MySQL.query.await('UPDATE businesses SET funds = funds - ?, stock = stock + ? WHERE id = ?', { cost, units, businessId })
        businessCache[businessId].funds = businessCache[businessId].funds - cost
        businessCache[businessId].stock = businessCache[businessId].stock + units
        MySQL.query.await('INSERT INTO deliveries (business_id, units, cost, type) VALUES (?, ?, ?, ?)', { businessId, units, cost, deliveryType })
        xPlayer.showNotification(TranslateCap('order_delivery'))
        API.UpdateBusinessDetails(playerId, businessId)
        if GetResourceState('esx_shops') == 'started' then
            TriggerClientEvent('esx_shops:refreshBlips', -1)
        else
            DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips")
        end
        DebugPrint(string.format("[esx_economyreworked] Gracz %s zamówił natychmiastową dostawę %d jednostek dla biznesu ID %d, koszt=%d", xPlayer.identifier, units, businessId, cost))
        return true
    elseif deliveryType == 'standard' then
        local configBusiness = nil
        for _, config in ipairs(Config.Businesses) do
            if config.businessId == businessId then
                configBusiness = config
                break
            end
        end

        if not configBusiness then
            xPlayer.showNotification(TranslateCap('invalid_business'))
            DebugPrint(string.format("[esx_economyreworked] Błąd: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
            return false
        end

        local orderData = {
            businessId = businessId,
            shopName = configBusiness.name,
            units = units,
            wholesalePrice = Config.BaseResourceCost,
            buyPrice = Config.BaseResourceCost * 1.5
        }

        if GetResourceState('esx_delivery') == 'started' then
            TriggerEvent('esx_delivery:registerOrder', orderData)
            xPlayer.showNotification(TranslateCap('order_placed'))
            DebugPrint(string.format("[esx_economyreworked] Gracz %s wystawił zlecenie standardowej dostawy %d jednostek dla biznesu ID %d", xPlayer.identifier, units, businessId))
            return true
        else
            xPlayer.showNotification(TranslateCap('delivery_not_available'))
            DebugPrint("[esx_economyreworked] Błąd: esx_delivery nie jest uruchomiony")
            return false
        end
    end

    xPlayer.showNotification(TranslateCap('invalid_delivery_type'))
    DebugPrint(string.format("[esx_economyreworked] Błąd: Nieprawidłowy typ dostawy %s dla biznesu ID %d", tostring(deliveryType), businessId))
    return false
end

-- Zarządzanie produktami
function API.SetProductDetails(businessId, productName, enabled, price, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    if not price or price <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    local services = Config.Services[business.type]
    if not services then
        xPlayer.showNotification(TranslateCap('invalid_business_type'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Typ biznesu %s nie istnieje w Config.Services", business.type))
        return false
    end

    local productExists = false
    for _, service in ipairs(services) do
        if service.name == productName then
            productExists = true
            break
        end
    end

    if not productExists then
        xPlayer.showNotification(TranslateCap('invalid_product'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Produkt %s nie istnieje dla biznesu ID %d", productName, businessId))
        return false
    end

    local success, existingProduct = pcall(MySQL.query.await, 'SELECT 1 FROM business_products WHERE business_id = ? AND product_name = ?', { businessId, productName })
    if not success then
        xPlayer.showNotification(TranslateCap('database_error'))
        DebugPrint(string.format("[esx_economyreworked] Błąd bazy danych w SetProductDetails dla biznesu ID %d, produkt %s", businessId, productName))
        return false
    end

    if existingProduct and #existingProduct > 0 then
        MySQL.query.await('UPDATE business_products SET enabled = ?, price = ? WHERE business_id = ? AND product_name = ?', { enabled and 1 or 0, price, businessId, productName })
    else
        MySQL.query.await('INSERT INTO business_products (business_id, product_name, enabled, price) VALUES (?, ?, ?, ?)', { businessId, productName, enabled and 1 or 0, price })
    end

    businessCache[businessId].products = businessCache[businessId].products or {}
    businessCache[businessId].products[productName] = {
        enabled = enabled,
        price = price
    }
    xPlayer.showNotification(TranslateCap('product_updated'))
    if GetResourceState('esx_shops') == 'started' then
        TriggerClientEvent('esx_shops:refreshBlips', -1)
        TriggerClientEvent('esx_shops:updateShopProducts', -1, businessId, businessCache[businessId].products)
    else
        DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips i updateShopProducts")
    end
    API.UpdateBusinessDetails(playerId, businessId)
    DebugPrint(string.format("[esx_economyreworked] Gracz %s zaktualizował produkt %s w biznesie ID %d: enabled=%s, price=%d", 
        xPlayer.identifier, productName, businessId, tostring(enabled), price))
    return true
end

-- Wystawienie faktury
function API.IssueInvoice(businessId, amount, isFictitious, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    if not amount or amount <= 0 then
        xPlayer.showNotification(TranslateCap('invalid_amount'))
        return false
    end

    local invoiceCount = MySQL.query.await('SELECT COUNT(*) as count FROM invoices WHERE business_id = ? AND DATE(created_at) = CURDATE()', { businessId })[1].count
    if invoiceCount >= 5 then
        xPlayer.showNotification(TranslateCap('invoice_limit_reached'))
        return false
    end

    MySQL.query.await('INSERT INTO invoices (business_id, amount, is_fictitious) VALUES (?, ?, ?)', { businessId, amount, isFictitious or false })
    xPlayer.showNotification(TranslateCap('issue_invoice'))
    DebugPrint(string.format("[esx_economyreworked] Gracz %s wystawił fakturę dla biznesu ID %d, kwota=%d, fikcyjna=%s", 
        xPlayer.identifier, businessId, amount, tostring(isFictitious)))
    return true
end
-- Update business cache
function API.UpdateBusinessCache(businessId, data)
    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        return false
    end

    if not businessCache[businessId] then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Biznes ID %d nie istnieje w businessCache", businessId))
        return false
    end

    for key, value in pairs(data) do
        businessCache[businessId][key] = value
    end
    return true
end



-- Włączenie/wyłączenie auto odnawiania
function API.ToggleAutoRenew(businessId, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    local newAutoRenew = not business.auto_renew
    MySQL.query.await('UPDATE businesses SET auto_renew = ? WHERE id = ?', { newAutoRenew and 1 or 0, businessId })
    businessCache[businessId].auto_renew = newAutoRenew
    xPlayer.showNotification(newAutoRenew and TranslateCap('auto_renew') or TranslateCap('auto_renew_off'))
    API.UpdateBusinessDetails(playerId, businessId)
    DebugPrint(string.format("[esx_economyreworked] Gracz %s zmienił auto-odnawianie dla biznesu ID %d na %s", 
        xPlayer.identifier, businessId, newAutoRenew and "włączone" or "wyłączone"))
    return true
end

-- Tymczasowe dodawanie zasobów
function API.AddStock(businessId, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie znaleziono gracza ID %d", playerId))
        return false
    end

    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] Błąd: businessCache nie jest zainicjalizowany dla biznesu ID %d", businessId))
        xPlayer.showNotification(TranslateCap('server_error'))
        return false
    end

    local business = businessCache[businessId]
    if not business or business.owner ~= xPlayer.identifier then
        xPlayer.showNotification(TranslateCap('not_owner'))
        DebugPrint(string.format("[esx_economyreworked] Błąd: Gracz %s nie jest właścicielem biznesu ID %d", xPlayer.identifier, businessId))
        return false
    end

    local maxStock = 10000
    if businessCache[businessId].stock + Config.DeliveryUnits > maxStock then
        xPlayer.showNotification(TranslateCap('stock_limit_reached'))
        return false
    end

    MySQL.query.await('UPDATE businesses SET stock = stock + ? WHERE id = ?', { Config.DeliveryUnits, businessId })
    businessCache[businessId].stock = (businessCache[businessId].stock or 0) + Config.DeliveryUnits
    xPlayer.showNotification(TranslateCap('add_stock'))
    API.UpdateBusinessDetails(playerId, businessId)
    if GetResourceState('esx_shops') == 'started' then
        TriggerClientEvent('esx_shops:refreshBlips', -1)
    else
        DebugPrint("[esx_economyreworked] Ostrzeżenie: esx_shops nie jest uruchomiony, pominięto refreshBlips")
    end
    DebugPrint(string.format("[esx_economyreworked] Gracz %s dodał %d jednostek zapasów do biznesu ID %d", 
        xPlayer.identifier, Config.DeliveryUnits, businessId))
    return true
end

-- Pobieranie biznesów
function API.GetBusinesses(type)
    if not isBusinessCacheReady then
        DebugPrint(string.format("[esx_economyreworked] GetBusinesses: businessCache nie jest zainicjalizowany dla typu %s", type or 'wszystkie'))
        return {}
    end

    local businesses = {}
    local query = type and 'SELECT id, owner, price, blocked_until, name, stock FROM businesses WHERE type = ?' or 'SELECT id, owner, price, blocked_until, name, stock FROM businesses'
    local params = type and { type } or {}
    local success, result = pcall(MySQL.query.await, query, params)
    if not success or not result then
        DebugPrint(string.format("[esx_economyreworked] Błąd: Nie udało się pobrać biznesów dla typu %s: %s", type or 'wszystkie', tostring(result)))
        return {}
    end

    for _, row in ipairs(result) do
        for _, business in ipairs(Config.Businesses) do
            if business.businessId == row.id then
                row.name = business.name
                row.coords = business.coords
                break
            end
        end
        table.insert(businesses, row)
    end
    DebugPrint(string.format("[esx_economyreworked] GetBusinesses: Zwrócono %d biznesów dla typu %s", #businesses, type or 'wszystkie'))
    return businesses
end

-- Rejestracja eksportów
for funcName, func in pairs(API) do
    exports(funcName, func)
    DebugPrint(string.format("[esx_economyreworked] Zarejestrowano eksport serwera: %s", funcName))
end

CreateThread(function()
    local attempts = 0
    while not isBusinessCacheReady do
        attempts = attempts + 1
        DebugPrint(string.format("[esx_economyreworked] Czekam na załadowanie businessCache (próba %d)", attempts))
        Citizen.Wait(1000)
        if attempts >= 30 then
            DebugPrint("[esx_economyreworked] Błąd: businessCache nie załadował się po 30 próbach!")
            return
        end
    end
    API.SyncBusinessProducts()
end)