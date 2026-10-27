# #136 focused combination fix round 3

### WI-1: Synchronize Inspector after direct grid search
- AC: With Inspector on D, filtering to A makes Inspector show A as soon as the projection is applied.
- AC: Filtering to nothing clears Inspector; clearing the filter restores the reconciled Current Item.
- AC: Direct search and watched refresh use the same post-reconcile Inspector hook.
- Tests: App combined window transition test; package RED on shared grid search reconciler.

### WI-2: Restore footer Tab loop and caret across Cmd-I
- AC: Forward Tab from grid visits each available shell control without expanding collapsed search, then Inspector close, then grid.
- AC: Shift-Tab traverses the exact reverse sequence.
- AC: Cmd-I from search restores the editor selection range and keeps query and focus.
- Tests: App combined window key cycle; package RED for first/last shell key-view targets.

## Deferred
- Signed device run, PR, rebase, and push are excluded by the brief.
