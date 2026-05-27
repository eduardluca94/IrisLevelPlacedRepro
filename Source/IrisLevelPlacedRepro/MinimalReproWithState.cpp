#include "MinimalReproWithState.h"
#include "Components/SceneComponent.h"
#include "Net/UnrealNetwork.h"

AMinimalReproWithState::AMinimalReproWithState()
{
	PrimaryActorTick.bCanEverTick = true;
	bReplicates = true;

	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void AMinimalReproWithState::BeginPlay()
{
	Super::BeginPlay();
	UE_LOG(LogTemp, Warning, TEXT("[%s] BeginPlay -- Role=%d SomeFloat=%f"), *GetName(), (int32)GetLocalRole(), SomeFloat);
}

void AMinimalReproWithState::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	++TickCount;
	if (TickCount % 60 == 0)
	{
		UE_LOG(LogTemp, Warning, TEXT("[%s] Tick %d -- Role=%d SomeFloat=%f"), *GetName(), TickCount, (int32)GetLocalRole(), SomeFloat);
	}
}

void AMinimalReproWithState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMinimalReproWithState, SomeFloat);
}
