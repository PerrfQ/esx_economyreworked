exports('getConfig', function()
    return Config
end)

exports('BuyBusiness', function(businessId, playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local business = businessCache[businessId]

    if business.owner then
        xPlayer.showNotification('Ten biznes jest już zajęty!')
        return false
    end

    if xPlayer.getMoney() < business.price then
        xPlayer.showNotification('Brak pieniędzy!')
        return false
    end

    xPlayer.removeMoney(business.price)
    MySQL.query.await('UPDATE businesses SET owner = ?, lease_expiry = DATE_ADD(NOW(), INTERVAL 7 DAY) WHERE id = ?', { xPlayer.identifier, businessId })
    businessCache[businessId].owner = xPlayer.identifier
    xPlayer.showNotification('Kupiłeś biznes!')
    TriggerClientEvent('esx_shops:refreshBlips', -1)
    return true
end)

exports('PerformService', function(businessId, serviceName, amount, totalPrice, stockCost)
    local business = businessCache[businessId]
    if not business then return false end

    local isNPC = business.owner == nil
    if not isNPC and business.stock < stockCost then return false end

    if not isNPC then
        MySQL.query.await('UPDATE businesses SET stock = stock - ?, funds = funds + ? WHERE id = ?', { stockCost, totalPrice, businessId })
        businessCache[businessId].stock = businessCache[businessId].stock - stockCost
        businessCache[businessId].funds = businessCache[businessId].funds + totalPrice
    end
    return true
end)

exports('OrderDelivery', function(businessId, deliveryType)
    local business = businessCache[businessId]
    if not business.owner then return false end

    local cost = deliveryType == 'instant' and Config.BaseDeliveryCost * 2 or Config.BaseDeliveryCost
    if business.funds < cost then
        return false
    end

    MySQL.query.await('UPDATE businesses SET funds = funds - ?, stock = stock + ? WHERE id = ?', { cost, Config.DeliveryUnits, businessId })
    businessCache[businessId].funds = businessCache[businessId].funds - cost
    businessCache[businessId].stock = businessCache[businessId].stock + Config.DeliveryUnits
    MySQL.query.await('INSERT INTO deliveries (business_id, units, cost, type) VALUES (?, ?, ?, ?)', { businessId, Config.DeliveryUnits, cost, deliveryType })
    return true
end)

exports('IssueInvoice', function(businessId, amount, isFictitious)
    local business = businessCache[businessId]
    if not business.owner then return false end

    local invoiceCount = MySQL.query.await('SELECT COUNT(*) as count FROM invoices WHERE business_id = ? AND DATE(created_at) = CURDATE()', { businessId })[1].count
    if invoiceCount >= 5 then return false end

    MySQL.query.await('INSERT INTO invoices (business_id, amount, is_fictitious) VALUES (?, ?, ?)', { businessId, amount or 1000, isFictitious or false })
    return true
end)

exports('AddStock', function(businessId)
    local business = businessCache[businessId]
    if not business.owner then return false end

    MySQL.query.await('UPDATE businesses SET stock = stock + ? WHERE id = ?', { Config.DeliveryUnits, businessId })
    businessCache[businessId].stock = businessCache[businessId].stock + Config.DeliveryUnits
    return true
end)

exports('GetBusinesses', function(type)
    local result = MySQL.query.await('SELECT id, owner, price, blocked_until, name FROM businesses WHERE type = ?', { type })
    for _, row in ipairs(result) do
        for _, business in ipairs(Config.Businesses) do
            if business.businessId == row.id then
                row.name = business.name
                row.coords = business.coords
                break
            end
        end
    end
    return result
end)