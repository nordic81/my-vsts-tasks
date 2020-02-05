function Test-Container {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    Write-Verbose "Testing container: '$LiteralPath'"
    if ((Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        Write-Verbose 'Exists.'
        return $true
    }
    Write-Verbose 'Does not exist.'
    return $false
}

function Test-Leaf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    Write-Verbose "Testing leaf: '$LiteralPath'"
    if ((Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        Write-Verbose 'Exists.'
        return $true
    }
    Write-Verbose 'Does not exist.'
    return $false
}

function Get-LatestVsVersionFolder {

    $vs15 = Get-InstalledVisualStudioInfo 15
    if ($vs15 -And $vs15.Path) {
        Write-Verbose "Version 15.x : $($vs15.Path)"
        return $vs15.Path
    }

    foreach ($version in @('15.0', '14.0', '12.0', '10.0')) {
        $folder = Get-VsVersionFolder -Version $version
        if ($folder) {
            Write-Verbose "Version $version : $folder"
            return $folder
        } else {
            Write-Verbose "Version $version not found/no folder."
        }
    }
}

function Get-VsVersionFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$version)
    $res = Get-ItemProperty -Path "HKLM:\Software\Wow6432Node\Microsoft\VisualStudio\$version" -ErrorAction SilentlyContinue
    if ($res -and [bool]($res.PSObject.Properties.Name -match "ShellFolder")) {
        return $res.ShellFolder
    }
    return $null
}

function Get-VSTestConsolePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path)
        
    $shellFolder15 = $Path.TrimEnd('\'[0]) + '\'
    $installDir15 = ([System.IO.Path]::Combine($shellFolder15, 'Common7', 'IDE')) + '\'
    $testWindowDir15 = [System.IO.Path]::Combine($installDir15, 'CommonExtensions', 'Microsoft', 'TestWindow') + '\'
    $vstestConsole15 = [System.IO.Path]::Combine($testWindowDir15, 'vstest.console.exe')
    return $vstestConsole15
}

