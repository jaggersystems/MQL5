Param( $Keyword )

#Get full path to your chm help file 
$chm_path = "c:/Users/Stefan/AppData/Roaming/MetaQuotes/Terminal/Help/mql5.chm"

if(-not (Get-Process -name keyhh -ErrorAction SilentlyContinue)) {
    # First open empty help window 
    keyHH.exe -MQL $chm_path
    
    # Increase this number if it opens two helps for you
    Start-Sleep -Milliseconds 500
}
# find the requested keyword
keyHH.exe -MQL -#klink "$Keyword" $chm_path