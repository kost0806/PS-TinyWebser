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
function global:ConvertFrom-PS2 {
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
            80 <# P #> {
                if ($State -eq $StateEnum."<") {
                    $State = $StateEnum."<P"
                    $Buffer += $iChar
                }
                else {
                    ToPlainState -State ([Ref] $State) -Fragment ([Ref] $Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
                }
            }
            83 <# S #> {
                if ($State -eq $StateEnum."<P") {
                    $State = $StateEnum."<PS"
                    $Buffer += $iChar
                }
                else {
                    ToPlainState -State ([Ref] $State) -Fragment ([Ref] $Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
                }
            }
            62 <# > #> {
                if ($State -eq $StateEnum."<PS") {
                    $State = $StateEnum."Plain"
                    if ($IsCloseTag) { # if </PS>
                        $Fragments += @{
                            Type = "Code"
                            Content = $Fragment
                        }
                        $IsCloseTag = $False
                        Remove-Variable $Fragment
                        $Fragment = @()
                    }
                    else { # <PS>
                        $Fragments += @{
                            Type = "Plain"
                            Content = $Fragment
                        }
                        Remove-Variable $Fragment
                        $Fragment = @()
                    }
                }
                else {
                    ToPlainState -State ([Ref] $State) -Fragment ([Ref] $Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
                }
                
            }
            47 <# / #> {
                if ($State -eq $StateEnum."<") {
                    $IsCloseTag = $True
                    $Buffer += $iChar
                }
                else {
                    ToPlainState -State ([Ref] $State) -Fragment ([Ref] $Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
                }
            }
            default {
                ToPlainState -State ([Ref] $State) -Fragment ([Ref] $Fragment) -Buffer ([Ref] $Buffer) -CharCode $iChar -IsCloseTag ([Ref] $IsCloseTag)
            }
        }
    }
    if ($Fragment) {
        $Fragments += @{
            Type = "Plain"
            Content = $Fragment
        }
    }
    $Ret = @()
    $Fragments | ForEach-Object {
        if ($_.Content.Length -gt 0) {
            if ($_.Type -eq "Plain") {
                $Ret += $_.Content
            }
            else {
                $Encoding = [Text.Encoding]::GetEncoding($ENV["Encoding"])
                $DecodedContent = $Encoding.GetChars($_.Content) -join ""
                $EvaluatedContent = Invoke-Expression $DecodedContent
                if ($EvaluatedContent.length -gt 0) {
                    $Ret += $Encoding.GetByptes($EvaluatedContent)
                }
            }
        }
    }

    $Ret
}

