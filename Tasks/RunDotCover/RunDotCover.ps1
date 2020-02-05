#
# RunDotCover.ps1 - Core script called by RunDotCoverTask.ps1,
# but can also be called directly from a PowerShell build task.
#

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string]$sourcesDirectory,
    [Parameter(Mandatory=$true)][string]$testAssembly,
    [switch]$disableCodeCoverage,
    [string]$runTitle,
    [string]$platform,
    [string]$configuration,
    [string]$testAdapterPath,
    [string]$testFiltercriteria="",
    [string]$testAdditionalCommandLine,
    [string]$dotCoverAdditionalCommandLine,
    [string]$dotCoverFilters="+[*]*",
    [string]$vsTestCommand,
    [switch]$publishRunAttachments,
    [switch]$taskMode,
    [string]$toolsBaseDirectory,
    [switch]$enableDotCoverLog,
    [switch]$nunit3MultiAssemblyWorkAround,
    [string]$runSettingsFile,
    [string]$testSeriesInfo
)

Trace-VstsEnteringInvocation $MyInvocation
Set-StrictMode -Version 3.0

$ErrorActionPreference = 'Stop'

Write-Verbose "Running task: $taskMode"

if (!$taskMode) {
    Import-Module "$PSScriptRoot\ps_modules\VstsTaskSdk"
}

function SendCommand($commandName, $properties, $data) {
    $command = '##vso['
    $command += $commandName

    $first = $true
    if ($properties -and $properties.Count -gt 0) {
        foreach ($key in $properties.Keys.GetEnumerator()) {
            $val = $properties[$key]
            if ($first) {
                $command += ' '
                $first = $false
            }
            $command += $key
            $command += '='
            $command += $val
            $command += ';'
        }
    }

    $command += ']'
    if ($data) {
        $command += $data.Replace('\r','%0D').Replace('\n', '%0A');
    }

    Write-Host $command
}

