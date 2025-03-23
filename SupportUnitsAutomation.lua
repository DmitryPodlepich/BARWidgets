--Current bugs--
--Support ground units attached to a hover experimental (Probably to ships also...)
	--Solution is to check guard target and filer not applicable. Also Check distance to a factory.

--Scheduled features--
--If returning support units meets applicable guard target then we attach that unit to target. 
--Treat AntiNuke vehicle and bot as support unit also.

function widget:GetInfo()
    return {
        name = "Support units automation V1",
        desc = "Automatically sends support units such as jummer, radar, groud AA with a guard command to closest units.",
        author = "Dmitry P",
        date = "February 2024",
        layer = 1000, -- this should be high enough to draw above ground, not sure of best value to use
        enabled = true,
		version = 1,
        handler = true
    }
end

local returningSupportUnitsRadius = 500
local returningSupportUnitMinDistanceToFactory = 500 -- Min distance for support unit who is in the returning state to change its state to waiting.
local targetGuardMaxSpeed = 70 --Max speed of applicable target of guard unit. If unit speed is more than this value then ignore this unit.

local myTeamId = Spring.GetMyTeamID()

local supportUnitsState = { IDLE = "IDLE", WAITING = "WAITING", GUARDING = "GUARDING", RETURNING = "RETURNING" }
local supportUnitType = { RADAR =  "RADAR", JUMMER = "JUMMER", GROUND_AA = "GROUND_AA", ANTI_NUKE = "ANTI_NUKE"}
local supportUnits = {}

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)

    if (unitTeam ~= myTeamId) then return end

	if(IsBuilder(unitDefID)) then return end

	if( IsFlying(unitDefID) ) then return end
	--Spring.Echo(dumpObject(UnitDefs[unitDefID]))

    -- Logic for support units. After unit creation it waits for guard target (radar, jummer, AA etc.)
    if(IsSupportUnit(unitDefID) and IsInPatrol(unitID)) then

		local unitSupportType = GetSupportUnitType(unitDefID)

		supportUnits[unitID] = { unitDefID = unitDefID, unitSupportType = unitSupportType, supportUnitState = supportUnitsState.WAITING, guardTargetUnitId = factID}
		
		Spring.GiveOrderToUnit(unitID, CMD.GUARD, {factID}, {})
	end

    --Logic for units who needs support. After unit creation waiting support units should be attached with guard command.
	if(IsInPatrol(unitID) and not IsSupportUnit(unitDefID) and IsFactoryTech2OrExperimental(factDefID)) then

		local isRadarAttached = false
		local isJummerAttached = false
		local groundAAUnitAttached = false
		local antiNukeUnitAttached = false

		--Attaching support units with GUARD command
		for waitingUnitID, waitingUnitData in pairs(supportUnits) do
            
			if(waitingUnitData.supportUnitState == supportUnitsState.WAITING and IsApplicable(unitDefID, waitingUnitData.unitDefID)) then

				if(isRadarAttached and isJummerAttached and groundAAUnitAttached) then return end

				if(waitingUnitData.unitSupportType == supportUnitType.RADAR and not isRadarAttached) then
					
					SendSupportUnitToGuard(waitingUnitID, unitID)
					isRadarAttached = true
				end

				if(waitingUnitData.unitSupportType == supportUnitType.JUMMER and not isJummerAttached) then
					
					SendSupportUnitToGuard(waitingUnitID, unitID)
					isJummerAttached = true
				end

				if(waitingUnitData.unitSupportType == supportUnitType.GROUND_AA and not groundAAUnitAttached) then
					
					SendSupportUnitToGuard(waitingUnitID, unitID)
					groundAAUnitAttached = true
				end

				if(waitingUnitData.unitSupportType == supportUnitType.ANTI_NUKE and not antiNukeUnitAttached) then
					
					SendSupportUnitToGuard(waitingUnitID, unitID)
					antiNukeUnitAttached = true
				end
			end
        end
	end

end

