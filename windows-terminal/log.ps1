# A transcript belongs to the PowerShell host in which tmx log start was run.
function global:Start-TmxLogSegment {
    Start-Transcript -LiteralPath $global:TmxLog.Path -UseMinimalHeader -ErrorAction Stop | Out-Null
}

function global:Update-TmxLog {
    param([long]$SegmentBytes=10MB)
    if(-not $global:TmxLog.Active){return}
    $path=$global:TmxLog.Path
    try{
        if((Get-Item -LiteralPath $path -ErrorAction Stop).Length -lt $SegmentBytes){return}
        Stop-Transcript -ErrorAction Stop | Out-Null
        $global:TmxLog.Active=$false
        if(Test-Path -LiteralPath ($path+'.1')){
            Move-Item -LiteralPath ($path+'.1') -Destination ($path+'.2') -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $path -Destination ($path+'.1') -ErrorAction Stop
        Start-TmxLogSegment
        $global:TmxLog.Active=$true
    }catch{
        $global:TmxLog.Active=$false
        Write-Warning 'TMX log rotation stopped. Check the log directory shown by tmx log status.'
    }
}

function global:Invoke-TmxLog([string[]]$Arguments){
    if($Arguments.Count -ne 1 -or $Arguments[0] -notin 'start','stop','status'){
        throw 'Usage: tmx log start|stop|status'
    }
    switch($Arguments[0]){
        'start'{
            if($global:TmxLog.Active){
                "Pane log: active ($($global:TmxLog.Path))"
                return
            }
            $dir=Join-Path ($global:TmuxStyleAssetDirectory.TrimEnd('\','/')+'-logs') ('pane-'+[Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
            $global:TmxLog=@{Path=(Join-Path $dir 'pane.log');Active=$false}
            Start-TmxLogSegment
            $global:TmxLog.Active=$true
            "Pane log started: $($global:TmxLog.Path)"
        }
        'stop'{
            if($global:TmxLog.Active){
                Stop-Transcript -ErrorAction Stop | Out-Null
                $global:TmxLog.Active=$false
                "Pane log stopped: $($global:TmxLog.Path)"
            }else{'Pane log: stopped'}
        }
        'status'{
            if($global:TmxLog.Active){"Pane log: active ($($global:TmxLog.Path))"}
            elseif($global:TmxLog.Path){"Pane log: stopped ($($global:TmxLog.Path))"}
            else{'Pane log: stopped'}
        }
    }
}
