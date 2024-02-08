function widget:GetInfo()
    return {
        name = "Auto Retreat Patrol",
        desc = "Retreats units to designated location on low HP",
        author = "PureTilt",
        date = "June 2023",
        layer = 1000, -- this should be high enough to draw above ground, not sure of best value to use
        enabled = true,
		version = 1,
        handler = true
    }
end

-- User Configuration ----------------------------------------------------------------------------------------
-- Edit these values to change the widget's behavior

local retreatThreshold = 0.8        -- Health below which units will retreat, 0.6 = 60% health
local returnAfterRetreatOn = true  -- If true, units will return to their original position after retreating
local markerRadius = 200            -- Radius of the gather point
local ignoredDefsIDs = {            -- List of unit IDs to ignore
    "armflea",
    "armpw",
    "armfast",
    "armflash",
    "armfav",
    "corak"
}



-- End of User Configuration ---------------------------------------------------------------------------------

local gameStarted = false
local unitMarketSize = 1
local markerOnlyOnSelected = false
local printOutAmountOfIgnoredOnChange = true

local myTeam = Spring.GetMyTeamID()
local allBuildedUnits = {}
local retreatingUnitsWithCommands = {}
local unitGroup = {}
local probedDefs = {}
local ignoredDefs = {}
local ignoredUnits = {}
local drawData = {}

for index, ID in pairs(ignoredDefsIDs) do
    ignoredDefs[ID] = true
end

local gatherPoint

local SetUnitGroup = Spring.SetUnitGroup
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetMouseState = Spring.GetMouseState
local SelectUnitArray = Spring.SelectUnitArray
local TraceScreenRay = Spring.TraceScreenRay
local GetUnitPosition = Spring.GetUnitPosition
local GetGameFrame = Spring.GetGameFrame
local spGetMyTeamID = Spring.GetMyTeamID
local deselectUnit = Spring.DeselectUnit

local Echo = Spring.Echo

for defID, udef in pairs(UnitDefs) do
    if not ignoredDefs[udef.name] then

        local canFly = udef.canFly
        local isMobile = (udef.canMove and udef.speed > 0.000001) or (udef.name == "armnanotc" or udef.name == "cornanotc")
        local builder = (udef.canReclaim and udef.reclaimSpeed > 0) or (udef.canResurrect and udef.resurrectSpeed > 0) or (udef.canRepair and udef.repairSpeed > 0) or (udef.buildOptions and udef.buildOptions[1])
        local tooFat = udef.health ~= nil and udef.health >= 10000
        local cloak = udef.canCloak
        local ground = udef.isGroundUnit
        local ship = udef.moveDef.name and string.find(udef.moveDef.name, 'boat')
        local bomb = udef.moveDef.name and string.find(udef.moveDef.name, 'bomb')

        --if not canFly and isMobile and not builder and not tooFat and not cloak and ground and not ship and not bomb then
        if not canFly and isMobile and not builder and not cloak and ground and not bomb then
            probedDefs[defID] = true
        end
    end
end

function widget:Initialize()

    Spring.Echo("Auto retreat patrol")

    Spring.SendCommands({
    "bind                  /  setRetreatPoint",
    "bind                  ,  ignoreSelectedUnits",
    "bind                  .  unignoreSelectedUnits",
    "bind             Ctrl+,  decreaseRetreatThreshold",
    "bind             Ctrl+.  increaseRetreatThreshold",
    "bind             Ctrl+/  returnAfterRetreat"
    })

    widgetHandler.actionHandler:AddAction(self, "setRetreatPoint", SetRetreatPoint, nil)
    widgetHandler.actionHandler:AddAction(self, "returnAfterRetreat", ReturnAfterRetreat, nil)
    widgetHandler.actionHandler:AddAction(self, "ignoreSelectedUnits", IgnoreSelectedUnits, nil)
    widgetHandler.actionHandler:AddAction(self, "unignoreSelectedUnits", UnignoreSelectedUnits, nil)

    widgetHandler.actionHandler:AddAction(self, "increaseRetreatThreshold", IncreaseRetreatThreshold, nil)
    widgetHandler.actionHandler:AddAction(self, "decreaseRetreatThreshold", DecreaseRetreatThreshold, nil)
