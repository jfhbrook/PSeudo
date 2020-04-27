# MIT License (Expat)
#
# Copyright (c) 2020 Josh Holbrook
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

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression','',Justification = 'We are trying to test code stored in strings')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments','',Justification = 'Expressions are invoked with these variables in their scope')]
param()

Import-Module .\PSeudo\PSeudo.psm1

Describe 'Get-Base64String' {
  It 'encodes strings to Base64' {
    @(
      @('hello world','aABlAGwAbABvACAAdwBvAHIAbABkAA=='),
      @("foo`r`nbar",'ZgBvAG8ADQAKAGIAYQByAA==')
    ) | ForEach-Object {
      $Actual = Get-Base64String $_[0]
      $Actual | Should -Be $_[1] -Because ('{0} should encode to {1}' -f $_[0],$_[1])
    }
  }
}

Describe 'ConvertTo-Representation/$DeserializerString' {
  Invoke-Expression $DeserializerString

  It 'converts to and from value types symmetrically' {
    @(
      'hello world',
      1,
      1.23,
      [byte]0x03
    ) | ForEach-Object {
      ConvertFrom-Representation (ConvertTo-Representation $_) | Should -Be $_ -Because "$_ should retain its value after a round trip"
    }
  }

  It 'converts to and from container types symmetrically' {
    $RoundTrippedArray = ConvertFrom-Representation (ConvertTo-Representation @('a','b','c'))
    $RoundTrippedArray | Should -HaveCount 3
    $RoundTrippedArray[0] | Should -Be 'a'
    $RoundTrippedArray[1] | Should -Be 'b'
    $RoundTrippedArray[2] | Should -Be 'c'

    $RoundTrippedHashTable = ConvertFrom-Representation (ConvertTo-Representation @{ string = 'foo bar'; int = 123 })

    $RoundTrippedHashTable.Keys | Should -HaveCount 2
    $RoundTrippedHashTable['string'] | Should -Be 'foo bar'
    $RoundTrippedHashTable['int'] | Should -Be 123
  }

  It 'converts to and from PSObjects symmetrically' {
    $TestObject = New-Object PSObject
    Add-Member -InputObject $TestObject -Name 'TestProperty' -MemberType NoteProperty -Value 'some string'

    $RoundTrippedObject = ConvertFrom-Representation (ConvertTo-Representation $TestObject)

    $RoundTrippedObject | Should -BeOfType PSObject
  }

  It 'converts to and from non-serializable objects with some loss of fidelity' {
    class NonSerializableProperty{
      [string]$StringProperty
    }

    class TestObject{
      [string]$StringProperty
      [hashtable]$HashProperty
      [psobject]$SerializableProperty
      [object]$NonSerializableProperty
    }

    $TestObject = New-Object TestObject

    $TestObject.StringProperty = 'hello world'
    $TestObject.HashProperty = @{ foo = 1; bar = 2 }

    $TestObject.SerializableProperty = New-Object PSObject
    $TestObject.SerializableProperty | Add-Member 'StringProperty' 'hello world'

    $TestObject.NonSerializableProperty = New-Object NonSerializableProperty
    $TestObject.NonSerializableProperty.StringProperty = 'hello world'

    $RoundTrippedObject = ConvertFrom-Representation (ConvertTo-Representation $TestObject)

    $RoundTrippedObject.StringProperty | Should -Be 'hello world'
    $RoundTrippedObject.HashProperty | Should -BeOfType hashtable
    $RoundTrippedObject.HashProperty.foo | Should -Be 1
    $RoundTrippedObject.HashProperty.bar | Should -Be 2
    $RoundTrippedObject.SerializableProperty | Should -BeOfType PSObject
    $RoundTrippedObject.SerializableProperty.StringProperty | Should -Be 'hello world'
    $RoundTrippedObject.NonSerializableProperty | Should -Match 'NonSerializableProperty$'
  }
}

