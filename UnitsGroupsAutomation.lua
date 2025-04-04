--Current bugs--
--AntiNuke bot and vehicle counted in a build queue size but not waiting units group.

--After Load game or reload widget everything is broken with units groups and support units logic.
	--Partially reason is that we can define ON REPEAT factories only on CommandNotify.

--VFS.Include("unbaconfigs/buildoptions.lua")
--VFS.Include("luarules/configs/customcmds.h.lua")
--VFS.Include("gamedata/movedefs.lua")
--VFS.Include("gamedata/moveDefs.lua")

local widgetName = "Units groups automation V1"

function widget:GetInfo()
    return {
        name = widgetName,
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
local distanceBetweenFrontAndRearThreshold = 240
local automaticCMD_Option = "automaticCMD_Option"

local unitsGroups = {}
local unitsStates = { WAITING = "WAITING", ONPATROL = "ONPATROL", ATTACKING = "ATTACKING", RETREATING = "RETREATING" }
local unitsStatuses = { UNDEFINED = "UNDEFINED", FRONTLINE = "FRONTLINE", REARLINE = "REARLINE" }

local factoriesAllowedToCreateGroups = {}

function widget:Initialize()
	Spring.Echo(widgetName.." inilialized...3");
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)

	--Spring.Echo("UnitFromFactory: "..unitID)

	if (unitTeam ~= myTeamId) then return end

	if(IsBuilder(unitDefID)) then return end

	if(IsFlying(unitDefID)) then return end

	--Prevent creating groups od experimental units
	if(IsFactoryExperimental(factDefID)) then return end

	local buildQueueSize = GetFactoryBuildQueueGroupSize(factID);

	--Create units group only if there are more than 1 NOT support unit in a factory build queue
	if(factoriesAllowedToCreateGroups[factID] and not IsSupportUnit(unitDefID) and IsInPatrol(unitID) and buildQueueSize > 1) then

		--if current factory builds its first group
		if(unitsGroups[factID] == nil) then
			unitsGroups[factID] = {}
		end

		if(GetTablelength(unitsGroups[factID]) == 0) then
			table.insert(unitsGroups[factID], { units = {}, initialCount = 1 })
		end
		
		local lastGroupIndex = #unitsGroups[factID];

		local lastGroup = unitsGroups[factID][lastGroupIndex]

		if( GetTablelength(lastGroup.units) == 0 ) then
			lastGroup.initialCount = buildQueueSize
		end

		if( GetTablelength(lastGroup.units) < lastGroup.initialCount) then

			Spring.GiveOrderToUnit(unitID, CMD.GUARD, {factID}, { "meta", "alt", "internal" })

			lastGroup.units[unitID] = { 
				unitID = unitID,
				unitDefID = unitDefID,
				unitMaxHealth = UnitDefs[unitDefID].health,
				groupIndex = lastGroupIndex,
				factoryCommands = {},
				rearLineGuardTargetID = 0,
				unitStatus = unitsStatuses.UNDEFINED,
				unitState = unitsStates.WAITING
			}
		end

		if(GetTablelength(lastGroup.units) >= lastGroup.initialCount) then
			-- Release units group and allow them to patrol
			SetFactoryCommandsToUnitsGroup(factID)
			
			table.insert(unitsGroups[factID], { units = {}, initialCount = 1 })
		end
	end
end

