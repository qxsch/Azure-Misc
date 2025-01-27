param($Context)

$output = @()

Set-DurableCustomStatus -CustomStatus ('Running ' + $Context.Input)
$output += Invoke-DurableActivity -FunctionName 'HelloActivity' -Input $Context.Input

Set-DurableCustomStatus -CustomStatus 'Running Tokyo'
$output += Invoke-DurableActivity -FunctionName 'HelloActivity' -Input 'Tokyo'

Set-DurableCustomStatus -CustomStatus 'Running Seattle'
$output += Invoke-DurableActivity -FunctionName 'HelloActivity' -Input 'Seattle'

Set-DurableCustomStatus -CustomStatus 'Running London'
$output += Invoke-DurableActivity -FunctionName 'HelloActivity' -Input 'London'

Set-DurableCustomStatus -CustomStatus 'Done'

$output
