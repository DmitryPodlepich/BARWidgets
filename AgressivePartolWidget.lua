function widget:GetInfo()
    return {
        name = "Aggressive Patrol V1",
        desc = "Move unit close to target on patrol to make maximum impact.",
        author = "Dmitry P",
        date = "February 2025",
        layer = 1000, -- this should be high enough to draw above ground, not sure of best value to use
        enabled = true,
		version = 1,
        handler = true
    }
end

local UPDATE_FREQUENCY = 30  -- Update every 30 frames (~1 second)
local experimentalUnits = {} -- Stores experimental units
local targetsToMove = {} -- Stores targetIds as keys and a list of unit which got an order to move to the target

local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetAllUnits = Spring.GetAllUnits
local MinRangeConstant = 200

local function IsExperimental(unitID)

    local unitDefID = spGetUnitDefID(unitID)
    if not unitDefID then return false end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return false end

    if unitDef.customParams and unitDef.customParams.experimental then
        return true
    end

    if unitDef.metalCost and unitDef.metalCost > 8000 then
        return true
    end

    return false
end

function widget:Initialize()
    local units = spGetAllUnits()
    for _, unitID in ipairs(units) do
        if IsExperimental(unitID) then
            experimentalUnits[unitID] = true
        end
    end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
    if IsExperimental(unitID) then
        experimentalUnits[unitID] = true
    end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID)
    
    if experimentalUnits[unitID] then  experimentalUnits[unitID] = nil end


    if targetsToMove[unitID] then
        for _, movingUnitID in ipairs(targetsToMove[unitID]) do
            local lastCommand = spGetUnitCommands(movingUnitID, 1)

            if lastCommand and lastCommand[1] and lastCommand[1].id == CMD.MOVE and IsInPatrol(movingUnitID) then
                Spring.GiveOrderToUnit(movingUnitID, CMD.REMOVE, {0, lastCommand[1].tag}, {"ctrl"})
            end
        end
    end

    if targetsToMove[unitID] then targetsToMove[unitID] = nil end
end

function widget:GameFrame(frame)
    if frame % UPDATE_FREQUENCY ~= 0 then return end

    for unitID, _ in pairs(experimentalUnits) do

        if IsInPatrol(unitID) then

            local commands = spGetUnitCommands(unitID, 1)
            
            if commands and commands[1] and (commands[1].id == CMD.ATTACK or commands[1].id == CMD.FIGHT) then
                
                local targetType, _, targetID = Spring.GetUnitWeaponTarget(unitID, 0)
                if targetID == nil then
                    targetType, _, targetID = Spring.GetUnitWeaponTarget(unitID, 1)
                end
                if targetID == nil then
                    targetType, _, targetID = Spring.GetUnitWeaponTarget(unitID, 2)
                end
                if targetID == nil then
                    targetType, _, targetID = Spring.GetUnitWeaponTarget(unitID, 3)
                end
                if targetID == nil then
                    targetType, _, targetID = Spring.GetUnitWeaponTarget(unitID, 4)
                end

                if targetID then
                    local minRange = math.huge

                    local unitDefID = spGetUnitDefID(unitID)
                    local unitDef = UnitDefs[unitDefID]

                    local weapons = unitDef.weapons

                    if #weapons > 0 then
                        for i = 1, #weapons do
                            local weaponDef = WeaponDefs[weapons[i].weaponDef]
                            if weaponDef and weaponDef.canAttackGround then
                                minRange = math.min(minRange, weaponDef.range)
                            end
                        end
                    end

                    if minRange < math.huge then

                        minRange = math.min(minRange, MinRangeConstant)

                        local ux, uy, uz = spGetUnitPosition(unitID)
                        local tx, ty, tz = spGetUnitPosition(targetID)
                        
                        if(tx and ty and tz )
                        then
                            local dx, dz = tx - ux, tz - uz
                            local distance = math.sqrt(dx * dx + dz * dz)
                            
                            if distance > minRange then
                                local normX = dx / distance
                                local normZ = dz / distance

                                local moveX = tx - normX * minRange
                                local moveZ = tz - normZ * minRange

                                Spring.GiveOrderToUnit(unitID,
                                    CMD.INSERT,
                                    {0, CMD.MOVE, CMD.OPT_ALT, moveX, uy, moveZ},
                                    {"alt"}
                                );

                                if not targetsToMove[targetID] then
                                    targetsToMove[targetID] = {}
                                end

                                table.insert(targetsToMove[targetID], unitID)
                            end
                        end
                    end
                end
            end
        end
    end
end

function IsInPatrol(unitID)
    local unitCommands = Spring.GetUnitCommands(unitID, 100);

    if(unitCommands == nil) then return false end

    for i, cmd in ipairs(unitCommands) do
        if(cmd.id == CMD.PATROL) then return true end
    end

    return false
end