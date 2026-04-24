local function ApplyCommonBlipSettings(blip, options)
    if not blip or blip == 0 then
        return nil
    end

    options = options or {}

    if options.sprite then
        SetBlipSprite(blip, options.sprite)
    end

    if options.color then
        SetBlipColour(blip, options.color)
    end

    if options.scale then
        SetBlipScale(blip, options.scale)
    end

    SetBlipAsShortRange(blip, options.shortRange == true)
    SetBlipCategory(blip, options.category or 10)
    SetBlipDisplay(blip, options.display or 6)

    if options.alpha then
        SetBlipAlpha(blip, options.alpha)
    end

    if options.flash then
        SetBlipFlashes(blip, true)
        if options.flashInterval then
            SetBlipFlashInterval(blip, options.flashInterval)
        end
    end

    if options.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(options.label)
        EndTextCommandSetBlipName(blip)
    end

    return blip
end

function CXEC_CreateEventBlip(coords, options)
    if not coords then
        return nil
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    return ApplyCommonBlipSettings(blip, options)
end

function CXEC_CreateEventRadiusBlip(coords, radius, options)
    if not coords or not radius then
        return nil
    end

    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    return ApplyCommonBlipSettings(blip, options)
end
