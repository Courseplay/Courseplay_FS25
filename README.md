FORKED from Original Courseplay

Antler22's edit to allow manual combine unloading, US units, and some small tweaks to pathfinder

# Courseplay — Manual Combine Unloader Feature

**Author of changes:** Antler22  
**Base branch:** FS25_Courseplay (current main)  
**Purpose of document:** Summary of all code changes for review and potential integration into the main branch.

---

## Overview

This feature adds a **"Call Grain Cart"** button to manually-driven combines (i.e. combines that the player is driving themselves, not Courseplay-controlled). When activated, a nearby Courseplay-managed grain cart automatically:

1. Approaches the combine via pathfinding
2. Positions itself under the combine's unloading pipe
3. Follows the combine while it harvests (including through gentle curves and S-bends)
4. Leaves when the player closes the pipe (2-second debounce prevents false exits)
5. Automatically re-approaches if it loses position

The design goal is that the player only touches the button once — the grain cart handles everything until the pipe is closed.

---

## Files Changed

| File | Status | Summary |
|---|---|---|
| `scripts/ai/CpManualCombineProxy.lua` | **New** | Proxy class mimicking `AIDriveStrategyCombineCourse` interface |
| `scripts/specializations/CpAIFieldWorker.lua` | **Modified** | Call Grain Cart button toggle and proxy lifecycle |
| `scripts/specializations/CpAIWorker.lua` | **Modified** | Disable button/keybind for forage harvesters |
| `scripts/ai/strategies/AIDriveStrategyUnloadCombine.lua` | **Modified** | Core unloader steering, off-track recovery, proximity fixes |
| `scripts/ai/PurePursuitController.lua` | **Modified** | Soft-recovery hook before hard CP shutdown |
| `scripts/pathfinder/PathfinderUtil.lua` | **Modified** | Defensive windrow filtering in `hasFruit()` |
| `config/VehicleSettingsSetup.xml` | **Modified** | Lower minimum for "Call Unloader At" setting |

---

## 1. New File: `scripts/ai/CpManualCombineProxy.lua`

A new class that implements the full `AIDriveStrategyCombineCourse` interface for manually-driven combines. This allows `AIDriveStrategyUnloadCombine` to interact with a manual combine using the same method calls it uses for CP-driven combines, without any nil checks or special-casing scattered through the unloader code.

### Key design decisions

**`isManualProxy() → true`**  
A marker method so the unloader strategy can identify a manual proxy without re-querying the vehicle. Used to gate manual-only behavior throughout `AIDriveStrategyUnloadCombine`.

**`getFillLevelPercentage() → 1`**  
Always reports 100% full. The farmer is in full control — the grain cart must never leave because of a low fill level. The only valid exit condition is `isUnloadFinished()`.

**`isUnloadFinished()`**  
Requires the discharge to be continuously off for **2 seconds** before returning true. This prevents a momentary swerve or brief pipe misalignment from prematurely ending the session. Once it returns true, the grain cart departs and the proxy re-summons it if the button is still active.

**`willWaitForUnloadToFinish()`**  
3-second debounce before reporting the combine as "stopped." A GPS micro-correction or terrain hitch lasting less than 3 seconds is ignored. Without this, a brief stop would flip the grain cart from `UNLOADING_MOVING_COMBINE` to `UNLOADING_STOPPED_COMBINE`, triggering unnecessary state cycling.

**`registerUnloader(driver)` / `deregisterUnloader()`**  
Uses a `CpTemporaryObject` with a 1-second TTL. The grain cart calls `registerUnloader` every frame while it has an active combine. When the cart releases (soft recovery or natural exit), the TTL expires and the proxy's `callUnloaderWhenNeeded()` can re-summon within ~2.5 seconds.

**`callUnloaderWhenNeeded()`**  
Runs every 1500 ms. If no unloader is registered, searches active CP unloader vehicles via `AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader()`, scores by fill level and distance, and calls `strategy:call(self.vehicle, nil)` on the best candidate. This is the mechanism that auto-resumes after soft recovery.

