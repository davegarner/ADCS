<#
        .SYNOPSIS
        Installs the Root (Offline) Certificate Authority role and configures it.
    
        .DESCRIPTION
        Script developed for to install a Root (Offline) Certificate Authority.
        The configuration uses certutil.exe to modify the CA settings.
        Tested on Windows Server 2012R2, Server 2016 and Windows Server 2019.

        .EXAMPLE
        Install-ADCSOfflineCA.ps1 -Company DEMO -DomainURL pki.demo.com -ConfigNC 'CN=Configuration,DC=demo,DC=lab'

        This will install the install and configure the Certificate Authority Service with the CA name "DEMO".
        It will create the PKI folder in the default location ("$env:SystemDrive\PKI").
        The PKI folder contains the Database and paths for AIA and CRL.

        .EXAMPLE
        Install-ADCSOfflineCA.ps1 -Company Contoso -DomainURL pki.contoso.com -ConfigNC 'CN=Configuration,DC=contoso,DC=com' -LocalPKIPath E:\CALocation

        This will install the install and configure the Certificate Authority Service with the CA name "Contoso".
        It will create a folder named PKI in CALocation on the disk E:\.
        The PKI folder contains the Database and paths for AIA and CRL.

            
        .NOTES
        Filename:       Install-ADCSOfflineCA.ps1
        Version:        0.1
        Requirements:   Powershell 4.0 (Module: ServerManager)
        Changelog:      
		
        .LINK
        https://davidgarner.nz
