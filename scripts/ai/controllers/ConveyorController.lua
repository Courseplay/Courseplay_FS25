--- Controls the unloading with a conveyor.
---@class ConveyorController : ImplementController
ConveyorController = CpObject(ImplementController)
ConveyorController.LEFT_SIDE = 0
ConveyorController.RIGHT_SIDE = 1

function ConveyorController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.conveyorSpec = self.implement.spec_conveyor
	self.cylinderedSpec = self.implement.spec_cylindered
	self.isDischargeEnabled = false

	---self:setupMoveablePipe()
end

function ConveyorController:delete()
	if self.armProjection then
		CpUtil.destroyNode(self.armProjection)
	end
	if self.pipeProjection then
		CpUtil.destroyNode(self.pipeProjection)
	end
end

function ConveyorController:getDriveData()
	local maxSpeed
	if self.isDischargeEnabled then
	
		if self:canDischargeToObject() then 
			if not self:isDischarging() then 
				self.implement:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
			end
		else 
			if self:isDischarging() then 
				self.implement:setDischargeState(Dischargeable.DISCHARGE_STATE_OFF)
			end
		end
		if self:isDischarging() and self:canDischargeToObject() then 
			self:clearInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
		else 
			self:setInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
		end
	end
	return nil, nil, nil, maxSpeed
end

function ConveyorController:update(dt)
--	self:updateMoveablePipe(dt)
end

function ConveyorController:isDischarging()
	return self.implement:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF
end

--- Allows the conveyor to automatically start unloading with a valid unload target.
function ConveyorController:enableDischargeToObject()
	self.isDischargeEnabled = true
end

--- Stops the unloading and disables automatic restart.
function ConveyorController:disableDischarge()
	self.isDischargeEnabled = false
	self:clearInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
end

function ConveyorController:onFinished()
	if self.wasLowered then
		--- Only allowed, if the vehicle was lowered once.
		self.implement:aiImplementEndLine()
	end
	self.implement:setIsTurnedOn(false)
	self:disableDischarge()
end

function ConveyorController:onLowering()
	self.wasLowered = true
	self.implement:aiImplementStartLine()
end

function ConveyorController:onRaising()
	self.implement:aiImplementEndLine()
end

--- Is discharging possible?
function ConveyorController:canDischargeToObject()
	return self.implement:getCanDischargeToObject(self.implement:getCurrentDischargeNode())
end

function ConveyorController:getDischargeFillType()
	return self.implement:getDischargeFillType(self:getDischargeNode())
end

function ConveyorController:getDischargeNode()
	return self.implement:getCurrentDischargeNode()
end

function ConveyorController:getPipeOffsetX()
	local x, _, _ = localToLocal(self:getDischargeNode().node, self.implement.rootNode, 0, 0, 0)
	return x
end

function ConveyorController:getPipeOffsetZ()
	return ImplementUtil.getDistanceToImplementNode(self.vehicle:getAIDirectionNode(), 
		self.implement, self:getDischargeNode().node)
end

function ConveyorController:isPipeOnTheLeftSide()
	return self:getPipeOffsetX() >= 0
end

function ConveyorController:isPipeMoving()
	return not self.implement:getCanAIImplementContinueWork()
end

--- WIP code might be implemented later!
function ConveyorController:setupMoveablePipe()
	self.armProjection = CpUtil.createNode("armProjection", 0, 0, 0)
	self.pipeProjection = CpUtil.createNode("pipeProjection", 0, 0, 0)
	self.pipeSide = self.LEFT_SIDE

	local armMovingToolIx = g_vehicleConfigurations:get(self.implement, 'armMovingToolIx') -- 2
	local movingToolIx = g_vehicleConfigurations:get(self.implement, 'movingToolIx') -- 1
	if movingToolIx and armMovingToolIx then
		self:debug("Setting up moving tools.")
		self.hasValidMovingTools = true
		self.pipeRotationTool = self.cylinderedSpec.movingTools[armMovingToolIx]
		self.armRotationTool = self.cylinderedSpec.movingTools[movingToolIx]
	end
end

