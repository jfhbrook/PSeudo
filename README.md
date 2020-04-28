# PSeudo

A PowerShell module that executes commands with Administrator privileges
in Windows 10 with output showing inside the host session, "like sudo".

## Installing PSeudo

This module is available on the
[PowerShell Gallery](https://www.powershellgallery.com/packages/PSeudo)
and can be installed with `Install-Module`:

```powershell
Install-Module -Name PSeudo
```

## Usage

PSeudo exports a function called `Invoke-AsAdministrator` that takes a
script block. For example:

```powershell
PS> Import-Module PSeudo
PS > Invoke-AsAdministrator { "hello world!" }
hello world!
```

If you run this, it will ask to run PowerShell as administrator, and then
print "hello world!" to your screen.

It will also work if you pass it a string:

```powershell
PS> Invoke-AsAdministrator '"hello world!"'
hello world!
```

And can also pass arguments to script blocks:

```powershell
PS> Invoke-AsAdministrator { param($Friend) "Hello $Friend!" } -ArgumentList 'Korben'
Hello Korben!
```

My pet budgie appreciates the greeting.

Script blocks may also contain variables - these will be resolved in the host
process. For example:

```powershell
PS> Invoke-AsAdministrator { $Env:AppData }
C:\Users\Josh\AppData\Roaming
```

PSeudo will handle thrown errors:

```powershell
PS> Invoke-AsAdministrator { throw 'baby' }
Invoke-AsAdministrator : baby
At line:1 char:1
+ Invoke-AsAdministrator { throw 'baby' }
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (baby:String) [Invoke-AsAdministrator], RuntimeExceptio
   n
    + FullyQualifiedErrorId : baby

```

We can also call a number of IO functions and have them do the right thing:

```
PS> Invoke-AsAdministrator {
>>   Write-Error 'this is a test error!'
>>   Write-Information 'this is some IMPORTANT INFORMATION!'
>>   Write-Host "I'm writing to your host!"
>> } 6>&1
Invoke-AsAdministrator : this is a test error!
At line:1 char:1
+ Invoke-AsAdministrator {
+ ~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (:) [Write-Error], Exception
    + FullyQualifiedErrorId :

this is some IMPORTANT INFORMATION!
I'm writing to your host!
```

PSeudo will also handle `Write-Output`, `Write-Verbose`, `Write-Warning` and
`Write-Progress` more or less correctly.

PSeudo works best with
[serializable objects](https://docs.microsoft.com/en-us/dotnet/api/system.serializableattribute?view=netcore-3.1)
but will do sensible things with non-serializable objects as well. For
example, process objects are non-serializable, but we can still get
privileged information on processes (a real use case!) with PSeudo:

```powershell
PS> Invoke-AsAdministrator {
>>   Get-Process -IncludeUsername |
>>   Sort-Object -Property VM -Descending |
>>   Select-Object -First 1
>> }


BasePriority               : 8
Container                  :
EnableRaisingEvents        : False
ExitCode                   :
ExitTime                   :
Handle                     : 2392
HandleCount                : 876
HasExited                  : False
Id                         : 25468
MachineName                : .
MainModule                 : System.Diagnostics.ProcessModule (firefox.exe)
MainWindowHandle           : 0
MainWindowTitle            :
MaxWorkingSet              : 1413120
MinWorkingSet              : 204800
Modules                    : {System.Diagnostics.ProcessModule (firefox.exe),
                             System.Diagnostics.ProcessModule (ntdll.dll),
                             System.Diagnostics.ProcessModule (KERNEL32.DLL),
                             System.Diagnostics.ProcessModule (KERNELBASE.dll)...}
NonpagedSystemMemorySize   : 135328
NonpagedSystemMemorySize64 : 135328
PagedMemorySize            : 498774016
PagedMemorySize64          : 498774016
PagedSystemMemorySize      : 1358736
PagedSystemMemorySize64    : 1358736
PeakPagedMemorySize        : 598388736
PeakPagedMemorySize64      : 598388736
PeakVirtualMemorySize      : 1349427200
PeakVirtualMemorySize64    : 2251912290304
PeakWorkingSet             : 573087744
PeakWorkingSet64           : 573087744
PriorityBoostEnabled       : True
PriorityClass              : Normal
PrivateMemorySize          : 498774016
PrivateMemorySize64        : 498774016
PrivilegedProcessorTime    : 00:03:16.7187500
ProcessName                : firefox
ProcessorAffinity          : 15
Responding                 : True
SafeHandle                 : Microsoft.Win32.SafeHandles.SafeProcessHandle
SessionId                  : 1
Site                       :
StandardError              :
StandardInput              :
StandardOutput             :
StartInfo                  : System.Diagnostics.ProcessStartInfo
StartTime                  : 4/25/2020 7:29:32 PM
SynchronizingObject        :
Threads                    : {System.Diagnostics.ProcessThread, System.Diagnostics.ProcessThread,
                             System.Diagnostics.ProcessThread, System.Diagnostics.ProcessThread...}
TotalProcessorTime         : 00:25:57.3125000
UserProcessorTime          : 00:22:40.5937500
VirtualMemorySize          : -814784512
VirtualMemorySize64        : 2245453111296
WorkingSet                 : 415858688
WorkingSet64               : 415858688
UserName                   : RATICATE\Josh
__NounName                 : Process
```

The culprit of all my memory woes is none other than my own FireFox process!
Curses!

## Help and Documentation

You can
[access comment-level help](https://github.com/jfhbrook/PSeudo/blob/master/PSeudo/PSeudo.psm1#L541-L659)
for `Invoke-AsAdministrator` through the `Get-Help` cmdlet:

```powershell
Get-Help Invoke-AsAdministrator
```

You can also get information on what PSeudo does and how it works from
[about_PSeudo](https://github.com/jfhbrook/PSeudo/blob/master/PSeudo/en-US/about_PSeudo.help.txt):

```powershell
Get-Help about_PSeudo
```

and you can get information about the environment and scope that PSeudo script
blocks fun in from
[about_PSeudo_Administrator_Scope](https://github.com/jfhbrook/PSeudo/blob/master/PSeudo/en-US/about_PSeudo_Administrator_Scope.help.txt):

```powershell
Get-Help about_PSeudo_Administrator_Scope
```

## Development

This project uses [Invoke-Build](https://github.com/nightroman/Invoke-Build) to
run tasks. All common tasks can be accessed by using Invoke-Build.

### Tests

This project comes with tests written in [Pester](https://pester.dev).

These tests can be ran with `Invoke-Build Test`. They have decent, but
unmeasured, coverage. The strategy used by PSeudo is a bit brittle, so it's
important that code changes are well-tested.

### Linting and Formatting

This project uses
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) for linting
and [PowerShell-Beautifier](https://github.com/DTW-DanWard/PowerShell-Beautifier)
to autoformat code. Linting can be ran with `Invoke-Build Lint`, and code can
be formatted with `Invoke-Build Format`.

Note that large chunks of the source for PSeudo are contained in strings, and
therefore can't actually be linted or formatted. This can be addressed on an
ad-hoc basis via copy and paste, but practically speaking do the best you can.

### Publishing

The Invoke-Build config includes a task for publishing to PSGallery which can
be ran with `Invoke-Build Publish`. It expects a file in the project directory
(which is gitignored! be careful!) called `.\Secrets.ps1` which defines a
variable called `$PowershellGalleryAPIKey`. If you're a PowerShell person and
you know of a better strategy, *please* share.

## Licensing

This project is hosted with a permissive MIT/Expat license.