Describe '$RunnerString' {
  function Invoke-NothingInParticular { 'nothing important' }

  class TestObject{
    [string]$Foo
  }

  @(
    @{
      It = 'invokes a simple string command and sends a string output through the pipe';
      Command = 'Invoke-NothingInParticular';
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Output'
        $Output.Object | Should -Be 'nothing important' }
    },
    @{
      It = 'invokes a parametrized script block and sends a string output through the pipe';
      Command = { param($Message) Write-Output $Message };
      ArgumentList = @('hello world');
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Output'
        $Output.Object | Should -Be 'hello world'
      }
    },
    @{
      It = 'sends a PSObject output through the pipe';
      Command = { $Obj = New-Object PSObject; $Obj | Add-Member 'Foo' 'bar'; return $Obj };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Output'
        $Output.Object | Should -Not -Be 'Null'
        $Output.Object.foo | Should -Be 'bar'
      }
    },
    @{
      It = 'sends a non-serializable output through the pipe';
      Command = { $Obj = New-Object TestObject; $Obj.foo = 'bar'; return $Obj };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Output'
        $Output.Object | Should -Not -Be 'Null'
        $Output.Object.foo | Should -Be 'bar' }
    },
    @{
      It = 'sends a non-terminating error with a message argument in a script block through the pipe';
      Command = { Write-Error 'Ponyyyy' };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Error'
        $Output.Object | Should -BeOfType [hashtable]
        $Output.Object.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
      }
    },
    @{
      It = 'sends a non-terminating error with a message argument in a string through the pipe';
      Command = "Write-Error 'Ponyyyy'";
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Error'
        $Output.Object | Should -BeOfType [hashtable]
        $Output.Object.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
      }
    },
    @{
      It = 'sends a non-terminating error with an Exception argument through the pipe';
      Command = { Write-Error (New-Object Exception 'Ponyyyy') };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Error'
        $Output.Object | Should -BeOfType [hashtable]
        $Output.Object.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
      }
    },
    @{
      It = 'sends a non-terminating error with an ErrorRecord argument through the pipe';
      Command = {
        $Exception = New-Object Exception 'Ponyyyy'

        $ErrorRecord = New-Object System.Management.Automation.ErrorRecord @(
          $Exception,
          'errorID',
          [System.Management.Automation.ErrorCategory]'NotSpecified',
          $null
        )

        Write-Error $ErrorRecord
      };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Error'
        $Output.Object | Should -BeOfType [hashtable]
        $Output.Object.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
      }
    },
    @{
      It = 'sends a terminating error through the pipe';
      Command = {
        $Exception = New-Object Exception 'Ponyyyy'

        throw $Exception
      };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Fatal'
        $Output.Object | Should -BeOfType [System.Management.Automation.ErrorRecord]
      }
    },
    @{
      It = 'sends a debug message through the pipe';
      Command = { Write-Debug 'Ponyyy' };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Debug'
        $Output.Object | Should -Be 'Ponyyy'
      }
    },
    @{
      It = 'sends a verbose message through the pipe';
      Command = { Write-Verbose 'Ponyyy' };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Verbose'
        $Output.Object | Should -Be 'Ponyyy'
      }
    },
    @{
      It = 'sends a warning message through the pipe';
      Command = { Write-Warning 'Ponyyy' };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Warning'
        $Output.Object | Should -Be 'Ponyyy'
      }
    },
    @{
      It = 'sends information through the pipe';
      Command = {
        $MessageData = New-Object PSObject
        $MessageData | Add-Member 'Foo' 'bar'

        Write-Information $MessageData @('hello','world')
      };
      ArgumentList = @();
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [hashtable]
        $Output.Type | Should -Be 'Information'
        $Output.Object | Should -BeOfType [hashtable]
        $Output.Object.MessageData | Should -BeOfType [PSObject]
        $Output.Object.MessageData.foo | Should -Be 'bar'
        $Output.Object.Tags[0] | Should -Be 'hello'
        $Output.Object.Tags[1] | Should -Be 'world'
      }
    }
  ) | ForEach-Object {
    It ($_.It) {
      class TestPipe{
        [hashtable[]]$Actions
        [string]$ServerName
        [string]$PipeName
        [string]$PipeDirection

        TestPipe () {
          $this.Actions = @()
        }

        [void] Connect () {
          $this.Actions += @{ Action = 'Connect' }
        }

        [void] Close () {
          $this.Actions += @{ Action = 'Close' }
        }

        [void] WaitForPipeDrain () {
          $This.Actions += @{ Action = 'WaitForPipeDrain' }
        }

        [void] WriteByte ([byte]$Byte) {
          $this.Actions += @{ Action = 'WriteByte'; Value = $Byte }
        }

        [void] Reset () {
          $this.Actions = @()
          $this.ServerName = $null
          $this.PipeName = $null
          $this.PipeDirection = $null
        }
      }

      $TestPipe = New-Object TestPipe

      Mock New-Object {
        $TestPipe.ServerName = $ArgumentList[0]
        $TestPipe.PipeName = $ArgumentList[1]
        $TestPipe.PipeDirection = $ArgumentList[2]

        return $TestPipe
      } -ParameterFilter { $TypeName -eq 'System.IO.Pipes.NamedPipeClientStream' }

      # A mocked BinaryFormatter
      class TestFormatter{
        [hashtable[]]$Actions

        TestFormatter () {
          $this.Actions = @()
        }

        [void] Serialize ([Object]$Pipe,[object]$Object) {
          if ($Pipe -is [TestPipe]) {
            $this.Actions += @{ Action = 'Serialize'; Object = $Object }
          }
        }

        [void] Reset () {
          $this.Actions = @()
        }
      }

      $TestFormatter = New-Object TestFormatter

      Mock New-Object {
        $TestFormatter
      } -ParameterFilter { $TypeName -eq 'System.Runtime.Serialization.Formatters.Binary.BinaryFormatter' }

      # Mocked PipeName and Location
      $PipeName = 'TestPipeName'
      $Location = (Get-Location).Path

      $Command = $_['Command']
      $ArgumentList = $_['ArgumentList']
      $Assertions = $_['Assertions']

      Invoke-Expression $RunnerString

      Assert-MockCalled New-Object -Times 1 -ParameterFilter { $TypeName -eq 'System.IO.Pipes.NamedPipeClientStream' }
      $TestPipe.ServerName | Should -Be '.'
      $TestPipe.PipeName | Should -Be 'TestPipeName'
      $TestPipe.PipeDirection | Should -Be 'Out'

      $TestPipe.Actions[0].Action | Should -Be 'Connect'
      $TestPipe.Actions[-2].Action | Should -Be 'WaitForPipeDrain'
      $TestPipe.Actions[-1].Action | Should -Be 'Close'

      Assert-MockCalled New-Object -Times 1 -ParameterFilter { $TypeName -eq 'System.Runtime.Serialization.Formatters.Binary.BinaryFormatter' }

      $Objects = @($TestFormatter.Actions | ForEach-Object { $_.Object })

      & $Assertions @Objects

      $TestPipe.Reset()
      $TestFormatter.Reset()
    }
  }
}

