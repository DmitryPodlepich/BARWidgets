--Current bugs--
--AntiNuke bot and vehicle counted in a build queue size but not waiting units group.

--After Load game or reload widget everything is broken with units groups and support units logic.
	--Partially reason is that we can define ON REPEAT factories only on CommandNotify.

--Scheduled features--
--Make units groups travel with the same speed. (Probably we need to add { "Ctrl" } to the command options...)

--VFS.Include("unbaconfigs/buildoptions.lua")
--VFS.Include("luarules/configs/customcmds.h.lua")
VFS.Include("gamedata/movedefs.lua")
VFS.Include("gamedata/moveDefs.lua")

function widget:GetInfo()
    return {
        name = "Units groups automation V1",
        desc = "Prevent NOT support units to go on patrol before factory build queue will be completed. After units build queue is completed release all group and send them all on a patrol as a group.",
        author = "Dmitry P",
        date = "February 2024",
        layer = 1000, -- this should be high enough to draw above ground, not sure of best value to use
        enabled = true,
		version = 1,
        handler = true
    }
end

local myTeamId = Spring.GetMyTeamID()

local clearQueueCommandId = 5

local unitsGroups = {}
--local unitsGroupMemberStates = { WAITING = "WAITING", ONPATROL = "ONPATROL" }

local factoriesAllowedToCreateGroups = {}

function widget:Initialize()
	Spring.Echo("Units groups gutomation V1 initialized!");

	if Spring.moveDefs then
		Spring.Echo("MoveCtrl loaded!");
	end
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)

	--Spring.Echo("UnitFromFactory: "..unitID)

	if (unitTeam ~= myTeamId) then return end

	if(IsBuilder(unitDefID)) then return end

	--Prevent creating groups od experimental units
	if(IsFactoryExperimental(factDefID)) then return end

	--Spring.Echo("GetUnitMoveTypeData: "..dumpObject(Spring.GetUnitMoveTypeData(unitID)))

	local buildQueueSize = GetFactoryBuildQueueGroupSize(factID);

	--Create units group only if there are more than 1 NOT support unit in a factory build queue
	if(factoriesAllowedToCreateGroups[factID] and not IsSupportUnit(unitDefID) and IsInPatrol(unitID) and buildQueueSize > 1) then

		--if current factory builds its first group
		if(unitsGroups[factID] == nil) then
			unitsGroups[factID] = { units = {}}
		end

		unitsGroups[factID].units[unitID] = { unitDefID = unitDefID}

		Spring.GiveOrderToUnit(unitID, CMD.GUARD, {factID}, {})

		local unitsCountInCurrentGroup = GetTablelength(unitsGroups[factID].units);

		-- Release units group and allow them to patrol
		if(unitsCountInCurrentGroup >= buildQueueSize) then

			SetFactoryCommandsToUnitsGroup(factID)

		end
	end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID)

	if(myTeamId ~= teamID) then return end

	--If factory has been destroyed
	if(unitsGroups[unitID]) then unitsGroups[unitID] = nil end
	if(factoriesAllowedToCreateGroups[unitID]) then factoriesAllowedToCreateGroups[unitID] = nil end
end

function widget:CommandNotify(commandId, params, options)

	-- local selectedUnits = Spring.GetSelectedUnits()

	-- for i = 1, #selectedUnits do

	-- 	local selectedUnitId = selectedUnits[i]
		
	-- 	local teamID = Spring.GetUnitTeam(selectedUnitId)

	-- 	if(myTeamId ~= teamID) then return end

	-- 	local selectedUnitDefId = Spring.GetUnitDefID(selectedUnitId)

		--Spring.Echo("commandId: "..tostring(commandId))
		--Spring.Echo("params: "..dumpObject(params))

		--If factory is selected and just received an order REPEAT ON then put it to factoriesAllowedToCreateGroups
		--Only factories which are in repeatON mode allowed to create units groups
		-- if(UnitDefs[selectedUnitDefId].isFactory and commandId == CMD.REPEAT and params) then
		-- 	if(params[1] == 1) then
		-- 		factoriesAllowedToCreateGroups[selectedUnitId] = {}
		-- 		Spring.Echo("Allowed FactoryID: "..selectedUnitId)
		-- 	else
		-- 		factoriesAllowedToCreateGroups[selectedUnitId] = nil
		-- 		Spring.Echo("Disallowed FactoryID: "..selectedUnitId)
		-- 	end
		-- end

		-- --ToDo if user pushs clear queue OR change buid queue then we release all units from unitsGroups related to that factory  
		-- if(UnitDefs[selectedUnitDefId].isFactory and unitsGroups[selectedUnitId]) then
		-- 	if(commandId == clearQueueCommandId or UnitDefs[commandId]) then
		-- 		Spring.Echo("Rease all units related to factory: "..selectedUnitId)
		-- 		SetFactoryCommandsToUnitsGroup(selectedUnitId)
		-- 	end
		-- end
	--end