function widget:UnitDestroyed(unitID, unitDefID, teamID)

	if(myTeamId ~= teamID) then return end

	--If destroyed unit was a support unit just forget him
	if(supportUnits[unitID]) then supportUnits[unitID] = nil end

	-- If destroyed unit was a support target unit
	-- Move all his support units to base and add them to a waiting list
	local fabricUnitId = GetAnyTech2OrExperimentalFabricUnitId()

	--If player does not have any Tech2 or Experimental fabric
	if(fabricUnitId == nil) then return end

	local targetSupportUnits = GetSupportUnitsByGuardTargetUnitId(unitID)

	if(GetTablelength(targetSupportUnits) <= 0) then return end

	for supportUnitId, supportUnitValue in pairs(targetSupportUnits) do
		
		if(supportUnits[supportUnitId] ~= nil) then

			Spring.GiveOrderToUnit(supportUnitId, CMD.GUARD, {fabricUnitId}, {})

			supportUnits[supportUnitId].supportUnitState = supportUnitsState.RETURNING
			supportUnits[supportUnitId].guardTargetUnitId = fabricUnitId

		end
	end
end

function widget:CommandNotify(commandId, params, options)

	local selectedUnits = Spring.GetSelectedUnits()

	for i = 1, #selectedUnits do

		local selectedUnitId = selectedUnits[i]
		
		local teamID = Spring.GetUnitTeam(selectedUnitId)

		if(myTeamId ~= teamID) then return end

		local selectedUnitDefId = Spring.GetUnitDefID(selectedUnitId)

		--If player gives any order to support unit then we dont use that unit in our widget anymore.
		if(supportUnits[selectedUnitId]) then
			supportUnits[selectedUnitId] = nil
		end

		--If player orders support unit to guard a TECH2 or Experimental factory
		-- then we mark this unit as waiting
		if(supportUnits[selectedUnitId] == nil and params and params[1] and commandId ==  CMD.GUARD and IsSupportUnit(selectedUnitDefId) and not IsBuilder(selectedUnitDefId)) then
			local commandTargetUnitId = params[1];

			local commandTargetUnitDefId = Spring.GetUnitDefID(commandTargetUnitId)

			if(IsFactoryTech2OrExperimental(commandTargetUnitDefId) and IsInPatrol(commandTargetUnitId)) then
				
				local unitSupportType = GetSupportUnitType(selectedUnitDefId)

				supportUnits[selectedUnitId] = {unitSupportType = unitSupportType, supportUnitState = supportUnitsState.WAITING, guardTargetUnitId = commandTargetUnitId}

			end
		end
	end
end

function widget:GameFrame(frame)

	if frame % 30 > 0 then return end

	for supportUnitId, supportUnitValue in pairs(supportUnits) do	
		if(supportUnitValue.supportUnitState == supportUnitsState.RETURNING) then
			local distance = GetDistance(supportUnitId, supportUnitValue.guardTargetUnitId)
			
			--if (distance == nil) then break end

			if(distance and distance <= returningSupportUnitMinDistanceToFactory) then
				supportUnitValue.supportUnitState = supportUnitsState.WAITING
				break
			else
				
				local x, y, z = Spring.GetUnitPosition(supportUnitId)
				local closestUnits = Spring.GetUnitsInSphere(x,y,z, returningSupportUnitsRadius);

				if(closestUnits) then
					for i, unitID in ipairs(closestUnits) do

						local teamID = Spring.GetUnitTeam(unitID)

						if (teamID == myTeamId) then
							local unitDefID = Spring.GetUnitDefID(unitID)

							if(IsInPatrol(unitID) and not IsBuilder(unitDefID) and not IsSupportUnit(unitDefID) and IsApplicable(unitDefID, supportUnitValue.unitDefID)) then
								if (Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID)) then
									SendSupportUnitToGuard(supportUnitId, unitID)
									break
								end
							end
						end
					end
				end
			end
		end
	end
end

function GetSupportUnitType(unitDefID)

	if (IsRadar(unitDefID)) then return supportUnitType.RADAR end
	if (IsJummer(unitDefID))  then return supportUnitType.JUMMER end
	if (IsGroundAAUnit(unitDefID)) then return supportUnitType.GROUND_AA end
	if (IsMobileAntiNuke(unitDefID)) then return supportUnitType.ANTI_NUKE end
end

function IsInPatrol(unitID)
    local unitCommands = Spring.GetUnitCommands(unitID, 100)

    if(unitCommands == nil) then return false end

    for i, cmd in ipairs(unitCommands) do
        if(cmd.id == CMD.PATROL) then return true end
    end

    return false
end

function IsSupportUnit(unitDefID)

	if IsMobileAntiNuke(unitDefID) or IsRadar(unitDefID) or IsJummer(unitDefID) or IsGroundAAUnit(unitDefID) then return true end

	return false
