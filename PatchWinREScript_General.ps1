################################################################################################
#
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
################################################################################################

Param (
[Parameter(HelpMessage="Work Directory for patch WinRE")][string]$workDir="",
[Parameter(Mandatory=$true,HelpMessage="Path of target package")][string]$packagePath
)

# ------------------------------------
# Help functions
# ------------------------------------

# Log message
function LogMessage([string]$message)
{
	$message = "$([DateTime]::Now) - $message"
	Write-Host $message
}

function IsTPMBasedProtector
{
	$DriveLetter = $env:SystemDrive

	LogMessage("Checking BitLocker status")
	$BitLocker = Get-WmiObject -Namespace "Root\cimv2\Security\MicrosoftVolumeEncryption" -Class "Win32_EncryptableVolume" -Filter "DriveLetter = '$DriveLetter'"

	if(-not $BitLocker)
	{
		LogMessage("No BitLocker object")
		return $False
	}

	$protectionEnabled = $False
    switch ($BitLocker.GetProtectionStatus().protectionStatus){

		("0"){
			LogMessage("Unprotected")
			break
		}

		("1"){
			LogMessage("Protected")
			$protectionEnabled = $True
			break
		}

		("2"){
			LogMessage("Uknown")
			break
		}

		default{
			LogMessage("NoReturn")
			break
		}

	}

	if (!$protectionEnabled)
	{
		LogMessage("Bitlocker isn’t enabled on the OS")
		return $False
	}

    $ProtectorIds = $BitLocker.GetKeyProtectors("0").volumekeyprotectorID       

    $return = $False

    foreach ($ProtectorID in $ProtectorIds){

		$KeyProtectorType = $BitLocker.GetKeyProtectorType($ProtectorID).KeyProtectorType

		switch($KeyProtectorType){

			"1"{
				LogMessage("Trusted Platform Module (TPM)")
				$return = $True
				break
			}


			"4"{
				LogMessage("TPM And PIN")
				$return = $True
				break
			}

			"5"{
				LogMessage("TPM And Startup Key")
				$return = $True
				break
			}

			"6"{
				LogMessage("TPM And PIN And Startup Key")
				$return = $True
				break
			}

			default {break}

		}#endSwitch


	}#EndForeach

	if ($return)
	{
		LogMessage("Has TPM-based protector")
	}
	else
	{
		LogMessage("Doesn't have TPM-based protector")
	}

	return $return
}

function SetRegistrykeyForSuccess
{
	reg add  HKLM\SOFTWARE\Microsoft\PushButtonReset /v WinREPathScriptSucceed /d 1 /f
}

