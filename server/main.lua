ESX = exports['es_extended']:getSharedObject()
businessCache = {} -- Globalny businessCache
isBusinessCacheReady = false -- Globalna flaga gotowości cache
IsBusinessDBReady = false -- Globalna flaga gotowości synchronizacji bazy danych
local DebugServer = false

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

ESX.RegisterCommand('debuginvoice', 'admin', function(xPlayer, args, showError)
    if not DebugServer then
        xPlayer.showNotification(TranslateCap('debug_off'))
        DebugPrint('[esx_economyreworked] debuginvoice: Komenda zablokowana, DebugServer=false')
        return
    end

    local businesses = {}
    for id, business in pairs(businessCache) do
        if business.owner == xPlayer.identifier then
            table.insert(businesses, id)
        end
    end

    if #businesses == 0 then
        xPlayer.showNotification(TranslateCap('no_businesses'))
        DebugPrint(string.format('[esx_economyreworked] debuginvoice: Gracz %s nie ma biznesów', xPlayer.identifier))
        return
    end

    for _, businessId in ipairs(businesses) do
        local success = exports.esx_economyreworked:IssueInvoice(businessId, 1000, xPlayer.source, 'debug')
        if success then
            xPlayer.showNotification(string.format('Wystawiono fakturę dla biznesu ID %d na $1000', businessId))
            DebugPrint(string.format('[esx_economyreworked] debuginvoice: Wystawiono fakturę dla biznesu ID %d, gracz %s', businessId, xPlayer.identifier))
        else
            xPlayer.showNotification(string.format('Nie udało się wystawić faktury dla biznesu ID %d', businessId))
            DebugPrint(string.format('[esx_economyreworked] debuginvoice: Błąd przy wystawianiu faktury dla biznesu ID %d, gracz %s', businessId, xPlayer.identifier))
        end
    end
end, false, {help = 'Wystawia fakturę debugową ($1000, powód: debug) dla wszystkich posiadanych biznesów'})


-- Synchronizacja produktów i inicjalizacja cache biznesów
Citizen.CreateThread(function()
    -- Wykonaj synchronizację produktów
    DebugPrint('[esx_economyreworked] Rozpoczynam synchronizację produktów z bazą danych...')
    local success = exports.esx_economyreworked:SyncBusinessProducts()
    if not success then
        DebugPrint('[esx_economyreworked] Błąd: Synchronizacja produktów nie powiodła się!')
        return
    end
    IsBusinessDBReady = true
    DebugPrint('[esx_economyreworked] Synchronizacja produktów zakończona, IsBusinessDBReady=true.')

    -- Inicjalizacja cache biznesów
    local success, result = pcall(MySQL.query.await, 'SELECT id, type, owner, stock, funds, blocked_until, price, auto_renew, UNIX_TIMESTAMP(lease_expiry) as lease_expiry FROM businesses')
    if not success or not result then
        DebugPrint('[esx_economyreworked] Błąd: Nie udało się pobrać danych z tabeli businesses! Sprawdź połączenie z bazą danych.')
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
            lease_expiry = row.lease_expiry or 0,
            products = {}
        }

        local products = MySQL.query.await('SELECT product_name, enabled, price FROM business_products WHERE business_id = ?', { row.id })
        for _, product in ipairs(products or {}) do
            local enabled = product.enabled == 1 or product.enabled == true or product.enabled == "1"
            businessCache[row.id].products[product.product_name] = {
                enabled = enabled,
                price = product.price
            }
            DebugPrint(string.format('[esx_economyreworked] Załadowano produkt dla biznesu ID %d: %s, enabled=%s, price=%d', 
                row.id, product.product_name, tostring(enabled), product.price))
        end

        DebugPrint(string.format('[esx_economyreworked] Załadowano biznes ID %d: type=%s, owner=%s, stock=%d, funds=%d, price=%d, lease_expiry=%s, produktów=%d', 
            row.id, row.type, row.owner or 'nil', row.stock or 0, row.funds or 0, row.price or 0, tostring(row.lease_expiry), exports.esx_economyreworked:TableCount(businessCache[row.id].products)))
    end

    if not next(businessCache) then
        DebugPrint('[esx_economyreworked] Ostrzeżenie: businessCache jest pusty! Sprawdź, czy tabela businesses zawiera rekordy.')
    else
        DebugPrint(string.format('[esx_economyreworked] Załadowano %d biznesów do businessCache.', exports.esx_economyreworked:TableCount(businessCache)))
    end
    isBusinessCacheReady = true
    DebugPrint('[esx_economyreworked] businessCache zainicjalizowany.')