Describe 'Invoke-AsAdministrator' {
  @(
    @{
      It = 'invokes a script block with no arguments';
      ScriptBlock = { Write-Output 'hello world' };
      ArgumentList = @();
      Assertions = { param($Output) $Output | Should -Be 'hello world' };
    },
    @{
      It = 'invokes a script block with arguments';
      ScriptBlock = { param($Message) Write-Output $Message };
      ArgumentList = @('hello world');
      Assertions = { param($Output) $Output | Should -Be 'hello world' };
    },
    @{
      It = 'invokes a string command';
      Command = "Write-Output 'hello world'";
      Assertions = { param($Output) $Output | Should -Be 'hello world' };
    },
    @{
      It = 'handles non-serializable output';
      ScriptBlock = {
        class TestObject{ [string]$Foo }
        $Obj = New-Object TestObject
        $Obj.foo = 'foo'
        Write-Output $Obj
      };
      ArgumentList = @()
      Assertions = { param($Output) $Output.foo | Should -Be 'foo' };
    },
    @{
      It = 'handles non-terminating error output';
      ScriptBlock = {
        Write-Error 'ponyyy'
      };
      ArgumentList = @();
      Stream = 2;
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $Output.Exception.Message | Should -Match 'ponyyy'
      }
    },
    @{
      It = 'handles terminating error output';
      ScriptBlock = {
        $Exception = New-Object Exception 'ponyyy'
        throw $Exception
      };
      ArgumentList = @();
      Throws = $true;
    },
    @{
      It = 'handles records written to the error stream by imported functions';
      ScriptBlock = {
        Import-Module './Pseudo.Test.ModuleFixture.psm1'

        Invoke-ErrorWritingFunction
      };
      ArgumentList = @();
      Stream = 2;
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $Output.Exception.Message | Should -Match 'ponyyy'
      }
    },
    @{
      It = 'handles verbose output';
      ScriptBlock = { Write-Verbose 'ponyyy' };
      ArgumentList = @();
      Stream = 4;
      Assertions = { param($Output) $Output | Should -Be 'ponyyy' }
    },
    @{
      It = 'handles warning output';
      ScriptBlock = { Write-Warning 'ponyyy' };
      ArgumentList = @();
      Stream = 3;
      Assertions = { param($Output) $Output | Should -Be 'ponyyy' }
    },
    @{
      It = 'handles information output';
      ScriptBlock = { Write-Information 'ponyyy' -Tags @('kate','beaton') };
      ArgumentList = @();
      Stream = 6;
      Assertions = {
        param($Output)

        $Output | Should -BeOfType [System.Management.Automation.InformationRecord]
        $Output.MessageData | Should -Be 'ponyyy'
        $Output.Tags[0] | Should -Be 'kate'
        $Output.Tags[1] | Should -Be 'beaton'
      }
    }
    @{
      It = 'handles host output';
      ScriptBlock = { Write-Host 'ayy lmao' };
      ArgumentList = @();
      Stream = 6;
      Assertions = {
        param($Output)

        $Output | Should -Be 'ayy lmao'
      }
    }
  ) | ForEach-Object {
    It ($_.It) {
      Mock -Module PSeudo Invoke-AdminProcess {
        [void](Start-Process $FilePath -ArgumentList @('-WindowStyle','Hidden','-EncodedCommand',(Get-Base64String $CommandString)))
      }

      $ScriptBlock = $_.ScriptBlock
      $Command = $_.Command
      $ArgumentList = $_.ArgumentList
      $Stream = $_.Stream
      $Throws = $_.Throws
      $Assertions = $_.Assertions

      if ($ScriptBlock) {
        if ($Throws) {
          { Invoke-AsAdministrator $ScriptBlock $ArgumentList } | Should -Throw
        } else {
          switch ($Stream) {
            6 {
              & $Assertions (Invoke-AsAdministrator $ScriptBlock $ArgumentList 6>&1)
            }
            4 {
              & $Assertions (Invoke-AsAdministrator $ScriptBlock $ArgumentList -Verbose 4>&1)
            }
            3 {
              & $Assertions (Invoke-AsAdministrator $ScriptBlock $ArgumentList 3>&1)
            }
            2 {
              & $Assertions (Invoke-AsAdministrator $ScriptBlock $ArgumentList 2>&1)
            }
            default {
              & $Assertions (Invoke-AsAdministrator $ScriptBlock $ArgumentList)
            }
          }
        }
      } else {
        if ($Throws) {
          { Invoke-AsAdministrator $Command } | Should -Throw
        } else {
          switch ($Stream) {
            6 {
              & $Assertions (Invoke-AsAdministrator $Command 6>&1)
            }
            4 {
              & $Assertions (Invoke-AsAdministrator $Command -Verbose 4>&1)
            }
            3 {
              & $Assertions (Invoke-AsAdministrator $Command 3>&1)
            }
            2 {
              & $Assertions (Invoke-AsAdministrator $Command 2>&1)
            }
            default {
              & $Assertions (Invoke-AsAdministrator $Command)
            }
          }
        }
      }
    }
  }
}
