param(
    [string]$Namespace = "canary-playground",
    [string]$Label = "app=service-a"
)

$pod = kubectl -n $Namespace get pods -l $Label -o jsonpath='{.items[0].metadata.name}'
if (-not $pod) {
    Write-Error "No pods found matching label $Label in namespace $Namespace"
    exit 1
}

Write-Host "Deleting pod $pod to simulate disruption..."
kubectl -n $Namespace delete pod $pod --grace-period=0 --force
