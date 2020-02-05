[CmdletBinding()]
param()

Set-StrictMode -Version 3.0

Trace-VstsEnteringInvocation $MyInvocation
try {
    . "$PSScriptRoot\Helpers.ps1"

    $sourcesDirectory = Get-VstsInput -Name sourcesDirectory -Require
    $testAssembly = Get-VstsInput -Name testAssembly -Require
    $testAdditionalCommandLine = Get-VstsInput -Name testAdditionalCommandLine
    $dotCoverAdditionalCommandLine = Get-VstsInput -Name dotCoverAdditionalCommandLine
    $testAdapterPath = Get-VstsInput -Name testAdapterPath
    $dotCoverFilters = Get-VstsInput -Name dotCoverFilters
    $testFilterCriteria = Get-VstsInput -Name testFiltercriteria
    $disableCodeCoverage = Get-VstsInput -Name disableCodeCoverage -Default $false -AsBool
    $vstestLocationMethod = Get-VstsInput -Name vstestLocationMethod -Default version
    $vsTestVersion = Get-VstsInput -Name vsTestVersion -Default latest
    $vstestLocation = Get-VstsInput -Name vstestLocation
    $runTitle = Get-VstsInput -Name testRunTitle
    $configuration = Get-VstsInput -Name configuration
    $platform = Get-VstsInput -Name platform
    $publishRunAttachments = Get-VstsInput -Name publishRunAttachments -Default $false -AsBool
    $toolsLocationMethod = Get-VstsInput -Name toolsLocationMethod
    $toolsBaseDirectory = Get-VstsInput -Name toolsBaseDirectory
    $enableDotCoverLog = Get-VstsInput -Name enableDotCoverLog -Default $false -AsBool
    $nunit3MultiAssemblyWorkAround = Get-VstsInput -Name nunit3MultiAssemblyWorkAround -Default $false -AsBool
    $runSettingsFile = Get-VstsInput -Name runSettingsFile
    $testSeriesInfo = Get-VstsInput -Name testSeriesInfo

    Write-Verbose "SourcesDirectory: $sourcesDirectory"
    Write-Verbose "testAssembly: $testAssembly"
    Write-Verbose "testAdditionalCommandLine: $testAdditionalCommandLine"
    Write-Verbose "dotCoverAdditionalCommandLine: $dotCoverAdditionalCommandLine"
    Write-Verbose "testAdapterPath: $testAdapterPath"
    Write-Verbose "dotCoverFilters: $dotCoverFilters"
    Write-Verbose "testFilterCriteria: $testFilterCriteria"
    Write-Verbose "disableCodeCoverage: $disableCodeCoverage"
    Write-Verbose "vstestLocationMethod: $vstestLocationMethod"
    Write-Verbose "vsTestVersion: $vsTestVersion"
    Write-Verbose "vstestLocation: $vstestLocation"
    Write-Verbose "runTitle: $runTitle"
    Write-Verbose "configuration: $configuration"
    Write-Verbose "platform: $platform"
    Write-Verbose "publishRunAttachments: $publishRunAttachments"
    Write-Verbose "runSettingsFile: $runSettingsFile"
    Write-Verbose "toolsLocationMethod: $toolsLocationMethod"
    Write-Verbose "toolsBaseDirectory: $toolsBaseDirectory"
    Write-Verbose "enableDotCoverLog: $enableDotCoverLog"
    Write-Verbose "nunit3MultiAssemblyWorkAround: $nunit3MultiAssemblyWorkAround"

    if ($toolsLocationMethod -and $toolsLocationMethod -eq "location") {
        if (-Not (Test-Path $toolsBaseDirectory)) {
            throw "Specified tools base directory '$toolsBaseDirectory' does not exist."
        }
    } elseif ($toolsLocationMethod -and $toolsLocationMethod -eq "nuget") {
        DownloadTool "JetBrains.dotCover.CommandLineTools" "dotCover.exe"
        DownloadTool "ReportGenerator" "ReportGenerator.exe"
        $toolsBaseDirectory = $Env:AGENT_TOOLSDIRECTORY
    } else {
        $toolsBaseDirectory = $null
    }

    $vsTestCommand = $null
    if ($vstestLocationMethod -and $vstestLocationMethod -eq "location") {
        Write-Verbose "Using specified VSTest location: $vstestLocation"
        if ([String]::IsNullOrWhiteSpace($vstestLocation)) {
            throw "Invalid location specified '$vstestLocation'."
        }
        $vsTestCommand = $vstestLocation.Trim()
        if (-not($vsTestCommand.EndsWith("vstest.console.exe", [System.StringComparison]::OrdinalIgnoreCase))) {
            $vsTestCommand = [System.IO.Path]::Combine($vstestCommand, "vstest.console.exe")
        }
        if (-Not (Test-Path $vstestLocation)) {
            throw "Specified VSTest '$vstestLocation' does not exist."
        }
        $vsTestCommand = $vstestLocation
    } elseif ($vsTestVersion) {
        Write-Host "Using specified VSTest version: $vsTestVersion"
        if ($vsTestVersion -eq "14.0") {
            $vs14Path = Get-VsVersionFolder -Version $vsTestVersion
            if (!$vs14Path) {
                throw "Specified Visual Studio Version $vsTestVersion is not installed or cannot be found."
            }
            $vsTestCommand = Get-VSTestConsolePath -Path $vs14Path
        } elseif ($vsTestVersion -eq "15.x") {
            $vs15 = Get-InstalledVisualStudioInfo 15
            if ($vs15 -and $vs15.Path) {
                $vsTestCommand = Get-VSTestConsolePath -Path $vs15.Path
            }
        } elseif ($vsTestVersion -eq "tools") {
            Write-Host "Looking for VSTest binary in $Env:AGENT_TOOLSDIRECTORY"
            $vsTestCommand = FindCommand $Env:AGENT_TOOLSDIRECTORY "vstest.console.exe"
        }

        if (!$vsTestCommand) {
            # Nothing found, fallback to latest
            $vsPath = Get-LatestVsVersionFolder
            Write-Host "Latest VS Version in $vsPath"
            if (!$vsPath) {
                throw "Specified version '$vsTestVersion' not found. Couldn't find any installed Visual Studio version."
            }
            $vsTestCommand = Get-VSTestConsolePath -Path $vsPath
        }
    }

    if ($runSettingsFile) {
        # tasks.json/runSettingsFile is of type filePath, which (as it looks) defaults to "$(build.SourcesDirectory)"
        # Make sure that we don't provide a directory-name as runSettings to VSTest; that makes it exit with an error.
        if(CheckIfDirectory $runSettingsFile -Or -Not(CheckIfRunsettings $runSettingsFile)) {
            Write-Verbose "Ignoring bogus run settings file: $runSettingsFile"
            $runSettingsFile = $null
        }
    }

    . $PSScriptRoot\RunDotCover.ps1 `
        -sourcesDirectory $sourcesDirectory `
        -testAssembly $testAssembly `
        -testAdditionalCommandLine $testAdditionalCommandLine `
        -dotCoverAdditionalCommandLine $dotCoverAdditionalCommandLine `
        -testAdapterPath $testAdapterPath `
        -dotCoverFilters $dotCoverFilters `
        -testFilterCriteria $testFilterCriteria `
        -disableCodeCoverage:$disableCodeCoverage `
        -vsTestCommand $vsTestCommand `
        -runTitle $runTitle `
        -configuration $configuration `
        -platform $platform `
        -publishRunAttachments:$publishRunAttachments `
        -taskMode `
        -toolsBaseDirectory $toolsBaseDirectory `
        -enableDotCoverLog:$enableDotCoverLog `
        -nunit3MultiAssemblyWorkAround:$nunit3MultiAssemblyWorkAround `
        -runSettingsFile $runSettingsFile `
        -testSeriesInfo $testSeriesInfo

} catch {

    Write-Host "----------------------------------------------------------------------------"
    $_ | format-list * -Force
    Write-Host "----------------------------------------------------------------------------"
    
    throw $_

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}