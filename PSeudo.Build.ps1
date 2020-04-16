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

Import-Module PowerShell-Beautifier
Import-Module PSScriptAnalyzer

task . Lint,Test

task Format {
  Get-ChildItem .\ -Include *.ps1,*.psm1,*.psd1 -Recurse | Edit-DTWBeautifyScript
}

task Lint {
  Invoke-ScriptAnalyzer -Recurse `
     -Path .\ `
     -Settings CodeFormatting,PSGallery,ScriptFunctions `
     -ExcludeRule PSAvoidUsingCmdletAliases,PSAvoidUsingWriteHost
}

task Test {
  powershell -Command Invoke-Pester
}

task Publish Lint,Test,{
  . .\Secrets.ps1

  Publish-Module -Path .\PSeudo\ -NuGetApiKey $PowershellGalleryAPIKey
}
