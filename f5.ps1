Add-PSSnapin iControlSnapIn

$script = $MyInvocation.MyCommand.Name
$output_path = "c:\Users\\Desktop\f5\"
$config_file = "$output_path\f5.config"
$logfile = "$output_path\$script.log"
$logflag = "silent"
$username = ""
$password = ""


import-module $output_path\logger.psm1

# define this as an arraylist so that items can be removed from it (i.e. it's not fixed length)
[System.Collections.ArrayList]$device_list = Get-Content $config_file

#work through the list assessing the failover status of each device
# This creates an array of only the active devices.
# While I could create a $devicelogin for each device, it's easier just to use the current credentials and re-authenticate

$active_device = @()
foreach ($device in $device_list)
{
    # log in to the device
    $login = Initialize-F5.iControl -ErrorAction SilentlyContinue -Hostname $device -Username $username -Password $password
    if ( $login -ne "True" )
    {
        Write-host "An Error occurred while authenticating to $device"
        logger "$logfile" "$logflag" "ERROR" "$device Authentication Error"       
    }
 
    # Check to make sure we are on the active device.  
    $failover_state = Get-F5.DBVariable | Where {$_.Name -eq "Failover.State"} | Select Value

    if ($failover_state.Value -eq "active")
    {
        $active_device+=$device
        write-host -ForegroundColor DarkGreen $device "is currently active."
        logger "$logfile" "$logflag" "INFO" "$device is currently active."
    }
    else
    {
        write-host -ForegroundColor Red $device "is not currently active."
        logger "$logfile" "$logflag" "INFO" "$device is not currently active."
    }
} #end of foreach loop


$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"