function Get-InstalledVisualStudioInfo {
    [CmdletBinding()]
    param($major, $minor)
    try {
        # Short-circuit if the setup configuration class ID isn't registered.
        if (!(Test-Container -LiteralPath 'REGISTRY::HKEY_CLASSES_ROOT\CLSID\{177F0C4A-1CD3-4DE7-A32C-71DBBB9FA36D}')) {
            return
        }

        # If the type has already been loaded once, then it is not loaded again.
        Write-Host "Adding Visual Studio setup helpers."
        Add-Type -Debug:$false -TypeDefinition @'
namespace CapabilityHelpers.VisualStudio.Setup
{
    using System;
    using System.Collections.Generic;
    using CapabilityHelpers.VisualStudio.Setup.Com;

    public sealed class Instance
    {
        public string Description { get; set; }
        public string DisplayName { get; set; }
        public string Id { get; set; }
        public System.Runtime.InteropServices.ComTypes.FILETIME InstallDate { get; set; }
        public string Name { get; set; }
        public string Path { get; set; }
        public Version Version
        {
            get
            {
                try
                {
                    return new Version(VersionString);
                }
                catch (Exception)
                {
                    return new Version(0, 0);
                }
            }
        }
        public string VersionString { get; set; }
        public static List<Instance> GetInstances()
        {
            List<Instance> list = new List<Instance>();
            ISetupConfiguration config = new SetupConfiguration() as ISetupConfiguration;
            IEnumSetupInstances enumInstances = config.EnumInstances();
            ISetupInstance[] instances = new ISetupInstance[1];
            int fetched = 0;
            enumInstances.Next(1, instances, out fetched);
            while (fetched > 0)
            {
                ISetupInstance instance = instances[0];
                list.Add(new Instance()
                {
                    Description = instance.GetDescription(),
                    DisplayName = instance.GetDisplayName(),
                    Id = instance.GetInstanceId(),
                    InstallDate = instance.GetInstallDate(),
                    Name = instance.GetInstallationName(),
                    Path = instance.GetInstallationPath(),
                    VersionString = instance.GetInstallationVersion(),
                });
                enumInstances.Next(1, instances, out fetched);
            }
            return list;
        }
    }
}

namespace CapabilityHelpers.VisualStudio.Setup.Com
{
    using System;
    using System.Runtime.InteropServices;

    [ComImport]
    [Guid("6380BCFF-41D3-4B2E-8B2E-BF8A6810C848")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IEnumSetupInstances
    {
        void Next(
            [In, MarshalAs(UnmanagedType.U4)] int celt,
            [Out, MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.Interface)] ISetupInstance[] rgelt,
            [Out, MarshalAs(UnmanagedType.U4)] out int pceltFetched);
        void Skip([In, MarshalAs(UnmanagedType.U4)] int celt);
        void Reset();
        [return: MarshalAs(UnmanagedType.Interface)]
        IEnumSetupInstances Clone();
    }

    [ComImport]
    [Guid("42843719-DB4C-46C2-8E7C-64F1816EFD5B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISetupConfiguration
    {
        [return: MarshalAs(UnmanagedType.Interface)]
        IEnumSetupInstances EnumInstances();
    }

    [ComImport]
    [Guid("B41463C3-8866-43B5-BC33-2B0676F7F42E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISetupInstance
    {
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetInstanceId();
        [return: MarshalAs(UnmanagedType.Struct)]
        System.Runtime.InteropServices.ComTypes.FILETIME GetInstallDate();
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetInstallationName();
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetInstallationPath();
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetInstallationVersion();
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetDisplayName([In, MarshalAs(UnmanagedType.U4)] int lcid = default(int));
        [return: MarshalAs(UnmanagedType.BStr)]
        string GetDescription([In, MarshalAs(UnmanagedType.U4)] int lcid = default(int));
    }

    [ComImport]
    [Guid("42843719-DB4C-46C2-8E7C-64F1816EFD5B")]
    [CoClass(typeof(SetupConfigurationClass))]
    [TypeLibImportClass(typeof(SetupConfigurationClass))]
    public interface SetupConfiguration : ISetupConfiguration
    {
    }

    [ComImport]
    [Guid("177F0C4A-1CD3-4DE7-A32C-71DBBB9FA36D")]
    [ClassInterface(ClassInterfaceType.None)]
    public class SetupConfigurationClass
    {
    }
}
'@
        Write-Host "Getting Visual Studio setup instances."
        $instances = @( [CapabilityHelpers.VisualStudio.Setup.Instance]::GetInstances() )
        Write-Host "Found $($instances.Count) instances."
        Write-Host ($instances | Format-List * | Out-String)
        return $instances |
            Where-Object { $_.Version.Major -eq $major } |
            Sort-Object -Descending -Property Version |
            Select-Object -First 1
    } catch {
        Write-Host ($_ | Out-String)
    }
}

function CheckIfRunsettings($runSettingsFilePath)
{
    if(([string]::Compare([io.path]::GetExtension($runSettingsFilePath), ".runsettings", $True) -eq 0) -Or ([string]::Compare([io.path]::GetExtension($runSettingsFilePath), ".tmp", $True) -eq 0))
    {
        return $true
    }
    return $false
}

function CheckIfDirectory($filePath)
{
    if(Test-Path $filePath -pathtype container)
    {
        return $true
    }
    return $false
}

function FindCommand ($directory, $commandName) {
    Write-Host "Checking for '$commandName' in '$directory' tree"
    $results = Get-ChildItem -Path $directory -Filter $commandName -Recurse -ErrorAction SilentlyContinue -Force
    if (!$results -or $results.Length -eq 0) {
        throw "Command '$commandName' not found in directory tree '$directory' (source directory)."
    }
    Write-Host "Using $($results[0].FullName)"
    return $results[0].FullName
}

function DownloadTool ($packageName, $binaryName){
    # if the binary already exists: return
    if ((Get-ChildItem -Path $Env:AGENT_TOOLSDIRECTORY -Filter $binaryName -Recurse | Measure-Object).Count -gt 0)
    {
        Write-Output "$packageName already installed."
        exit 0
    }

    Write-Host "Downloading $packageName from nuget"
    Save-Package -Name $packageName -ProviderName NuGet -Path $Env:AGENT_TEMPDIRECTORY
    $nugetPackage = Get-ChildItem -Path $Env:AGENT_TEMPDIRECTORY -Filter $packageName* | Select-Object -First 1

    Write-Output "Extracting $packageName ($nugetPackage) to $Env:AGENT_TOOLSDIRECTORY"
    Expand-Archive -LiteralPath $nugetPackage -DestinationPath $Env:AGENT_TOOLSDIRECTORY
}

function PublishTestResults ($sourceDir, $title, $platform, $config, $publish) {
    $resultFiles = Find-VstsFiles -LegacyPattern "**\*.trx" -LiteralDirectory $sourceDir
    foreach ($resultFile in $resultFiles) {
        $testResultParameters = [ordered]@{
            type = 'VSTest';
            resultFiles = $resultFile;
            runTitle = $title;
            platform = $platform;
            config = $config;
            publishRunAttachments = $publish
        }    

        SendCommand 'results.publish' $testResultParameters ''
    }
}

function JoinStrings ([array] $array, [string] $separator){
    $result = [String]::Join($separator, $array)
    return $result;
}

function JoinFullPaths ([array] $array, [string] $separator, [switch] $doubleQuotes){
    $replacement = ""
    if ($doubleQuotes) {
        $replacement = '"'
    }    
    return (JoinStrings ($array | Select-Object -Property FullName) $separator).Replace("@{FullName=", $replacement).Replace("}", $replacement)
}