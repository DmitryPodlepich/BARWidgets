--Current bugs--
--AntiNuke bot and vehicle counted in a build queue size but not waiting units group.

--After Load game or reload widget everything is broken with units groups and support units logic.
--Partially reason is that we can define ON REPEAT factories only on CommandNotify.
--We can try to check if factory is on repeat in UnitFromFactory additionaly.

--Scheduled features--
--Make units groups travel with the same speed. (Probably we need to add { "Ctrl" } to the command options...)
--If returning support units meets applicable guard target then we attach that unit to target. 

function widget:GetInfo()
    return {
        name = "Auto unit groups V2",
        desc = "Automatically sends support units such as jummer, radar etc with guar command to closest units.",
        author = "Dmitry P",
        date = "June 2024",
        layer = 1000, -- this should be high enough to draw above ground, not sure of best value to use
        enabled = true,
		version = 1,
        handler = true
    }
end

local returningSupportUnitMinDistanceToFactory = 500 -- Min distance for support unit who is in the returning state to change its state to waiting.
local targetGuardMaxSpeed = 70 --Max speed of applicable target of guard unit. If unit speed is more than this value then ignore this unit.

local myTeamId = Spring.GetMyTeamID()

local supportUnitsState = { IDLE = "IDLE", WAITING = "WAITING", GUARDING = "GUARDING", RETURNING = "RETURNING" }
local supportUnitType = { RADAR =  "RADAR", JUMMER = "JUMMER", GROUND_AA = "GROUND_AA"}
local supportUnits = {}

local unitsGroups = {}
local unitsGroupMemberStates = { WAITING = "WAITING", ONPATROL = "ONPATROL" }

local factoriesAllowedToCreateGroups = {}

local selectedUnits = Spring.GetSelectedUnits()

-- function widget:Initialize()
-- 	Spring.Echo("BBB");
-- end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)

	if (unitTeam ~= myTeamId) then return end

	if(IsBuilder(unitDefID)) then return end

	-- Logic for support units. After unit creation it waits for guard target (radar, jummer, AA etc.)
    if(IsSupportUnit(unitDefID) and IsInPatrol(unitID)) then

		local unitSupportType = GetSupportUnitType(unitDefID)

		supportUnits[unitID] = {unitSupportType = unitSupportType, supportUnitState = supportUnitsState.WAITING, guardTargetUnitId = factID}
		
		Spring.GiveOrderToUnit(unitID, CMD.GUARD, {factID}, {})
	end

	--Logic for units who needs support. After unit creation waiting support units should be attached with guard command.
	if(IsInPatrol(unitID) and not IsSupportUnit(unitDefID) and IsFactoryTech2OrExperimental(factDefID) and IsApplicableByMoveSpeed(unitDefID)) then

		local isRadarAttached = false
		local isJummerAttached = false
		local groundAAUnitAttached = false

		--Attaching support units with GUARD command
		for waitingUnitID, waitingUnitData in pairs(supportUnits) do
            
			if(waitingUnitData.supportUnitState == supportUnitsState.WAITING) then

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
			end
        end
	end

	--Create units groups--
	if(IsFactoryExperimental(factDefID)) then return end

	local factoryCommands = Spring.GetUnitCommands(factID, 100)

	local buildQueueSize = GetFactoryBuildQueueGroupSize(factID);

	--Spring.Echo("factoriesAllowedToCreateGroups: ".. dumpObject(factoriesAllowedToCreateGroups))

	--Create units group only if there are more than 1 NOT support unit in a factory build queue
	if(factoriesAllowedToCreateGroups[factID] and not IsSupportUnit(unitDefID) and IsInPatrol(unitID) and buildQueueSize > 1) then

		if(unitsGroups[factID] == nil) then
			unitsGroups[factID] = { units = {}}
		end

		Spring.GiveOrderToUnit(unitID, CMD.GUARD, {factID}, {})

		unitsGroups[factID].units[unitID] = { unitDefID = unitDefID, unitState = unitsGroupMemberStates.WAITING}

		local unitsCountInCurrentGroup = GetTablelength(unitsGroups[factID].units);

		Spring.Echo("buildQueueSize: ".. buildQueueSize);
		Spring.Echo("unitsCountInCurrentGroup: ".. unitsCountInCurrentGroup)

		-- Release units group and allow them to patrol
		if(unitsCountInCurrentGroup >= buildQueueSize) then

			for wUnitID, wUnitData in pairs(unitsGroups[factID].units) do

				if(supportUnits[wUnitID] == nil and wUnitData.unitState == unitsGroupMemberStates.WAITING) then
					for i, cmd in ipairs(factoryCommands) do
						
						local cmdType = cmd.id
						local cmdParams = cmd.params
						local cmdOptions = cmd.options

						Spring.GiveOrderToUnit(wUnitID, cmdType, cmdParams, cmdOptions)
					end

					---wUnitData.unitState = unitsGroupMemberStates.ONPATROL
				end
			end

			unitsGroups[factID].units = {}
		end
	end

end

