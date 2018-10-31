try {
    Remove-Module Functions -ErrorAction Stop
    Import-Module -Global .\Functions.psm1
} catch {
    Import-Module -Global .\Functions.psm1
}

try {
    Remove-Module DBModule -ErrorAction Stop
    Import-Module -Global .\..\DB\sbin\DBModule.psm1
} catch {
    Import-Module -Global .\..\DB\sbin\DBModule.psm1
}

<#
Description : ps1xml parser
#>
function global:ConvertFrom-PS {
    param (
        [Parameter(Mandatory = $True)]
        $Content
    )
    
    <# For Reduce duplicateed Code #>
    function ToPlainState {
        param (
            [Ref]
            $State,

            [Ref]
            $Fragment,

            [Ref]
            $Buffer,

            [Ref]
            $IsCloseTag,

            $CharCode
        )

        $State.Value = $StateEnum."Plain"
        if($Buffer.Value.Length -gt 0) {
            $Fragment.Value += $Buffer.Value
            $Buffer.Value = @()
        }
        $Fragment.Value += $CharCode
        $IsCloseTag.Value = $False
    }

    $Fragment = @() # Temporary Variable to store byte array of code or plain stream
    $Fragments = @() # Fragmanet Hashtable @(@{Type(Plain, Code) ; Content}, ...)
    $Buffer = @()

    $StateEnum = @{
        "<" = 0
        "<P" = 1
        "<PS" = 2
        "</" = 4
        "</P" = 5
        "</PS" = 6
        "<Plain" = 8
    }
    $State = $StateEnum."Plain"
    $IsCloseTag = $false
    $ContentStream = $Content.GetEnumerator()
    $ContentStream | ForEach {
        # Handleing lower clse
        $iChar = $_
        switch ($_) {
            112 <# p #> {
                $cChar = [Byte]80
            }
            115 <# s #> {
                $cChar = [Byte]83
            }
            default {
                $cChar = $_
            }
        }

        # Start State Machine
        switch ($cChar) {
            60 <# < #> {
                if ($State -eq $StateEnum."Plain") {
                    $State = $StateEnum."<"
                    $Buffer += $iChar
                }
                else {
                    ToPlainState -State ([Ref] $State) -Fragment ([Ref]$Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
                }
            }
        }
    }

    
}

