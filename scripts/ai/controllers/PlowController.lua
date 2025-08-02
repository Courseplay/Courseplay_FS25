--- Controller for Plows
--- Implements the automatic side(x) Offset calculation.
---@class PlowController : ImplementController
PlowController = CpObject(ImplementController)

function PlowController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.plowSpec = self.implement.spec_plow
    -- towed (not hitch mounted) and can reverse
    self.towed = AIUtil.getFirstReversingImplementWithWheels(vehicle, true)
    -- temporarily store the direction of the last turn. This hack is for the case when for some reason
    -- the plow was not rotated into the working position before lowering. If that's the case, onLowering will
    -- rotate it but it needs to know which direction to lower, which, however is not known at that point
    -- anymore
    self.lastPlowSide = CpTemporaryObject()
end


---@return number|nil if an X offset could be calculated, return that, otherwise nil
function PlowController:getAutomaticXOffset()
    if self:isRotatablePlow() and not self:isFullyRotated() then
        self:debugSparse('Plow is not fully rotated, not calculating offset')
        return nil
    end
	local aiLeftMarker, aiRightMarker, aiBackMarker = self.implement:getAIMarkers()
    if aiLeftMarker and aiBackMarker and aiRightMarker then
        local attacherJoint = self.implement:getActiveInputAttacherJoint()
        local referenceNode = attacherJoint and attacherJoint.node or self.vehicle:getAIDirectionNode()
        -- find out the left/right AI markers distance from the attacher joint (or, if does not exist, the
        -- vehicle's direction node) to calculate the offset.
        self.plowReferenceNode = referenceNode
        local leftMarkerDistance, rightMarkerDistance = self:getOffsets(referenceNode, 
			aiLeftMarker, aiRightMarker)
        -- some plows rotate the markers with the plow, so swap left and right when needed
        -- so find out if the left is really on the left of the vehicle's root node or not
        local leftDx, _, _ = localToLocal(aiLeftMarker, self.vehicle:getAIDirectionNode(), 0, 0, 0)
        local rightDx, _, _ = localToLocal(aiRightMarker, self.vehicle:getAIDirectionNode(), 0, 0, 0)
        if leftDx < rightDx then
            -- left is positive x, so looks like the plow is inverted, swap left/right then
            leftMarkerDistance, rightMarkerDistance = -rightMarkerDistance, -leftMarkerDistance
        end
        local newToolOffsetX = -(leftMarkerDistance + rightMarkerDistance) / 2
        self:debugSparse('Current Offset left = %.1f, right = %.1f, leftDx = %.1f, rightDx = %.1f, new = %.1f',
            leftMarkerDistance, rightMarkerDistance, leftDx, rightDx, newToolOffsetX)
		return newToolOffsetX
    end
	return 0
end

function PlowController:getOffsets(referenceNode, aiLeftMarker, aiRightMarker)
    local refX, _, refZ = getWorldTranslation(referenceNode)
    local lx, _, lz = getWorldTranslation(aiLeftMarker)
    local rx, _, rz = getWorldTranslation(aiRightMarker)
    local leftOffset = -self:getScalarProjection(lx - refX, lz - refZ, lx - rx, lz - rz)
    local rightOffset = self:getScalarProjection(rx - refX, rz - refZ, rx - lx, rz - lz)
    return leftOffset, rightOffset
end

--- Get scalar projection of vector v onto vector u
function PlowController:getScalarProjection(vx, vz, ux, uz)
    local dotProduct = vx * ux + vz * uz
    local length = math.sqrt(ux * ux + uz * uz)
    return dotProduct / length
end

--- Is the plow currently being rotated?
---@return boolean
function PlowController:isRotationActive()
	return self:isRotatablePlow() and self.implement:getIsAnimationPlaying(self.plowSpec.rotationPart.turnAnimation)
end

--- Can the plow be rotated?
function PlowController:isRotatablePlow()
    return self.plowSpec.rotationPart.turnAnimation ~= nil
end

function PlowController:getIsPlowRotationAllowed()
    return self.implement:getIsPlowRotationAllowed()
end

function PlowController:isFullyRotated()
    local rotationAnimationTime = self.implement:getAnimationTime(self.plowSpec.rotationPart.turnAnimation)
    return rotationAnimationTime < 0.001 or rotationAnimationTime > 0.999
end

--- Rotates the plow if possible.
---@param shouldBeOnTheLeft boolean|nil
function PlowController:rotate(shouldBeOnTheLeft)
    if self:isRotatablePlow() and self:getIsPlowRotationAllowed() then
        self.implement:setRotationMax(shouldBeOnTheLeft)
    end
end

--- We rotate plows in 180º turns to the center so we can turn on a smaller radius. This is
--- triggered by the onFinishRow and onTurnEndProgress controller events emitted by all
--- CourseTurn and derived turns.
--- With the Giants helper, plows are rotated by the onAIFieldWorkerTurnProgress event which
--- we now only use in the KTurn (only 3-point hitch mounted plows use the KTurn, so all
--- plow turns are covered)

--- This is called once when the row is finished and the turn is just about to start.
--- Rotate the plow to the center position to allow for smaller turn radius (when not rotated,
--- the tractor's back wheel touching the plow won't let us turn sharp enough, and thus
--- using a lot of real estate for a turn.
---@param isHeadlandTurn boolean true if this is a headland turn
function PlowController:onFinishRow(isHeadlandTurn)
    -- no need to rotate to center on headland turns
    if self:isRotatablePlow() and not isHeadlandTurn then
        PlowCenterTurnEvent.sendEvent(self.implement)
    end
end


--- making sure the plow is in the working position when lowering
-- TODO: this whole magic hack would not be necessary if we moved the actual lowering into onTurnEndProgress()
function PlowController:onLowering()
    -- if we just turned (that is, not starting to work)
    local lastPlowSide = self.lastPlowSide:get()
    if lastPlowSide ~= nil and
            self:isRotatablePlow() and not self:isFullyRotated() and not self:isRotationActive() then
        self:debug('Lowering, rotating plow to working position (plow in last turn was left %s).', lastPlowSide)
        -- rotation direction depends on the direction of the last turn
        self.implement:setRotationMax(lastPlowSide)
    end
end

--- This is called in every loop when we approach the start of the row, the location where
--- the plow must be lowered. Currently the WorkStarter takes care of the lowering,
--- here we only make sure that the plow is rotated to the work position (from the center position)
--- in time.
---@param workStartNode number node where the work starts as calculated by TurnContext
---@param reversing boolean driving in reverse now
---@param shouldLower boolean the implement should be lowered as we are close to the work start (this
--- should most likely be calculated here in the controller, but for now, we get it from an argument
---@param shouldBeOnTheLeft boolean should the plow be turned to the left to be in the good position after the turn?
function PlowController:onTurnEndProgress(workStartNode, reversing, shouldLower, shouldBeOnTheLeft)
    self.lastPlowSide:set(shouldBeOnTheLeft or false, 2000)
    if self:isRotatablePlow() and not self:isFullyRotated() and not self:isRotationActive() then
        -- more or less aligned with the first waypoint of the row, start rotating to working position
        if CpMathUtil.isSameDirection(self.implement.rootNode, workStartNode, 30) or shouldLower then
            if self.towed then
                -- let towed plows remain in the center position while reversing to the start of the row
                if not reversing then
                    self:debug('Rotating towed plow to working position.')
                    self.implement:setRotationMax(shouldBeOnTheLeft)
                end
            else
                self:debug('Rotating hitch-mounted plow to working position.')
                self.implement:setRotationMax(shouldBeOnTheLeft)
            end
        end
    end
end

function PlowController:canContinueWork()
    if self:isRotatablePlow() then
        return self:isFullyRotated()
    else
        return true
    end
end