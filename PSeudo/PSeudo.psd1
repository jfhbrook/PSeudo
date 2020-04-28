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

@{
  RootModule = 'PSeudo.psm1'
  ModuleVersion = '1.0.2'
  GUID = 'd540a6db-930e-4b14-bd04-4ed21eeed8c3'
  Author = 'Josh Holbrook'
  CompanyName = 'Josh Holbrook'
  Copyright = 'Copyright 2020 Josh Holbrook. Licensed under an MIT/Expat license.'
  Description = 'Allows for executing commands as an Administrator and returning output to an unprivileged host session'

  PowerShellVersion = '5.1'

  FunctionsToExport = 'Invoke-AsAdministrator'
  FileList = @('PSeudo.psd1','PSeudo.psm1','LICENSE','en-US\about_PSeudo.help.txt','en-US\bout_PSeudo_Administrator_Scope.help.txt')

  PrivateData = @{
    PSData = @{
      Tags = @('Invoke-AsAdministrator','Admin','Administrator','Administration','Elevate','Elevated','Privileges','sudo','UAC')
      LicenseUri = 'https://github.com/jfhbrook/PSeudo/blob/master/PSeudo/LICENSE'
      ProjectUri = 'https://github.com/jfhbrook/PSeudo'
    }
  }
}