function widget:UnitIdle(unitID, unitDefID, teamID)

	if(myTeamId ~= teamID) then return end

	for factoryID, groups in pairs(unitsGroups) do
		
		for groupIndex, group in ipairs(groups) do
			
			for groupUnitID, unitData in pairs(group.units) do
				
				--It seems like rear line unit is Idle because front line unit has been destroyed
				if(unitID == groupUnitID and unitData.unitStatus == unitsStatuses.REARLINE) then
					
					--Check if we have some alive front line units in this group. If yes lets guard one of those.
					for frontLineGroupUnitID, unitData in pairs(group.units) do

						if(unitData.unitStatus == unitsStatuses.FRONTLINE and Spring.ValidUnitID(frontLineGroupUnitID) and not Spring.GetUnitIsDead(frontLineGroupUnitID)) then
							
							unitData.rearLineGuardTargetID = frontLineGroupUnitID
							Spring.GiveOrderToUnit(groupUnitID, CMD.GUARD, {frontLineGroupUnitID}, { })
							return
						end
					end

					--If there is not any alive frontLineUnits just go on patrol.
					Spring.GiveOrderArrayToUnit(groupUnitID, unitData.factoryCommands)
					return
				end
			end
		end
	end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)

	if(myTeamId ~= unitTeam) then return end

	for factoryID, factoryUnitGroups in pairs(unitsGroups) do
		
		for groupIndex, unitsGroup in ipairs(factoryUnitGroups) do
			
			for rearLineUnitID, unitData in pairs(unitsGroup.units) do
				
				if(unitID == rearLineUnitID and unitData.unitStatus == unitsStatuses.REARLINE) then

					local curHealth, maxHealth = Spring.GetUnitHealth(rearLineUnitID)

					--Spring.Echo("curHealth: "..dumpObject(curHealth).." maxHealth "..dumpObject(maxHealth))

					if (curHealth / maxHealth <= 0.5) then 
						--Unfortunately GatherPointOfPatrolRetreat is nil...
						--Try to write somth to Unitdefs[frontLineUnitId] to link 2 widgets...
						--Spring.Echo("Rear line unit: "..rearLineUnitID.." has been damaged hard...".." GatherPointOfPatrolRetreat: "..GatherPointOfPatrolRetreat)
					end
				end
			end
		end
	end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID)

	if(myTeamId ~= teamID) then return end

	--If factory has been destroyed
	if(unitsGroups[unitID]) then unitsGroups[unitID] = nil end
	if(factoriesAllowedToCreateGroups[unitID]) then factoriesAllowedToCreateGroups[unitID] = nil end

	--if not factory but unit has been destroyed
	if(unitsGroups[unitID] == nil) then

		for factoryID, unitsGroup in pairs(unitsGroups) do
			for groupIndex, groupUnitData in ipairs(unitsGroup) do

				for unitIDInGroupUnits, unitData in pairs(groupUnitData.units) do
					
					if(unitID == unitIDInGroupUnits) then

						groupUnitData.units[unitID] = nil
						--Spring.Echo("UnitDestroyed: "..unitID)
						return
					end
				end
			end
		end
	end
end

function widget:CommandNotify(commandId, params, options)

	local selected = Spring.GetSelectedUnits()
	
	--if unit received an order from user forget it
	for factoryID, factoryUnitGroups in pairs(unitsGroups) do	
		for groupIndex, unitsGroup in ipairs(factoryUnitGroups) do				
			for index, ID in pairs(selected) do
				if (unitsGroup.units[ID]) then
					unitsGroup.units[ID] = nil
				end
			end
		end
	end

end

function widget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)

	if(myTeamId ~= teamID) then return end

	if(UnitDefs[unitDefID].isFactory and cmdID == CMD.REPEAT and cmdParams) then
		if(cmdParams[1] == 1) then
			factoriesAllowedToCreateGroups[unitID] = {}
			--Spring.Echo("Allowed FactoryID: "..unitID)
		else
			factoriesAllowedToCreateGroups[unitID] = nil
			--Spring.Echo("Disallowed FactoryID: "..unitID)
		end
	end

	--ToDo if user change buid queue then we release all units from unitsGroups related to that factory  
	if(UnitDefs[unitDefID].isFactory and unitsGroups[unitID]) then
		if(cmdID == clearQueueCommandId) then
			SetFactoryCommandsToUnitsGroup(unitID)
		end
	end

end

