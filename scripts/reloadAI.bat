@echo off
set outfile=..\reload.xml
echo ^<code^> > %outfile%
echo ^<![CDATA[ >> %outfile%
type ai\strategies\AIDriveStrategyCourse.lua >> %outfile%
type ai\strategies\AIDriveStrategyFieldWorkCourse.lua >> %outfile%
type ai\strategies\AIDriveStrategyCombineCourse.lua >> %outfile%
type ai\strategies\AIDriveStrategyPlowCourse.lua >> %outfile%
type ai\strategies\AIDriveStrategyDriveToFieldWorkStart.lua >> %outfile%
type ai\strategies\AIDriveStrategyVineFieldWorkCourse.lua >> %outfile%
type ai\strategies\AIDriveStrategyFindBales.lua >> %outfile%
type ai\strategies\AIDriveStrategyUnloadCombine.lua >> %outfile%
type ai\strategies\AIDriveStrategyStreetDriveToPoint.lua >> %outfile%
echo ]]^> >> %outfile%
echo ^</code^> >> %outfile%