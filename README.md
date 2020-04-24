# PSeudo

A PowerShell module that lets you execute commands with Administrator
privileges while keeping output inside the host session, "like sudo".

## Install

This module is available on
[PSGallery](https://www.powershellgallery.com/packages/PSeudo) and can be
installed by running `Install-Module PSeudo`.

## About

PowerShell doesn't have an analog to sudo from the \*nix world. This means
that if we want to execute commands with elevated privileges - ie, as
Administrator - that we need to spawn a child PowerShell process with the
`-Verb` parameter set to `RunAs`.

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

This function uses .NET's serialization framework to send code in the form
of a script block to a child Administrator process, which then uses a named
pipe to connect back to the parent and send results, also using .NET's
serialization framework. This allows us to execute commands in an
Administrator-level process and have the output print in the host terminal,
"just like sudo".

Make no mistake: This approach is extremely cursed, and there are a number
of limitations. Specifically: only objects that support .NET serialization can
be sent in either direction, and this implementation can only handle the output
and error streams.

Finally, the implementation can be brittle. If the command passed to the
Administrator process is malformed and exits before the client connection
can be established, then it will permanently lock up the parent process,
which will be deadlocked.

As usual, be careful when working with elevated privileges and untrusted
input. You've been warned.

## Examples 

```powershell
Invoke-AsAdmin {Get-Process -IncludeUserName | Sort-Object UserName | Select-Object UserName, ProcessName}
```

This will obtain a process list with user name information, sorted by UserName.
Because Process objects are not serializable, if you want to transform the
output of Get-Process, enclose the command with curly braces to ensure that
pipeline processing should be done in the called process.

```powershell
Invoke-AsAdmin {cmd /c mklink $env:USERPROFILE\bin\test.exe test.exe}
```

This will reate a symbolic link to test.exe in the $env:USERPROFILE\bin folder. Note that $env:USERPROFILE is evaluated in the context of the caller process.

## Development

This project uses [Invoke-Build](https://github.com/nightroman/Invoke-Build) to run tasks. You can install it with `Install-Module`. The default task lints and runs tests.

### Tests

This project comes with tests written in [Pester](https://pester.dev). Pester can be installed with `Install-Module` and the tests can be ran with `Invoke-Build Test`.

### Linting

This project is linted with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). PSScriptAnalyzer can be installed with `Install-Module` and can be ran with `Invoke-Build Lint`.

### Formatting

This project uses [PowerShell-Beautifier](https://github.com/DTW-DanWard/PowerShell-Beautifier) to autoformat code. Powershell-Beautifier can be installed with `Install-Module` and formatting can be ran with `Invoke-Build Format`.

### Licensing

This project is hosted with a permissive MIT/Expat license.