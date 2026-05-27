#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MinimalReproWithState.generated.h"

UCLASS()
class IRISLEVELPLACEDREPRO_API AMinimalReproWithState : public AActor
{
	GENERATED_BODY()

public:
	AMinimalReproWithState();

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

private:
	UPROPERTY(Replicated)
	float SomeFloat = 1.0f;

	int32 TickCount = 0;
};
