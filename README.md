# IrisLevelPlacedRepro

Minimal reproduction project for **UE-357736** — *Iris: BeginPlay not called on client for statically placed, low-priority replicated actor* — with an engine-source patch.

- Tracker: [issues.unrealengine.com/issue/UE-357736](https://issues.unrealengine.com/issue/UE-357736)
- Affects: Unreal Engine **5.7.x** (verified 5.7.4) and **5.8** (per the UE-357736 reporter)
- Replication system: **Iris** (legacy networking unaffected)
- Symptom: a deterministic subset of level-placed `bReplicates=true` actors never receive `BeginPlay` on clients; their tick functions are never registered

## Mechanism (engine-source walkthrough)

Within a single `FReplicationReader::DispatchStateData` flush cycle on the client:

1. `FReplicationReader::ReadObjectInBatch` invokes `UNetActorFactory::InstantiateReplicatedObjectFromHeader` for each object in the incoming batch. For a static (level-placed) actor, the path at `NetActorFactory.cpp:322` calls `Actor->SetActorIsPendingPostNetInit(true)`.
2. `FReplicationReader::DispatchStateData → FlushPostDispatchForBatch` Loop 1 (`ReplicationReader.cpp:2206-2216`) executes `CallLegacyPostApplyFunctions` per object — this is where OnReps fire. If `AGameStateBase` is in the same batch, its `OnRep_ReplicatedHasBegunPlay` (`GameStateBase.cpp:196-203`) calls `GetWorldSettings()->NotifyBeginPlay()`, which iterates `FActorIterator(World)` and invokes `DispatchBeginPlay` on every actor (`WorldSettings.cpp:353-369`). For the static actors in this batch, the early-return at `Actor.cpp:4693-4699` fires because `bActorIsPendingPostNetInit` is still set, and `BeginPlay` is skipped.
3. `FlushPostDispatchForBatch` Loop 2 (`ReplicationReader.cpp:2219-2243`) then runs `PostApplyInitialState → UNetActorFactory::PostInit`. The flag is unconditionally cleared at `NetActorFactory.cpp:468`. But the `IsDynamic()` gate at `NetActorFactory.cpp:471` prevents `Actor->PostNetInit()` from being invoked for static actors, so `AActor::PostNetInit`'s existing recovery code (`Actor.cpp:4638-4654`, which calls `DispatchBeginPlay` if `!HasActorBegunPlay() && World->HasBegunPlay()`) never runs.
4. Result: `bActorIsPendingPostNetInit` is cleared, but no second `DispatchBeginPlay` attempt is made for static actors. `BeginPlay` is permanently skipped. `RegisterAllActorTickFunctions` at `Actor.cpp:4759` lives inside `BeginPlay()`, so the actor never ticks client-side.

The bug is **Iris-only**: the early-return at `Actor.cpp:4695` is gated by `UE::Net::FReplicationSystemUtil::GetReplicationSystem(this)` returning non-null (Iris-specific); the flag is only ever set inside `NetActorFactory.cpp:322/347/424` (also Iris-specific). Legacy networking never reaches either codepath.

## What's in this project

- `Source/IrisLevelPlacedRepro/MinimalRepro.{h,cpp}` — `AMinimalRepro : public AActor` with `bReplicates=true`, default `NetPriority=1.0`, no replicated UPROPERTYs
- `Source/IrisLevelPlacedRepro/MinimalReproWithState.{h,cpp}` — same shape plus one `UPROPERTY(Replicated) float SomeFloat = 1.0f` and `GetLifetimeReplicatedProps`, no OnRep handler. Demonstrates the bug fires regardless of whether the actor has replicated state
- `Content/Maps/M_Repro.umap` — Basic level with 20 instances of each class + PlayerStart + NavMeshBoundsVolume
- `Config/DefaultEngine.ini` — enables Iris (`net.Iris.UseIrisReplication=1`) and the required `net.SubObjects.DefaultUseSubObjectReplicationList=1`
- `IrisLevelPlacedRepro.uproject` — enables the `Iris` plugin (required since it's `EnabledByDefault: false` in `Engine/Plugins/Experimental/Iris/Iris.uplugin`)
- `Patches/UE-357736-fix.patch` — unified diff for `Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp`
- `Patches/apply-patch.sh`, `Patches/revert-patch.sh` — convenience scripts (record SHA-256 of original, apply/restore with verification). Use `git apply` directly if working against a source-build engine clone.

## Reproducing the bug

Requires a source-build engine clone (or any engine setup where Iris actually runs). Installed-build engines from Epic Launcher work for *triggering* the bug but cannot test the patch.

1. Build the project module (right-click `.uproject` → Generate Visual Studio project files → Build via VS, or use Live Coding once initial build is done)
2. Open the project in UE 5.7
3. Load `Content/Maps/M_Repro`
4. Edit → Editor Preferences → Level Editor → Play: **Number of Players = 2**, **Net Mode = Play As Client**, leave **Run Under One Process** checked (or unchecked — bug reproduces in both)
5. Click Play
6. In the Output Log, filter by `Role=1` (client side). Count unique `[MinimalRepro_N]` and `[MinimalReproWithState_N]` instance names showing `BeginPlay`. Expected: 40 unique names. Observed (buggy): 30-32 unique names, with 8-10 silent per client. Silent subsets vary across PIE restarts and between clients within a run — characteristic load-order-dependent variability.

## Applying the patch

Against a source-build engine clone at `/path/to/UnrealEngine`:

```bash
cd /path/to/UnrealEngine
git apply /path/to/IrisLevelPlacedRepro/Patches/UE-357736-fix.patch
# Rebuild via Build.bat (or Visual Studio Build Solution):
./Engine/Build/BatchFiles/Build.bat UnrealEditor Win64 Development -WaitMutex
# Typically ~30-60 sec incremental — only NetActorFactory.cpp recompiles
# (UBT bundles it into Module.Engine.NN.cpp), then UnrealEditor-Engine.dll relinks.
```

To revert:

```bash
cd /path/to/UnrealEngine
patch -p1 -R < /path/to/IrisLevelPlacedRepro/Patches/UE-357736-fix.patch
./Engine/Build/BatchFiles/Build.bat UnrealEditor Win64 Development -WaitMutex
# (or `git checkout -- Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp` if you have a git clone)
# Engine returns to byte-identical pre-patch state.
```

## Validated results

Both `Patches/baseline-evidence.log` (3 unpatched PIE runs on installed UE 5.7.4) and `Patches/patched-evidence.log` (3 patched PIE runs on source-build UE 5.7.4-release with the patch applied + engine module recompiled) are scrubbed log excerpts included in this repo.

| Metric | Baseline (unpatched) | Patched | Result |
|---|---|---|---|
| Iris active | ✓ | ✓ | controlled |
| Server (Role=3) `BeginPlay` per run | 40 / 40 | 40 / 40 | unchanged ✓ |
| Total client (Role=1) `BeginPlay` lines per run (across 2 clients) | 63-64 | **80** | fixed |
| Distinct Role=1 instance names per run | **32 of 40** | **40 of 40** | fixed |
| Silent (no BeginPlay) actors per run | 8 | **0** | **fixed** |
| Run-to-run consistency | varies (load-order dependent) | identical across all 3 runs | fixed |

Three patched PIE runs all show 40/40 distinct `Role=1` instance names with zero variability — the race window is closed by construction.

### Observable signature of the recovery in the log

In the patched logs the 8 actors that would have been silent are visible as a clear **second wave** of `Role=1 BeginPlay` lines following the main `NotifyBeginPlay` wave:

```
LogTemp: Warning: [MinimalRepro_1] Tick 660 -- Role=1      ← Wave 1: ~32 actors
LogTemp: Warning: [MinimalRepro_2] Tick 660 -- Role=1        BeginPlay'd via the
...                                                          normal NotifyBeginPlay
LogTemp: Warning: [MinimalReproWithState_19] Tick 660 ...    path (their flag was
                                                             already cleared)
LogTemp: Warning: [MinimalRepro_3] Tick 660 -- Role=1      ← Wave 2: ~8 actors
LogTemp: Warning: [MinimalReproWithState_13] Tick 660 ...    recovered via the
LogTemp: Warning: [MinimalReproWithState_8] Tick 660 ...     patch's new branch
...                                                          in PostInit
```

Mapping to engine source:

```
FlushPostDispatchForBatch (ReplicationReader.cpp:2188-2245):
  Loop 1 (line 2206-2216, CallLegacyPostApplyFunctions):
    GameState's OnRep_ReplicatedHasBegunPlay fires →
      NotifyBeginPlay → FActorIterator → DispatchBeginPlay on every actor
      • 32 actors (flag was already false): BeginPlay runs           ← Wave 1
      • 8 actors (flag still true from line 322): early-return       ← would have been silent

  Loop 2 (line 2219-2243, PostApplyInitialState → UNetActorFactory::PostInit):
    flag cleared at line 468
    PATCH'S NEW BRANCH fires for the 8 still-not-begun-play actors:
      DispatchBeginPlay(bFromLevelStreaming=true) → BeginPlay runs   ← Wave 2
```

Recovery happens in the same `FlushPostDispatchForBatch` cycle as the original race, so the recovered actors begin ticking from the same frame onward — same `Tick` counter values, indistinguishable from a clean BeginPlay from the user's perspective.

## Fix design notes

The patch adds an `else if (!Actor->HasActorBegunPlay())` branch to `UNetActorFactory::PostInit` that mirrors `AActor::PostNetInit`'s existing recovery pattern (`Actor.cpp:4638-4654`) — re-invoking `DispatchBeginPlay` if BeginPlay was skipped. Choices:

- **Inline the recovery rather than calling `Actor->PostNetInit()`** for static actors: avoids triggering `ALevelInstance::PostNetInit`'s `ensure(!LevelInstanceActorGuid.IsValid())` (`LevelInstanceActor.cpp:72-82`), which would fire for level-placed `ALevelInstance` actors whose GUID is already valid from disk
- **`bFromLevelStreaming = true`** explicitly, matching `AWorldSettings::NotifyBeginPlay`'s `DispatchBeginPlay(bFromLevelLoad=true)` call (`WorldSettings.cpp:353-369`). User code that branches on `IsActorBeginningPlayFromLevelStreaming()` observes the same context as the non-buggy path. `AActor::PostNetInit`'s default of `false` is genuinely correct for dynamic actors but wrong-semantic for static actors
- **`SCOPE_CYCLE_COUNTER(STAT_ActorBeginPlay)`** wraps the dispatch, matching the other `DispatchBeginPlay` callsites (`Actor.cpp:4501`, `Actor.cpp:4650`, `Level.cpp:3886`, `WorldSettings.cpp:362`). Stat declared in `Engine/Public/EngineStats.h:44`; patch adds the corresponding include

Total diff: 1 include + ~22 line addition in `PostInit`. Smallest change that fixes UE-357736 without regressing existing dynamic-actor or `ALevelInstance` behavior.

## License

Project files (`Source/`, `Content/`, `Config/`, `*.uproject`) are MIT-licensed. The patch in `Patches/UE-357736-fix.patch` modifies Unreal Engine source code and is subject to the Unreal Engine End User License Agreement.