end

function widget:GameStart()
    gameStarted = true
    widget:PlayerChanged()
end

function widget:PlayerChanged(playerID)
    if Spring.GetSpectatingState() and (Spring.GetGameFrame() > 0 or gameStarted) then
        widgetHandler:RemoveWidget()
        return
    end
    myTeam = Spring.GetMyTeamID()
end

function dumpObject(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dumpObject(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)

    if( IsBuilder(unitDefID) ) then return end

    local unitCommands = Spring.GetUnitCommands(unitID, 1000);
    allBuildedUnits[unitID] = { unitDefID = unitDefID, previousCommand = unitCommands }

end

function widget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if(teamID ~= spGetMyTeamID()) then return end

    if( IsBuilder(unitDefID) ) then return end

    --Forget unit if that unit just received an order from player.
    if(retreatingUnitsWithCommands[unitID]) then
        -- If unit just got an order during his way to retreat point. Or during healing but healing was not completed.
        if (retreatingUnitsWithCommands[unitID].retreating) then
            if(cmdID ~= CMD.MOVE or (cmdID == CMD.MOVE and cmdParams and (cmdParams[1] ~= gatherPoint[1] or cmdParams[2] ~= gatherPoint[2] or cmdParams[3] ~= gatherPoint[3] ))) then
                allBuildedUnits[unitID] = nil
                retreatingUnitsWithCommands[unitID] = nil
                return
            end
        end

        --If unit just got an order after it has been healed. Or unit already returned on its patrol route. Or unit just got an order when it was standing on a gather point.
        if(not retreatingUnitsWithCommands[unitID].retreating) then
            
            --If that command does not exist in the initial unit order commands list. It means that it is a new order and we need to forger unit initial patrol route.
            if(allBuildedUnits[unitID] and allBuildedUnits[unitID].previousCommand and not IsCommandExistInInitialCommands(unitID, cmdID, cmdParams)) then
                allBuildedUnits[unitID] = nil
                retreatingUnitsWithCommands[unitID] = nil
                --Spring.Echo("["..currentTime.."]".."Forget unit line 165: "..unitID)
            end
        end
    end

    --If unit just got a new patrol order from user. Save new patrol route to as initial.
    -- if(cmdID == CMD.PATROL and allBuildedUnits[unitID] == nil and retreatingUnitsWithCommands[unitID] == nil) then
    --     local unitCommands = Spring.GetUnitCommands(unitID, 1000);
    --     allBuildedUnits[unitID] = { unitDefID = unitDefID, previousCommand = unitCommands }
    --     Spring.Echo("["..currentTime.."]".."Save new inilial patrol route for unit: "..unitID)
    -- end
end

function IsCommandExistInInitialCommands(unitID, cmdID, cmdParams)

    for i, cmd in ipairs(allBuildedUnits[unitID].previousCommand) do
        
        if(cmd.id == cmdID and cmdParams and cmd.params) then
            
            if(cmd.id == CMD.MOVE or cmd.id == CMD.PATROL) then
                
                if(cmdParams[1] == cmd.params[1] and cmdParams[2] == cmd.params[2] and cmdParams[3] == cmd.params[3]) then
                    return true
                end
            end
        end
    end

    return false
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
    if (unitTeam ~= spGetMyTeamID()) then
        return
    end -- not my unit
    if not probedDefs[unitDefID] or ignoredUnits[unitID] then
        return
    end

    local curHealth, maxHealth = GetUnitHealth(unitID)

    if gatherPoint then
        if (not retreatingUnitsWithCommands[unitID] or not retreatingUnitsWithCommands[unitID].retreating) and IsInPatrol(unitID) then
            if curHealth / maxHealth <= retreatThreshold then

                -- deselect retreating unit
                local selectedUnits = GetSelectedUnits()
                for index, ID in pairs(selectedUnits) do
                    if ID == unitID then
                        selectedUnits[index] = nil
                        break
                    end
                end

                local unitCurrentCommands = {}

                Spring.SelectUnitArray(selectedUnits, false)

                --Get initial unit patrol commands. To send unit on patrol according to the same sequence as it was initially.
                if(allBuildedUnits[unitID]) then
                    unitCurrentCommands = allBuildedUnits[unitID].previousCommand  
                else
                    unitCurrentCommands = Spring.GetUnitCommands(unitID, 1000);
                end

                unitGroup[unitID] = Spring.GetUnitGroup(unitID)
                retreatingUnitsWithCommands[unitID] = {retreating = true, previousCommand = unitCurrentCommands}
                Spring.GiveOrderToUnit(unitID, CMD.MOVE, { gatherPoint[1], gatherPoint[2], gatherPoint[3] }, {})
                SetUnitGroup(unitID, -1)
            end
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    ignoredUnits[unitID] = nil
    retreatingUnitsWithCommands[unitID] = nil
    allBuildedUnits[unitID] = nil
end

local frameCount = 0
local frameDelay = 1
function widget:GameFrame(gameFrame)
    frameCount = frameCount + 1
    if Spring.GetSelectionBox() ~= nil then
        frameCount = frameDelay
    end
    if frameCount >= frameDelay then
        frameCount = frameCount - frameDelay
        drawData = {}

        local selectedUnits = {}
        if markerOnlyOnSelected then
            local selected = GetSelectedUnits()
            for index, ID in pairs(selected) do
                selectedUnits[ID] = true
            end
        end
        for unitID, ignored in pairs(ignoredUnits) do
            if ignored then
                if not markerOnlyOnSelected or selectedUnits[unitID] then
                    local size = ((7.5 * (UnitDefs[GetUnitDefID(unitID)].xsize ^ 2 + UnitDefs[GetUnitDefID(unitID)].zsize ^ 2) ^ 0.5) + 8) * unitMarketSize
                    local locX, locY, locZ = GetUnitPosition(unitID)
                    drawData[unitID] = { size = size, locX = locX, locY = locY, locZ = locZ }
                end
            end
        end
    end
    if gameFrame % 30 == 0 then
        for unitID, data in pairs(retreatingUnitsWithCommands) do
            if data.retreating then
                local curHealth, maxHealth = GetUnitHealth(unitID)
                if curHealth / maxHealth >= 1 then
                    if unitGroup[unitID] ~= nil then
                        SetUnitGroup(unitID, unitGroup[unitID])
                    end
                    
                    if returnAfterRetreatOn then

                        retreatingUnitsWithCommands[unitID].retreating = false

                        for i, cmd in ipairs(data.previousCommand) do
                            local cmdType = cmd.id
                            local cmdParams = cmd.params
                            local cmdOptions = cmd.options

                            Spring.GiveOrderToUnit(unitID, cmdType, cmdParams, cmdOptions)
                        end
                    end
                end
            end
        end
    end
end

function IsBuilder(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.isBuilder
	or (unitDef.canReclaim and unitDef.reclaimSpeed > 0)
	or (unitDef.canResurrect and unitDef.resurrectSpeed > 0)
	or (unitDef.canRepair and unitDef.repairSpeed > 0) or (unitDef.buildOptions and unitDef.buildOptions[1])
end

function IsInPatrol(unitID)
    local unitCommands = Spring.GetUnitCommands(unitID, 100);

    if(unitCommands == nil) then return false end

    for i, cmd in ipairs(unitCommands) do
        if(cmd.id == CMD.PATROL) then return true end
    end

    return false
end

function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

local function isChatActive()
    return WG['chat'].isInputActive() or false
end

function widget:KeyRelease(keyCode, mods, label, utf32char, scanCode, actionList)
    if isChatActive() then
        return
    end
end

function SetRetreatPoint()
    local gatherPointX, gatherPointY = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(gatherPointX, gatherPointY, true)
    if gatherPoint ~= nil and ((pos[1] - gatherPoint[1]) ^ 2 + (pos[3] - gatherPoint[3]) ^ 2 <= markerRadius ^ 2) then
        gatherPoint = nil
        for unitID, data in pairs(retreatingUnitsWithCommands) do
            if data then
                if unitGroup[unitID] ~= nil then
                    SetUnitGroup(unitID, unitGroup[unitID])
                end
                retreatingUnitsWithCommands[unitID] = nil
            end
        end
    else

        gatherPoint = pos
        -- if the selected units are healers (and not a commander) then also move them to the gather point and give them a repair order
        local selectedUnits = GetSelectedUnits()
        for index, unitID in pairs(selectedUnits) do
            if isHealer(unitID) then
                for index, unitID in pairs(selectedUnits) do
                    -- Set the selected units' repeat option to true
                    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, {})
                    Spring.GiveOrderToUnit(unitID, CMD.MOVE, { gatherPoint[1], gatherPoint[2], gatherPoint[3] }, {})
                    -- Give a repair order to the selected units in a circle around the gather point
                    Spring.GiveOrderToUnit(unitID, CMD.REPAIR, { gatherPoint[1], gatherPoint[2], gatherPoint[3], markerRadius+20 }, { "shift" })
                end
            end
        end
    end
end

function isHealer(unitID)
    local unitDefID = GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]
    if unitDef.canRepair and not unitDef.customParams.iscommander then
        return true
    end
    return false