**`getFruitAtSides() → nil, nil`**  
Forage harvesters crash `calculateAutoAimPipeOffsetX()` if this returns nil before `checkFruit()` has run. Returning `nil, nil` is safe for standard combines and avoids the crash for any chopper that might somehow reach this code path.

**`isTurning() → false`**  
The unloader has special "wait during combine turn" logic that is inappropriate when the farmer is manually steering. Always returning false keeps the grain cart tracking the pipe rather than holding position at the headland.

---

## 2. Modified: `scripts/specializations/CpAIFieldWorker.lua`

### What was added

- **`cpIsCallGrainCartActive()`** — Returns `true` when `spec.cpManualCombineProxy ~= nil`.
- **`cpToggleCallGrainCart()`** — Creates a new `CpManualCombineProxy` (activate) or deletes the existing one (deactivate). Guards against activation when CP is already active on the combine.
- **`cpGetManualCombineProxy()`** — Returns the current proxy instance.
- **`onUpdate(dt)`** — Drives the proxy's update loop each tick (course refresh + unloader call cycle). Auto-deactivates the proxy if `getIsCpActive()` becomes true on the combine.

---

## 3. Modified: `scripts/specializations/CpAIWorker.lua`

### "Call Grain Cart" button disabled for forage harvesters

Forage harvesters (choppers) have an auto-aiming spout and behave very differently from grain combines. Calling a grain cart unloader on a chopper causes errors. The button and keybind are now hidden when the vehicle has `pipeSpec.numAutoAimingStates > 0`.

```lua
local isChopper = pipeSpec and (pipeSpec.numAutoAimingStates or 0) > 0
local showCallGrainCart = hasPipe and not isCpActive and not isChopper
```

---

## 4. Modified: `scripts/ai/strategies/AIDriveStrategyUnloadCombine.lua`

This is the most significant set of changes. All modifications are backward-compatible with CP-driven combines — manual-only code is gated by `combineStrategy:isManualProxy()`.

### 4a. `setAIVehicle()` — Extended PPC grace period

```lua
if self.ppc then
    self.ppc.offTrackGracePeriodMs = 20000
end
```

Unloaders track moving targets (combine position changes, rendezvous shifts, post-turn realignment). The default 10-second off-track grace period is too short for this use case. Extended to 20 seconds to give the pathfinder and steering more time to recover before any shutdown is considered.

### 4b. `onOffTrackShutdown()` — New soft-recovery method

```lua
function AIDriveStrategyUnloadCombine:onOffTrackShutdown()
    self:info('Soft recovery to IDLE instead of stopping CP.')
    self:startWaitingForSomethingToDo()
    return true  -- handled; PPC must NOT call stopCurrentAIJob
end
```

Called by the PPC (see section 5) when the off-track grace period expires. Transitions the grain cart to `IDLE` and releases the combine. The proxy's `callUnloaderWhenNeeded()` re-summons within ~2.5 seconds. The user never has to walk over to the grain cart to restart it manually.

This is safe for both manual and CP-driven combines: CP combines call `unloader:call()` again when they need service; the proxy does the same via its update loop.

### 4c. `driveBesideCombine()` — Direct steering goal for manual combines

**The problem with course-based steering for manual combines:**  
`AIDriveStrategyUnloadCombine` normally steers by following a copy of the combine's fieldwork course offset to the pipe side. Manual combines have no fieldwork course — only a static placeholder is available. As the combine curves or S-bends, the grain cart drifts far from the stale placeholder, and the PPC cannot correct.

**The solution — live goal point from the pipe reference node:**

```lua
local isManual = strategy.isManualProxy and strategy:isManualProxy()
if dz > 5 or isManual then
    _, _, dz = localToLocal(self.vehicle:getAIDirectionNode(),
                            self:getPipeOffsetReferenceNode(), 0, 0, 0)
    local lookahead = isManual
            and (self.ppc.normalLookAheadDistance or 6)
            or self.ppc:getLookaheadDistance()
    gx, gy, gz = localToWorld(self:getPipeOffsetReferenceNode(),
            self:getPipeOffset(self.combineToUnload), 0, dz + lookahead)
end
```

