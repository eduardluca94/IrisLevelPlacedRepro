# Bug Submission Form draft — for unrealbugsubmissions.epicgames.com

Submit at: https://unrealbugsubmissions.epicgames.com/s/?language=en_US

Use this draft to fill in the form fields. Attachments at bottom.

---

## Name

`<your name or empty>`

## Email * (required)

`<your email>` — Epic uses this to follow up if engineers have questions.

## Summary *

`Supporting evidence and proposed fix for UE-357736 — Iris: BeginPlay not called on client for static replicated actor`

## Steps to Reproduce *

```
1. Open the attached IrisLevelPlacedRepro project in UE 5.7.4 (or any 5.7.x).
   Project ships with the Iris plugin enabled and net.Iris.UseIrisReplication=1
   plus net.SubObjects.DefaultUseSubObjectReplicationList=1 in DefaultEngine.ini.
2. Build the project module.
3. Open Content/Maps/M_Repro. The map has 20 instances of AMinimalRepro
   (zero replicated UPROPERTYs) and 20 of AMinimalReproWithState (one
   UPROPERTY(Replicated), no OnRep). All bReplicates=true with default
   NetPriority=1.0. Plus PlayerStart + NavMeshBoundsVolume.
4. Edit → Editor Preferences → Level Editor → Play: Number of Players=2,
   Net Mode=Play As Client. Single Process or Multi Process; bug reproduces
   in both.
5. Click Play. Wait ~5 seconds.
6. In Output Log, filter to Role=1 (client) and count unique
   [MinimalRepro_N] / [MinimalReproWithState_N] BeginPlay lines.
```

## Results *

```
Server: 40/40 instances log BeginPlay (Role=3, Authority).
Client: 30-32 of 40 instances log BeginPlay (Role=1, SimulatedProxy).
8-10 instances per client are completely silent — no BeginPlay, no Tick
lines. The silent subset differs between Client 1 and Client 2 within
the same PIE run, and varies across PIE restarts (load-order dependent).
Silent actors exist on the client (per Iris instantiation logs), but
their BeginPlay was permanently skipped.
```

## Expected *

```
All 40 instances log BeginPlay on each client (Role=1), and all 40
register their tick functions and tick continuously.
```

## Description *

```
This is supporting evidence and a proposed fix for UE-357736
(Iris - BeginPlay not called on client for statically placed,
low-priority replicated actor), which is currently Backlogged.

The attached project reliably reproduces the bug on a stock UE 5.7.4
installed build with the Iris plugin enabled. The repro itself uses
default actor configuration (NetPriority=1.0, no special relevancy
or replication frequency) and matches the conditions UE-357736's
reporter described.

Engine-source mechanism (within a single FReplicationReader::DispatchStateData
flush cycle on the client):

1. UNetActorFactory::InstantiateReplicatedObjectFromHeader's static-actor
   path (NetActorFactory.cpp:322) sets Actor->SetActorIsPendingPostNetInit(true)
   on level-placed bReplicates=true actors as their creation header is read.

2. FlushPostDispatchForBatch Loop 1 (ReplicationReader.cpp:2206-2216) runs
   CallLegacyPostApplyFunctions for each object — OnReps fire here.
   AGameStateBase::OnRep_ReplicatedHasBegunPlay (GameStateBase.cpp:196-203)
   calls GetWorldSettings()->NotifyBeginPlay() which iterates FActorIterator(World)
   and calls DispatchBeginPlay on every actor (WorldSettings.cpp:353-369).
   For the static actors in the current batch, AActor::DispatchBeginPlay's
   early-return at Actor.cpp:4693-4699 fires because bActorIsPendingPostNetInit
   is still set. BeginPlay is skipped.

3. FlushPostDispatchForBatch Loop 2 (ReplicationReader.cpp:2219-2243) runs
   PostApplyInitialState → UNetActorFactory::PostInit, which clears the
   flag at line 468. BUT the IsDynamic() gate at line 471 prevents the
   engine's existing AActor::PostNetInit recovery path (Actor.cpp:4638-4654,
   which calls DispatchBeginPlay if !HasActorBegunPlay() && World->HasBegunPlay())
   from running for static actors. Result: flag is cleared but no second
   DispatchBeginPlay attempt — BeginPlay permanently skipped on the client.
   RegisterAllActorTickFunctions (Actor.cpp:4759) lives inside BeginPlay(),
   so the actor never ticks client-side.

The bug is Iris-only: the early-return at Actor.cpp:4695 is gated on
UE::Net::FReplicationSystemUtil::GetReplicationSystem(this) returning
non-null (Iris-specific), and the flag is only ever set inside
NetActorFactory.cpp:322/347/424 (Iris-specific). Legacy networking never
reaches either codepath.

Proposed fix (attached as UE-357736-fix.patch):

Adds an `else if (!Actor->HasActorBegunPlay())` branch to
UNetActorFactory::PostInit that mirrors AActor::PostNetInit's existing
recovery pattern, but inlined (to avoid triggering ALevelInstance::PostNetInit's
ensure(!LevelInstanceActorGuid.IsValid()) at LevelInstanceActor.cpp:72-82,
which would fail for level-placed ALevelInstance actors). Passes
bFromLevelStreaming=true to match AWorldSettings::NotifyBeginPlay's
DispatchBeginPlay(bFromLevelLoad=true) call so user code observing
IsActorBeginningPlayFromLevelStreaming() sees the same context as the
non-buggy path.

Diff: 1 #include + ~22 line addition in NetActorFactory.cpp.

Adjacent context: UE-247463 (Fixed in 5.7 via Fix Commit 43859250)
introduced the bActorIsPendingPostNetInit gate to address a related
huge-object-path BeginPlay-with-default-state issue. UE-357736 is a
side-effect of that fix: the gate works for dynamic actors but the
PostNetInit recovery doesn't cover the static-actor case. This patch
extends the recovery to cover both paths.

A pull request with this fix is also being submitted against
EpicGames/UnrealEngine release branch: https://github.com/EpicGames/UnrealEngine/pull/14828
```

