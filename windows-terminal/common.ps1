function Read-TmuxStyleJson([string]$Path) {
    $text=[IO.File]::ReadAllText($Path)
    $clean=[Text.StringBuilder]::new()
    $quoted=$false; $escaped=$false
    for($i=0;$i -lt $text.Length;$i++) {
        $ch=$text[$i]
        if($quoted){
            [void]$clean.Append($ch)
            if($escaped){$escaped=$false} elseif($ch -eq '\'){$escaped=$true} elseif($ch -eq '"'){$quoted=$false}
            continue
        }
        if($ch -eq '"'){$quoted=$true;[void]$clean.Append($ch);continue}
        if($ch -eq '/' -and $i+1 -lt $text.Length){
            if($text[$i+1] -eq '/'){
                while($i -lt $text.Length -and $text[$i] -ne "`n"){$i++}
                [void]$clean.Append("`n");continue
            }
            if($text[$i+1] -eq '*'){
                $i+=2
                while($i+1 -lt $text.Length -and -not($text[$i] -eq '*' -and $text[$i+1] -eq '/')){$i++}
                if($i+1 -ge $text.Length){throw 'Unterminated JSON comment'}
                $i++;[void]$clean.Append(' ');continue
            }
        }
        [void]$clean.Append($ch)
    }
    $text=$clean.ToString();$clean.Clear()|Out-Null;$quoted=$false;$escaped=$false
    for($i=0;$i -lt $text.Length;$i++){
        $ch=$text[$i]
        if($quoted){
            [void]$clean.Append($ch)
            if($escaped){$escaped=$false}elseif($ch -eq '\'){$escaped=$true}elseif($ch -eq '"'){$quoted=$false}
            continue
        }
        if($ch -eq '"'){$quoted=$true}
        if($ch -eq ','){
            $next=$i+1;while($next -lt $text.Length -and [char]::IsWhiteSpace($text[$next])){$next++}
            if($next -lt $text.Length -and $text[$next] -in @('}',']')){continue}
        }
        [void]$clean.Append($ch)
    }
    return ($clean.ToString()|ConvertFrom-Json)
}

function ConvertTo-TmuxStyleCanonical($Value,[string]$Key=''){
    if($null -eq $Value){return 'null'}
    if($Value -is [string]){
        if($Key -eq 'command'){return (ConvertTo-TmuxStyleCanonical ([pscustomobject]@{action=$Value}))}
        if($Value -match '^#[a-fA-F0-9]{6}$'){$Value=$Value.ToLowerInvariant()}
        return (ConvertTo-Json -InputObject $Value -Compress)
    }
    if($Value -is [array]){
        $items=@($Value|ForEach-Object {ConvertTo-TmuxStyleCanonical $_})
        if($Key -in @('actions','keybindings','schemes')){$items=@($items|Sort-Object)}
        return '['+($items -join ',')+']'
    }
    if($Value -is [pscustomobject]){
        $pairs=@($Value.PSObject.Properties|Sort-Object Name|ForEach-Object {
            (ConvertTo-Json -InputObject $_.Name -Compress)+':'+(ConvertTo-TmuxStyleCanonical $_.Value $_.Name)
        })
        return '{'+($pairs -join ',')+'}'
    }
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function Test-TmuxStyleNormalization($Expected,$Actual){
    foreach($property in $Expected.PSObject.Properties){
        $name=$property.Name
        if($name -eq 'profiles'){
            if((ConvertTo-TmuxStyleCanonical $Expected.profiles.defaults) -ne (ConvertTo-TmuxStyleCanonical $Actual.profiles.defaults)){return $false}
            foreach($profile in @($Expected.profiles.list)){
                $match=@($Actual.profiles.list|Where-Object {$_.guid -eq $profile.guid})
                if($match.Count -ne 1 -or (ConvertTo-TmuxStyleCanonical $profile) -ne (ConvertTo-TmuxStyleCanonical $match[0])){return $false}
            }
            $known=@($Expected.profiles.list|ForEach-Object {$_.guid})
            foreach($extra in @($Actual.profiles.list|Where-Object {$_.guid -notin $known})){
                if(-not $extra.source -and $extra.guid -notin @('{61c54bbd-c2c6-5271-96e7-009a87ff44bf}','{0caa0dad-35be-5f56-a8ff-afceeeaa6101}')){return $false}
            }
        }elseif((ConvertTo-TmuxStyleCanonical $property.Value $name) -ne (ConvertTo-TmuxStyleCanonical $Actual.$name $name)){return $false}
    }
    foreach($extra in $Actual.PSObject.Properties|Where-Object {$_.Name -notin @($Expected.PSObject.Properties.Name)}){
        if($extra.Name -eq '$help'){continue}
        if($extra.Name -eq 'themes' -and @($extra.Value).Count -eq 0){continue}
        if($extra.Name -eq 'newTabMenu' -and (ConvertTo-TmuxStyleCanonical $extra.Value) -eq '[{"type":"remainingProfiles"}]'){continue}
        return $false
    }
    return $true
}
