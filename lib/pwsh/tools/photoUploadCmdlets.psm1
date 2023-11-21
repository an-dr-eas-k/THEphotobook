
function Get-StandardGPPath {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$File,
		$ReferencePath,
		[Parameter(DontShow)]
		$DirSep = [System.IO.Path]::DirectorySeparatorChar
	)
	if (-not ($File -is [System.IO.FileInfo])) {
		$File = $File | Get-Item
	}
	$relativePath = (
		Resolve-RelativePath -Path $File.Directory.FullName -ReferencePath $ReferencePath
	).Trim(".$($DirSep)") `
		-replace $DirSep, "."

  ("{0}.{1}" -f $relativePath, $File.Name).Trim(".")
}

function Send-Photos {
	[CmdletBinding()]
	param(
		[System.IO.DirectoryInfo[]]$InputPath = ".",
		$ReferencePath = $null,
		$Pattern = "((\.jpe?g)|(\.png))$",
		$TmpDir = "/tmp/send-photos",
		$MaxResolution = 10000000,
		$DoneIndicator = "send-photos.done",
		$GPhotosConfigDir = "~/.gphotos-uploader-cli/tmp",
		[switch]$WhatIf,
		[switch]$WhatNot,
		[switch]$FilenamesOnly
	)
	begin {
		$startDir = Get-Location
		$InputPath = @($InputPath | Get-Item)
		if (-not $ReferencePath) {
			if ($InputPath.Count -eq 1) {
				$ReferencePath = $InputPath[0]
			}
			else {
				throw "Please specify a reference path"
			}
		}
		$ReferencePath = $ReferencePath | Get-Item
		Remove-Item $TmpDir -ErrorAction SilentlyContinue -Force -Recurse
		New-Item -ItemType Directory -Path $TmpDir -Force | Set-Location

		$convertCmd = "magick mogrify -resize $($MaxResolution)`@> '{0}'"
		$convertCmd | Write-Verbose
		$inspectCmd = "magick identify -precision 0 -format '{{`"filesize`": `"%[size]`", `"format`": `"%m`", `"height`": %h, `"width`": %w, `"compression_type`": `"%C`", `"compression`": %Q}}' '{0}'"
		$inspectCmd | Write-Verbose

		$env:GPHOTOS_CLI_TOKENSTORE_KEY = "foobar"
	}

	process {
      ($InputPath | Get-ChildItem -Recurse -Directory | Get-Item) `
			+ @($InputPath | Get-Item) `
		| Sort-Object -Property FullName `
		| ? { @($_ | Get-ChildItem -File | ? { $_.FullName -match $Pattern } ).Count -gt 0 }
		| ? { @($_ | Get-ChildItem -File | ? { $_.Name -eq $DoneIndicator } | % { Write-Verbose "ignoring $($_.Directory.FullName)"; $_; } ).Count -eq 0 }
		| % {
			$sourceFolder = $_
			"sourceFolder: $($sourceFolder.FullName)" | Write-Verbose

			if ($WhatNot) {
				return
			}

			if ($FilenamesOnly) {
				$sourceFolder `
				| Get-ChildItem -File `
				| % { @{
						file       = $_;
						googlePath = Get-StandardGPPath -ReferencePath $ReferencePath -File $_;
					} | Write-Output }
				return
			}

			"copying..." | Write-Verbose
			$sourceFolder `
			| Get-ChildItem -File `
			| ? { $_.FullName -match $Pattern } `
			| % { $_ | Copy-Item -Destination (Get-StandardGPPath -ReferencePath $ReferencePath -File $_) -PassThru } `
			| Measure-Object | % { "items: $($_.Count)" } | Write-Verbose

			if ($PSBoundParameters.Debug -eq $true) {
				Get-ChildItem | Out-String | Write-Verbose
			}

			"resizing..." | Write-Verbose
			Get-ChildItem `
			| % { @{
					item   = $_;
					pixels = $inspectCmd -f $_.FullName `
					| Invoke-Expression `
					| ConvertFrom-Json `
					| % { ( $_.width * $_.height ) };
				} } `
			| ? { $_.pixels -gt $MaxResolution }
			| % {
				"resizing $($_.item.FullName), size $($_.pixels)" | Write-Verbose
				$convertCmd -f $_.item.FullName | Invoke-Expression
			}

			if ($PSBoundParameters.Debug -eq $true) {
				Get-ChildItem | Out-String | Write-Verbose
				break
			}

			if ($PSBoundParameters.WhatIf -eq $true) {
				"'d do the uploading now, but whatif is present" | Write-Host
				continue
			}
			else {
				"uploading..." | Write-Verbose
				& gphotos-uploader-cli push --silent --config $GPhotosConfigDir
				if (! $?) {
					"cancel, upload failed" | Write-Error
					break;
				}

				New-Item -Path ( Join-Path -Path $sourceFolder.FullName -ChildPath $DoneIndicator ) -ItemType File | Out-Null
			}

			Remove-Item "$($TmpDir)/*" -Force
		}
	}

	clean {
		$startDir | Set-Location
	}
}


function Get-PhotosMappedFromGPhotos {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$GPhotosSourceDir,
		[System.IO.DirectoryInfo]$Destination,
		$StandardGPPath,
		$Pattern = "((\.jpe?g)|(\.png))$"
	)
	$GPhotosSourceDir = Get-Item $GPhotosSourceDir
	$GPhotosSourceDir | Write-Verbose

	$GPhotosSourceDir | Get-ChildItem -Recurse -File 
	| ? { $_.FullName -match $Pattern }
	| % {
		$gphotosPath = Get-StandardGPPath -ReferencePath ($GPhotosSourceDir.FullName) -File $_
		if (@($StandardGPPath).Contains($gphotosPath)) {
			if ($Destination) {
				$_ | Copy-Item -Destination (Join-Path -Path $Destination -ChildPath $gphotosPath)
			}
			else {
				$_
			}
		}
	}
}

Export-ModuleMember -Function Send-Photos, Get-PhotosMappedFromGPhotos