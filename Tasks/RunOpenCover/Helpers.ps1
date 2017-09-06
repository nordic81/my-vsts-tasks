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
    $res = Get-ItemProperty -Path "HKLM:\Software\Wow6432Node\Microsoft\VisualStudio\$version"
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
        Write-Verbose "Adding Visual Studio setup helpers."
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
        Write-Verbose "Getting Visual Studio setup instances."
        $instances = @( [CapabilityHelpers.VisualStudio.Setup.Instance]::GetInstances() )
        Write-Verbose "Found $($instances.Count) instances."
        Write-Verbose ($instances | Format-List * | Out-String)
        return $instances |
            Where-Object { $_.Version.Major -eq $major } |
            Sort-Object -Descending -Property Version |
            Select-Object -First 1
    } catch {
        Write-Verbose ($_ | Out-String)
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

function SetupRunSettingsFileForParallel {
	[cmdletbinding()]
	[OutputType([System.String])]
	param(
		[string]$runInParallelFlag,
		[string]$runSettingsFilePath,
		[string]$defaultCpuCount
	)

	if($runInParallelFlag -eq "True")
	{
		if([string]::Compare([io.path]::GetExtension($runSettingsFilePath), ".testsettings", $True) -eq 0)
		{
			Write-Warning "Run in Parallel is not supported with testsettings file."
		}
		else
		{
			$runSettingsForParallel = [xml]'<?xml version="1.0" encoding="utf-8"?>'
            if([System.String]::IsNullOrWhiteSpace($runSettingsFilePath) `
                -Or ([string]::Compare([io.path]::GetExtension($runSettingsFilePath), ".runsettings", $True) -ne 0) `
                -Or (Test-Path $runSettingsFilePath -pathtype container))  # no file provided so create one and use it for the run
			{
				Write-Verbose "No runsettings file provided"
				$runSettingsForParallel = [xml]'<?xml version="1.0" encoding="utf-8"?>
				<RunSettings>
				  <RunConfiguration>
					<MaxCpuCount>0</MaxCpuCount>
				  </RunConfiguration>
				</RunSettings>
				'
			}
			else
			{
				Write-Verbose "Adding maxcpucount element to runsettings file provided"
				$runSettingsForParallel = [System.Xml.XmlDocument](Get-Content $runSettingsFilePath)
				$runConfigurationElement = $runSettingsForParallel.SelectNodes("//RunSettings/RunConfiguration")
				if($runConfigurationElement.Count -eq 0)
				{
					$runConfigurationElement = $runSettingsForParallel.RunSettings.AppendChild($runSettingsForParallel.CreateElement("RunConfiguration"))
				}

				$maxCpuCountElement = $runSettingsForParallel.SelectNodes("//RunSettings/RunConfiguration/MaxCpuCount")
				if($maxCpuCountElement.Count -eq 0)
				{
					$runConfigurationElement.AppendChild($runSettingsForParallel.CreateElement("MaxCpuCount"))
				}
			}

			$runSettingsForParallel.RunSettings.RunConfiguration.MaxCpuCount = $defaultCpuCount
			$tempFile = [io.path]::GetTempFileName()
			$runSettingsForParallel.Save($tempFile)
			Write-Verbose "Temporary runsettings file created at $tempFile"
			return $tempFile
		}
	}

	return $runSettingsFilePath
}