For manual combines, a goal point is computed **every frame** regardless of `dz`. The goal is always `normalLookAheadDistance` meters ahead of the cart's current longitudinal position **in the combine's own local frame**, at the pipe's lateral offset. As the combine turns, `getPipeOffsetReferenceNode()` rotates with it — so the goal point rotates too, and the cart naturally follows curves.

**Why `normalLookAheadDistance` instead of `getLookaheadDistance()`:**  
`getLookaheadDistance()` inflates the lookahead up to 2× the base value when cross-track error is large (which it always is, since the cart is far from the stale placeholder course). A 12 m lookahead makes the cart too slow to respond to gentle heading changes. `normalLookAheadDistance` (≈5–6 m) is constant and un-inflated, enabling tight S-curve tracking.

**CP-driven combines:** zero behavior change. The `isManual` branch is not taken, and the existing `dz > 5` gate applies as before.

### 4d. `unloadMovingCombine()` — Off-track suppression during manual unloading

Because the placeholder course is intentionally stale (steering is derived from the live pipe reference node, not the course), the grain cart WILL drift far from the placeholder during curves. Without suppression, the PPC's off-track detection would fire. This is suppressed per-tick:

```lua
if combineStrategy and combineStrategy.isManualProxy and combineStrategy:isManualProxy() then
    if self.ppc and self.ppc.disableStopWhenOffTrack then
        self.ppc:disableStopWhenOffTrack(5000)
    end
end
```

The 5000 ms TTL (much longer than any realistic frame interval) ensures there is no gap between ticks where the check can briefly re-enable.

### 4e. `startCourseFollowingCombine()` — Placeholder course for manual combines

The PPC requires a course object to be initialised. For manual combines, a placeholder is built from the combine's current position in its current heading direction (100 m straight forward). This course is **never used for steering** — `driveBesideCombine()` returns the live goal point every frame, overriding the PPC's course-based calculation.

```lua
local combineX, _, combineZ = getWorldTranslation(self.combineToUnload:getAIDirectionNode())
local forwardX, _, forwardZ = localToWorld(self.combineToUnload:getAIDirectionNode(), 0, 0, 100)
local placeholder = Course.createFromTwoWorldPositions(
        self.vehicle, combineX, combineZ, forwardX, forwardZ,
        0, 0, 0, 10, false)
self.followCourse = placeholder
self.followCourse:setOffset(self.followingCourseOffset, 0)
startIx = 1
```

No periodic refresh of this course is needed or performed.

### 4f. `ignoreProximityObject()` — Terrain hits during approach and unloading

Windrows and straw swaths are height-map physics objects. The proximity sensor's raycasts hit them as `hitTerrain = true`, slowing the grain cart to a crawl mid-approach. Terrain hits are now ignored in the relevant states:

```lua
function AIDriveStrategyUnloadCombine:ignoreProximityObject(object, vehicle, moveForwards, hitTerrain)
    return (self.state == self.states.UNLOADING_ON_THE_FIELD and hitTerrain) or
            (self.state == self.states.DRIVING_TO_COMBINE and hitTerrain) or
            (self.state == self.states.UNLOADING_MOVING_COMBINE and hitTerrain) or
            (self.state == self.states.UNLOADING_MOVING_COMBINE and vehicle == self.combineToUnload) or
            (self.state == self.states.HANDLE_CHOPPER_HEADLAND_TURN and vehicle == self.combineToUnload)
end
```

### 4g. `calculateAutoAimPipeOffsetX()` — Nil guard for forage harvesters

`getFruitAtSides()` can return `nil` before `checkFruit()` has run (e.g., when a chopper just started). This caused a Lua arithmetic error on line 1022:

```lua
local fruitLeft, fruitRight = strategy:getFruitAtSides()
fruitLeft = fruitLeft or 0
fruitRight = fruitRight or 0
```

### 4h. `driveToCombine()` — Smarter approach redirect

The original approach redirect fired every 10 seconds unconditionally, causing the grain cart to swerve even on a stable straight approach. The redirect now only fires when the combine's pipe reference node has moved **>15 m** from the last redirect target:

```lua
local pipeMoved = MathUtil.vector2Length(cX - lastX, cZ - lastZ)
if combineAhead and angleToCombieDeg < 40 and pipeMoved > 15 then
    -- redirect
end
```

