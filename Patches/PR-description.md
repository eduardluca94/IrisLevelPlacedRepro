# PR draft — for opening against EpicGames/UnrealEngine

## Suggested title

`Iris: dispatch BeginPlay for static actors after PostInit clears bActorIsPendingPostNetInit (UE-357736)`

(Branch name suggestion: `fix/ue-357736-iris-static-actor-beginplay`)

## Suggested description (Markdown — paste into GitHub PR body)

---

Fixes [UE-357736](https://issues.unrealengine.com/issue/UE-357736) — *Iris: BeginPlay not called on client for statically placed, low-priority replicated actor*.

### Mechanism

On the client, in a single `FReplicationReader::DispatchStateData` flush cycle:

1. `UNetActorFactory::InstantiateReplicatedObjectFromHeader`'s static-actor path sets `bActorIsPendingPostNetInit=true` on level-placed actors (`NetActorFactory.cpp:322`).
2. `FlushPostDispatchForBatch` Loop 1 fires OnReps. `AGameStateBase::OnRep_ReplicatedHasBegunPlay` → `AWorldSettings::NotifyBeginPlay` → `FActorIterator` → `AActor::DispatchBeginPlay` early-returns for level-placed actors (`Actor.cpp:4693-4699`) because the flag is still set.
3. `FlushPostDispatchForBatch` Loop 2 invokes `UNetActorFactory::PostInit`, which clears the flag at line 468 — but the `IsDynamic()` gate at line 471 prevents `AActor::PostNetInit`'s recovery code (`Actor.cpp:4638-4654`, which would re-attempt `DispatchBeginPlay`) from running for static actors.

Result: `BeginPlay` is permanently skipped on the client. `RegisterAllActorTickFunctions` (`Actor.cpp:4759`) never runs, so the actor doesn't tick client-side.

The bug is Iris-only: the early-return at `Actor.cpp:4695` is gated on `UE::Net::FReplicationSystemUtil::GetReplicationSystem(this)`, and the flag is only set inside `NetActorFactory.cpp` (Iris-specific).

### Fix

Adds an `else if (!Actor->HasActorBegunPlay())` branch to `UNetActorFactory::PostInit` (inside the existing `if (Actor)` block, after the flag-clear and the `IsDynamic` branch). Mirrors `AActor::PostNetInit`'s existing recovery pattern:

```cpp
else if (!Actor->HasActorBegunPlay())
{
    const UWorld* MyWorld = Actor->GetWorld();
    if (MyWorld && MyWorld->HasBegunPlay())
    {
        SCOPE_CYCLE_COUNTER(STAT_ActorBeginPlay);
        constexpr bool bFromLevelStreaming = true;
        Actor->DispatchBeginPlay(bFromLevelStreaming);
    }
}
```

### Design choices

- **Inlined the recovery** rather than calling `Actor->PostNetInit()` for static actors. The virtual `PostNetInit` would also fire `ALevelInstance::PostNetInit`'s `ensure(!LevelInstanceActorGuid.IsValid())` (`LevelInstanceActor.cpp:72-82`), which would fail for level-placed `ALevelInstance` actors whose GUID is already valid from disk.
- **`bFromLevelStreaming=true`** matches `AWorldSettings::NotifyBeginPlay`'s call (`WorldSettings.cpp:362-364` passes `bFromLevelLoad=true` into the `bFromLevelStreaming` parameter). User code observing `IsActorBeginningPlayFromLevelStreaming()` sees the same context as the non-buggy path. `AActor::PostNetInit`'s default of `false` is correct for dynamic actors but the wrong semantic for static actors.
- **`SCOPE_CYCLE_COUNTER(STAT_ActorBeginPlay)`** matches the other `DispatchBeginPlay` callsites (`Actor.cpp:4501,4650`, `Level.cpp:3886`, `WorldSettings.cpp:362`). Stat declared in `Engine/Public/EngineStats.h:44`; the PR adds the include.
- **Guards against re-dispatch** via the `!HasActorBegunPlay()` check at the branch entry plus `AActor::DispatchBeginPlay`'s own `!HasActorBegunPlay() && IsValidChecked(this)` guard at `Actor.cpp:4700`. Safe no-op when `BeginPlay` already ran.

### Files changed

- `Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp` (+24, -0)

### Testing

Reference minimal repro at https://github.com/eduardluca94/IrisLevelPlacedRepro. 20 instances each of `AMinimalRepro` and `AMinimalReproWithState` placed in a Basic map, default `NetPriority=1.0`, 2-client Dedicated Server PIE.

| | Baseline | Patched |
|---|---|---|
| Server (Role=3) `BeginPlay` per run | 40 / 40 | 40 / 40 |
| Total client (Role=1) `BeginPlay` lines (across 2 clients) | 63-64 | **80** |
| Distinct Role=1 instance names per run | 32 of 40 | **40 of 40** |
| Silent (no BeginPlay) actors per client per run | 8 | **0** |
| Run-to-run consistency | varies (load-order dependent) | identical, 3/3 runs |

Both baseline (unpatched UE 5.7.4, 3 PIE runs) and patched (source-build UE 5.7.4-release + this PR applied + Engine module recompiled, 3 PIE runs) evidence files included with the linked repro project (`Patches/baseline-evidence.log` and `Patches/patched-evidence.log`).

In the patched logs the 8 previously-silent actors are observable as a distinct **second wave** of Role=1 `BeginPlay` lines following the main `NotifyBeginPlay` wave — concrete log-level evidence that the new `else if (!Actor->HasActorBegunPlay())` branch in `PostInit` is firing for the actors that would have been silent without it. Recovery happens in the same `FlushPostDispatchForBatch` cycle, so recovered actors tick from the same frame onward (no observable client-side delay).

Regression tests in the same PIE session:
- Dynamic actor `BeginPlay` (`ADefaultPawn` spawned at client connect): unchanged — fires correctly via the unchanged `IsDynamic()` branch.
- `AMinimalReproWithState`'s `UPROPERTY(Replicated) float SomeFloat` replicates correctly to clients post-patch (no regression in initial-state apply for actors with replicated UPROPERTYs).
- `ALevelInstance`-derived actors not exercised in this repro, but the design choice of inlining the recovery (rather than calling the virtual `Actor->PostNetInit()`) intentionally avoids `ALevelInstance::PostNetInit`'s `ensure(!LevelInstanceActorGuid.IsValid())` (`LevelInstanceActor.cpp:72-82`), which would fail for level-placed `ALevelInstance` actors whose GUID is already valid from disk.

### Related

- Reporter-described bug at [UE-357736](https://issues.unrealengine.com/issue/UE-357736); Backlogged as of submission.
- Adjacent prior fix: [UE-247463](https://issues.unrealengine.com/issue/UE-247463) (*incorrect initial state in pawn's BeginPlay if replicated via huge object path*), Fixed in 5.7 via Fix Commit 43859250. UE-247463 introduced the `bActorIsPendingPostNetInit` gate; this PR extends the recovery path to cover the static-actor case that UE-247463's fix didn't address.

---
