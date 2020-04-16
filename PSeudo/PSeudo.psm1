# Licensed to Josh Holbrook under one or more contributor
# license agreements.  See the NOTICE file distributed
# with this work for additional information regarding
# copyright ownership.  Josh Holbrook licenses this file to
# you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

$ClientConnectionCode = "
  `$NamedPipeClient = New-Object System.IO.Pipes.NamedPipeClientStream '.', '{0}', 'Out'
  `$NamedPipeClient.Connect()
  `$NamedPipeWriter = New-Object System.IO.StreamWriter `$NamedPipeClient
  `$NamedPipeWriter.AutoFlush = `$True
"

$ConvertToSerializableCode = "
  function ConvertTo-Serializable {
    param(
      [object]`$Object
    )

    `$ErrorActionPreference = 'Stop'

    `$Compatible = @{}

    # PowerShell is extremely bad at things that depend on dynamic typing
    # and/or pattern matching of arbitrary types, so our options are
    # limited in terms of how we can approach serializing arbitrary
    # objects. In other words, this is a little cheesed.

    # First, we try to lean on the JSON serializer. Going back and forth is
    # pretty inefficient, but it also meets our requirements for easy cases.
    # It can make pretty big objects, unfortunately, but I don't have a great
    # answer for that.
    try {
      `$Compatible = (`$Object | ConvertTo-Json | ConvertFrom-Json)
    } catch {
      Write-Host $_
      # There are many objects which won't serialize to JSON. For these, we
      # try to generate one level of keys on a hashtable, and naively
      # stringifying the values.
      try {
        `$Compatible = @{}

        @('Property', 'NoteProperty') | ForEach-Object {
          `$Object | Get-Member -MemberType `$_ | ForEach-Object {
            `$Compatible[`$_.Name] = [string]`$Object[`$_Name]
          }
        }
      } catch {
        # If the above crashes for some reason, we should still be able to
        # naively stringify the whole object
        try {
          `$Compatible = [string]`$Object
        } catch {
          # If we get this far the object is *extremely* cursed
          `$Compatible = '<Unserializable>'
        }
      }
    }

    return `$Compatible
  }
"

$SendMessageCode = "
  function Send-Message {
    param(
      [ValidateSet(
        'Debug','Error', 'Host', 'Information', 'Output', 'Progress',
        'TerminatingError', 'Verbose', 'Warning'
      )]
      [MessageType]`$Type,

      # Debug, Verbose and Warning params
      [string]`$Message,

      # Write-Error params
      [Exception]`$Exception,
      [System.Management.Automation.ErrorRecord]`$ErrorRecord,
      [System.Management.Automation.ErrorCategory]`$Category,
      [string]`$ErrorId,
      [string]`$TargetObject,
      [string]`$RecommendedAction,
      [string]`$CategoryActivity,
      [string]`$CategoryReason,
      [string]`$CategoryTargetName,
      [string]`$CategoryTargetType,

      # Write-Host params
      [Object]`$Object,
      [boolean]`$NoNewLine,
      [Object]`$Separator,
      [ConsoleColor]`$ForegroundColor,
      [ConsoleColor]`$BackgroundColor,

      # Write-Information params
      [Object]`$MessageData,
      [String[]]`$Tags,

      # Write-Output params
      [PSObject[]]`$InputObject,
      [boolean]`$NoEnumerate,

      # Write-Progress params
      [string]`$Activity,
      [string]`$Status,
      [int32]`$Id,
      [int32]`$PercentComplete,
      [int32]`$SecondsRemaining,
      [string]`$CurrentOperation,
      [boolean]`$Completed,
      [int32]`$SourceId
    )

    if ($Exception) {
      $SerializedException = @{Message = `$Exception.Message}
    }

    if ($ErrorRecord) {
      $SerializedErrorRecord = @{
          CategoryInfo = @{
            Category = [string]`$ErrorRecord.CategoryInfo.Category
            Activity = `$ErrorRecord.CategoryInfo.Activity
            Reason = `$ErrorRecord.CategoryInfo.Reason
            TargetName = `$ErrorRecord.CategoryInfo.TargetName
            TargetType = `$ErrorRecord.CategoryInfo.TargetType
          }
          Exception = @{Message = `$ErrorRecord.Exception.Message}
          FullyQualifiedErrorId = `$ErrorRecord.FullyQualifiedErrorId
          TargetObject = (ConvertTo-Serializable `$ErrorRecord.TargetObject)
        }
    }

    $Payload = (@{
      Type = [int]`$Type,
      Message = [string]`$Message,
      Exception = $SerializedException,
      ErrorRecord = $SerializedErrorRecord,
      ErrorCategory = [string]`$ErrorCategory,
      ErrorId = `$ErrorId,
      TargetObject = `$TargetObject,
      RecommendedAction = `$RecommendedAction,
      CategoryActivity = `$CategoryActivity,
      CategoryReason = `$CategoryReason,
      CategoryTargetType = `$CategoryTargetType,
      Object = (ConvertTo-Serializable `$Object),
      NoNewLine = `$NoNewLine,
      Separator = `$Separator,
      ForegroundColor = [string]`$ForegroundColor,
      BackgroundColor = [string]`$BackgroundColor,
      MessageData = (ConvertTo-Serializable `$MessageData),
      Tags = `$Tags,
      InputObject = (ConvertTo-Serializable `$InputObject),
      NoEnumerate = `$NoEnumerate,
      Activity = `$Activity,
      Status = `$Status,
      Id = `$Id,
      PercentComplete = `$PercentComplete,
      SecondsRemaining = `$SecondsRemaining,
      CurrentOperation = `$CurrentOperation,
      Completed = `$Completed,
      SourceId = `$SourceId
    } | ConvertTo-Json -Compress)

    `$NamedPipeWriter.WriteLine(`$Payload)
  }