try {
    if (!$testAdapterPath) {
        if (Test-Path "$sourcesDirectory\.packages") {
            $testAdapterPath = "$sourcesDirectory\.packages"
        } elseif (Test-Path "$sourcesDirectory\packages") {
            $testAdapterPath = "$sourcesDirectory\packages"
        }
    }

    if ($toolsBaseDirectory) {
        $dotCoverConsoleExe = FindCommand $toolsBaseDirectory "dotCover.exe"
        $reportGeneratorExe = FindCommand $toolsBaseDirectory "ReportGenerator.exe"
    } else {
        Write-Host "Using packaged tools."
        $dotCoverConsoleExe = "$PSScriptRoot\tools\dotCover\dotCover.exe"
        $reportGeneratorExe = "$PSScriptRoot\tools\ReportGenerator\ReportGenerator.exe"
    }

    if ($vsTestCommand) {
        $vsconsoleExe = $vsTestCommand
    } else {
        $vsconsoleExe = "$env:VS140COMNTOOLS\..\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
    }
    Write-Host "Using VSTest: $vsconsoleExe"

    # resolve test assembly files (copied from VSTest.ps1)
    $testAssemblyFiles = @()
    # check for solution pattern
    if ($testAssembly.Contains("*") -Or $testAssembly.Contains("?"))
    {
        Write-Verbose "Pattern found in solution parameter. Calling Find-Files."
        Write-Verbose "Calling Find-Files with pattern: $testAssembly"    
        $testAssemblyFiles = Find-VstsFiles -LegacyPattern $testAssembly -LiteralDirectory $sourcesDirectory
        Write-Verbose "Found files: $testAssemblyFiles"
    }
    else
    {
        Write-Verbose "No Pattern found in solution parameter."
        $testAssembly = $testAssembly.Replace(';;', "`0") # Barrowed from Legacy File Handler
        foreach ($assembly in $testAssembly.Split(";"))
        {
            $testAssemblyFiles += ,($assembly.Replace("`0",";"))
        }
    }

    if (($testAssemblyFiles -is [array]) -and ($testAssemblyFiles.Count -eq 0)) {
        Write-Warning "Specified filter '$testAssembly' matches no files."
        Exit 0
    }

    Trace-VstsPath $testAssemblyFiles

    # build test assembly files string for vstest
    $testFilesString = ""
    foreach ($file in $testAssemblyFiles) {
        $testFilesString = $testFilesString + " ""$file"""
    }

    # Create tempDir underneath sources so that any publish-artificats task
    # don't pick stuff up accidentally.
    $tempDir = $Env:AGENT_TEMPDIRECTORY + "\CoverageResults"
    # if ($runTitle) {
    #     $tempDir += '\' + $runTitle
    # }
    # if (Test-Path $tempDir) {
    #     Remove-Item -Path $tempDir -Recurse -Force
    # }

    if (-Not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory | Out-Null
    }
    $runId = $runTitle
    if (!$runId) {
        $runId = [Guid]::NewGuid().ToString("N")
    }
    $trxDir = "$tempDir\$runId"
    if (Test-path $trxDir) {
        Remove-Item -Recurse -Path $trxDir | Out-Null
    }
    New-Item -Path $trxDir -ItemType Directory | Out-Null
    
    $vsconsoleArgs = $testFilesString
    if ($testAdapterPath) { $vsconsoleArgs += " /TestAdapterPath:""$testAdapterPath""" }
    if ($testFilterCriteria) { $vsconsoleArgs += " /TestCaseFilter:""$testFiltercriteria""" }
    if ($runSettingsFile) { $vsconsoleArgs += " /Settings:""$runSettingsFile""" }
    $vsconsoleArgs += " /logger:trx"
    if ($testAdditionalCommandLine) {
        $vsconsoleArgs += " "
        $vsconsoleArgs += $testAdditionalCommandLine
    }

    $returnCodeCoverage = 0
    $returnCodeVsTest = 0
    $returnCodeMerge = 0
    $returnCodeReportGen = 0
    $returnCodeReportParsing = 0

    if (!$disableCodeCoverage) {
        # According to "https://github.com/OpenCover/opencover/wiki/Usage",
        # "Notes on Spaces in Arguments", to preserve quotes in -targetargs,
        # we should escape them by a backslash.
        $vsconsoleArgs = $vsconsoleArgs.Replace('"', '\"')

        $dotCoverDcvr = "$tempDir\\$runId.dcvr"
        $dotCoverReport = "$tempDir\\$runId.xml"
        $multiAssemblyRunId = $runId;

        if ($testSeriesInfo -eq "multi2") {
            $tempRunId = [Guid]::NewGuid().ToString("N")
            $dotCoverDcvr = "$tempDir\\$tempRunId.dcvr"
            $multiAssemblyRunId = $tempRunId;
        }

        
        $dotCoverConsoleArgsBasic = "cover"
        if ($dotCoverFilters) {
            # Only append filters, if there actually is a value. This way,
            # the caller could use a fully custom filter situation (e.g.
            # with -coverbytest, etc.) using the $dotCoverAdditionalCommandLine
            # option.
            $dotCoverConsoleArgsBasic += " --Filters=""$dotCoverFilters"""
        }
        $dotCoverConsoleArgsBasic += " --TargetExecutable=""$vsconsoleExe"""
        $dotCoverConsoleArgsBasic += " --ReturnTargetExitCode"
        if ($enableDotCoverLog) {
            $dotCoverConsoleArgsBasic += " --LogFile=""$sourcesDirectory\\dotCover.log"""
        }
        if ($dotCoverAdditionalCommandLine) {
            $dotCoverConsoleArgsBasic += " "
            $dotCoverConsoleArgsBasic += $dotCoverAdditionalCommandLine
        }

        $reportDirectory = "$tempDir\CoverageReport"          
        $coberturaReport = "$reportDirectory\Cobertura.xml"     

        # workaround for nunit 3 test runs with multiple test assemblies: create a single test run for each test assembly
        if ($nunit3MultiAssemblyWorkAround -and ($testAssemblyFiles -is [array]) -and ($testAssemblyFiles.Count -gt 1))
        {
            $runIdCounter = 1;
            foreach ($file in $testAssemblyFiles) {
                $vsconsoleArgs = " ""$file"""
                if ($testAdapterPath) { $vsconsoleArgs += " /TestAdapterPath:""$testAdapterPath""" }
                if ($testFilterCriteria) { $vsconsoleArgs += " /TestCaseFilter:""$testFiltercriteria""" }
                if ($runSettingsFile) { $vsconsoleArgs += " /Settings:""$runSettingsFile""" }
                $vsconsoleArgs += " /logger:trx"
                if ($testAdditionalCommandLine) {
                    $vsconsoleArgs += " "
                    $vsconsoleArgs += $testAdditionalCommandLine
                }
                
                $dotCoverConsoleArgs = $dotCoverConsoleArgsBasic
                $dotCoverConsoleArgs += " --Output=""$tempDir\\$multiAssemblyRunId" + "_$runIdCounter.dcvr"""
                $dotCoverConsoleArgs += " --TargetArguments=""$vsconsoleArgs"""
                $runIdCounter++
                Invoke-VstsTool -FileName $dotCoverConsoleExe -Arguments $dotCoverConsoleArgs -WorkingDirectory $trxDir
                $returnCodeCoverage = [System.Math]::Max($returnCodeCoverage, $LASTEXITCODE)
            }

            # merge coverage results
            $filterString = "$multiAssemblyRunId" + "_*.dcvr"
            $partialCoverFiles = Get-ChildItem -Path $tempDir -Filter $filterString -Recurse
            $resFiles = JoinFullPaths $partialCoverFiles ";" True
            $dotCoverMergeArgs = "merge --Source=$resFiles --Output=""$dotCoverDcvr"""
            if ($enableDotCoverLog) {
                $dotCoverMergeArgs += " --LogFile=""$sourcesDirectory\\dotCover.log"""
            }            

            Invoke-VstsTool -FileName $dotCoverConsoleExe -Arguments $dotCoverMergeArgs -WorkingDirectory $trxDir
            $returnCodeMerge = [System.Math]::Max($returnCodeMerge, $LASTEXITCODE)

            # remove partial results
            $partialCoverFiles | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        } else {      
            $dotCoverConsoleArgs = $dotCoverConsoleArgsBasic
            $dotCoverConsoleArgs += " --Output=""$dotCoverDcvr"""
            $dotCoverConsoleArgs += " --TargetArguments=""$vsconsoleArgs""" 
            Invoke-VstsTool -FileName $dotCoverConsoleExe -Arguments $dotCoverConsoleArgs -WorkingDirectory $trxDir
            $returnCodeCoverage = [System.Math]::Max($returnCodeCoverage, $LASTEXITCODE)
        }

        if ($testSeriesInfo -eq "multi2") {
            # merge single coverage results
            $coverageFiles = Get-ChildItem -Path $tempDir -Filter "*.dcvr" -Recurse
            if (($coverageFiles -is [array]) -and ($coverageFiles.Count -gt 1)) {
                $coverageFilesParam = JoinFullPaths $coverageFiles ";" True
                $dotCoverDcvr  = "$tempDir\\$runId.dcvr"
                $dotCoverMergeArgs = "merge --Source=$coverageFilesParam --Output=""$dotCoverDcvr"""
                if ($enableDotCoverLog) {
                    $dotCoverMergeArgs += " --LogFile=""$sourcesDirectory\\dotCover.log"""
                }            

                Invoke-VstsTool -FileName $dotCoverConsoleExe -Arguments $dotCoverMergeArgs -WorkingDirectory $trxDir
                $returnCodeMerge = [System.Math]::Max($returnCodeMerge, $LASTEXITCODE)

                # delete single coverage results
                $coverageFiles | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
            }
            elseif ($coverageFiles -is [array]) { 
                $dotCoverDcvr = $coverageFiles | Select-Object -First 1
            } 
            else { 
                $dotCoverDcvr = $coverageFiles; 
            } 
        }

        # generate a report we can work with
        if ($testSeriesInfo -ne "multi1") {
            # convert the dcvr report to detailed xml
            $dotCoverReportArgs = "report --Source=""$dotCoverDcvr"" --Output=""$dotCoverReport"" --ReportType=DetailedXML"
            Invoke-VstsTool -FileName $dotCoverConsoleExe -Arguments $dotCoverReportArgs -WorkingDirectory $trxDir
            $returnCodeReportParsing = [System.Math]::Max($returnCodeReportParsing, $LASTEXITCODE)

            # delete dcvr
            if ($dotCoverDcvr -is [string]) { Remove-Item -LiteralPath $dotCoverDcvr } else { Remove-Item -LiteralPath $dotCoverDcvr.FullName }

            # create the report
            $reportGeneratorArgs = "-reports:""$dotCoverReport"""
            $reportGeneratorArgs += " -targetdir:""$reportDirectory"""
            $reportGeneratorArgs += " -reporttypes:HtmlInline_AzurePipelines;Cobertura;SonarQube"

            Invoke-VstsTool -FileName $reportGeneratorExe -Arguments $reportGeneratorArgs
            $returnCodeReportGen = [System.Math]::Max($returnCodeReportGen, $LASTEXITCODE)
        }
    } else {
        Invoke-VstsTool -FileName $vsconsoleExe -Arguments $vsconsoleArgs -WorkingDirectory $tempDir
        $returnCodeVsTest = [System.Math]::Max($returnCodeVsTest, $LASTEXITCODE)
    }

    if (($testSeriesInfo -ne "multi1") -or ($returnCodeVsTest -ne 0) -or ($returnCodeCoverage -ne 0) -or ($returnCodeMerge -ne 0) -or ($returnCodeReportGen -ne 0)) {
        PublishTestResults $sourcesDirectory $runTitle $platform $configuration $publishRunAttachments
        PublishTestResults $tempDir $runTitle $platform $configuration $publishRunAttachments
    }
            
    if (!$disableCodeCoverage -and ($testSeriesInfo -ne "multi1")) {
        # Publish code coverage data.
        $codeCoverageParameters = [ordered]@{
            codecoveragetool = 'Cobertura';
            summaryfile = $coberturaReport
            reportdirectory = $reportDirectory
            additionalcodecoveragefiles = $dotCoverReport
        }

        SendCommand 'codecoverage.publish' $codeCoverageParameters ''
    }

    if ($returnCodeVsTest -ne 0) {
        Write-Error (Get-VstsLocString -Key PSLIB_Process0ExitedWithCode1 -ArgumentList "vstest.console.exe", $returnCodeVsTest)
    }
    if ($returnCodeCoverage -ne 0) {
        Write-Error (Get-VstsLocString -Key PSLIB_Process0ExitedWithCode1 -ArgumentList "dotcover.exe cover", $returnCodeCoverage)
    }
    if ($returnCodeMerge -ne 0) {
        Write-Error (Get-VstsLocString -Key PSLIB_Process0ExitedWithCode1 -ArgumentList "dotcover.exe merge", $returnCodeMerge)
    }
    if ($returnCodeReportParsing -ne 0) {
        Write-Error (Get-VstsLocString -Key PSLIB_Process0ExitedWithCode1 -ArgumentList "dotCover.exe report", $returnCodeReportParsing)
    }
    if ($returnCodeReportGen -ne 0) {
        Write-Error (Get-VstsLocString -Key PSLIB_Process0ExitedWithCode1 -ArgumentList "ReportGenerator.exe", $returnCodeReportGen)
    }

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}