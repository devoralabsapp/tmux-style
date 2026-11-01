# Color only the final terminal renderer. Objects flowing between commands
# retain their types, properties and values; existing ANSI output is preserved.
function global:Write-TmxPrismLine {
    param([AllowEmptyString()][string]$Line)
    if($Line.Contains([string][char]27)){Write-Host $Line;return}
    $pattern='(?<error>\b(?:error|failed|failure|fatal|denied|exception)\b)|(?<good>\b(?:ok|success|passed|true|enabled|running)\b)|(?<warning>\b(?:warning|warn|false|disabled|pending)\b)|(?<path>(?:[a-zA-Z]:[\\/]|\.{0,2}/|~/)[^\s]+)|(?<quote>"[^"\r\n]*"|''[^''\r\n]*'')|(?<number>\b\d+(?:[.:/%-]\d+)*%?\b)|(?<flag>(?<!\w)--?[a-zA-Z][\w-]*)'
    $colors=@{error='Red';good='Green';warning='Yellow';path='Cyan';quote='Magenta';number='Yellow';flag='Blue'}
    $at=0
    foreach($match in [regex]::Matches($Line,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)){
        if($match.Index -gt $at){Write-Host -NoNewline $Line.Substring($at,$match.Index-$at) -ForegroundColor Gray}
        $color='Gray'
        foreach($name in $colors.Keys){if($match.Groups[$name].Success){$color=$colors[$name];break}}
        Write-Host -NoNewline $match.Value -ForegroundColor $color
        $at=$match.Index+$match.Length
    }
    if($at -lt $Line.Length){Write-Host -NoNewline $Line.Substring($at) -ForegroundColor Gray}
    Write-Host ''
}
if(-not $global:TmxOutputInstalled -and -not(Get-Command Out-Default -CommandType Function -ErrorAction SilentlyContinue)){
    function global:Out-Default {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)][AllowNull()][psobject]$InputObject,[switch]$Transcript)
        begin{
            $savedExit=$global:LASTEXITCODE
            if($global:TmuxStyleTheme -eq 'prism' -and -not $Transcript){
                $width=120
                try{$width=[Math]::Max(20,$Host.UI.RawUI.WindowSize.Width)}catch{}
                $pipe={Microsoft.PowerShell.Utility\Out-String -Stream -Width $width | ForEach-Object {Write-TmxPrismLine $_}}.GetSteppablePipeline($MyInvocation.CommandOrigin)
            }else{
                $pipe={Microsoft.PowerShell.Core\Out-Default -Transcript:$Transcript}.GetSteppablePipeline($MyInvocation.CommandOrigin)
            }
            $pipe.Begin($PSCmdlet)
        }
        process{$pipe.Process($InputObject)}
        end{try{$pipe.End()}finally{$global:LASTEXITCODE=$savedExit}}
    }
    $global:TmxOutputInstalled=$true
}