Redirect tracking (`lastApproachRedirectX/Z`, `lastApproachRedirectTime`) is reset after each successful pathfinding completion so the next approach starts fresh.

### 4i. Fill level exit condition — discharge check

```lua
if fillPct <= 0.1 and not isDischarging and not combineStrategy:alwaysNeedsUnloader() then
```

Previously, the `fillPct <= 0.1` check could fire at exactly 10% fill while the pipe was still open, causing a tarp-open/close cycle. The `not isDischarging` guard ensures the cart only leaves after the pipe has actually closed. (For manual combines this is moot since `getFillLevelPercentage()` always returns 1, but the fix is correct for all combines.)

---

## 5. Modified: `scripts/ai/PurePursuitController.lua`

### Soft-recovery hook before hard shutdown

Before calling `vehicle:stopCurrentAIJob(AIMessageCpError.new())`, the PPC now checks whether the current drive strategy implements `onOffTrackShutdown()`:

```lua
if (now - self.offTrackShutdownSince) >= offTrackGracePeriodMs then
    local strategy = self.vehicle.getCpDriveStrategy and self.vehicle:getCpDriveStrategy()
    if strategy and strategy.onOffTrackShutdown then
        local handled = strategy:onOffTrackShutdown()
        if handled then
            CpUtil.infoVehicle(self.vehicle,
                    'vehicle off track, strategy performed soft recovery instead of shutdown.')
            self.offTrackShutdownSince = nil
            break
        end
    end
    CpUtil.infoVehicle(self.vehicle, 'vehicle off track, shutting off Courseplay now.')
    self.vehicle:stopCurrentAIJob(AIMessageCpError.new())
    return
end
```

If the strategy returns `true` from `onOffTrackShutdown()`, the PPC resets its shutdown timer and continues running. This hook is intentionally generic — any strategy can implement it to provide graceful degradation instead of a hard stop.

---

## 6. Modified: `scripts/pathfinder/PathfinderUtil.lua`

### Defensive windrow filtering in `hasFruit()`

Added name-based checks to skip windrow, swath, straw and chaff fill types in the fruit detection loop:

```lua
local name = string.lower(fruitType.name or '')
if string.find(name, 'windrow') or string.find(name, 'swath')
        or name == 'straw' or name == 'chaff' then
    ignoreThis = true
end
```

**Note:** Windrows are height-map physics objects, not fruit density map objects, so `getFruitArea()` will not detect them regardless of this filter. The filter is defensive coding only and has no functional effect on current game versions. It is safe to remove if the maintainer prefers.

---

## 7. Modified: `config/VehicleSettingsSetup.xml`

### `callUnloaderPercent` minimum lowered to 20%

```xml
<!-- Before -->
<Setting ... name="callUnloaderPercent" min="60" max="90" ... />

<!-- After -->
<Setting ... name="callUnloaderPercent" min="20" max="90" ... />
```

The minimum threshold for "Call Unloader at" is reduced from 60% to 20%. High-yield crops (e.g., corn) fill combines faster; a lower call threshold lets CP-driven combines summon unloaders earlier, keeping combines harvesting continuously without stopping to wait for an unloader.

---

## Interaction with CP-Driven Combines

All changes are backward-compatible. The two-combine scenario (one manual + one CP-driven, served by one or two grain carts) works correctly:

- Manual-specific code is gated by `combineStrategy:isManualProxy()`.
- Shared changes (proximity terrain ignore, PPC soft-recovery hook, off-track grace period extension) benefit CP-driven unloaders as well.
- The `callUnloaderPercent` slider change applies to all combines regardless of control mode.

---

## Known Limitations / Future Work

- The grain cart can follow gentle curves and S-bends but will lose tracking on very sharp turns (>~60°). On such turns the soft-recovery mechanism kicks in and the cart re-approaches after a few seconds.
- Forage harvesters are explicitly unsupported (button hidden). Their auto-aim spout geometry would require a separate implementation similar to `unloadMovingChopper()`.
- The feature requires the grain cart to be running Courseplay as a Combine Unloader job. It does not integrate with AutoDrive or Giants helper unloaders.
