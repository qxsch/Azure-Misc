# Call Durable Functions from Azure Data Factory

Deploys a durable function and an Azure Data Factory pipeline that calls the durable function.

The DurabaleFuncCaller is a resuable pipeline that can be called from any other pipeline in the data factory.

## Setup

```pwsh
./setup.ps1 -location northeurope -resourceGroupName rg-adf-durable-functions
```

## Test

1. Go to the data factory and trigger the DurabaleFuncCaller pipeline (debug mode) 
1. Go to the data factory and trigger the TestPipe pipeline (debug mode) 