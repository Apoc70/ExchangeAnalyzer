#requires -Modules ExchangeAnalyzer

#This function verifies the Active Directory Domain level is at the correct level
Function Run-AD001()
{
    [CmdletBinding()]
    param()

    $TestID = "AD001"
    Write-Verbose "----- Starting test $TestID"

    $PassedList = @()
    $FailedList = @()
    $ErrorList = @()

    # Domain Check - Current Forest
    $Domains = @()
    $Forest = @()
    # 2016-04-29 try/catch added to smoothen test, Thomas Stensitzki
    try { $Domains = @((get-adforest ).domains) }
    catch {$Domains = @()}
    try { $Forest = @((get-adforest).name) }
    catch { $Forest = @() }
    $AllDomains = $domains
    $AllForests = $forest

    Write-Verbose "$($domains.count) domain(s) found."

    # Check for other forest domains (via trusts)
    If($? -and $Domains -ne $Null) {
        Write-Verbose "Checking for domain trusts to other forests."
        ForEach($Domain in $Domains) { 
            # Get list of AD Domain Trusts in each domain
            $ADDomainTrusts = Get-ADObject -Filter {ObjectClass -eq "trustedDomain"} -Server $Domain -Properties * -EA 0
            If($? -and $ADDomainTrusts -ne $Null) {
                Write-Verbose "Domain trusts found."
                If($ADDomainTrusts -is [array]) {
                    [int]$ADDomainTrustsCount = $ADDomainTrusts.Count 
                } Else {
                    [int]$ADDomainTrustsCount = 1
                }
                ForEach($Trust in $ADDomainTrusts) { 
                    [string]$TrustName = $Trust.Name
                    If ($TrustName -ne $Forests) {
                        $TrustAttributesNumber = $Trust.TrustAttributes
                        if (($TrustAttributesNumber -eq "8")) {
                            $newdomains = (get-adforest $trustname).domains
                            $newforest = (get-adforest $trustname).name
                            $alldomains += $newdomains
                            $allforests += $newforest
                        }
                    }
                }
            }
            else
            {
                Write-Verbose "No domain trusts found."
            }
        }
    }
    else
    {
        Write-Verbose "An error occurred or no domains were found."
    }

    #Determine newest and oldest Exchange versions in the org and set min/max functional levels
    #based on supportability matrix: https://technet.microsoft.com/library/ff728623(v=exchg.150).aspx

    $ExchangeVersions = @{
                        Newest = ($ExchangeServers | Sort AdminDisplayVersion -Descending)[0].AdminDisplayVersion
                        Oldest = ($ExchangeServers | Sort AdminDisplayVersion -Descending)[-1].AdminDisplayVersion
                        }

    if ($ExchangeVersions.Newest -like "Version 15.1*")
    {
        $MinFunctionalLevel = 3
        $MinFunctionalLevelText = "Windows Server 2008"
    }
    else
    {
        $MinFunctionalLevel = 2
        $MinFunctionalLevelText = "Windows Server 2003"
    }

    if ($ExchangeVersions.Oldest -like "Version 8.0*")
    {
        $MaxFunctionalLevel = 5
        $MaxFunctionalLevelText = "Windows Server 2012"
    }
    else
    {
        $MaxFunctionalLevel = 6
        $MaxFunctionalLevelText = "Windows Server 2012 R2"
    }

    Write-Verbose "The Domain Functional level must be:"
    Write-Verbose " - Minimum: $MinFunctionalLevelText"
    Write-Verbose " - Maximum: $MaxFunctionalLevelText"

    foreach ($domain in $alldomains)
    {
        $pdc = (get-addomain $domain).pdcemulator
        Write-Verbose "Using PDCE $pdc"
        $dse = ([ADSI] "LDAP://$pdc/RootDSE")
        $dlevel = $dse.domainFunctionality
        #$flevel = $dse.forestFunctionality

        switch ($dlevel)
        {
            2 {$dleveltext = "Windows Server 2003"}
            3 {$dleveltext = "Windows Server 2008"}
            4 {$dleveltext = "Windows Server 2008 R2"}
            5 {$dleveltext = "Windows Server 2012"}
            6 {$dleveltext = "Windows Server 2012 R2"}
        }

        if ($dlevel -ge $MinFunctionalLevel -and $dlevel -le $MaxFunctionalLevel)
        {
            $PassedList += "$($domain) ($dleveltext)"
        }
        else
        {
            $FailedList += "$($domain) ($dleveltext)"
        }
    }

    #Roll the object to be returned to the results
    $ReportObj = Get-TestResultObject -ExchangeAnalyzerTests $ExchangeAnalyzerTests `
                                      -TestId $TestID `
                                      -PassedList $PassedList `
                                      -FailedList $FailedList `
                                      -ErrorList $ErrorList `
                                      -Verbose:($PSBoundParameters['Verbose'] -eq $true)

    return $ReportObj
}

Run-AD001