end

function widget:UnitCreated(unitID, unitDefID, teamID, builderID)
end

function widget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)

	--Spring.Echo("Spring.MoveCtrl: "..dumpObject(Spring))
	--Spring.Echo("Spring: "..dumpObject(Spring))
	--Spring.Echo("cmdID: "..dumpObject(cmdID).." cmdParams: "..dumpObject(cmdParams).." cmdOptions: "..dumpObject(cmdOptions))

	if(myTeamId ~= teamID) then return end

	if(UnitDefs[unitDefID].isFactory and cmdID == CMD.REPEAT and cmdParams) then
		if(cmdParams[1] == 1) then
			factoriesAllowedToCreateGroups[unitID] = {}
			Spring.Echo("Allowed FactoryID: "..unitID)
		else
			factoriesAllowedToCreateGroups[unitID] = nil
			Spring.Echo("Disallowed FactoryID: "..unitID)
		end
	end

	--ToDo if user pushs clear queue OR change buid queue then we release all units from unitsGroups related to that factory  
	if(UnitDefs[unitDefID].isFactory and unitsGroups[unitID]) then
		if(cmdID == clearQueueCommandId) then
			SetFactoryCommandsToUnitsGroup(unitID)
		end
	end
end

function widget:GameFrame(frame)
end

function SetFactoryCommandsToUnitsGroup(factID)

	local unitsArray = {}

	local orderArray = {}

	local factoryCommands = Spring.GetUnitCommands(factID, 1000)

	local minSpeed = GetMinimumUnitsMoveSpeed(unitsGroups[factID].units)

	--Spring.Echo("minSpeed: "..minSpeed)

	for wUnitID, wUnitData in pairs(unitsGroups[factID].units) do
		table.insert(unitsArray,wUnitID)

		if(math.huge ~= minSpeed) then
			local currentSpeed = Spring.GetUnitMoveTypeData(wUnitID)

			--Spring.MoveCtrl.SetGroundMoveTypeData(wUnitID, "maxSpeed", minSpeed)
			--Spring.MoveCtrl.SetGroundMoveTypeData(wUnitID, { maxSpeed = minSpeed, turnRate = currentSpeed.turnRate, slopeMod = currentSpeed.slopeMod })
		end

		--ERROR call SetUnitMoveGoal a nil 
		-- for i, cmd in ipairs(factoryCommands) do
		-- 	if(cmd.id == CMD.MOVE or cmd.id == CMD.PATROL) then
		-- 		if(cmd.params and cmd.params[1] and cmd.params[2] and cmd.params[3]) then
		-- 			Spring.SetUnitMoveGoal(wUnitID, cmd.params[1], cmd.params[2], cmd.params[3], minSpeed)
		-- 		end
		-- 	end
		-- end

		unitsGroups[factID].units[wUnitID] = nil
	end

	for i, cmd in ipairs(factoryCommands) do
		local cmdOptions = cmd.options

		cmdOptions["ctrl"] = true
		--cmdOptions["shift"] = true
		cmdOptions["right"] = true
		cmdOptions["alt"] = true

		local coded = 0

		if cmdOptions["alt"]  then coded = coded + CMD.OPT_ALT   end
		if cmdOptions["ctrl"]  then coded = coded + CMD.OPT_CTRL  end
		if cmdOptions["meta"]  then coded = coded + CMD.OPT_META  end
		if cmdOptions["shift"] then coded = coded + CMD.OPT_SHIFT end
		if cmdOptions["right"] then coded = coded + CMD.OPT_RIGHT end

		cmdOptions.coded = coded

		local order = { cmd.id, cmd.params, cmdOptions }
		table.insert(orderArray, order)
	end

	--Spring.Echo("orderArray: "..dumpObject(orderArray))

	Spring.GiveOrderArrayToUnitArray(unitsArray, orderArray)
end

function GetMinimumUnitsMoveSpeed(unitsGroups)
    local minSpeed = math.huge

    for unitID, unitData in pairs(unitsGroups) do

		local moveSpeed = Spring.GetUnitMoveTypeData(unitID).maxSpeed

		if moveSpeed and moveSpeed < minSpeed then
			minSpeed = moveSpeed
		end
    end

    return minSpeed
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

function IsBuilder(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.isBuilder
	or (unitDef.canReclaim and unitDef.reclaimSpeed > 0)
	or (unitDef.canResurrect and unitDef.resurrectSpeed > 0)
	or (unitDef.canRepair and unitDef.repairSpeed > 0) or (unitDef.buildOptions and unitDef.buildOptions[1])
end

function IsFactoryExperimental(factDefID)
	
	local factDef = UnitDefs[factDefID]
	if string.find(factDef.translatedTooltip, "Experimental") then return true end

	return false

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