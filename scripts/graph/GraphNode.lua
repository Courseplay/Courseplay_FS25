---@class GraphNode
GraphNode = CpObject()
function GraphNode:init()
    self._id = -1
    ---@type GraphNode[]
    self._childNodes = {}
    ---@type GraphNode|nil
    self._parentNode = nil
end

---@param id number
function GraphNode:setID(id)
    self._id = id
end

---@return number
function GraphNode:getID()
    return self._id
end

---@return string
function GraphNode:getRelativeID()
    if self._parentNode then 
        return string.format("%s.%s", self._parentNode:getID(), self._id)
    end
    return "?." .. tostring(self._id)
end

function GraphNode:decrementID()
    self._id = self._id - 1
end

function GraphNode:incrementID()
    self._id = self._id + 1
end

function GraphNode:repairIDs()
    for i, node in ipairs(self._childNodes) do 
        node:setID(i)
    end
end

---@return boolean
function GraphNode:isValid()
    return self._id >= 0
end

function GraphNode:setInvalid()
    self._id = -1
end

---@return GraphNode
function GraphNode:getParentNode()
    return self._parentNode
end

---@param node GraphNode|nil
function GraphNode:setParent(node)
    self._parentNode = node
end

---@return boolean
function GraphNode:isFirstNode()
    if not self._parentNode then 
        return true
    end
    local index = self._parentNode:getChildNodeIndex(self)
    return index == 1
end

---@return boolean
function GraphNode:isLastNode()
    if not self._parentNode then 
        return false
    end
    local index = self._parentNode:getChildNodeIndex(self)
    return index == self._parentNode:getNumChildNodes()
end

function GraphNode:hasChildNodes()
    return #self._childNodes > 0
end

---@param childNode GraphNode|nil
---@return number|nil
function GraphNode:getChildNodeIndex(childNode)
    for ix, node in ipairs(self._childNodes) do 
        if node == childNode then
            return ix     
        end
    end
end

---@param index number|nil
---@return GraphNode|nil
function GraphNode:getChildNodeByIndex(index)
    if index ~= nil then
        return self._childNodes[index]
    end
end

---@param sx number
---@param ex number
---@return GraphNode[]
function GraphNode:cloneChildNodesBetweenIndex(sx, ex)
    local nodes = {}
    for ix, node in ipairs(self._childNodes) do 
        if ix >= sx and ix <= ex then
            table.insert(nodes, node:clone(true))
        end
    end
    return nodes
end

---@return number
function GraphNode:getNumChildNodes()
    return #self._childNodes
end

---@return GraphNode[]
function GraphNode:getAllChildNodes()
    return self._childNodes
end

---@return string|nil
function GraphNode:getLastNodeID()
    local node = self._childNodes[#self._childNodes]
    return node and node:getRelativeID()
end

--- Unlink the node from the parent and remove it from it's children
---@param successCallback function|nil
---@return boolean
function GraphNode:unlink(successCallback)
    local success = false
    if self._parentNode then 
        local parentNode = self._parentNode
        if self._parentNode:removeChildNode(self) then 
            success = true
            if successCallback then
                successCallback(self, parentNode)
            end
        end
    end
    return success 
end

---@param newNode GraphNode
function GraphNode:appendChildNode(newNode) 
    table.insert(self._childNodes, newNode)
    newNode:setID(#self._childNodes)
    self:onAddedChildNode(newNode)
end

---@param newNode GraphNode
---@param reverse boolean
function GraphNode:extendByChildren(newNode, reverse)
    self:extendByChildNodes(newNode:getAllChildNodes(), reverse)
end

---@param newNodes GraphNode[]
---@param reverse boolean
function GraphNode:extendByChildNodes(newNodes, reverse)
    local ix, l, dx = 1, #newNodes, 1
    if reverse then 
        ix, l, dx = #newNodes, 1, -1
    end
    for i=ix, l, dx do 
        self:appendChildNode(newNodes[i]:clone(true))
    end
end

---@param newNode GraphNode
---@param reverse boolean
function GraphNode:prepandByChildren(newNode, reverse)
    local ix, l, dx = 1, newNode:getNumChildNodes(), 1
    if reverse then 
        ix, l, dx = newNode:getNumChildNodes(), 1, -1
    end
    for i=ix, l, dx do 
        self:insertChildNodeAtIndex(
            newNode:getChildNodeByIndex(i):clone(true), 1)
    end
end

---@param newNode GraphNode
---@param index number|nil [1, #self._childNodes + 1]
function GraphNode:insertChildNodeAtIndex(newNode, index)
    if index == nil then 
        return
    end
    table.insert(self._childNodes, index, newNode)
    newNode:setID(index)
    for ix=index + 1, #self._childNodes do 
        self._childNodes[ix]:incrementID()
    end
    self:onAddedChildNode(newNode)
    return newNode:getRelativeID()
end

---@param node GraphNode
function GraphNode:onAddedChildNode(node)
    node:setParent(self)
end

---@param sx number
---@param ex number
function GraphNode:removeChildNodesBetweenIndex(sx, ex)
    for ix = math.min(ex, #self._childNodes), sx, -1 do 
        local n = table.remove(self._childNodes, ix)
        n:setInvalid()
        self:onRemovedChildNode(n)
    end
    self:repairIDs()
end

---@param oldNode GraphNode
function GraphNode:removeChildNode(oldNode)
    local found = false
    for ix, point in ipairs(self._childNodes) do 
        if point == oldNode then 
            self:removeChildNodeAtIndex(ix)
            found = true
            break
        end
    end
    return found
end

---@param index number
---@return boolean, GraphNode|nil
function GraphNode:removeChildNodeAtIndex(index)
    local n = table.remove(self._childNodes, index)
    if n ~= nil then 
        for ix = index, #self._childNodes do 
            self._childNodes[ix]:decrementID()
        end
        n:setInvalid()
        self:onRemovedChildNode(n)
    end
    return n ~= nil, n
end

---@param node GraphNode
function GraphNode:onRemovedChildNode(node)
    node:setParent(nil)
end

function GraphNode:clearChildNodes()
    for i = #self._childNodes, 1, -1 do 
        self._childNodes[i]:unlink()
    end
end

---@param newNode GraphNode
---@param unlink boolean|nil
function GraphNode:copyTo(newNode, unlink)
    if not unlink then
        newNode._parentNode = self._parentNode
    end
    for _, node in ipairs(self._childNodes) do 
        newNode:appendChildNode(node:clone(unlink))
    end
end

---@param unlink boolean|nil
function GraphNode:clone(unlink)
    --- Override
end

---@return string[]
function GraphNode:getDebugInfos()
    local data = {string.format("ID: %s", self:getRelativeID())}
    if self._parentNode then 
        for ix, l in ipairs(self._parentNode:getDebugInfos()) do
            data[ix + 1] = l
        end
    end
    return data
end