end

function ReturnAfterRetreat()
    -- toggle return after retreat behavior
    returnAfterRetreatOn = not returnAfterRetreatOn
    --Echo("Return after retreat: " .. tostring(returnAfterRetreatOn))
end

function IgnoreSelectedUnits()
    local selectedUnits = GetSelectedUnits()
    for index, ID in pairs(selectedUnits) do
        if not ignoredDefs[GetUnitDefID(ID)] then
            ignoredUnits[ID] = { true }
            changedIgnored = true
        end
    end
end

function UnignoreSelectedUnits()
    local selectedUnits = GetSelectedUnits()
    for index, ID in pairs(selectedUnits) do
        if not ignoredDefs[GetUnitDefID(ID)] then
            ignoredUnits[ID] = false
            changedIgnored = true
        end
    end
end

function IncreaseRetreatThreshold()
    retreatThreshold = math.min(retreatThreshold + 0.1, 1.0)
    Echo("Retreat Threshold: " .. string.format("%.0f", retreatThreshold * 100) .. "%")
end

function DecreaseRetreatThreshold()
    retreatThreshold = math.max(retreatThreshold - 0.1, 0.0)
    Echo("Retreat Threshold: " .. string.format("%.0f", retreatThreshold * 100) .. "%")  
end

local glColor2 = gl.Color
local function MyGLColor(r, g, b, a)
    if type(r) == "table" then
        r, g, b, a = r[1], r[2], r[3], r[4]
    end
    if not r or not g or not b or not a then
        return
    end
    -- new alpha is globalDim * a, clamped between 0 and 1
    local a2 = a
    if a2 > 1 then
        a = 1
    end
    if a2 < 0 then
        a = 0
    end
    glColor2(r, g, b, a2)
