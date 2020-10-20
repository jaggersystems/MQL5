#gets the File To Compile as an external parameter... Defaults to a Test file...
Param( $FileToCompile = "C:\Users\Stefan\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\Experts\Test.mq5")

#cleans the terminal screen and sets the log file name...
Clear-Host
$LogFile = $FileToCompile + ".log"

#before continue check if the Compile File has any spaces in it...
if ($FileToCompile.Contains(" ")) {
    "";"";
    Write-Host "ERROR!  Impossible to Compile! Your Filename or Path contains SPACES!" -ForegroundColor Red;
    "";
    Write-Host $FileToCompile -ForegroundColor Red;
    "";"";
    return;
}

#first of all, kill MT Terminal (if running)... otherwise it will not see the new compiled version of the code...
Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Id -gt 0} | Stop-Process

#fires up the Metaeditor compiler...
& "C:\Program Files\MetaTrader 5 Terminal\metaeditor64.exe" /compile:${FileToCompile} /log:"`"$LogFile`"" /inc:"C:\Users\Stefan\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\Experts" | Out-Null

#& "y:\Tmp\MT5-64\metaeditor64.exe" /compile:${FileToCompile} /log:"`"$LogFile`"" /inc:"y:\Tmp\MT5-64\MQL5\" | Out-Null


#get some clean real state and tells the user what is being compiled (just the file name, no path)...
"";"";"";"";""
$JustTheFileName = Split-Path $FileToCompile -Leaf
Write-Host "Compiling........: $JustTheFileName"
""

#reads the log file. Eliminates the blank lines. Skip the first line because it is useless.
$Log = Get-Content -Path $LogFile | Where-Object {$_ -ne ""} | Select-Object -Skip 1

#Green color for successful Compilation. Otherwise (error/warning), Red!
$WhichColor = "Red"
$Log | ForEach-Object { if ($_.Contains("0 error(s), 0 warning(s)")) { $WhichColor="Green" } }

#runs through all the log lines...
$Log | ForEach-Object {
     #ignores the ": information: error generating code" line when ME was successful
     if (-Not $_.Contains("information:")) {
           #common log line... just print it...
           Write-Host $_ -ForegroundColor $WhichColor
     }
}

#get the MT Terminal back if all went well...
if ( $WhichColor -eq "Green") { 
    Start-Sleep -Seconds 3
    & "C:\Program Files\MetaTrader 5 Terminal\terminal64.exe"
}