function TargetfileVersionExam([string]$mountDir)
{
	# Exam target binary
	$targetBinary=$mountDir + "\Windows\System32\bootmenuux.dll"
	LogMessage("TargetFile: " +  $targetBinary)
	$realNTVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($targetBinary).ProductVersion
	$versionString = "$($realNTVersion.Split('.')[0]).$($realNTVersion.Split('.')[1])"
	$fileVersion = $($realNTVersion.Split('.')[2])
	$fileRevision = $($realNTVersion.Split('.')[3])

	LogMessage("Target file version: " + $realNTVersion)
	
	if (!($versionString -eq "10.0"))
	{
		LogMessage("Not Windows 10 or later")
		return $False
	}
	
	$hasUpdated = $False
	
	#Windows 10, version 1507 10240.19567
	#Windows 10, version 1607 14393.5499
	#Windows 10, version 1809 17763.3646
	#Windows 10, version 2004 1904X.2247
	#Windows 11, version 21H2 22000.1215
	#Windows 11, version 22H2 22621.815
	
	switch ($fileVersion) {
		"10240" {
			LogMessage("Windows 10, version 1507")
			if ($fileRevision -ge 19567)
			{
				LogMessage("Windows 10, version 1507 with revision " + $fileRevision + " >= 19567, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		"14393" {
			LogMessage("Windows 10, version 1607")
			if ($fileRevision -ge 5499)
			{
				LogMessage("Windows 10, version 1607 with revision " + $fileRevision + " >= 5499, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		"17763" {
			LogMessage("Windows 10, version 1809")
			if ($fileRevision -ge 3646)
			{
				LogMessage("Windows 10, version 1809 with revision " + $fileRevision + " >= 3646, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		"19041" {
			LogMessage("Windows 10, version 2004")
			if ($fileRevision -ge 2247)
			{
				LogMessage("Windows 10, version 2004 with revision " + $fileRevision + " >= 2247, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		"22000" {
			LogMessage("Windows 11, version 21H2")
			if ($fileRevision -ge 1215)
			{
				LogMessage("Windows 11, version 21H2 with revision " + $fileRevision + " >= 1215, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		"22621" {
			LogMessage("Windows 11, version 22H2")
			if ($fileRevision -ge 815)
			{
				LogMessage("Windows 11, version 22H2 with revision " + $fileRevision + " >= 815, updates have been applied")
				$hasUpdated = $True
			}
			break
		}
		default {
			LogMessage("Warning: unsupported OS version")
		}
	}
	
	return $hasUpdated
}

function PatchPackage([string]$mountDir, [string]$packagePath)
{
	# Exam target binary
	$hasUpdated = TargetfileVersionExam($mountDir)
	
	if ($hasUpdated)
	{
		LogMessage("The update has already been added to WinRE")
		SetRegistrykeyForSuccess
		return $False
	}
	
	# Add package
	LogMessage("Apply package:" + $packagePath)
	Dism /Add-Package /Image:$mountDir /PackagePath:$packagePath
	if ($LASTEXITCODE -eq 0)
	{
		LogMessage("Successfully applied the package")
	}
	else
	{
		LogMessage("Applying the package failed with exit code: " + $LASTEXITCODE)
		return $False
	}
	
	# Cleanup recovery image
	LogMessage("Cleanup image")
	Dism /image:$mountDir /cleanup-image /StartComponentCleanup /ResetBase
	if ($LASTEXITCODE -eq 0)
	{
		LogMessage("Cleanup image succeed")
	}
	else
	{
		LogMessage("Cleanup image failed: " + $LASTEXITCODE)
		return $False
	}
	
	return $True
}


# ------------------------------------
# Execution starts
# ------------------------------------

# Check breadcrumb
if (Test-Path HKLM:\Software\Microsoft\PushButtonReset)
{
	$values = Get-ItemProperty -Path HKLM:\Software\Microsoft\PushButtonReset 
	if (!(-not $values))
	{
		if (Get-Member -InputObject $values -Name WinREPathScriptSucceed) 
		{
			$value = Get-ItemProperty -Path HKLM:\Software\Microsoft\PushButtonReset -Name WinREPathScriptSucceed
			if ($value.WinREPathScriptSucceed -eq 1)
			{
				LogMessage("This script was previously run successfully")
				exit 1
			}
		}
	}
}

# Get WinRE info
$WinREInfo = Reagentc /info
$findLocation = $False
foreach ($line in $WinREInfo)
{
	$params = $line.Split(':')
	if ($params.count -le 1)
	{
		continue
	}
	if ($params[1].Lenght -eq 0)
	{
		continue
	}
	$content = $params[1].Trim()
	if ($content.Lenght -eq 0)
	{
		continue
	}

	$index = $content.IndexOf("\\?\")
	if ($index -ge 0)
	{
		LogMessage("Find \\?\ at " + $index + " for [" + $content + "]")
		$WinRELocation = $content
		$findLocation = $True
	}
}

if (!$findLocation)
{
	LogMessage("WinRE Disabled")
	exit 1
}

LogMessage("WinRE Enabled. WinRE location:" + $WinRELocation)
	
$WinREFile = $WinRELocation + "\winre.wim"

if ([string]::IsNullorEmpty($workDir))
{
	LogMessage("No input for mount directory")
	LogMessage("Use default path from temporary directory")
	$workDir = [System.IO.Path]::GetTempPath()

}

LogMessage("Working Dir: " + $workDir)
$name = "CA551926-299B-27A55276EC22_Mount"
$mountDir = Join-Path $workDir $name
LogMessage("MountDir: " + $mountdir)
	
# Delete existing mount directory
if (Test-Path $mountDir)
{
	LogMessage("Mount directory: " + $mountDir + " already exists")
	
	LogMessage("Try to unmount it")
	Dism /unmount-image /mountDir:$mountDir /discard
	
	if (!($LASTEXITCODE -eq 0))
	{
		LogMessage("Warning: unmount failed: " + $LASTEXITCODE)
	}
	
	LogMessage("Delete existing mount direcotry " + $mountDir)
	Remove-Item $mountDir -Recurse
}

# Create mount directory
LogMessage("Create mount directory " + $mountDir)
New-Item -Path $mountDir -ItemType Directory

# Set ACL for mount directory
LogMessage("Set ACL for mount directory")
icacls $mountDir /inheritance:r
icacls $mountDir /grant:r SYSTEM:"(OI)(CI)(F)"
icacls $mountDir /grant:r *S-1-5-32-544:"(OI)(CI)(F)"
	
# Mount WinRE
LogMessage("Mount WinRE:")
Dism /mount-image /imagefile:$WinREFile /index:1 /mountdir:$mountDir
if ($LASTEXITCODE -eq 0)
{
	# Patch WinRE
	if (PatchPackage -mountDir $mountDir -packagePath $packagePath)
	{
		$hasUpdated = TargetfileVersionExam($mountDir)
		if ($hasUpdated)
		{
			LogMessage("After patch, find expected version for target file")
		}
		else
		{
			LogMessage("Warning: After applying the patch, unexpected version found for the target file")
		}
		
		LogMessage("Patch succeed, unmount to commit change")
		Dism /unmount-image /mountDir:$mountDir /commit
		
		if (!($LASTEXITCODE -eq 0))
		{
			LogMessage("Unmount failed: " + $LASTEXITCODE)
			exit 1
		}
		else
		{
			if ($hasUpdated)
			{
				if (IsTPMBasedProtector)
				{
					# Disable WinRE and re-enable it to let new WinRE be trusted by BitLocker
					LogMessage("Disable WinRE")
					reagentc /disable
					LogMessage("Re-enable WinRE")
					reagentc /enable
					
					reagentc /info
				}
				
				# Leave a breadcrumb indicates the script has succeed
				SetRegistrykeyForSuccess
			}
		}
	}
	else
	{
		LogMessage("Patch failed or is not applicable, discard unmount")
		Dism /unmount-image /mountDir:$mountDir /discard
		
		if (!($LASTEXITCODE -eq 0))
		{
			LogMessage("Unmount failed: " + $LASTEXITCODE)
			exit 1
		}

	}
}
else
{
	LogMessage("Mount failed: " + $LASTEXITCODE)
}
	
# Cleanup Mount directory in the end
LogMessage("Delete mount direcotry")
Remove-Item $mountDir -Recurse
