# WinREupdate

This is a sample PowerShell script developed by the Microsoft product team to help automate the patching of WinRE images on Windows 10 and Windows 11 machines. Run the script with Administrator privileges on affected platforms. There are 2 scripts based on the version of Windows you are running. Please use the appropriate version for your environment.
- PatchWinREScript_2004plus.ps1 : This is for Windows 10 version 2004 and newer, including Windows 11
- PatchWinREScript_General.ps1  : This is for Windows 10 version 1909 and older, but executes on all versions.

This script will:
1. Mount the existing WinRE image
2. Updates the WinRE image with the specified package
3. Unmount the WinRE image
4. If the BitLocker TPM protector is present, reconfigures WinRE for BitLocker service

## Usage

There are 2 parameters that can be passed to the script

workDir&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Specifies the scratch space used to patch WinRE. Optional (defaults to system TEMP folder).<br>
packagePath&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Specifies the package to be used to update the WinRE. Required. Can be a local path or a remote UNC path.<br>


Example:
```
.\PatchWinREScript_2004plus.ps1 -packagePath "\\server\share\windows10.0-kb5021043-x64_efa19d2d431c5e782a59daaf2d04d026bb8c8e76.cab"
```
