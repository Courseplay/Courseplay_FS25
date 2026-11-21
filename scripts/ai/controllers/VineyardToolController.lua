--- Lowers and raises vineyard tools without AI markers.
--- These are not in the AI implement list of giants, so lowering all implements
--- at the start of the work would not turn them on.
---@class VineyardToolController : ImplementController
VineyardToolController = CpObject(ImplementController)

function VineyardToolController:onLowering()
    self:debug('Lowering vineyard tool without AI markers')
    self.implement:aiImplementStartLine()
end

function VineyardToolController:onRaising()
    self:debug('Raising vineyard tool without AI markers')
    self.implement:aiImplementEndLine()
end
