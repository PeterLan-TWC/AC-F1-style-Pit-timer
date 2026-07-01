local wasinpit = false
local pitentrytime = 0
local pitexittime = 0
local pitstopdone = false
local timeinpit = 0
local current_duration = 0

local current_stop_duration = 0
local last_stop_time = 0
local stationary_time = 0

-- UI Colors from F1 Timing HUD
local BgColor = rgbm.from0255(15, 16, 21, 235)       -- Translucent dark F1 card background
local ActiveWhite = rgbm.from0255(255, 255, 255)    -- Active Pitstop Color (#FFFFFF)
local DoneGreen = rgbm.from0255(54, 215, 57)         -- F1 Green for sector/completion
local IdleGray = rgbm.from0255(80, 81, 85)          -- Muted gray for inactive borders
local SeparatorColor = rgbm.from0255(35, 37, 43)     -- Card panel lines
local WhiteTextColor = rgbm.from0255(242, 243, 248)   -- High contrast white text
local GrayTextColor = rgbm.from0255(162, 163, 167)    -- Muted gray labels
local RetiredRed = rgbm.from0255(225, 6, 0)          -- F1 Red for Retired status
local PurpleSectorColor = rgbm.from0255(211, 69, 215) -- F1 Sector Purple

function script.update(dt)
    local car = ac.getCar(0)
    if not car then return end

    -- 1. Stationary (Vehicle Stop Time) Detection
    if car.speedKmh < 1.0 then
        stationary_time = stationary_time + dt
    else
        stationary_time = 0
    end

    local inpit = car.isInPitlane
    local enteringpitlane = inpit and not wasinpit
    local exitingpitlane = not inpit and wasinpit

    if enteringpitlane then
        wasinpit = true
        ac.log(wasinpit, os.clock())
        pitentrytime = os.clock()
        pitstopdone = false
        current_stop_duration = 0
    elseif exitingpitlane then
        wasinpit = false
        ac.log(wasinpit, os.clock())
        pitexittime = os.clock()
        timeinpit = pitexittime - pitentrytime
        last_stop_time = current_stop_duration
        ac.log(timeinpit)
        ac.log(last_stop_time)
        pitstopdone = true
    end

    if inpit then
        current_duration = os.clock() - pitentrytime
        if car.speedKmh < 1.0 then
            current_stop_duration = current_stop_duration + dt
        end
    end
end

function script.windowMain()
    -- Lock window cursor/canvas bounds to 260x80
    ui.setCursor(vec2(260, 80))

    local car = ac.getCar(0)
    local inpit = car and car.isInPitlane

    -- Determine if vehicle is Retired (stationary for 3 minutes / 180 seconds)
    local isRetired = stationary_time >= 180

    -- Determine colors, state, and status texts
    local accentColor = ActiveWhite -- Normal state shows #FFFFFF
    local statusText = "PITSTOP TIMER"

    if isRetired then
        accentColor = RetiredRed
        statusText = "VEHICLE STATUS"
    elseif inpit then
        accentColor = ActiveWhite
        statusText = "PITSTOP ACTIVE"
    elseif pitstopdone then
        statusText = "PREVIOUS PITSTOP"
        if last_stop_time >= 2.9 then
            accentColor = RetiredRed -- F1 Red
        elseif last_stop_time >= 2.0 then
            accentColor = DoneGreen -- F1 Sector Green
        else
            accentColor = PurpleSectorColor -- F1 Sector Purple
        end
    end

    -- Determine tyre compound and color
    local tyreColor = GrayTextColor
    local tyreText = ""
    if car then
        local tyreLong = car:tyresLongName() or ""
        tyreText = string.match(tyreLong, "%(([^)]+)%)") or tyreLong:upper()
        if not tyreText or tyreText == "" then tyreText = "TYRE" end

        if string.match(tyreLong:upper(), "SOFT") then
            tyreColor = rgbm.from0255(246, 4, 22)
        elseif string.match(tyreLong:upper(), "MEDIUM") then
            tyreColor = rgbm.from0255(250, 224, 8)
        elseif string.match(tyreLong:upper(), "HARD") then
            tyreColor = rgbm.from0255(227, 213, 214)
        elseif string.match(tyreLong:upper(), "INTER") then
            tyreColor = rgbm.from0255(58, 200, 44)
        elseif string.match(tyreLong:upper(), "WET") then
            tyreColor = rgbm.from0255(68, 145, 210)
        end
    end

    -- Corner flags: None rounds all corners, Left (5) rounds only TopLeft and BottomLeft
    local cornerNone = (ui.CornerFlags and ui.CornerFlags.None) or 0
    local cornerLeft = (ui.CornerFlags and ui.CornerFlags.Left) or 5

    -- Draw Main Translucent Background Card
    ui.drawRectFilled(vec2(0, 0), vec2(260, 80), BgColor, 6, cornerNone)

    -- Draw Left F1 Accent Border
    ui.drawRectFilled(vec2(0, 0), vec2(6, 80), accentColor, 6, cornerLeft)

    -- Draw Thin Separator Line Below Header
    ui.drawRectFilled(vec2(16, 27), vec2(250, 28), SeparatorColor)

    -- Draw Header Label
    ui.pushDWriteFont("fonts/Formula1-Regular.ttf")
    ui.dwriteDrawTextClipped(
        statusText, 
        10, 
        vec2(16, 10), 
        vec2(180, 26), 
        ui.Alignment.Start, 
        ui.Alignment.Center, 
        false, 
        GrayTextColor
    )
    ui.popDWriteFont()

    -- Draw Tyre Badge (Right side of Header)
    if car and tyreText ~= "" then
        ui.pushDWriteFont("fonts/Formula1-Regular.ttf")
        ui.dwriteDrawTextClipped(
            tyreText, 
            9, 
            vec2(190, 10), 
            vec2(250, 26), 
            ui.Alignment.End, 
            ui.Alignment.Center, 
            false, 
            tyreColor
        )
        ui.popDWriteFont()
    end

    if isRetired then
        -- If Retired, draw a single prominent "RETIRED" notification in the middle
        ui.pushDWriteFont("fonts/F1TV-2022-ObliqueSemiBold.ttf")
        ui.dwriteDrawTextClipped(
            "RETIRED", 
            26, 
            vec2(16, 32), 
            vec2(250, 72), 
            ui.Alignment.Center, 
            ui.Alignment.Center, 
            false, 
            RetiredRed
        )
        ui.popDWriteFont()
    else
        -- Draw two columns: Pit Time (Left) and Stop Time (Right)
        local pitTimeStr = "--.-- s"
        local stopTimeStr = "--.-- s"
        local pitTimeColor = GrayTextColor
        local stopTimeColor = GrayTextColor

        if inpit then
            pitTimeStr = string.format("%.2f s", current_duration)
            stopTimeStr = string.format("%.2f s", current_stop_duration)
            pitTimeColor = ActiveWhite
            stopTimeColor = ActiveWhite
        elseif pitstopdone then
            pitTimeStr = string.format("%.2f s", timeinpit)
            stopTimeStr = string.format("%.2f s", last_stop_time)
            pitTimeColor = WhiteTextColor
            stopTimeColor = WhiteTextColor
        end

        -- Draw Middle Vertical Separator
        ui.drawRectFilled(vec2(130, 34), vec2(131, 72), SeparatorColor)

        -- 1. Left Column: PIT TIME
        ui.pushDWriteFont("fonts/Formula1-Regular.ttf")
        ui.dwriteDrawTextClipped(
            "PIT TIME", 
            9, 
            vec2(16, 30), 
            vec2(124, 44), 
            ui.Alignment.Start, 
            ui.Alignment.Center, 
            false, 
            GrayTextColor
        )
        ui.popDWriteFont()

        ui.pushDWriteFont("fonts/F1TV-2022-ObliqueSemiBold.ttf")
        ui.dwriteDrawTextClipped(
            pitTimeStr, 
            20, 
            vec2(16, 44), 
            vec2(124, 72), 
            ui.Alignment.Start, 
            ui.Alignment.Center, 
            false, 
            pitTimeColor
        )
        ui.popDWriteFont()

        -- 2. Right Column: STOP TIME
        ui.pushDWriteFont("fonts/Formula1-Regular.ttf")
        ui.dwriteDrawTextClipped(
            "STOP TIME", 
            9, 
            vec2(136, 30), 
            vec2(250, 44), 
            ui.Alignment.Start, 
            ui.Alignment.Center, 
            false, 
            GrayTextColor
        )
        ui.popDWriteFont()

        ui.pushDWriteFont("fonts/F1TV-2022-ObliqueSemiBold.ttf")
        ui.dwriteDrawTextClipped(
            stopTimeStr, 
            20, 
            vec2(136, 44), 
            vec2(250, 72), 
            ui.Alignment.Start, 
            ui.Alignment.Center, 
            false, 
            stopTimeColor
        )
        ui.popDWriteFont()
    end
end


