# MIT License (Expat)
#
# Copyright (c) 2020 Josh Holbrook
# Copyright (c) 2014 msumimz
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

function script:Get-Base64String {
  <#
  .Description
  The Get-Base64String function converts a string into bytes and then into a
  base64 string. Note that this encoding is based on a UTF-16 LE byte
  encoding, rather tha UTF-8.

  .Parameter String
  An unencoded string to convert to base64.
  #>

  param(
    [string]$String
  )

  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($String)
  [Convert]::ToBase64String($Bytes)
}

$script:Formatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter

function script:ConvertTo-Representation {
  <#
  .Description
  The ConvertTo-Representation function converts an input object into a
  deserializable base64 representation. This is so that we can send objects
  over a named pipe from the host process into our administrator process.
  Currently this only works with objects that support .NET's serialization
  framework, but in those cases it will also serialize them in a fully
  reversible manner - in other words, serialization and deserialization are
  symmetric.

  .Parameter InputObject
  A serializable object.vim PS
  #>

  param(
    $InputObject
  )

  $FormattedString = New-Object -TypeName System.IO.MemoryStream
  $Formatter.Serialize($FormattedString,$InputObject)
  $Bytes = New-Object -TypeName byte[] -ArgumentList ($FormattedString.length)
  [void]$FormattedString.Seek(0,"Begin")
  [void]$FormattedString.Read($Bytes,0,$FormattedString.length)
  [Convert]::ToBase64String($Bytes)
}

$script:DeserializerString = @'
function script:ConvertFrom-Representation {
  <#
  .Description
  The ConvertFrom-Representation function converts a deserializable base64
  object representation into an object, using .NET's serialization framework.
  This is used inside of the admin process to re-hydrate objects sent to it
  over a named pipe from a host process.

  .Parameter Representation
  A base64 representation of an object.
  #>

  param(
    [string]$Representation
  )

	$Formatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$Bytes = [Convert]::FromBase64String($Representation)
	$FormattedString = New-Object -TypeName System.IO.MemoryStream
	[void]$FormattedString.Write($Bytes, 0, $Bytes.length)
	[void]$FormattedString.Seek(0, "Begin")
	$Formatter.Deserialize($FormattedString)
}
'@

# The code in this string opens a client connection to a named pipe, reads in
# arguments passed to PowerShell (, runs the command, serializes the results
# (using .NET's serialization framework as elsewhere in this code) and sends
# it back to the named pipe.
$script:RunnerString = @'
$script:Serializable = $null
$script:Output = $null

filter Send-ToPipe {
	if ($null -eq $Serializable) {
		$script:Serializable = $_.GetType().IsSerializable
		if (-Not $Serializable) {
			$script:Output = New-Object -TypeName System.Collections.ArrayList
		}
	}
	if ($Serializable) {
		$OutPipe.WriteByte(1)
		$Formatter.Serialize($OutPipe, $_)
	} else {
		[void]$script:Output.Add($_)
	}
}

$Formatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter

Set-Location $Location

try {
	try {
		$OutPipe = New-Object -TypeName System.IO.Pipes.NamedPipeClientStream -ArgumentList (".", $PipeName, "Out")
		$OutPipe.Connect()

		if ($arglist.length -eq 0 -and $Command -is [string]) {
			Invoke-Expression -Command $Command 2>&1 | Send-ToPipe
		} else {
			& $Command @arglist 2>&1 | Send-ToPipe
		}
		if (!$serializable) {
			foreach ($String in $Output | Out-String -Stream) {
				$OutPipe.WriteByte(1)
				$Formatter.Serialize($OutPipe, $String)
			}
		}
	} catch [Exception] {
		$OutPipe.WriteByte(1)
		$Formatter.Serialize($OutPipe, $_)
	}
} finally {
	$OutPipe.WriteByte(0)
	$OutPipe.WaitForPipeDrain()
	$OutPipe.Close()
}
'@

function Invoke-AdminProcess {
  param(
    [string]$CommandString
  )

  # Set up the new admin "child" process.
  $ProcStartInfo = New-Object System.Diagnostics.ProcessStartInfo
  $ProcStartInfo.FileName = "powershell.exe"
  $ProcStartInfo.Verb = "Runas"

  # If the INVOKEASADMINDEBUG environment variable is set, the process will
  # not exit, but return to an admin prompt. Otherwise, it will normally
  # start without any window of it's own.
  if ($env:INVOKEASADMINDEBUG) {
    $ProcStartInfo.Arguments = "-NoExit","-EncodedCommand",(Get-Base64String $CommandString)
  } else {
    $ProcStartInfo.WindowStyle = "Hidden"
    $ProcStartInfo.Arguments = "-EncodedCommand",(Get-Base64String $CommandString)
  }

  # Execute the side process.
  $Process = [System.Diagnostics.Process]::Start($ProcStartInfo)

  # Silence powershell process output.
  [void]$Process
}