function widget:UnitDestroyed(unitID, unitDefID, teamID)

	if(myTeamId ~= teamID) then return end

	--If destroyed unit was a support unit just forget him
	if(supportUnits[unitID]) then supportUnits[unitID] = nil end

	if(unitsGroups[unitID]) then unitsGroups[unitID] = nil end

	if(factoriesAllowedToCreateGroups[unitID]) then factoriesAllowedToCreateGroups[unitID] = nil end

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

	--Spring.Echo("CMD.REPEAT: "..tostring(CMD.REPEAT).."commandId: ".. commandId .. " params: ".. dumpObject(params))

	for i = 1, #selectedUnits do

		local selectedUnitId = selectedUnits[i]
		
		local teamID = Spring.GetUnitTeam(selectedUnitId)

		if(myTeamId ~= teamID) then return end

		local selectedUnitDefId = Spring.GetUnitDefID(selectedUnitId)

		--If factory is selected and just received an order REPEAT ON then pui it to factoriesAllowedToCreateGroups
		--Only factories which are in repeatON mode allowed to create units groups
		if(UnitDefs[selectedUnitDefId].isFactory and commandId == CMD.REPEAT and params) then
			if(params[1] == 1) then
				factoriesAllowedToCreateGroups[selectedUnitId] = {}
			else
				factoriesAllowedToCreateGroups[selectedUnitId] = nil
			end
		end

		--If player gives any order to support unit then we dont use that unit in our widget anymore.
		if(supportUnits[selectedUnitId]) then
			supportUnits[selectedUnitId] = nil
		end

		--If player orders support unit to guard a TECH2 or Experimental factory
		-- then we mark this unit as waiting
		if(supportUnits[selectedUnitId] == nil and params and params[1] and commandId ==  CMD.GUARD and IsSupportUnit(selectedUnitDefId)) then
			local commandTargetUnitId = params[1];

			local commandTargetUnitDefId = Spring.GetUnitDefID(commandTargetUnitId)

			if(IsFactoryTech2OrExperimental(commandTargetUnitDefId)) then
				
				local unitSupportType = GetSupportUnitType(selectedUnitDefId)

				supportUnits[selectedUnitId] = {unitSupportType = unitSupportType, supportUnitState = supportUnitsState.WAITING, guardTargetUnitId = commandTargetUnitId}

			end
		end
	end
end

function widget:SelectionChanged(sel)
	selectedUnits = sel
end

function widget:GameFrame(frame)

	for supportUnitId, supportUnitValue in pairs(supportUnits) do	
		if(supportUnitValue.supportUnitState == supportUnitsState.RETURNING) then
			local distance = GetDistance(supportUnitId, supportUnitValue.guardTargetUnitId)
			if(distance ~= nil and distance <= returningSupportUnitMinDistanceToFactory) then
				supportUnitValue.supportUnitState = supportUnitsState.WAITING
			end
		end
	end
end

--Gets count of NOT support units in factory build queue
function GetFactoryBuildQueueGroupSize(factID)

	local fullBuildQueue = Spring.GetFullBuildQueue(factID)

	local unitsCount = 0

	for i = 1, #fullBuildQueue do

		for unitDefID, unitDefCount in pairs(fullBuildQueue[i]) do
			if(not IsSupportUnit(unitDefID) and not IsBuilder(unitDefID)) then
				unitsCount = unitsCount + unitDefCount;
			end
		end

	end

	return unitsCount

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
end

--Prevent guarding too fast units
function IsApplicableByMoveSpeed(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.speed <= targetGuardMaxSpeed
end

function IsBuilder(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.isBuilder
	or (unitDef.canReclaim and unitDef.reclaimSpeed > 0)
	or (unitDef.canResurrect and unitDef.resurrectSpeed > 0)
	or (unitDef.canRepair and unitDef.repairSpeed > 0) or (unitDef.buildOptions and unitDef.buildOptions[1])
end

function IsFactoryTech2OrExperimental(factDefID)

	local factDef = UnitDefs[factDefID]
	if string.find(factDef.translatedTooltip, "Tech 2") or string.find(factDef.translatedTooltip, "Experimental") then return true end

	return false
end

function IsFactoryExperimental(factDefID)
	
	local factDef = UnitDefs[factDefID]
	if string.find(factDef.translatedTooltip, "Experimental") then return true end

	return false

end

function GetSupportUnitType(unitDefID)

	if (IsRadar(unitDefID)) then return supportUnitType.RADAR end
	if (IsJummer(unitDefID))  then return supportUnitType.JUMMER end
	if (IsGroundAAUnit(unitDefID)) then return supportUnitType.GROUND_AA end
end

function IsSupportUnit(unitDefID)

	if IsRadar(unitDefID) or IsJummer(unitDefID) or IsGroundAAUnit(unitDefID) then return true end

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

function SendToRandomPointInRadius(unitID, radius)
	local randonPoint = GetRandomPointInRadousAroundUnit(unitID, radius)

    Spring.GiveOrderToUnit(unitID, CMD.MOVE, {randonPoint.x, randonPoint.y, randonPoint.z}, {})
end

function GetRandomPointInRadousAroundUnit(unitID, radius)
	local x, y, z = Spring.GetUnitPosition(unitID)

    local angle = math.random() * 2 * math.pi

    local x = x + radius * math.cos(angle)
    local z = z + radius * math.sin(angle)

	return {x = x, y = y, z = z}
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

function IsInPatrol(unitID)
    local unitCommands = Spring.GetUnitCommands(unitID, 100)

    if(unitCommands == nil) then return false end

    for i, cmd in ipairs(unitCommands) do
        if(cmd.id == CMD.PATROL) then return true end
    end

    return false
end

--debug functions--

function echoLongString(longString)
    local chunkSize = 1000  -- Set the desired chunk size

    for i = 1, #longString, chunkSize do
        local chunk = string.sub(longString, i, i + chunkSize - 1)
        Spring.Echo(chunk)
    end
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

function GetTablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end