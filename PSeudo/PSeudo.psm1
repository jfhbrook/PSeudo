# The MIT License (MIT, Expat)
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

# A function to take a supplied string argument, convert it to a byte array,
# and convert the resulting bytes to a base64 string. Note that this encoding
# is based on a UTF-16 LE byte encoding, rather than UTF-8.
#
# Check the .NET API documentation for the UnicodeEncoding.GetBytes Method
# for more information.
function script:Get-Base64String ([string]$String) {
  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($String)
  [Convert]::ToBase64String($Bytes)
}

# Formatter is a new instance of the BinaryFormatter class, which can serialize
# and deserialize an object into or out of a binary format. The goal is
# to generate encoded data that is guaranteed to be perfectly decodable, without
# change. In other words, and provided we have a place to put the data, we can
# use this to help us clone objects.
#
# Check the .NET API documentation for the BinaryFormatter Class for more
# information.
$script:Formatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter

# This is how we are going to clone the object. InputObject is any .NET object
# that will be passed to the admin process. In computer science, the standard
# by which memory (or binary) is interpreted is called Data Representation
# (or encoding). By taking an object and serializing it into memory, that
# memory stream can then be copied into a new object or string. To pass an
# object into a child process, we will want to reencode the memory
# representation into base64 for use as a command-line encoded argument later.
#
# FormattedString is a new instance of the MemoryStream class. The resulting
# object has its own real memory store. The contents of InputObject are then
# serialized into binary using the Formatter function from above and fed into
# the memory stream.
#
# Check the .NET API documentation for the MemoryStream Class for more
# information.
function script:ConvertTo-Representation ($InputObject) {
  $FormattedString = New-Object -TypeName System.IO.MemoryStream
  $Formatter.Serialize($FormattedString,$InputObject)
  $Bytes = New-Object -TypeName byte[] -ArgumentList ($FormattedString.length)
  [void]$FormattedString.Seek(0,"Begin")
  [void]$FormattedString.Read($Bytes,0,$FormattedString.length)
  [Convert]::ToBase64String($Bytes)
}

# The below two variables are, in essence, storing scripts that can be encoded
# and passed as arguments to be executed by another process. The @ symbol with
# quotes denotes a block of string text. The variable DeserializeString then
# stores the text of the code instead of the results.

# This function acts as the opposite of the one above. Take the base64 encoded
# data representation, and convert it into a clone of the original object. This
# will be done from within the admin process.
$script:DeserializerString = @'
function script:ConvertFrom-Representation($Representation) {
	$Formatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$Bytes = [Convert]::FromBase64String($Representation)
	$FormattedString = New-Object -TypeName System.IO.MemoryStream
	[void]$FormattedString.Write($Bytes, 0, $Bytes.length)
	[void]$FormattedString.Seek(0, "Begin")
	$Formatter.Deserialize($FormattedString)
}
'@

# This is the latter portion of the script to be executed in the new process.
# 
# RunnerString starts by setting up some variables. Filter is a special type of
# function cast that primarily acts the same as the Process block of an
# advanced function. 
$script:RunnerString = @'
$script:Serializable = $null
$script:Output = $null
filter SendTo-Pipe() {
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
			Invoke-Expression -Command $Command 2>&1 | SendTo-Pipe
		} else {
			& $Command @arglist 2>&1 | SendTo-Pipe
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

# Each function block intended to be exported as a command-object should have
# a block of synopsis information. This can then be used by `Get-Help` as the
# short-form basis for man-like help text.
<#
.SYNOPSIS
	Execute a command as an elavated user.

.DESCRIPTION
	The Invoke-AsAdmin cmdlet executes the command specified by the arguments as an elavated user.

	When the command is a single string, it is executed by the Invoke-Expression cmdlet. Otherwise, the ampersand (&) shell command is used.

	The command line is then executed in an elavated process that is different from the caller. The output is serialized and transfered as a pipeline stream to the caller. If the output is not serializable, it is converted to a text stream by means of the Out-String cmdlet.

	The Invoke-AsAdmin cmdlet will not open a new console window. Instead, it executes the command utilizing the same console session as the caller process. All environment variables are evaluated in the context of the caller process.

.EXAMPLE
	PS> Invoke-AsAdmin {cmd /c mklink $env:USERPROFILE\bin\test.exe test.exe}
	Creates a symbolic link to test.exe in the $env:USERPROFILE\bin folder. Note that $env:USERPROFILE is evaluated in the context of the caller process.

.EXAMPLE
	PS> Invoke-AsAdmin {Get-Process -IncludeUserName | Sort-Object UserName | Select-Object UserName, ProcessName}
	Obtains a process list with user name information, sorted by UserName. Because the System.Diagnostics.Process objects are not serializable, if you want to transform the output of Get-Process, enclose the command with curly braces to ensure that pipeline processing should be done in the called process.
#>
function Invoke-AsAdmin {
  [CmdletBinding()]
  param(
    [Parameter(
      Position = 0,
      ValueFromRemainingArguments = $true)]
    $Expression
  )

  Set-StrictMode -Version Latest

  # If no expression is given, write an error and return to the prompt.
  # Since $null is a scalar value, always put it left of the evaluation
  # operator.
  if ($null -eq $Expression) {
    Write-Error "Command to execute not specified"
    return
  }

  # Create a unique title for the pipe.
  $PipeName = "AdminPipe-" + [guid].GUID.ToString()

  # Explicitly set the argument list to be the contents of the user
  # provided expression.
  $args = @($Expression)

  # TODO: There is a lot of tom-foolery going on in here.
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

  # If there is more than one argument, serialize and convert them into a
  # single base64 string. This is an extra argument check. In the event that
  # the input expression is not wrapped in quotes or braces, an attempt will
  # still be made to construct and execute the command.
  # TODO: I'm really not sure if this is a feature or a potential flaw.
  if ($args.length -gt 1) {
    $CommandString +=
    "`$argList = @(ConvertFrom-Representation `'" +
    (ConvertTo-Representation $args[1..($args.length - 1)]) +
    "`')`n"
  } else {
    $CommandString += "`$argList = @()`n"
  }

  # Join the command string with the string that contains the function to
  # deserialize and execute all of this code..
  $CommandString += $RunnerString + "`n"
  Write-Debug $CommandString

  # Open a new pipeline stream.
  try {
    $InPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName,"In" -ErrorAction Stop
  } catch {
    Write-Error $_.Exception.Message
  }

  Invoke-AdminProcess $CommandString

  # Now that the process is up and listening, trigger a pipe connection check.
  $InPipe.WaitForConnection()

  # Read all input until the end of the input pipe. 
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
