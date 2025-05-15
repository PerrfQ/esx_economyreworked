Config = {}
Config.Locale = GetConvar("esx:locale", "en")
Config.BaseResourceCost = 50
Config.Businesses = {
    { businessId = 1, type = 'shop', name = 'LTD Eclipse Blvd', coords = { x = 373.8, y = 325.8, z = 103.5 }, price = 100000 },
    { businessId = 2, type = 'shop', name = 'LTD Palomino Fwy', coords = { x = 2557.4, y = 382.2, z = 108.6 }, price = 100000 },
    { businessId = 3, type = 'shop', name = 'LTD San Andreas Ave', coords = { x = -3038.9, y = 585.9, z = 7.9 }, price = 100000 },
    { businessId = 4, type = 'shop', name = 'LTD Barbareno Rd', coords = { x = -3241.9, y = 1001.4, z = 12.8 }, price = 100000 },
    { businessId = 5, type = 'shop', name = 'LTD Route 68', coords = { x = 547.4, y = 2671.7, z = 42.1 }, price = 100000 },
    { businessId = 6, type = 'shop', name = 'LTD Algonquin Blvd', coords = { x = 1961.4, y = 3740.6, z = 32.3 }, price = 100000 },
    { businessId = 7, type = 'shop', name = 'LTD Joshua Rd', coords = { x = 2678.9, y = 3280.6, z = 55.2 }, price = 100000 },
    { businessId = 8, type = 'shop', name = 'LTD Great Ocean Hwy', coords = { x = 1729.2, y = 6414.1, z = 35.0 }, price = 100000 },
    { businessId = 9, type = 'shop', name = 'Robs West Mirror Dr', coords = { x = 1135.8, y = -982.2, z = 46.4 }, price = 120000 },
    { businessId = 10, type = 'shop', name = 'Robs Vespucci Blvd', coords = { x = -1222.9, y = -906.9, z = 12.3 }, price = 120000 },
    { businessId = 11, type = 'shop', name = 'Robs Rockford Dr', coords = { x = -1487.5, y = -379.1, z = 40.1 }, price = 120000 },
    { businessId = 12, type = 'shop', name = 'Robs Magellan Ave', coords = { x = -2968.2, y = 390.9, z = 15.0 }, price = 120000 },
    { businessId = 13, type = 'shop', name = 'Robs Senora Fwy', coords = { x = 1166.0, y = 2708.9, z = 38.1 }, price = 120000 },
    { businessId = 14, type = 'shop', name = 'Robs Panorama Dr', coords = { x = 1392.5, y = 3604.6, z = 34.9 }, price = 120000 }
}

Config.Services = {
    shop = {
        { name = 'bread', label = 'Chleb', price = 100, stockCost = 1 },
        { name = 'water', label = 'Woda', price = 100, stockCost = 1 },
        { name = 'carokit', label = 'Body Kit', price = 1000, stockCost = 10 },
        { name = 'diamond', label = 'Diament', price = 10000, stockCost = 100 }
    }
}

Config.Holding = {
    coords = { x = -219.96, y = -631.59, z = 40.49 },
    blip = {
        sprite = 475, -- Ikona biura
        color = 38,   -- Niebieski
        scale = 0.8,
        name = 'Business Holding'
    }
}

Config.BaseDeliveryCost = 500
Config.DeliveryUnits = 300
Config.NPCMargin = 1.5
Config.InvoiceTax = 0.10
Config.WeeklyFundsTax = 0.05