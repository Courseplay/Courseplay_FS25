package.path = package.path .. ";../test/?.lua;../geometry/?.lua;../../geometry/?.lua;../genetic/?.lua;..?.lua;../?.lua;../../?.lua;../../pathfinder/?.lua;../../util/?.lua"
lu = require("luaunit")
dofile('require.lua')