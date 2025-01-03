--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2018-2023 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]


-- We are using a genetic algorithm to find the optimum sequence of the blocks to work on.
-- In case of a non-convex field or a field with island(s) in it, the field is divided into
-- multiple areas (blocks) which are covered by the up/down rows independently. 

-- We are looking for the optimum route to work these blocks, meaning the one with the shortest
-- path between the blocks. There are two factors determining the length of this path: 
-- 1. the sequence of blocks
-- 2. where do we start each block (which corner), which also determines the exit corner of 
--    the block.
--
-- This is an improved version of the algorithm detailed in:]
-- Ibrahim A. Hameed, Dionysis Bochtis and Claus A. Sørensen: An Optimized Field Coverage Planning
-- Approach for Navigation of Agricultural Robots in Fields Involving Obstacle Areas

--- Composite chromosome for a field block to determine the best sequence of blocks 
---@class FieldBlockChromosome
local FieldBlockChromosome = Genetic.newClass()

---@param blocks CourseGenerator.Block[]
function FieldBlockChromosome:new(blocks)
    local instance = {}
    -- this chromosome has the sequence of blocks encoded
    instance.blockSequence = Genetic.PermutationEncodedChromosome:new(#blocks, blocks)
    -- then there is one chromosome for each block with the entry point for that block encoded
    -- due to the fact that the entries, and even the number of entry points can be different for
    -- each block, we can't put all entry genes in the same chromosome.
    instance.entries = {}
    instance.possibleEntries = {}
    self.blocks = blocks
    for _, b in ipairs(blocks) do
        local entries = {}
        -- store the actual possible entries for this block
        instance.possibleEntries[b] = b:getPossibleEntries()
        for i, e in ipairs(instance.possibleEntries[b]) do
            -- and then, in the chromosome for b, we just store the index of the entry in possibleEntries[b]
            -- so the gene values are integers, not tables so when manipulating the gene, we don't have to
            -- copy tables
            table.insert(entries, i)
        end
        instance.entries[b] = Genetic.ValueEncodedChromosome:new(1, entries)
    end
    return setmetatable(instance, self)
end

function FieldBlockChromosome:__tostring()
    local str = ''
    for _, b in ipairs(self.blockSequence) do
        str = string.format('%s%s(%s)-', str, b, self.entries[b][1])
    end
    if self.distance and self.fitness then
        str = string.format('%s f = %.1f, d = %.1f m', str, self.fitness, self.distance)
    end
    return str
end

function FieldBlockChromosome:fillWithRandomValues()
    self.blockSequence:fillWithRandomValues()
    for _, entry in pairs(self.entries) do
        entry:fillWithRandomValues()
    end
end

function FieldBlockChromosome:setToValues(blockSequenceValues, entriesValues)
    self.blockSequence:setToValues(blockSequenceValues)
    for b, entry in pairs(self.entries) do
        entry:setToValues({ entriesValues[b:getId()] })
    end
end

function FieldBlockChromosome:crossover(spouse)
    local offspring = FieldBlockChromosome:new(self.blockSequence)
    offspring.blockSequence = self.blockSequence:crossover(spouse.blockSequence)
    for b, entry in pairs(self.entries) do
        offspring.entries[b] = entry:crossover(spouse.entries[b])
    end
    return offspring
end

function FieldBlockChromosome:mutate(mutationRate)
    self.blockSequence:mutate(mutationRate)
    self.entries[self.blocks[math.random(#self.blocks)]]:mutate(mutationRate)
end

---@return CourseGenerator.Block[], CourseGenerator.RowPattern.Entry[] blocks in the sequence they should be worked on, entries
--- for each block are in the entries table, indexed by the block itself
function FieldBlockChromosome:getBlockSequenceAndEntries()
    local blocksInSequence = {}
    for _, b in ipairs(self.blockSequence) do
        table.insert(blocksInSequence, b)
    end
    local entries = {}
    for block, e in pairs(self.entries) do
        entries[block] = self.possibleEntries[block][e[1]]
    end
    return blocksInSequence, entries
end

---@param d number total distance travelling between blocks
function FieldBlockChromosome:setDistance(d)
    self.distance = d
end

function FieldBlockChromosome:getDistance()
    return self.distance
end

function FieldBlockChromosome:setFitness(f)
    self.fitness = f
end

function FieldBlockChromosome:getFitness()
    return self.fitness
end

---@class Genetic.FieldBlockChromosome
Genetic.FieldBlockChromosome = FieldBlockChromosome

local BlockSequencer = CpObject()

---@param blocks CourseGenerator.Block[]
function BlockSequencer:init(blocks)
    self.blocks = blocks
    self.logger = Logger('BlockSequencer', nil, CpDebug.DBG_COURSES)
end

--- Find the (near) optimum sequence of blocks and entry/exit points.
-- NOTE: remember to call randomseed before. It isn't part of this function
-- to allow for automatic tests.
-- headland is the innermost headland pass.
--
function BlockSequencer:findBlockSequence(fitnessFunction)
    -- GA parameters, depending on the number of blocks
    local maxGenerations = 10 * #self.blocks
    local tournamentSize = 5
    local mutationRate = 0.3
    local populationSize = 40 * #self.blocks

    math.randomseed(g_time or os.clock())

    -- Set up the initial population with random solutions
    local population = Genetic.Population:new(fitnessFunction, tournamentSize, mutationRate)
    population:initialize(populationSize, function()
        local c = FieldBlockChromosome:new(self.blocks)
        c:fillWithRandomValues()
        return c
    end)

    -- let the solution evolve through multiple generations
    population:calculateFitness()
    local generation = 1
    while generation < maxGenerations do
        local newGeneration = population:breed()
        population:recombine(newGeneration)
        generation = generation + 1
        self.logger:debug('generation %d %s', generation, tostring(population.bestChromosome))
    end
    self.logger:debug(tostring(population.bestChromosome))
    if population.bestChromosome:getFitness() == 0 then
        self.logger:error('no solution found!')
        return nil
    else
        local blocks, entries = population.bestChromosome:getBlockSequenceAndEntries()
        return blocks, entries, population.bestChromosome:getDistance()
    end
end

---@class CourseGenerator.BlockSequencer
CourseGenerator.BlockSequencer = BlockSequencer