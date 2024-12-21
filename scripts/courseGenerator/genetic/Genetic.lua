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

Genetic = {}

-- for 5.1 and 5.2 compatibility
local unpack = unpack or table.unpack

function Genetic.newClass(parent)
	local child = {}
	child.__index = child
	if parent then
		setmetatable(child, { __index = parent })
		child.__tostring = parent.__tostring
	end

	return child
end

--- Generic chromosome
---@class Chromosome
local Chromosome = Genetic.newClass()

--- A chromosome with nGenes number of genes, each can have a 
-- value of one of the values table
function Chromosome:new(nGenes, validValues)
	local instance = {}
	instance.nGenes = nGenes
	instance.validValues = validValues
	return setmetatable(instance, self)
end

function Chromosome:create(genes)
	local newChromosome = {unpack(genes)}
	return setmetatable(newChromosome, self)
end

function Chromosome:newRandom(nGenes, validValues)
	local c = self:new(nGenes, validValues)
	c:fillWithRandomValues()
	return c
end

-- For automated testing, set each gene to one of the valid values
function Chromosome:setToValues(values)
	for i = 1, self.nGenes do
		self[i] = self.validValues[values[i]]
	end
end

function Chromosome:__tostring()
	local str = ''
	for i = 1, #self do
		str = str .. tostring(self[i]) .. '-'
	end
	if self.fitness then
		str = str .. ' f=' .. self.fitness
	end
	return str
end

function Chromosome:getFitness()
	return self.fitness
end

---@class Genetic.Chromosome
Genetic.Chromosome = Chromosome

--- Chromosome where the sequence of the genes is important
---@class PermutationEncodedChromosome : Chromosome
local PermutationEncodedChromosome = Genetic.newClass(Chromosome)

