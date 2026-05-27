#include "MinimalRepro.h"
#include "Components/SceneComponent.h"

AMinimalRepro::AMinimalRepro()
{
	PrimaryActorTick.bCanEverTick = true;
	bReplicates = true;

	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void AMinimalRepro::BeginPlay()
{
	Super::BeginPlay();
	UE_LOG(LogTemp, Warning, TEXT("[%s] BeginPlay -- Role=%d"), *GetName(), (int32)GetLocalRole());
}

void AMinimalRepro::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	++TickCount;
	if (TickCount % 60 == 0)
	{
		UE_LOG(LogTemp, Warning, TEXT("[%s] Tick %d -- Role=%d"), *GetName(), TickCount, (int32)GetLocalRole());
	}
}