end)

-- Callback dla pobierania biznesów
ESX.RegisterServerCallback('esx_economyreworked:getBusinesses', function(source, cb, businessType)

    if not exports.esx_economyreworked:ValidateFrameworkReady(source, "getBusinesses") then
        cb({})
        return
    end

    local businesses = {}
    for id, business in pairs(businessCache) do
        if not businessType or business.type == businessType then
            local configBusiness = nil
            for _, config in ipairs(Config.Businesses) do
                if config.businessId == id then
                    configBusiness = config
                    break
                end
            end
            table.insert(businesses, {
                id = id,
                owner = business.owner,
                price = business.price,
                blocked_until = business.blocked_until,
                name = configBusiness and configBusiness.name or "Nieznany Biznes",
                coords = configBusiness and configBusiness.coords,
                stock = business.stock,
                funds = business.funds,
                type = business.type,
                auto_renew = business.auto_renew,
                lease_expiry = business.lease_expiry,
                products = business.products
            })
        end
    end
    cb(businesses)
end)

-- Callback dla pobierania biznesów gracza
ESX.RegisterServerCallback('esx_economyreworked:getPlayerBusinesses', function(source, cb)
    if not exports.esx_economyreworked:ValidateFrameworkReady(source, "getPlayerBusinesses") then
        cb({})
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Nie znaleziono gracza ID %d!", source))
        cb({})
        return
    end

    local businesses = {}
    DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Szukam biznesów dla gracza %s (identifier: %s)", xPlayer.getName(), xPlayer.identifier))
    DebugPrint(string.format("[esx_economyreworked] getPlayerBusinesses: Liczba biznesów w businessCache: %d", exports.esx_economyreworked:TableCount(businessCache)))

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
    if not exports.esx_economyreworked:ValidateFrameworkReady(source, "getBusinessDetails") then
        cb({})
        return
    end

    if not xPlayer then
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Nie znaleziono gracza ID %d!", source))
        cb(nil)
        return
    end


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

    -- Funkcja pomocnicza do pobrania pełnych danych biznesu
    local function getBusinessData(playerId, businessId)
        local business = businessCache[businessId]
        local success, result = pcall(MySQL.query.await, 'SELECT UNIX_TIMESTAMP(lease_expiry) as lease_expiry, funds, stock, auto_renew FROM businesses WHERE id = ?', { businessId })
        if not success or not result or not result[1] then
            DebugPrint(string.format("[esx_economyreworked] getBusinessData: Nie udało się pobrać szczegółów biznesu ID %d z bazy danych: %s", businessId, tostring(result)))
            return nil
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
            DebugPrint(string.format("[esx_economyreworked] getBusinessData: Brak configu dla biznesu ID %d w Config.Businesses", businessId))
            return nil
        end
            
        return {
            id = businessId,
            name = configBusiness.name or "Nieznany Biznes",
            funds = result[1].funds or 0,
            stock = result[1].stock or 0,
            type = business.type or "shop",
            leaseExpiry = leaseExpiry,
            auto_renew = result[1].auto_renew,
            daysRemaining = daysRemaining,
            products = business.products or {},
            owner = business.owner or nil,
            price = business.price or 0
        }
    end

    local businessData = getBusinessData(source, businessId)
    if not businessData then
        DebugPrint(string.format("[esx_economyreworked] getBusinessDetails: Nie udało się pobrać danych dla businessId=%d", businessId))
        cb(nil)
        return
    end

    cb(businessData)
end)