function Invoke-AsAdmin {
<#
  .SYNOPSIS
  Execute commands with elevated Administrator privileges.

  .DESCRIPTION
  The Invoke-AsAdmin cmdlet executes command as an elevated user.

  PowerShell doesn't have an analog to sudo from the *nix world. This means
  that if we want to execute commands with elevated privileges - ie, as
  Administrator - that we need to spawn a child PowerShell process with the
  -Verb parameter set to RunAs.

  Typically, when executing commands in a child PowerShell process, everything
  works the way we would like it to - the subshell is spawned, our commands
  (either in string or script block format) are executed in the subshell, and
  the results are printed back in the host terminal.

  However, this is not the case for Administrator processes. In these
  situations, the child PowerShell process spawns a separate window, logs its
  output to that window, and then typically exits when the script terminates.
  Any IO and feedback that happens in that process, regardless of whether it's
  the output stream, the error stream or otherwise, is lost into the aether.
  This is further complicated by the fact that we typically don't want end
  users to see the administrator window - it looks sloppy. This can be
  mitigated by keeping the administrator window open after the command has
  terminated, but this makes for a bad user experience.

  This function uses a named pipe to create a connection to the child process
  and sends data back and forth over that connection using .NET's serialization
  framework in order to get commands we want to execute to the process and
  output from that process back to the parent. This allows us to execute\
  commands in an Administrator-level process and have the output print in the
  host terminal, "just like sudo". As a matter of implementation details:
  Invoke-Expression is used when the command is a single string, but in other
  cases the call operator (&) is used instead.

  Note that environment variables are evaluated in the context of the parent
  process and not the child.

  There are some limitations. Only objects that support .NET serialization can
  be sent in either direction, and this implementation can only handle the output
  and error streams. Moreover, it doesn't support an -ArgumentList abstraction.

  Finally, the implementation can be brittle. If the command passed to the
  Administrator process is malformed and exits before the client connection
  can be established, then it will permanently lock up the parent process,
  which will be deadlocked.

  .EXAMPLE
  PS> Invoke-AsAdmin {cmd /c mklink $env:USERPROFILE\bin\test.exe test.exe}

  This command creates a symbolic link to test.exe in the
  $env:USERPROFILE\bin folder. Note that $env:USERPROFILE is evaluated in
  the context of the caller process.

  .EXAMPLE
  PS> Invoke-AsAdmin {Get-Process -IncludeUserName | Sort-Object UserName | Select-Object UserName, ProcessName}

  This command obtains a process list with user name information, sorted by
  UserName. Because the System.Diagnostics.Process objects are not
  serializable, if you want to transform the output of Get-Process, enclose
  the command with curly braces to ensure that pipeline processing should be
  done in the called process.
  #>

  [CmdletBinding()]
  param(
    [Parameter(
      Position = 0,
      ValueFromRemainingArguments = $true)]
    $Expression
  )

  Set-StrictMode -Version Latest

  if ($null -eq $Expression) {
    Write-Error "Command to execute not specified"
    return
  }

  $PipeName = "AdminPipe-" + [guid].GUID.ToString()

  $args = @($Expression)

  $CommandString = $DeserializerString +
  "`n" +
  "`$PipeName = `'" +
  $PipeName +
  "`'`n" +
  "`$Location = ConvertFrom-Representation `'" +
  (ConvertTo-Representation (Get-Location).Path) +
  "`'`n" +
  "`$Command = ConvertFrom-Representation `'" +
  (ConvertTo-Representation $args[0]) +
  "`'`n"

  if ($args.length -gt 1) {
    $CommandString +=
    "`$argList = @(ConvertFrom-Representation `'" +
    (ConvertTo-Representation $args[1..($args.length - 1)]) +
    "`')`n"
  } else {
    $CommandString += "`$argList = @()`n"
  }

  $CommandString += $RunnerString + "`n"
  Write-Debug $CommandString

  try {
    $InPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName,"In" -ErrorAction Stop
  } catch {
    Write-Error $_.Exception.Message
  }

  Invoke-AdminProcess $CommandString

  $InPipe.WaitForConnection()

  try {
    for (;;) {
      $Type = $InPipe.ReadByte()
      if ($Type -eq 0) {
        break
      }

      $InputObject = $Formatter.Deserialize($InPipe)
      if ($InputObject -is
        [System.Management.Automation.ErrorRecord] -or
        $InputObject -is
        [Exception]
      ) {
        Write-Error $InputObject
      } else {
        $InputObject
      }
    }
  } catch {
    Write-Warning $_
  } finally {
    $InPipe.Close()
  }
}

Export-ModuleMember `
   -Function @(`
     'Get-Base64String',`
     'ConvertTo-Representation',`
     'Invoke-AdminProcess',`
     'Invoke-AsAdmin' `
  ) `
   -Variable @(`
     'DeserializerString',`
     'RunnerString' `
  )