--- WIP code might be implemented later!
function ConveyorController:updateMoveablePipe(dt)
	if self.hasValidMovingTools and not self:isPipeMoving() then 
		local dischargeNode = self.implement:getCurrentDischargeNode()
		local bx, _, bz = getWorldTranslation(dischargeNode.node)
		local px, _, pz = getWorldTranslation(self.pipeProjection)
		if MathUtil.vector2Length(px - bx, pz - bz) < 1 then 
			ImplementUtil.stopMovingTool(self.implement, self.armRotationTool)
			ImplementUtil.stopMovingTool(self.implement, self.pipeRotationTool)
			return
		end


		local r1 = calcDistanceFrom(self.pipeRotationTool.node, self.armRotationTool.node)
		DebugUtil.drawDebugCircleAtNode(self.armRotationTool.node, r1, 30, nil)

		local r2 = calcDistanceFrom(self.pipeRotationTool.node, dischargeNode.node)
		DebugUtil.drawDebugCircleAtNode(self.pipeRotationTool.node, r2, 30, nil)

		--- Arm target
		local ax, ay, dz = localToLocal(self.armRotationTool.node, self.implement.rootNode, 0, 0, 0)

		local px, _, pz = localToWorld(self.implement.rootNode, 0, 0, -r1 + dz)

		local ax, ay, az = getWorldTranslation(self.armRotationTool.node)

		local tx, ty, tz = getWorldTranslation(self.pipeRotationTool.node)

		setWorldTranslation(self.armProjection, px, ay, pz)


		local dirX, _, dirZ = localDirectionToWorld(self.implement.rootNode, 0, 0, 0)
		local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
		setWorldRotation(self.armProjection, 0, yRot, 0)

		DebugUtil.drawDebugLine(px, ay, pz, ax, ay, az)
		DebugUtil.drawDebugLine(px, ay, pz, tx, ty, tz)
		
		local curRot = {}
		curRot[1], curRot[2], curRot[3] = getRotation(self.armRotationTool.node)
		local oldRot = curRot[self.armRotationTool.rotationAxis]

		local yRot = math.atan2(MathUtil.vector3Length(px - tx, ay - ty, pz - tz),
		MathUtil.vector3Length(px - ax, ay - ay, pz - az))

		local dyRot = 0

		local dx, _, _ = localToLocal(self.pipeRotationTool.node, self.implement.rootNode, 0, 0, 0)

		if dx < 0 then 
			dyRot = -yRot
		else 
			dyRot = yRot
		end
		self:debug("Arm: yRot: %.2f, dyRot: %.2f, oldRot: %.2f, dx: %.2f", math.deg(yRot), math.deg(dyRot), math.deg(oldRot), dx)
		ImplementUtil.moveMovingToolToRotation(self.implement, self.armRotationTool, dt, 
			CpMathUtil.clamp(oldRot + dyRot, self.armRotationTool.rotMin, self.armRotationTool.rotMax))
		local _, _, dz = localToLocal(self.pipeRotationTool.node, self.implement.rootNode, 0, 0, 0)
		local px, py, pz
		if self.pipeSide == self.LEFT_SIDE then 
			px, py, pz = localToWorld(self.implement.rootNode, -r2, 0, dz)
		else 
			px, py, pz = localToWorld(self.implement.rootNode, r2, 0, dz)
		end
		setWorldTranslation(self.pipeProjection, px, ay, pz)
		local ax, ay, az = getWorldTranslation(self.pipeRotationTool.node)

		local tx, ty, tz = getWorldTranslation(dischargeNode.node)
		DebugUtil.drawDebugLine(px, ay, pz, ax, ty, az)
		DebugUtil.drawDebugLine(px, ty, pz, tx, ay, tz)

		local curRot = {}
		curRot[1], curRot[2], curRot[3] = getRotation(self.pipeRotationTool.node)
		local oldRot = curRot[self.pipeRotationTool.rotationAxis]

		local yRot = math.atan2(MathUtil.vector2Length(px - tx, pz - tz),
		MathUtil.vector2Length(px - ax, pz - az))

		local dyRot = 0

		local dx, _, dz2 = localToLocal(dischargeNode.node, self.implement.rootNode, 0, 0, 0)


		if dx > 0 then 
			dyRot = -yRot
		else 
			dyRot = yRot
		end
		if dz2 > dz then 
			dyRot = -dyRot
		end
		local bx, _, bz = getWorldTranslation(dischargeNode.node)
		if MathUtil.vector2Length(px - bx, pz - bz) > 1 then 
			ImplementUtil.moveMovingToolToRotation(self.implement, self.pipeRotationTool, dt, 
				CpMathUtil.clamp(MathUtil.normalizeRotationForShortestPath(dyRot, oldRot), self.pipeRotationTool.rotMin, self.pipeRotationTool.rotMax))
			self:debug("Pipe: yRot: %.2f, dyRot: %.2f, oldRot: %.2f, dx: %.2f, dz: %.2f, dz2: %.2f",
				math.deg(yRot), math.deg(dyRot), math.deg(oldRot), dx, dz, dz2)
		end
	end
end