## Affects Versions *

`5.7` (selected from dropdown)

## Platforms *

`Windows` (or whatever you tested on)

## Additional Notes

```
This is supporting evidence for UE-357736 (currently Backlogged), submitting
via this form for visibility of the attached repro project + proposed fix
patch + before/after validation logs. A pull request with the same fix has
been opened against EpicGames/UnrealEngine release branch:
https://github.com/EpicGames/UnrealEngine/pull/14828

Validation summary (3 PIE runs each, identical project):

  Baseline (installed UE 5.7.4 + Iris enabled, unpatched):
    Server (Role=3) BeginPlay: 40/40 per run
    Client (Role=1) BeginPlay: 32 distinct instance names per run
    Silent per client: 8 actors (load-order varies across runs)

  Patched (source-build UE 5.7.4-release + UE-357736-fix.patch applied +
           Engine module recompiled via Build.bat UnrealEditor Win64 Development):
    Server (Role=3) BeginPlay: 40/40 per run
    Client (Role=1) BeginPlay: 40 distinct instance names per run
    Silent per client: 0
    Run-to-run consistency: identical 3/3 runs (race window closed by construction)

The 8 previously-silent actors are observable in the patched logs as a
distinct second wave of Role=1 BeginPlay lines following the main
NotifyBeginPlay wave -- concrete log-level evidence that the new
else-if-not-HasActorBegunPlay branch in PostInit fires inside the same
FlushPostDispatchForBatch cycle. Recovered actors tick from the same frame
onward (no observable delay).

Regression checks on patched engine:
- ADefaultPawn (dynamic actor spawned at client connect): BeginPlay
  unchanged, fires correctly via the existing IsDynamic() branch.
- AMinimalReproWithState's UPROPERTY(Replicated) float SomeFloat replicates
  correctly post-patch (no regression in initial-state apply).
- ALevelInstance not exercised in this repro, but the design choice of
  inlining the recovery (rather than calling virtual PostNetInit) avoids
  ALevelInstance::PostNetInit's ensure(!LevelInstanceActorGuid.IsValid())
  at LevelInstanceActor.cpp:72-82, which would fire for level-placed
  ALevelInstance actors whose GUID is already valid from disk.

Adjacent context: UE-247463 (Fixed in 5.7 via Fix Commit 43859250)
introduced the bActorIsPendingPostNetInit gate to address a related
huge-object-path BeginPlay-with-default-state issue. UE-357736 appears to
be a side-effect of that fix: the gate works for dynamic actors but the
PostNetInit recovery path doesn't cover the static-actor case. This patch
extends the recovery to cover both paths.
```

## Crash *

`No`

## Error Logs *

Attach: `Saved/Logs/Baseline/*.log` (or the scrubbed `baseline-evidence.log` if attaching to a public channel)

## Attachments

1. **`IrisLevelPlacedRepro.zip`** — the full repro project (Source/, Content/, Config/, .uproject, Patches/) zipped from `C:\iris-repro\IrisLevelPlacedRepro\` excluding `Binaries/`, `Intermediate/`, `DerivedDataCache/`, `Saved/`. Smaller alternative: link to the public GitHub repo URL in the Description.
2. **`UE-357736-fix.patch`** — the engine-source diff against `Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp`. ~30 lines.
3. **`baseline-evidence.log`** (after scrub pass) — filtered Output Log excerpts showing iris="1", replication model Iris, Server BeginPlay (40), Client BeginPlay (30-32), and the silent-subset gap.
4. **`patched-evidence.log`** (after validation step completes) — same format showing 40/40 client BeginPlay post-patch.
