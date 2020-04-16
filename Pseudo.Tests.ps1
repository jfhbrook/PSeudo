
Import-Module .\PSeudo\PSeudo.psm1

Describe 'ConvertTo-Serializable' {
  Invoke-Expression $ConvertToSerializableCode

  It 'passes through nulls' {
    ConvertTo-Serializable $null | Should -Be $null
  }

  It 'can process a simple class instance to a JSON serializable object' {
    class TestClass{
      [string]$StringProperty
      [int]$IntProperty
      [hashtable]$HashProperty
      [float[]]$ArrayProperty
    }

    $TestObject = New-Object TestClass
    $TestObject.StringProperty = 'string property'
    $TestObject.IntProperty = 1
    $TestObject.HashProperty = @{ a = 'a'; b = 'b' }
    $TestObject.ArrayProperty = @(1.0,2.0,3.0,4.0,5.0)

    $Serializable = ConvertTo-Serializable $TestObject

    $Serializable | Should -Not -Be $null
    $Serializable.StringProperty | Should -Be 'string property'
    $Serializable.IntProperty | Should -Be 1
    $Serializable.HashProperty | Should -Not -Be $null

    # Note that this loss is expected - PowerShell serializes hashtables
    # into JSON objects, and all JSON objects back into PSObjects.
    $Serializable.HashProperty.a | Should -Be 'a'
    $Serializable.HashProperty.b | Should -Be 'b'

    # This works fine though.
    $Serializable.ArrayProperty | Should -Not -Be $null
    $Serializable.ArrayProperty.length | Should -Be 5

    $Serializable | ConvertTo-Json | Should -Not -Be $null
  }
}
