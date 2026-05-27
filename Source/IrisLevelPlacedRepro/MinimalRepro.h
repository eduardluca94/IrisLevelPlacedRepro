#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MinimalRepro.generated.h"

UCLASS()
class IRISLEVELPLACEDREPRO_API AMinimalRepro : public AActor
{
	GENERATED_BODY()

public:
	AMinimalRepro();

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

private:
	int32 TickCount = 0;
};