#>
#requires -Version 4.0
[cmdletbinding()]
param (

    # Company name that will belong in the Certificate Authority Name.
    # Example: 'Contoso' will be "Contoso"
    [Parameter(
            Mandatory = $true,
            HelpMessage = "Company name that will belong in the Certificate Authority Name.`nExample: 'Contoso'`n'Contoso' will be 'Contoso'"
    )]
    [string]$Company,

    # URL for CRL and AIA publishing from the Subordinate CA.
    # Example: 'pki.contoso.com'
    [Parameter(
            Mandatory = $true,
            HelpMessage = "Domain URL for CRL and AIA publishing.`nExample: 'pki.contoso.com'"
    )]
    [string]$DomainURL,

    # Active Directory Configuration Naming Context where the Subordinate Certificate Authority will be placed.
    # Example: 'CN=Configuration,DC=contoso,DC=com'
    [Parameter(
            Mandatory = $true,
            HelpMessage = "Active Directory Configuration Naming Context where the Subordinate Certificate Authority will be placed.`nExample: 'CN=Configuration,DC=contoso,DC=com'"
    )]
    [string]$ConfigNC,

    # Local file path to store Certificate Database and Logs. Also used for creating Web directory and fileshare location.
    # Example: 'C:\PKI'
    [Alias('LocalPath')]
    [string]$LocalPKIPath = "$env:SystemDrive\PKI"

)
begin
{
    function Confirm-ToContinue
    {
        $caption = 'Manual Step'  
        $message = 'Are you done with the manual step?'
        [int]$defaultChoice = 1
        $yes = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Done with manual step.'
        $no = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Not done, continue to prompt.'
        $cancel = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Cancel', 'Not done, exit script.'
        $options = [Management.Automation.Host.ChoiceDescription[]]($yes, $no, $cancel)
        
        $do = $true
        do
        {   
            $choice = $Host.ui.PromptForChoice($caption,$message, $options,$defaultChoice)
            switch ($choice)
            {
                0 
                {
                    $do = $false
                }
                1 
                {
                    'Issued: Not done, continue to prompt.'
                    $do = $true
                }
                Default 
                {
                    'Cancel, exiting script.'
                    $do = $false
                    break
                }
            }
        }
        while ($do)
    }

    # Clear all errors    
    $Error.Clear()
}
process
{
    if ($PSCmdlet.ShouldProcess("$($Company)($($DomainURL)) - $($LocalPKIPath)",'Configure Offline CA'))
    {
        #region Create directories
        $certdb  = New-Item -Path "$($LocalPKIPath)\Database\CertDB" -ItemType Directory -Force
        $certlog = New-Item -Path "$($LocalPKIPath)\Database\CertLog" -ItemType Directory -Force
        $null = New-Item -Path "$($LocalPKIPath)\Web" -ItemType Directory -Force
        $crlpath = New-Item -Path "$($LocalPKIPath)\Web\CRL" -ItemType Directory -Force
        $aiapath = New-Item -Path "$($LocalPKIPath)\Web\AIA" -ItemType Directory -Force
        #endregion Create directories

        #region Install Windowsfeature ADCS-Cert-Authority
        try
        {
            $null = Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
        }
        catch
        {
            Write-Warning -Message 'Unable to install Windows Feature ADCS-Cert-Authority'
            Write-Warning -Message "$($_.Exception.Message)"
            return
        }
        #endregion Install Windowsfeature ADCS-Cert-Authority

        #region Generate a CAPolicy.inf file for "$($env:windir)\CAPolicy.inf"
        $capolicy = '[Version]
Signature="$Windows NT$"

[PolicyStatementExtension]
Policies=InternalUseOnly

[Certsrv_Server]
RenewalKeyLength=4096
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=10
CRLPeriod=Years
CRLPeriodUnits=1
CRLDeltaPeriod=Days
CRLDeltaPeriodUnits=0

[BasicConstraintsExtension]
PathLength=1
Critical=Yes

[CRLDistributionPoint]
Empty=True

[AuthorityInformationAccess]
Empty=True'

        $capolicy | Out-File -FilePath "$($env:windir)\capolicy.inf" -Encoding default -Force
        #region Generate a CAPolicy.inf file for "$($env:windir)\CAPolicy.inf"

        #region Install-AdcsCertificationAuthority
        try
        { 
            $null = Install-AdcsCertificationAuthority -CAType StandaloneRootCA `
            -CACommonName "$Company" `
            -CADistinguishedNameSuffix "OU=PKI,O=$Company,C=SE" `
            -KeyLength 4096 `
            -HashAlgorithmName SHA256 `
            -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' `
            -DatabaseDirectory $($certdb.FullName) `
            -LogDirectory $($certlog.FullName) `
            -ValidityPeriod Years `
            -ValidityPeriodUnits 10 `
            -OverwriteExistingKey `
            -WarningAction SilentlyContinue `
            -ErrorAction Stop `
        }
        catch
        {
            Write-Warning -Message 'Unable to Install-AdcsCertificationAuthority -CAType StandaloneRootCA'
            Write-Warning -Message "$($_.Exception.Message)"
            Write-Output -InputObject 'Manual install AdcsCertificationAuthority with the following properties:'
            Write-Output -InputObject "
                -CAType StandaloneRootCA
                -CACommonName '$Company'
                -CADistinguishedNameSuffix 'OU=PKI,O=$Company,C=SE'
                -KeyLength 4096
                -HashAlgorithmName SHA256
                -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider'
                -DatabaseDirectory '$($certdb.FullName)'
                -LogDirectory '$($certlog.FullName)'
                -ValidityPeriod Years
                -ValidityPeriodUnits 10"
            Confirm-ToContinue
        }
        #endregion Install-AdcsCertificationAuthority


        # Declare Configuration and Domain NCs
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\DSConfigDN $ConfigNC

        # Set Validity Period for Issued Certificates (Subordinate) to 5 years
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\ValidityPeriodUnits 5
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\ValidityPeriod 'Years'

        # Define CRL Publication Intervals
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLPeriodUnits 52
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLPeriod 'Weeks'
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLDeltaPeriodUnits 0
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLDeltaPeriod 'Days'
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLOverlapPeriodUnits 12
        $null = & "$env:windir\system32\certutil.exe" -setreg ca\CRLOverlapPeriod 'Hours'

        # Enable CA Audit
        $null = & "$env:windir\system32\certutil.exe" -setreg CA\AuditFilter 127

        #region Remove any CRL Distribution Points
        $crllist = Get-CACrlDistributionPoint -ErrorAction SilentlyContinue
        foreach ($crl in $crllist)
        {
            $null = Remove-CACrlDistributionPoint -Uri $crl.uri -Force -ErrorAction SilentlyContinue
        }
        #endregion Remove any CRL Distribution Points
  

        #region Remove any certificates Authority Information Access
        $aialist = Get-CAAuthorityInformationAccess -ErrorAction SilentlyContinue
        foreach ($aia in $aialist)
        {
            $null = Remove-CAAuthorityInformationAccess -Uri $aia.uri -Force -ErrorAction SilentlyContinue
        }
        #endregion Remove any Authority Information Access certificates

        # Set New correct URLs for CRL and AIA
        $null = & "$env:windir\system32\certutil.exe" -setreg CA\CRLPublicationURLs "1:$($crlpath.FullName)\%3%8.crl\n2:http://$($DomainURL)/CRL/%3%8.crl"
        $null = & "$env:windir\system32\certutil.exe" -setreg CA\CACertPublicationURLs "1:$($aiapath.FullName)\%3%4.crt\n2:http://$($DomainURL)/AIA/%3%4.crt"
        #& "$env:windir\system32\certutil.exe" -getreg ca\CRLDeltaPeriodUnits
        

        Start-Sleep -Seconds 3
        try
        {
            $null = Stop-Service -Name 'certsvc' -Force -ErrorAction Stop -WarningAction SilentlyContinue
        }
        catch
        {
            Write-Warning -Message 'The Certificate Services (certsvc) did not stop correctly.' 
            Write-Output -InputObject 'Please stop the service manually.'
            Confirm-ToContinue
        }
        try
        {
            $null = Start-Service -Name 'certsvc' -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop
        }
        catch
        {
            Write-Warning -Message 'The Certificate Services (certsvc) did not start correctly.' 
            Write-Output -InputObject 'Please start the service manually.'
            Confirm-ToContinue
        }
        
        #region Copy all AIA (Certificates) from the original store to the new AIA-Path
        try
        {
            Copy-Item -Path "$($env:windir)\system32\certsrv\certenroll\*.crt" -Destination $aiapath.FullName -ErrorAction Stop
        }
        catch
        {
            Write-Warning -Message "Unable to Copy-Item $($env:windir)\system32\certsrv\certenroll\*.crt to $($aiapath.FullName)"
            Write-Warning -Message "$($_.Exception.Message)"
            Write-Output -InputObject "Do a manual copy of '($env:windir)\system32\certsrv\certenroll\*.crt' to '$($aiapath.FullName)'"
            Confirm-ToContinue
        }
        #region Copy all AIA (Certificates) from the original store to the new AIA-Path

        #region View all errors
        if ($Error.Count -eq 0)
        {
            Clear-Host
        }
        else
        {
            Write-Output -InputObject 'Errors were deteted while running the script, displaying errors:'
            Start-Sleep -Milliseconds 500
            foreach ($e in $Error)
            {
                "$($e.Exception.Message)"
            }
            Write-Output -InputObject 'Does everything look OK?'
            Confirm-ToContinue
        }
        #region View all errors

        Write-Output -InputObject "`nFinished installing and configuring the Root Certificate Authority."
        Write-Output -InputObject 'The next step is to install the Subordinate Certificate Authority.'
    }
}
end
{
    
}