"

function Receive-Message {
  param(
    [string]$Line
  )

  $Payload = ($Line | ConvertFrom-Json)

  switch ($Payload.Type) {
    'Debug' { Write-Debug $Payload.Message }
    'Error' { Receive-Error $Payload }
    'Host' {
      Write-Host `
         -Object $Payload.Object `
         -NoNewline $Payload.NoNewLine `
         -Separator $Payload.Separator `
         -ForegroundColor $Payload.ForegroundColor `
         -BackgroundColor $Payload.BackgroundColor
    }
    'Information' {
      Write-Information -MessageData $Payload.MessageData -Tags $Payload.Tags
    }
    'Output' {
      Write-Output -InputObject $Payload.InputObject -NoEnumerate $Payload.NoEnumerate
    }
    'Progress' {
      Write-Progress `
         -Activity $Payload.Activity `
         -Status $Payload.Status `
         -Id $Payload.Id `
         -PercentComplete $Payload.PercentComplete `
         -SecondsRemaining $Payload.SecondsRemaining `
         -CurrentOperation $Payload.CurrentOperation `
         -Completed $Payload.Completed `
         -SourceId $Payload.SourceId

    }
    'TerminatingError' { Receive-TerminatingError $Payload }
    'Verbose' { Write-Verbose $Payload.Message }
    'Warning' { Write-Warning $Payload.Message }
    default { Write-Warning "Unexpected message from Administrator process: $Line" }
  }
}

$SendLoggingCode = "
  function Send-Debug {
    [CmdletBinding]
    param(

      [Parameter(Position=0)]
      [string]`$Message
    )

    Send-Payload -Type Debug -Message `$Message
  }

  function Send-Verbose {
    [CmdletBinding]
    param(
      [Parameter(Position=0)]
      [string]`$Message
    )

    Send-Payload -Type Verbose -Message `$Message
  }

  function Send-Warning {
    [CmdletBinding]
    param(
      [Parameter(Position=0)]
      [string]`$Message
    )

    Send-Payload -Type Warning -Message `$Message
  }
"

$SendErrorCode = "
  function Send-Error {
    [CmdletBinding()]
    param(
      [Parameter(ParameterSetName='Exception')]
      [Exception]`$Exception,

      [Parameter(ParameterSetName='ErrorRecord')]
      [System.Management.Automation.ErrorRecord]`$ErrorRecord,

      [string]`$Message,
      [System.Management.Automation.ErrorCategory]`$Category,
      [string]`$ErrorId,
      [Object]`$TargetObject,
      [string]`$RecommendedAction,
      [string]`$CategoryActivity,
      [string]`$CategoryReason,
      [string]`$CategoryTargetName,
      [string]`$CategoryTargetType
    )

    Send-Payload ``
      -Type Error ``
      -Message `$Message ``
      -Exception `$Exception ``
      -ErrorRecord `$ErrorRecord ``
      -Category `$Category ``
      -ErrorId `$ErrorId ``
      -TargetObject `$TargetObject ``
      -RecommendedAction `$RecommendedAction ``
      -CategoryActivity `$CategoryActivity ``
      -CategoryReason `$CategoryReason ``
      -CategoryTargetName `$CategoryTargetName ``
      -CategoryTargetType `$CategoryTargetType
  }
"

function Receive-Error {
  param(
    [psobject]$Payload
  )

  $Message = $Payload.Message
  $ErrorId = $Payload.ErrorId

  try {
    $Category = [System.Management.Automation.ErrorCategory]$Payload.Category
  } catch {
    $Category = [System.Management.Automation.ErrorCategory]'NotSpecified'
  }

  $CategoryActivity = $Payload.CategoryActivity
  $CategoryReason = $Payload.CategoryReason
  $CategoryTargetName = $Payload.CategoryTargetName
  $CategoryTargetType = $Payload.CategoryTargetType

  $TargetObject = $Payload.TargetObject

  if ($Payload.ErrorRecord) {
    $Exception = New-Object Exception $Payload.ErrorRecord.Exception.Message
    $ErrorId = $Payload.ErrorRecord.FullyQualifiedErrorId
    $TargetObject = $Payload.ErrorRecord.TargetObject

    try {
      $Category = [System.Management.Automation.ErrorCategory]$Payload.ErrorRecord.CategoryInfo.Category
    } catch {
      $Category = [System.Management.Automation.ErrorCategory]'NotSpecified'
    }

    if (-not $CategoryActivity) {
      $CategoryActivity = $Payload.ErrorRecord.CategoryInfo.Activity
    }

    if (-not $CategoryReason) {
      $CategoryReason = $Payload.ErrorRecord.CategoryInfo.Reason
    }

    if (-not $CategoryTargetName) {
      $CategoryTargetName = $Payload.ErrorRecord.CategoryInfo.TargetName
    }

    if (-not $CategoryTargetType) {
      $CategoryTargetType = $Payload.ErrorRecord.CategoryInfo.TargetType
    }

    $ErrorRecord = New-Object System.Management.Automation.ErrorRecord $Exception,$ErrorId,$Category,$TargetObject
  } else {
    if (-not $ErrorID) {
      $ErrorId = 'PSeudoReceivedError'
    }

    if ($Payload.Exception) {
      $Exception = New-Object Exception $Payload.Exception.Message
      $ErrorRecord = New-Object System.Management.Automation.ErrorRecord $Exception,$ErrorId,$Category,$TargetObject
    }
  }

  if ($ErrorRecord) {
    Write-Error `
       -ErrorRecord $ErrorRecord `
       -RecommendedAction $Payload.RecommendedAction `
       -CategoryActivity $Payload.CategoryActivity `
       -CategoryReason $Payload.CategoryReason `
       -CategoryTargetName $Payload.CategoryTargetName `
       -CategoryTargetType $Payload.CategoryTargetType
  } else {
    Write-Error `
       -Message $Message `
       -Category $Category `
       -ErrorId $ErrorId `
       -TargetObject $TargetObject `
       -RecommendedAction $Payload.RecommendedAction `
       -CategoryActivity $Payload.CategoryActivity `
       -CategoryReason $Payload.CategoryReason `
       -CategoryTargetName $Payload.CategoryTargetName `
       -CategoryTargetType $Payload.CategoryTargetType
  }
}

