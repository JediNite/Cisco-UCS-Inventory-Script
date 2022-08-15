# Cisco UCS Inventory Script
The UCS Inventory Script (UIS) is a PowerTool script that retrieves the full configuration of an UCS Manager (or multiple) and displays it in a very readable and portable HTML file for offline use. It also includes some configuration recommendations that come from experience implementing FlexPods. **Disclaimer**: These recommendations are not official recommendations from Cisco, but taken from experience from the field.

I wrote this script to get an easy overview of UCS installations after completing the initial build. To answer basic questions like “How many port licenses do we have left?” or “Did we create VLAN X?” – when you have no easy connectivity to the management console.

It evolved into a script that gets run periodically to retrieve up to date information and serve as attachment to delivery documents.

This script requires an installed PowerShell and Ciscos PowerTool version 1 or 2, make sure you have them installed and working before you try running the UCS Inventory Script.

## Running the script
You can run the script without arguments; it will ask you for the required input. You can also run the script with the arguments required to run. If you want to run it in a scheduled task, run it with all the arguments.

.\UCS-Inventory-Script.ps1 -UCSM UCS-Cluster-01.cosco.com -OutFile UCS-Cluster-01.html -Username ucsUsername -Password ucsPassword  
* -UCSM: UCS Manager IP address or hostname
* -OutFile: The filename used to output the generated HTML
* -Username: Username used to login to UCS Manager
* -Password: Password used to login to UCS Manager

NOTE: If a UCSM authentication domain is used in your environment, the username provided will be "ucs-<AUTHDOMAIN>\<Username>"

## Multiple UCS Managers
**OR** you can use a CSV file with the information about multiple UCS Managers. The command looks a bit different in that case:

.\UCS-Inventory-Script.ps1 -CSVFile c:\ucs-domains.csv
* -CSVFile: CSV file with info on one or more UCS Manager.

### Storing Passwords in CSV
The password of the UCS Manager login is stored in the CSV in an encrypted format. You can generate that encrypted format by using the **-GeneratePassword** parameter.

```
.\UCS-Inventory-Script.ps1 -GeneratePassword
Please enter your password: MyPassword
Done! Here's your encrypted password, save this in the CSV:
01000000d0verylongstring
```

Take that very long string and put it in the "Encrypted Password" column of the CSV.

### Using Credential Management PowerShell Module
The PowerShell module called "CredentialManagement" allows Credentials to be stored within the Windows Credential Store against the user account that is running the script.
Details on this module are available at https://www.mosaicmk.com/credential-management-module
If you wish to use this facility within the UCS Inventory Script, ensure that the "Encrypted Password" field within the CSVFile is set to "CredentialManagement"
Refer to ucs-domains-uscpecredm.csv for en example of this format.
You will also need to run the following as the user who is running the task to initially add the credentials into the Windows Credential store.
```
Import-Module CredentialManagement
Add-StoredCredentials -UserName "<USERNAME>" -Password '<PASSWORD>' -Target "<TARGET>"
Add-StoredCredentials -UserName "ucspe" -Password 'ucspe' -Target "192.168.1.170"
```

## Emailing the UCS Inventory reports
Email capability has been added to the UCS Inventory Script.
Within the top of the script update the following lines to suit your configuration.
* $smtpServer = "smtpserver" 
* $mailFrom = "Cisco UCS Inventory Script <ucscheck@domain.com>"
* $mailTo = "user@domain.com"
* $OutFilePath = "C:\Scripts\Cisco-UCS-Inventory-Script\"

.\UCS-Inventory-Script.ps1 -CSVFile c:\ucs-domains.csv -SendEmail
* -CSVFile: CSV file with info on one or more UCS Manager.
* -SendEmail: Triggers an Email to be sent once the report has been generated using values stored within the script

## Logging output
If you're using this script in an automated fashion, it might be useful to log the scripts output. You can use the -LogFile parameter for that:

.\UCS-Inventory-Script.ps1 -LogFile c:\uis.log
* -LogFile: Destination log file.

## Example Output
Before you download and run it yourself, you can [check here](http://lostdomain.org/wp-content/uploads/2014/06/UIS-example.html) if this will fit your needs. This example contains the output of a testlab with a simple setup.


If there are any changes you’d like to see, more information or other recommendations. Send me a message and I’ll see what I can do to include it!

## Changelog
```
v1.7 - 15-08-2022 - Added support for the "CredentialManagement" Powershell module https://www.mosaicmk.com/credential-management-module
v1.6 - 17-03-2022 - Added Email capability, Added Package Versions to Firmware releases, Cleaned up use of ConvertTo-Html
v1.3 - 17-04-2016 - Added multiple UCS Manager support via a CSV file and logging to a file.
v1.2 - 30-06-2014 - Added a recommendations tab for configuration and health recommendations,
                    taken from experience in the field.  
v1.1 - 30-12-2013 - Add arguments for the require input data, allow it to run as a scheduled task.  
v1.0 - 25-11-2013 - First version; capture every bit of information from UCS Manager I could think of.
```