function widget:GameFrame(frame)

	--if frame > 0 then return end

	if frame % 30 > 0 then return end

	--If front line unit has target all rear line units switch to that target.
	--ToDo: if health of the taget is less than front line DPS than prevent it...
	for factoryID, factoryUnitGroups in pairs(unitsGroups) do
		
		for groupIndex, unitsGroup in ipairs(factoryUnitGroups) do
			
			for frontLineUnitID, unitData in pairs(unitsGroup.units) do
				
				if(unitData.unitStatus == unitsStatuses.FRONTLINE) then

					local targetType, _, targetUnitID = Spring.GetUnitWeaponTarget(frontLineUnitID, 1)

					local allRearLineUnitsAreFar = true

					for rareLineUnitID, rearLineUnitData in pairs(unitsGroup.units) do

						if(rearLineUnitData.unitStatus == unitsStatuses.REARLINE and rearLineUnitData.rearLineGuardTargetID == frontLineUnitID) then

							local distanceBetweenFrontAndRear = GetDistance(rareLineUnitID, rearLineUnitData.rearLineGuardTargetID)

							if(targetUnitID == nil or ( distanceBetweenFrontAndRear and distanceBetweenFrontAndRear > distanceBetweenFrontAndRearThreshold ) ) then
								
								local currentCommands = Spring.GetUnitCommands(rareLineUnitID, 1)
	
								if( currentCommands[1] and currentCommands[1].id ~= CMD.GUARD ) then

									Spring.GiveOrderToUnit(rareLineUnitID, CMD.GUARD, {rearLineUnitData.rearLineGuardTargetID}, {})
									--Spring.Echo(tostring(frame).."Order rearLine unit to guard: "..dumpObject(rearLineUnitData.rearLineGuardTargetID))
									--break

								end

							else

								local _, _, rearLineTargetUnitID = Spring.GetUnitWeaponTarget(rareLineUnitID, 1)

								if(rearLineTargetUnitID ~= targetUnitID and Spring.ValidUnitID(targetUnitID) and not Spring.GetUnitIsDead(targetUnitID)) then
								--if(rearLineTargetUnitID ~= targetUnitID) then
									
									Spring.GiveOrderToUnit(rareLineUnitID, CMD.ATTACK, { targetUnitID }, {})
									--Spring.GiveOrderToUnit(rareLineUnitID, CMD.INSERT,{-1, CMD.ATTACK, CMD.OPT_SHIFT, targetUnitID}, {});
									--Spring.Echo(tostring(frame).."Order rearLine unut to ATTACK: "..dumpObject(targetUnitID))
									--break
								end
							end

							-- сheck distance between all rear line units and front unit
							-- if all rear line are so far so front line unnit should wait for them

							if(distanceBetweenFrontAndRear < distanceBetweenFrontAndRearThreshold) then
								allRearLineUnitsAreFar = false
							end

						end
					end

					--if(allRearLineUnitsAreFar) then
						--Spring.GiveOrderToUnit(frontLineUnitID, CMD.GATHERWAIT, {}, {})
						--Spring.Echo(tostring(frame).."Order frontLine unut to WAIT: "..dumpObject(frontLineUnitID))
					--else
						--Spring.Echo(tostring(frame).."Order frontLine unut to STOP WAIT: "..dumpObject(frontLineUnitID))
					--end

				end
			end
		end
	end
end