end

function IsJummer(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.radarDistanceJam > 100
end

function IsRadar(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.radarDistance >= 1000
end

function IsMobileAntiNuke(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return string.find(unitDef.translatedTooltip, "Nuke")
end

function IsGroundAAUnit(unitDefID)
	local unitDef = UnitDefs[unitDefID]

	local canAttackGroundForAnyOfWeapon = false;
	local weapons = unitDef.weapons
	if #weapons > 0 then
		for i = 1, #weapons do
			local weaponDef = WeaponDefs[weapons[i].weaponDef]
			if(weaponDef.canAttackGround) then canAttackGroundForAnyOfWeapon = true break end
		end
	end

	return not canAttackGroundForAnyOfWeapon
end

function GetAnyTech2OrExperimentalFabricUnitId()
	for unitTeamId, unitId in pairs(Spring.GetTeamUnits(myTeamId)) do

		local unitDefID = Spring.GetUnitDefID(unitId)
		local unitDef = UnitDefs[unitDefID]

		if(unitDef.isFactory and IsFactoryTech2OrExperimental(unitDefID)) then		
			return unitId
		end
	end

	return nil
end

function SendSupportUnitToGuard(supportUnitId, targetUnitId)
	Spring.GiveOrderToUnit(supportUnitId, CMD.GUARD, {targetUnitId}, {})
	supportUnits[supportUnitId].supportUnitState = supportUnitsState.GUARDING
	supportUnits[supportUnitId].guardTargetUnitId = targetUnitId

	local targetUnitDefId = Spring.GetUnitDefID(targetUnitId)
	--Spring.Echo("SendSupportUnitToGuard: "..UnitDefs[targetUnitDefId].translatedTooltip)
end

--Prevent guarding differect types of unit (for example groud radar to ship)
--Prevent guarding too fast units (targetGuardMaxSpeed)
--Prevent guarding flying units.
--Prevent guarding bombs.
function IsApplicable(targetUnitDefID, supportUnitDefID)
	local targetUnitDef = UnitDefs[targetUnitDefID]
	local supportUnitDef = UnitDefs[supportUnitDefID]

	if(supportUnitDef == nil) then
		return
	end

	local isTargetBoat = targetUnitDef.moveDef.name and string.find(targetUnitDef.moveDef.name, 'boat')
	local isSupportBoat = supportUnitDef.moveDef.name and string.find(supportUnitDef.moveDef.name, 'boat')

	if(isTargetBoat ~= isSupportBoat) then return false end

	return  targetUnitDef.speed <= targetGuardMaxSpeed and not targetUnitDef.canFly and (targetUnitDef.moveDef.name and not string.find(targetUnitDef.moveDef.name, 'bomb'))
end

function IsBuilder(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.isBuilder
	or (unitDef.canReclaim and unitDef.reclaimSpeed > 0)
	or (unitDef.canResurrect and unitDef.resurrectSpeed > 0)
	or (unitDef.canRepair and unitDef.repairSpeed > 0) or (unitDef.buildOptions and unitDef.buildOptions[1])
end

function IsFlying(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.canFly
end

function IsFactoryTech2OrExperimental(factDefID)

	local factDef = UnitDefs[factDefID]
	if string.find(factDef.translatedTooltip, "Tech 2") or string.find(factDef.translatedTooltip, "Experimental") then return true end

	return false
end

function GetSupportUnitsByGuardTargetUnitId(unitID)

	local currentSupportUnits = {}

	for supportUnitId, supportUnitValue in pairs(supportUnits) do
		if(supportUnitValue.guardTargetUnitId == unitID and supportUnitValue.supportUnitState == supportUnitsState.GUARDING) then
			currentSupportUnits[supportUnitId] = supportUnitValue
		end
	end

	return currentSupportUnits
end

function GetDistance(unitID1, unitID2)
    local x1, y1, z1 = Spring.GetUnitPosition(unitID1)
    local x2, y2, z2 = Spring.GetUnitPosition(unitID2)

    if x1 and y1 and z1 and x2 and y2 and z2 then
        local dx = x1 - x2
        local dy = y1 - y2
        local dz = z1 - z2

        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        return distance
    else
        return nil  -- One or both units do not exist or have no position
    end
end

function GetTablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
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