end
local glColor = MyGLColor

local glLineWidth = gl.LineWidth
local glPushMatrix = gl.PushMatrix
local glPopMatrix = gl.PopMatrix
local glBlending = gl.Blending
local glDepthTest = gl.DepthTest
local glBeginEnd = gl.BeginEnd
local glBeginText = gl.BeginText
local glEndText = gl.EndText
local glTexture = gl.Texture
local glTexRect = gl.TexRect
local glText = gl.Text
local glVertex = gl.Vertex
local glPointSize = gl.PointSize
local GL_LINES = GL.LINES
local GL_LINE_LOOP = GL.LINE_LOOP
local GL_POINTS = GL.POINTS
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local glCallList = gl.CallList
local sin = math.sin
local cos = math.cos

local glColor2 = gl.Color

local bgTexture = "bitmaps/default/circlefx1.png"
local bgTextureSizeRatio = 1.9
local bgTextureColor = { 1, 0, 0, 0.8 }
local dividerInnerRatio = 0.4
local dividerOuterRatio = 1
local textAlignRadiusRatio = 0.9
local dividerColor = { 1, 1, 1, 0.15 }

function invertColors (r, g, b, a)
    return 1 - r, 1 - g, 1 - b, a
end

function widget:DrawWorldPreUnit()
    if gatherPoint then
        glPushMatrix()

        gl.Rotate(-90, 1, 0, 0)
        glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        --glColor(invertColors(Spring.GetTeamColor(Spring.GetMyTeamID())))  -- inverting color for the glow texture :)
        glColor(1, 0.2, 0.2, 1)
        glTexture(bgTexture)
        for unitID, data in pairs(drawData) do
            gl.Translate(0, 0, data.locY)
            local size = data.size
            glTexRect(data.locX - size, -data.locZ - size, data.locX + size, -data.locZ + size)
            gl.Translate(0, 0, -data.locY)
        end--[[
        for unitID, ignored in pairs(ignoredUnits) do
            if ignored then
                local locX, locY, locZ = GetUnitPosition(unitID)
                gl.Translate(0, 0, locY)
                local size = (7.5 * ( UnitDefs[GetUnitDefID(unitID)].xsize^2 + UnitDefs[GetUnitDefID(unitID)].zsize^2 ) ^ 0.5) + 8
                glTexRect(locX - size, -locZ - size, locX + size, -locZ + size)
                gl.Translate(0, 0, -locY)

            end
        end
        --]]
        gl.Rotate(-90, -1, 0, 0)
        gl.Translate(gatherPoint[1], gatherPoint[2], gatherPoint[3])
        gl.Rotate(-90, 1, 0, 0)
        --gl.Rotate(-90, 1, 0, 0)
        glColor(0.25, 1, 0.25, 1)
        gl.Text("Gather\n  point", 0, 0, 50, "cxo")

        gl.Translate(-gatherPoint[1], -gatherPoint[2], 0)
        --[[
        -- add the blackCircleTexture as background texture
        glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glColor(bgTextureColor)    -- inverting color for the glow texture :)
        glTexture(bgTexture)
        -- use pingWheelRadius as the size of the background texture
        local halfSize = 50 * bgTextureSizeRatio
        glTexRect(gatherPoint[1] - halfSize, gatherPoint[2] - halfSize, gatherPoint[1] + halfSize, gatherPoint[2] + halfSize)
        glTexture(false)
--]]
        -- draw a smooth circle at the pingWheelScreenLocation with 128 vertices
        --glColor(pingWheelColor)
        glColor(0.3, 1, 0.3, 1)
        local camera = Spring.GetCameraState()
        local addedThicknes = 0
        if camera.height ~= nil then
            addedThicknes = 8 * 1 / camera.height
        end
        glLineWidth(2 + addedThicknes)

        local function Circle(r)
            for i = 1, 128 do
                local angle = (i - 1) * 2 * math.pi / 128
                glVertex(gatherPoint[1] + r * sin(angle), gatherPoint[2] + r * cos(angle))
            end
        end

        glBeginEnd(GL_LINE_LOOP, Circle, markerRadius)

        --gl.Translate(0, 0, -gatherPoint[3])



        glPopMatrix()
    end
end

function GetTablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end