function Receive-TerminatingError {
  param(
    [psobject]$Payload
  )

  if ($Payload.Exception) {
    $Message = $Payload.Exception.Message
  }

  $Exception = New-Object Exception $Message

  throw $Exception
}

$SendHostCode = "
  function Send-Host {
    [CmdletBinding()]
    param(
      [Object]`$Object,
      [switch]`$NoNewLine,
      [Object]`$Separator,
      [ConsoleColor]`$ForegroundColor,
      [ConsoleColor]`$BackgroundColor
    )

    Send-Payload ``
      -Type Host ``
      -Object `$Object ``
      -NoNewLine `$NoNewLine ``
      -Separator `$Separator ``
      -ForegroundColor `$ForegroundColor ``
      -BackgroundColor `$BackgroundColor
  }
"

$SendInformationCode = "
  function Send-Information {
    [CmdletBinding()]
    param(
      [Object]`$MessageData,
      [string[]]`$Tags
    )

    Send-Payload -Type Information -Object `$Object -Tags `$Tags
  }
"

$SendOutputCode = "
  function Send-Output {
    [CmdletBinding()]
    param(
      [PSObject[]]`$InputObject,
      [boolean]`$NoEnumerate
    )

    Send-Payload -Type Output -InputObject `$InputObject -NoEnumerate `$NoEnumerate
  }
"

$SendProgressCode = "
  function Send-Progress {
    [CmdletBinding()]
    param(
      [string]`$Activity,
      [string]`$Status,
      [int32]`$Id,
      [int32]`$PercentComplete,
      [int32]`$SecondsRemaining,
      [string]`$CurrentOperation,
      [switch]`$Completed,
      [int32]`$SourceId
    )

    Send-Payload ``
      -Type Progress ``
      -Activity `$Activity ``
      -Status `$Status ``
      -Id `$id ``
      -PercentComplete `$PercentComplete ``
      -SecondsRemaining `$SecondsRemaining ``
      -CurrentOperation `$CurrentOperation ``
      -Completed `$Completed ``
      -SourceId `$SourceId
  }
"

$CommandAliasesCode = "
  Set-Alias Write-Debug Send-Debug
  Set-Alias Write-Error Send-Error
  Set-Alias Write-Host Send-Host
  Set-Alias Write-Information Send-Information
  Set-Alias Write-Output Send-Output
  Set-Alias Write-Progress Send-Progress
  Set-Alias Write-Verbose Send-Verbose
  Set-Alias Write-Warning Send-Warning
"

$CommandRunnerCode = "
  try {
      Invoke-Expression '$Command'
  } catch {
    Send-Payload -Type TerminatingError -Exception $_
  } finally {
    $NamedPipeClient.Dispose()
  }
"

function Invoke-ValidateCommand {
  param(
    [string]$Command
  )

  $Tokens = @()
  $ParseErrors = @()
  [System.Management.Automation.Language.Parser]::ParseInput(
    $Command,
    $null,
    [ref]$Tokens,
    [ref]$ParseErrors
  )

  if ($ParseErrors) {
    throw $ParseErrors[0]
  }
}

function Invoke-AsAdministrator {
  param(
    [string]$Command,
    [string]$Verb = 'RunAs',
    [switch]$NoExit,
    [int]$IOIntervalSeconds = 0.5
  )

  $ErrorActionPreference = 'Stop'

  $PipeName = 'PSeudoPipe_{0}' -f (New-Guid)

  $Server = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName,'In'

  $ConnectionCode = $ClientConnectionCode -f $PipeName

  $Command = "& {
    $ConnectionCode

    $ConvertToSerializableCode

    $SendMessageCode

    $SendLoggingCode
    $SendErrorCode
    $SendHostCode
    $SendInformationCode
    $SendOutputCode
    $SendProgressCode

    $CommandAliasesCode

    $CommandRunnerCode
  }"

  $Tokens = @()
  $ParseErrors = @()

  [System.Management.Automation.Language.Parser]::ParseInput(
    $Command,
    $null,
    [ref]$Tokens,
    [ref]$ParseErrors
  )

  if ($ParseErrors) {
    throw $ParseErrors[0]
  }

  if ($NoExit) {
    $Process = Start-Process `
       -Passthru `
       -Verb $Verb `
       powershell.exe -ArgumentList '-NoExit','-Command',$Command
  } else {
    $Process = Start-Process `
       -Passthru `
       -Verb $Verb `
       powershell.exe -ArgumentList '-WindowStyle','hidden','-Command',$Command
  }

  $Server.WaitForConnection()

  $Reader = New-Object System.IO.StreamReader $Server

  while ($True) {
    $IOStart = Get-Date

    $Line = $Reader.ReadLine()

    while ($Line) {
      Receive-Message $Line
      $Line = $Reader.ReadLine()
    }

    if ($Process.HasExited) {
      break
    }

    Start-Sleep -Seconds ($args[0] - ((Get-Date) - $IOStart).TotalSeconds)
  }

  $Server.Dispose()
}

Export-ModuleMember `
   -Function @('Invoke-AsAdministrator') `
   -Variable @(`
     'ClientConnectionCode',`
     'ConvertToSerializableCode',`
     'SendMessageCode',`
     'SendLoggingCode',`
     'SendErrorCode',`
     'SendHostCode',`
     'SendInformationCode',`
     'SendOutputCode',`
     'SendProgressCode',`
     'CommandAliasesCode',`
     'CommandRunnerCode' `
  )