echo "<HTML>" > $output_path\index.html
foreach ($device in $active_device)
{
    Write-host -ForegroundColor Yellow Processing $device
    logger "$logfile" "$logflag" "INFO" "$device Processing Begin."
    $output_file="$script-$device-out.txt"
    $last_run_file = "$script-$device-out-last-run.txt"

    if ( Test-Path -Path $output_path\$last_run_file )
    {
        write-host "Removing Previous Last run."
        Remove-Item $output_path\$last_run_file
    }

    if ( Test-Path $output_path\$output_file )
    {
        write-host "Renaming current run to previous run"
        Rename-Item $output_path\$output_file $output_path\$last_run_file
    }

    $ErrorActionPreference= 'silentlycontinue'
    Try
    {
        #$login = Initialize-F5.iControl -Hostname $device -Username "asdasdas" -Password "asdsadas"
        $login = Initialize-F5.iControl -Hostname $device -Username $username -Password $password
        #$login = Initialize-F5.iControl -Hostname $device -Credentials (Get-Credential -Message "Enter your F5 username and password")
    }
    Catch [Exception]
    {
        Write-host "An Error occurred"
        exit 1;
    }

    if ($login -ne "True") 
    { 
        Write-host -foregroundcolor Red "[ERROR: 2] $device Login not correct."
        logger "$logfile" "$logflag" "ERROR" "$device Login not correct."
        exit 2;
    }

    $ErrorActionPreference= 'continue'


    # Check to make sure we are on the active device.
    # this should not be necessary as we have an array of only active devices
    $failover_state = Get-F5.DBVariable | Where {$_.Name -eq "Failover.State"} | Select Value

    if ($failover_state.Value -ne "active")
    {
        Write-Host -ForegroundColor  Red "[ERROR: 3] The device " $device " is currently in state" $failover_state.Value " - please change the device to be the active node and try again."
        exit 3;
    }


    $virtuals = Get-F5.LTMVirtualServer

    write-host $virtuals.count " virtual servers need to be processed."

    $ic = Get-F5.iControl
    #Set script to top level folder so that enumerated folders are from the root.
    $ic.SystemSession.set_active_folder("/")

    # Get the active number of partitions on the device.
    #Split these in to an array so that each is individually addressable
    #$partitions_array[1] is the second element

    $partitions = $ic.ManagementFolder.get_list()

    # Open a file and write a header in to the file.
    # header is important when we later use import-csv to import directly to an array.
    $file = New-Object System.IO.StreamWriter $output_path\$output_file
    $file.WriteLine("VIP,IP,PORT,STATISTIC,VALUE")

    foreach ($element in $partitions)
    {
        write-host "Processing Partition: " $element 
        $ic.SystemSession.set_active_folder($element)
        $virtual_servers = Get-F5.LTMVirtualServer
        foreach ($item in $virtual_servers)
        {
            if ($virtual_servers.count -ne 0) 
            {
                $virtual_servers_statistics = Get-F5.LTMVirtualServerStatistics $item.Name
                if ( $output )
                {
                    write-host $item.Name `n`t $virtual_servers_statistics.Statistics[10].Type $virtual_servers_statistics.Statistics[10].Value
                }
                $virt_address = $ic.LocalLBVirtualServer.get_destination($item.name)
                $file.WriteLine($item.Name + "," + $virt_address[0].address + "," + $virt_address.port + "," + $virtual_servers_statistics.Statistics[10].Type + "," + $virtual_servers_statistics.Statistics[10].Value)
                write-host -nonewline "."                
            } #end of if statement           
        } #end of foreach loop virtual_servers
        write-host
    }

    $file.Close();

    #import the last run date and the current run then produce an array of the differences.

    if ( Test-Path -Path $output_path\$last_run_file )
    {
        $last_run = import-csv $output_path\$last_run_file
    }
    $current_run = import-csv $output_path\$output_file

#if ( Test-Path $output_path\$last_run_file )
#{
#    $differences = Compare-Object $current_run $last_run -Property VIP, VALUE | Where-Object {$_.SideIndicator -eq '=>'} 
#    $differences  | Select VIP, VALUE
#    write-host
#    Write-Host "There are " $differences.count " differences"
#}


    # create a custom object that can be added to an array with current and previous values.
    # much neater way of doing this because it means that I can use a custom object to contain only the values I need.
    Write-Host "Building object table."
    $array = @()
    foreach ($item in $last_run)
    {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -Name 'VIP' -MemberType NoteProperty -Value $item.VIP
        $object | Add-Member -Name 'IP' -MemberType NoteProperty -Value $item.IP
        $object | Add-Member -Name 'PORT' -MemberType NoteProperty -Value ([int64]$item.PORT)
        $object | Add-Member -Name 'PreviousTotalConnections' -MemberType NoteProperty -Value ([int64]$item.VALUE)
        $current_value = $current_run | where {$_.VIP -eq $item.VIP} | select VALUE
        $object | Add-Member -Name 'CurrentTotalConnections' -MemberType NoteProperty -Value ([int64]$current_value.VALUE)
        $difference = $object.CurrentTotalConnections - $object.PreviousTotalConnections
        if ( $difference -lt 0 )
        {
            $object | Add-Member -Name 'Difference' -MemberType NoteProperty -Value "N/A"
        }
        else
        {
            $object | Add-Member -Name 'Difference' -MemberType NoteProperty -Value ([int64]$difference)
        }
        $array += $object   
    }

    # loop through my new custom array and only get the ones that have increased.
    Write-Host "Writing HTML files."
    $array | where {$_.PreviousTotalConnections -ne $_.CurrentTotalConnections} | ConvertTo-Html -Head $style > $output_path\$script-$device-differences.html
    $array | ConvertTo-Html -Head $style > $output_path\$script-$device-totals.html

    Write-host -ForegroundColor Yellow Completed Processing $device
    write-host "--------------------------------------------------------"
    echo "<a href=$script-$device-totals.html target=""iframe"">$device</a><br>" >> $output_path\index.html
    logger "$logfile" "$logflag" "INFO" "$device Processing End."
} #end device foreach
echo "<iframe name=""iframe"" width=2000 height=4000 frameborder=0></iframe>" >> $output_path\index.html