function PermutationEncodedChromosome:fillWithRandomValues()
	local validValues = {}
	for i, v in ipairs(self.validValues) do
		validValues[i] = v
	end
	for i = 1, self.nGenes do
		local validValueIx = math.random(#validValues)
		self[i] = validValues[validValueIx]
		table.remove(validValues, validValueIx)
	end
end

function PermutationEncodedChromosome:mutate()
	if #self < 2 then return end
	local firstPos = math.random(#self)
	local secondPos = firstPos
	while firstPos == secondPos do secondPos = math.random(#self) end
	self[firstPos], self[secondPos] = self[secondPos], self[firstPos]
end

function PermutationEncodedChromosome:crossover(spouse)
	local xOverPos = math.random(#self)
	local offspring = {}
	for i = 1, xOverPos do
		offspring[ i ] = self[ i ]
	end
	for _, g in ipairs(spouse) do
		local found = false
		for i = 1, #offspring do
			if g == offspring[ i ] then found = true end
		end
		if not found then
			table.insert(offspring, g)
		end
	end
	return PermutationEncodedChromosome:create(offspring)
end

---@class Genetic.PermutationEncodedChromosome
Genetic.PermutationEncodedChromosome = PermutationEncodedChromosome

--- Chromosome uses real values as the genes
local ValueEncodedChromosome = Genetic.newClass(Chromosome)

function ValueEncodedChromosome:copy(other)
	local instance = {}
	instance.nGenes = other.nGenes
	instance.validValues = other.validValues
	for _, c in ipairs(other) do
		table.insert(instance, c)
	end
	return setmetatable(instance, self)
end

--- Initialize each gene with a random valid value 
function ValueEncodedChromosome:fillWithRandomValues()
	for i = 1, self.nGenes do
		self[i] = self.validValues[math.random(#self.validValues)]
	end
end

-- Uniform crossover
function ValueEncodedChromosome:crossover(spouse)
	local offspring = ValueEncodedChromosome:copy(self)
	for i = 1, #self do
		if math.random(2) > 1 then
			offspring[ i ] = spouse[ i ]
		end
	end
	return offspring
end

--- Change a random gene to a random new valid value
-- TODO: is it really ok to pick a random value or should we pick 
-- the next/previous one?
function ValueEncodedChromosome:mutate(mutationRate)
	if math.random() <= mutationRate then
		local newValue = self.validValues[ math.random(#self.validValues)]
		self[ math.random(self.nGenes)] = newValue
	end
end

---@class Genetic.ValueEncodedChromosome
Genetic.ValueEncodedChromosome = ValueEncodedChromosome

---@class Population
local Population = Genetic.newClass()

function Population:new(fitnessFunc, tournamentSize, mutationRate)
	local instance = {}
	instance.tournamentSize = tournamentSize or 5
	instance.mutationRate = mutationRate or 0.02
	instance.fitnessFunc = fitnessFunc
	return setmetatable(instance, self)
end

function Population:initialize(size, chromosomeFactory)
	for i = 1, size do
		local c = chromosomeFactory()
		self[ i ] = c
	end
	self.size = size
	self.totalFitness = 0
end

--- Calculate the fitness of all chromosomes of the population.
-- fitnessFunction is expected to take a Chromosome as an argument
-- and calculate and store the fitness of the chromosome and also 
-- return the calculated fitness for total population fitness calculation
function Population:calculateFitness()
	self.totalFitness = 0
	self.bestFitness = -1
	self.misfits = 0
	self.bestChromosome = nil
	for i = 1, #self do
		self.fitnessFunc(self[ i ])
		self.totalFitness = self.totalFitness + self[i]:getFitness()
		if self[i]:getFitness() > self.bestFitness then
			self.bestFitness = self[i]:getFitness()
			self.bestChromosome = self[ i ]
		end
		if self[i]:getFitness() == 0 then
			self.misfits = self.misfits + 1
		end
	end
end

function Population:selectElite(maxEliteRatio)
	local elite = Population:new()
	for _, c in ipairs(self)  do
		if c:getFitness() >= (self.bestFitness * 0.7) then
			table.insert(elite, c)
			if #elite > #self * maxEliteRatio then
				break
			end
		end
	end
	return elite
end

function Population:selectRouletteWheel()
	local limit = math.random(self.totalFitness)
	local totalFitness = 0
	for i, c in ipairs(self) do
		totalFitness = totalFitness + c:getFitness()
		if totalFitness >= limit then
			return c
		end
	end
end

function Population:selectTournament()
	local bestFitness = -1
	local selected
	for i = 1, self.tournamentSize do
		local randomIx = math.floor(math.random(#self))
		if self[ randomIx ]:getFitness() > bestFitness then
			selected = self[ randomIx ]
		end
	end
	return selected
end

function Population:selectParentsTournament()
	local mother = self:selectTournament()
	local father = self:selectTournament()
	return mother, father
end

function Population:selectParentsRouletteWheel()
	local mother = self:selectRouletteWheel()
	local father = self:selectRouletteWheel()
	return mother, father
end

-- Breed a new generation
function Population:breed()
	local newGeneration = {}
	for j = 1, #self do
		local mother, father = self:selectParentsTournament()
		local offspring = mother:crossover(father)
		offspring:mutate(self.mutationRate)
		table.insert(newGeneration, offspring)
	end
	return newGeneration
end

-- recombine the new generation with the current population
function Population:recombine(newGeneration)
	for _, c in ipairs(newGeneration) do
		table.insert(self, c)
	end
	self:calculateFitness()
	-- sort according to the fitness, fittest first
	table.sort(self, function (a, b) return a:getFitness() > b:getFitness() end)
	-- keep the population size stable, keeping only the fittest individuals
	for i = self.size, #self - 1 do
		table.remove(self, #self)
	end
end

function Population:__tostring()
	local str = ''
	for i = 1, #self do
		str = string.format('%s\n%d\t%s', str, i, self[ i ])
	end
	if self.totalFitness then
		str = string.format('%s\nTotal fitness: %.1f', str, self.totalFitness)
	end
	if self.misfits then
		str = string.format('%s\nZero fitness population: %d', str, self.misfits)
	end
	if self.bestFitness then
		str = string.format('%s\nBest fitness: %.1f', str, self.bestFitness)
	end
	if self.bestChromosome then
		str = string.format('%s\nBest solution: %s', str, self.bestChromosome)
	end
	return str
end

---@class Genetic.Population
Genetic.Population = Population