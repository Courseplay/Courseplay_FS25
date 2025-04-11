
---@class GraphEditor : CourseEditor
GraphEditor = CpObject(CourseEditor)
GraphEditor.TRANSLATION_PREFIX = "CP_editor_graph_"

function GraphEditor:init()
    CourseEditor.init(self)
    ---@type EditorGraphWrapper
    self.graphWrapper = EditorGraphWrapper(g_graph)
    self.title = string.format("TODO: CP GraphEditor")

    g_consoleCommands:registerConsoleCommand("cpOpenGraphEditor", "Opens the CP Graph editor", "open", self)
end

function GraphEditor:load()
    self.brushCategory = self:loadCategory(Utils.getFilename("config/GraphEditorCategories.xml", g_Courseplay.BASE_DIRECTORY))
end

function GraphEditor:draw(x, y, z)
    self.graphWrapper:draw({x, y, z})
end

function GraphEditor:open()
    self.isActive = true
    g_messageCenter:publish(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU, self)
end

function GraphEditor:getStartPosition()
    return 
end

function GraphEditor:getCourseWrapper()
    return self.graphWrapper
end

function GraphEditor:onClickExit(callbackFunc)
    self.isActive = false
    callbackFunc()
	-- YesNoDialog.show(
	-- 	function (self, clickOk)
	-- 		self:deactivate(clickOk)
	-- 		callbackFunc()
	-- 	end,
	-- 	self, string.format(g_i18n:getText("CP_GraphEditor_save_changes"), self.file:getName()))
end


--- Updates the course display, when a waypoint change happened.
function GraphEditor:updateChanges(ix)
	-- self.courseDisplay:updateChanges(ix)
end

--- Updates the course display, when a single waypoint change happened.
function GraphEditor:updateChangeSingle(ix)
	-- self.courseDisplay:updateWaypoint(ix)
end

--- Updates the course display, between to waypoints.
function GraphEditor:updateChangesBetween(firstIx, lastIx)
	-- self.courseDisplay:updateChangesBetween(firstIx, lastIx)
end

---@type GraphEditor
g_graphEditor = GraphEditor()