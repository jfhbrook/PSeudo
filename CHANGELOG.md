* PSeudo Version 2.0.0
  - Code now autoformatted with PowerShell-Beautifier
  - Renamed Invoke-AsAdmin to Invoke-AsAdministrator
  - Script blocks are now passed to Invoke-AsAdministrator with the -ScriptBlock parameter and are distinguished from the string-formatted -Command parameter via the ScriptBlock and StringCommand parameter sets
  - Arguments are now passed to script blocks with the -ArgumentList parameter, which is included in the ScriptBlock parameter set
  - The exe used to call PowerShell can be overridden with the -FilePath flag
  - The verb used to call PowerShell can be overridden with the -Verb flag
  - The secondary captured stream can be configured with the -CapturedStream flag
  - Non-Serializable objects are converted to simplified PSObjects before serialization
  - Write-Output, Write-Error, Write-Debug, Write-Verbose, Write-Warning, Write-Information, Write-Host and Write-Process are captured and proxied to the appropriate cmdlet on the host by shadowing them on the Administrator process with aliases
  - Terminating errors are proxied to the host as terminating errors
  - Code passed to the Administrator process is validated as parseable beforehand
  - Documentation has been rewritten and expanded


* PSeudo Version 1.0.2
  - Initial import of inherited code
  - Addition of tests, linting and publishing tasks