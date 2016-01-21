Add-PSSnapin iControlSnapIn

$script = $MyInvocation.MyCommand.Name
$output_path = "c:\Users\Desktop\"
$output_file="$script-out.txt"
$last_run_file = "$script-out-last-run.txt"
$device = "xxxx"

$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"


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
    $login = Initialize-F5.iControl -Hostname $device -Credentials (Get-Credential -Message "Enter your F5 username and password")
}
Catch [Exception]
{
    Write-host "An Error occurred"
    exit 1;
}

if ($login -ne "True") 
{ 
    Write-host -foregroundcolor Red "[ERROR: 2] Login not correct."
    exit 2;
}

$ErrorActionPreference= 'continue'

# Check to make sure we are on the active device.
$failover_state = Get-F5.DBVariable | Where {$_.Name -eq "Failover.State"} | Select Value

if ($failover_state.Value -ne "active")
{
    Write-Host -ForegroundColor  Red "[ERROR: 3] The device " $device " is currently in state" $failover_state.Value " - please change the device to be the active node and try again."
    exit 3;
}


#Get-F5.iControlCommands

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
    $object | Add-Member -Name 'Difference' -MemberType NoteProperty -Value ([int64]$difference)
    $array += $object   
}

# loop through my new custom array and only get the ones that have increased.


$array | where {$_.PreviousTotalConnections -ne $_.CurrentTotalConnections}
$array | where {$_.PreviousTotalConnections -ne $_.CurrentTotalConnections} | ConvertTo-Html -Head $style > $output_path\$script-differences.html
$array | ConvertTo-Html -Head $style > $output_path\$script-totals.html