ESX.RegisterServerCallback('esx_economyreworked:getConfig', function(source, cb)
    local config = {
        BaseResourceCost = Config.BaseResourceCost or 1,
        InstantDeliveryMultiplier = Config.InstantDeliveryMultiplier or 2.5
    }
    print("[DEBUG] getConfig: Sending config, BaseResourceCost:", config.BaseResourceCost, "InstantDeliveryMultiplier:", config.InstantDeliveryMultiplier)
    cb(config)
end)

-- Eventy serwerowe
RegisterServerEvent('esx_economyreworked:buyBusiness')
AddEventHandler('esx_economyreworked:buyBusiness', function(businessId)
    exports.esx_economyreworked:BuyBusiness(businessId, source)
end)

RegisterServerEvent('esx_economyreworked:performService')
AddEventHandler('esx_economyreworked:performService', function(businessId, serviceName, amount)
    exports.esx_economyreworked:PerformService(businessId, serviceName, amount, source)
end)

RegisterServerEvent('esx_economyreworked:depositToBusiness')
AddEventHandler('esx_economyreworked:depositToBusiness', function(businessId, amount)
    exports.esx_economyreworked:DepositToBusiness(businessId, amount, source)
end)

RegisterServerEvent('esx_economyreworked:sellBusiness')
AddEventHandler('esx_economyreworked:sellBusiness', function(businessId)
    exports.esx_economyreworked:SellBusiness(businessId, source)
end)

RegisterServerEvent('esx_economyreworked:payInvoice')
AddEventHandler('esx_economyreworked:payInvoice', function(businessId, invoiceId, amount)
    exports.esx_economyreworked:PayInvoice(businessId, invoiceId, amount, source)
end)

ESX.RegisterServerCallback('esx_economyreworked:getUnpaidInvoices', function(source, cb, businessId)
    cb(exports.esx_economyreworked:getUnpaidInvoices(source, businessId))
end)

RegisterServerEvent('esx_economyreworked:withdrawToPlayer')
AddEventHandler('esx_economyreworked:withdrawToPlayer', function(businessId, amount)
    exports.esx_economyreworked:WithdrawToPlayer(businessId, amount, source)
end)

RegisterServerEvent('esx_economyreworked:transferToPlayer')
AddEventHandler('esx_economyreworked:transferToPlayer', function(businessId, playerId, amount)
    exports.esx_economyreworked:TransferToPlayer(businessId, playerId, amount, source)
end)

RegisterServerEvent('esx_economyreworked:orderDelivery')
AddEventHandler('esx_economyreworked:orderDelivery', function(businessId, deliveryType, units, buyPrice)
    exports.esx_economyreworked:OrderDelivery(businessId, deliveryType, units, buyPrice, source)
end)

RegisterServerEvent('esx_economyreworked:setProductDetails')
AddEventHandler('esx_economyreworked:setProductDetails', function(businessId, productName, enabled, price)
    exports.esx_economyreworked:SetProductDetails(businessId, productName, enabled, price, source)
end)

RegisterServerEvent('esx_economyreworked:issueInvoice')
AddEventHandler('esx_economyreworked:issueInvoice', function(businessId)
    exports.esx_economyreworked:IssueInvoice(businessId, 1000, false, source)
end)

RegisterServerEvent('esx_economyreworked:toggleAutoRenew')
AddEventHandler('esx_economyreworked:toggleAutoRenew', function(businessId)
    exports.esx_economyreworked:ToggleAutoRenew(businessId, source)
end)

RegisterServerEvent('esx_economyreworked:addStock')
AddEventHandler('esx_economyreworked:addStock', function(businessId)
    exports.esx_economyreworked:AddStock(businessId, source)
end)