function global:ConvertFrom-PS {
    param (
        [Parameter(Mandatory = $True)]
        $Content
    )

    $Length = $Content.Length
    $Fragment = [Array]::CreateInstance("Byte", $Length)
    $Fragments = @()

    $IsCode = $false
    $Idx = 0
    $FragIdx = 0
    while ($Idx -lt ($Length - 4)) {
        if ($Content[$Idx] -eq 60) { # <
            if ($IsCode) {
                if ($Content[$Idx + 1] -eq 47) {# /
                    if ($Content[$Idx + 2] -eq 112 -or $Content[$Idx + 2] -eq 80) { # p
                        if ($Content[$Idx + 3] -eq 115 -or $Content[$Idx + 3] -eq 83) { #s
                            if ($Content[$Idx + 4] -eq 62) { # >
                                $IsCode = $False                                
                                if ($FragIdx -gt 1) {
                                    $Fragments += @{
                                        Type = "Code"
                                        Content = $Fragment[0..($FregIdx - 1)]
                                    }
                                }
                                elseif ($FragIdx -eq 1) {
                                    $Fragments += @{
                                        Type = "Code"
                                        Content = $Fragment[0]
                                    }
                                }
                                $Idx += 4
                                $FragIdx = 0
                            }
                            else {
                                $Fragment[$FragIdx++] = $Content[$Idx]
                            }
                        }
                        else {
                            $Fragment[$FragIdx++] = $Content[$Idx]
                        }
                    }
                    else {
                        $Fragment[$FragIdx++] = $Content[$Idx]
                    }
                }
                else {
                    $Fragment[$FragIdx++] = $Content[$Idx]
                }
            }
            else {
                if ($Content[$Idx + 2] -eq 112 -or $Content[$Idx + 2] -eq 80) { # p
                    if ($Content[$Idx + 3] -eq 115 -or $Content[$Idx + 3] -eq 83) { #s
                        if ($Content[$Idx + 4] -eq 62) { # >
                            $IsCode = $True                                
                            if ($FragIdx -gt 1) {
                                $Fragments += @{
                                    Type = "Code"
                                    Content = $Fragment[0..($FregIdx - 1)]
                                }
                            }
                            elseif ($FragIdx -eq 1) {
                                $Fragments += @{
                                    Type = "Code"
                                    Content = $Fragment[0]
                                }
                            }
                            $Idx += 3
                            $FragIdx = 0
                        }
                        else {
                            $Fragment[$FragIdx++] = $Content[$Idx]
                        }
                    }
                    else {
                        $Fragment[$FragIdx++] = $Content[$Idx]
                    }
                }
                else {
                    $Fragment[$FragIdx++] = $Content[$Idx]
                }
            }
        }
        else {
            $Fragment[$FragIdx++] = $Content[$Idx]
        }
        ++$Idx
    }
    while ($Idx -lt $Length) {
        $Fragment[$FragIdx++] = $Content[$Idx++]
    }
    if ($Fragment) {
        $Fragments += @{
            Type = "Plain"
            Content = $Fragment[0..($FragIdx - 1)]
        }
    }
    $Ret = ()
    $Fragments | ForEach-Object {
        if ($_.Content.Length -gt 0) {
            if ($_.Type -eq "Plain") {
                $Ret += $_.Content
            }
            else {
                $Encoding = [Text.Encoding]::GetEncoding($ENV["Encoding"])
                $DecodedContent = $Encoding.GetChars($_.Content) -join ""
                $EvaluatedContent = Invoke-Expression $DecodedContent
                if ($EvaluatedContent.Length -gt 0) {
                    $Ret += $Encoding.GetBytes($EvaluatedContent)
                }
            }
        }
    }

    $Ret
}

function Write-Log {
    param (
        $LogPath,
        $Content,

        # Level
        [Switch]
        $Info,
        [Switch]
        $Error,
        [Switch]
        $Crit,
        [Switch]
        $Debug
    )

    if (-not $LogPath) {
        if ($Global:LogPath) {
            $LogPath = $Global:LogPath
        }
        else {
            throw "LogPath Required"
        }        
    }

    if ($Error) {
        $Level = "Error"
    }
    elseif ($Crit) {
        $Level = "Crit"
    }
    elseif ($Debug) {
        $Level = "Debug"
    }
    else {
        $Level = "Info"
    }

    try {
        $File = Get-Item $LogPath -ErrorAction Stop
    } catch {
        $File = New-Item -Path $LogPath -Type File
    }

    $LogText = $("[{0}] [{1}] {2}" -f $Level, `
        $($(Get-Data -UFormat "%Y-%m-%d %H:%M:%S") + (([String]([Math]::Round([Double](Get-Date -UFormat ^s) % 1, 4)))[1..4] -join "")), `
        $Content)
    $fw = $File.AppendText()
    $fw.WriteLine($LogText)
    $fw.Close()
    if ($ENV.LogByPass -eq "True") {
        Write-Host $LogText
    }
}

function Get-Query {
    Param (
        [Parameter(Mandatory = $True)]
        [String]
        $Query <# ?<Key>=<Value>[&<Key>=<Value>] #>
    )

    $Querys = $Query.Split("&")
    $Hashtable = @{}
    $Querys | ForEach-Object {
        $Pair = $_ -split "="
        $Hashtable[$Pair[0]] = $Pair[1]
    }

    return $Hashtable
}

<# Custom Mime Mapping #>
$CONTENT_TYPE = @{
    ".js" = "text/javascript"
    ".ps1xml" = "text/html"
}
function Get-ContentType {
    param (
        $FileName
    )

    $Extension = "." + ($FileName -split "\.")[-1]
    try {
        $Reg = (Get-Item ("Registry::HKEY_CLASSES_ROOT\" + $Extension) -ErrorAction Stop)
        $ContentType = $Reg.GetValue("Content Type")
    }
    catch {}

    if (-not $ContentType) {
        if ($CONTENT_TYPE[$Extension]) {
            $ContentType = $CONTENT_TYPE[$Extension]
        }
        else {
            $ContentType = "text/plain"
        }
    }

    return $ContentType
}

