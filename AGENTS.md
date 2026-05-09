# Courseplay Agent Guidelines

## Code Style

- **Always use getters to access member variables.** Do not read fields like `self.ppc.normalLookAheadDistance` directly from outside the owning class; call the appropriate getter instead (e.g. `self.ppc:getNormalLookaheadDistance()`). Add a getter to the class if one does not already exist.