function SetFactoryCommandsToUnitsGroup(factID)

	local unitsIdsArray = {}

	local orderArray = {}

	local factoryCommands = Spring.GetUnitCommands(factID, 1000)

	local lastGroupIndex = #unitsGroups[factID];

	if(lastGroupIndex == nil or lastGroupIndex <= 0) then return end

	local lastGroup = unitsGroups[factID][lastGroupIndex]

	if(GetTablelength(lastGroup.units) <= 0) then return end

	for wUnitID, wUnitData in pairs(lastGroup.units) do

		table.insert(unitsIdsArray, wUnitID)
		lastGroup.units[wUnitID].unitState = unitsStates.ONPATROL

	end

	for i, cmd in ipairs(factoryCommands) do
		local order = { cmd.id, cmd.params, cmd.options }
		table.insert(orderArray, order)
	end

	--Spring.Echo("orderArray: "..dumpObject(orderArray))

	--Sort units by health
	local unitsValues = {}

	for key, value in pairs(lastGroup.units) do
		table.insert(unitsValues, value)
	end

	table.sort(unitsValues, function(a, b) return a.unitMaxHealth > b.unitMaxHealth end)

	--get the most fat units
	local maxHealthAmongGroup = unitsValues[1].unitMaxHealth

	local frontLineOfGroup = FilterByArrayValues(unitsValues, function(a) return a.unitMaxHealth == maxHealthAmongGroup end)
	local rearLineOfGroup = FilterByArrayValues(unitsValues, function(a) return a.unitMaxHealth < maxHealthAmongGroup end)

	--set units statuses and factory commands
	for index, unitValue in ipairs(frontLineOfGroup) do
		lastGroup.units[unitValue.unitID].unitStatus = unitsStatuses.FRONTLINE
		lastGroup.units[unitValue.unitID].factoryCommands = orderArray
	end

	for index, unitValue in ipairs(rearLineOfGroup) do
		lastGroup.units[unitValue.unitID].unitStatus = unitsStatuses.REARLINE
		lastGroup.units[unitValue.unitID].factoryCommands = orderArray
	end

	--If group contains all same units so we dont have any leaders.
	if(#frontLineOfGroup == lastGroup.initialCount) then
		Spring.GiveOrderArrayToUnitArray(unitsIdsArray, orderArray)
		return
	end

	local frontLineUnitsIds = SelectFromArrayValues(frontLineOfGroup, function(a) return a.unitID end)
	local rearLineUnitsIds = SelectFromArrayValues(rearLineOfGroup, function(a) return a.unitID end)

	if(#frontLineOfGroup == 1 or #frontLineOfGroup >= #rearLineOfGroup) then

		--Save guard target unitID
		for index, unitValue in ipairs(rearLineOfGroup) do
			lastGroup.units[unitValue.unitID].rearLineGuardTargetID = frontLineUnitsIds[1]
		end

		Spring.GiveOrderToUnitArray(rearLineUnitsIds, CMD.GUARD, {frontLineUnitsIds[1]}, {})
		Spring.GiveOrderArrayToUnitArray(frontLineUnitsIds, orderArray)

		return
	end

	local groupedRearLineUnitsIds = GroupArrayByValue(rearLineOfGroup, function(a) return a.unitDefID end)

	for unitDefID, rearLineUnitsValues in pairs(groupedRearLineUnitsIds) do

		--ToDo make smart balance if not
		if(#rearLineUnitsValues % #frontLineUnitsIds == 0) then

			local guardUnitsCount = #rearLineUnitsValues / #frontLineUnitsIds

			for index, unitID in ipairs(frontLineUnitsIds) do

				local indexWithGuardUnitsCount = index

				if (indexWithGuardUnitsCount > 1) then
					indexWithGuardUnitsCount = indexWithGuardUnitsCount + (guardUnitsCount - 1)
				end

				local endIndex = indexWithGuardUnitsCount + (guardUnitsCount - 1)

				local rareLineUnitsForGuard = TakeFromTable(rearLineUnitsValues, indexWithGuardUnitsCount, endIndex)

				if(rareLineUnitsForGuard == nil) then error("rareLineUnitsForGuardIds was nil!!!") end

				local rareLineUnitsForGuardIds = SelectFromArrayValues(rareLineUnitsForGuard, function(a) return a.unitID end)

				--Save guard target unitID
				for index, unitValue in ipairs(rearLineUnitsValues) do
					lastGroup.units[unitValue.unitID].rearLineGuardTargetID = unitID
				end
				Spring.GiveOrderToUnitArray(rareLineUnitsForGuardIds, CMD.GUARD, {unitID}, {})
			end

		else

			--Save guard target unitID
			for index, unitValue in ipairs(rearLineUnitsValues) do
				lastGroup.units[unitValue.unitID].rearLineGuardTargetID = frontLineUnitsIds[1]
			end
			local rareLineUnitsForGuardIds = SelectFromArrayValues(rearLineUnitsValues, function(a) return a.unitID end)
			Spring.GiveOrderToUnitArray(rareLineUnitsForGuardIds, CMD.GUARD, {frontLineUnitsIds[1]}, {})

		end
	end

	--ToDo if leader is far from guard squad than wait for them.
	Spring.GiveOrderArrayToUnitArray(frontLineUnitsIds, orderArray)
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

function IsFlying(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef.canFly
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

function IsInPatrol(unitID)
    local unitCommands = Spring.GetUnitCommands(unitID, 100)

    if(unitCommands == nil) then return false end

    for i, cmd in ipairs(unitCommands) do
        if(cmd.id == CMD.PATROL) then return true end
    end

    return false
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
        return nil
    end
end

---@generic T
---@param arrayToSlice T[]
---@param startIndex number
---@param endIndex number
function TakeFromTable(arrayToSlice, startIndex, endIndex)

	local slicedArray = {}

	for i = startIndex, endIndex do
		table.insert(slicedArray, arrayToSlice[i])
	end

	return slicedArray
end

---@generic T
---@param array T[]
---@param comp? fun(a: T):boolean
function FilterByArrayValues(array, comp)

	local filtered = {}

	if(array == nil or comp == nil) then
		return filtered
	end

	for index, value in ipairs(array) do
		if ( comp(value) ) then
			table.insert(filtered, value)
		end
	end

	return filtered
end

---@generic T
---@param array T[]
---@param comp? fun(a: T):any
function SelectFromArrayValues(array, comp)
	local selected = {}

	if(array == nil or comp == nil) then
		return selected
	end

	for index, value in ipairs(array) do
		table.insert(selected, comp(value))
	end

	return selected
end

---@generic T
---@param array T[]
---@param comp? fun(a: T):any
function GroupArrayByValue(array, comp)

	local groups = {}

	if(array == nil or comp == nil) then
		return groups
	end

	for index, value in ipairs(array) do

		local groupKey = comp(value);

		if(groups[groupKey] == nil) then
			groups[groupKey] = {}
		end

		table.insert(groups[groupKey], value)
	end

	return groups
end

---@generic T
---@param someTable T[]
---@param comp? fun(a: T):boolean
function FilterByTableValues(someTable, comp)

	local filtered = {}

	if(someTable == nil or comp == nil) then
		return filtered
	end

	for key, value in pairs(someTable) do
		if ( comp(value) ) then
			filtered[key] = value
		end
	end

	return filtered
end

function IsNumber(object)
	return type(object) == "number"
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