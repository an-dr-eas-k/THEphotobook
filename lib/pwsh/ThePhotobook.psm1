class ThePhoto {

	[string]$Path;
	[int]$Width;
	[int]$Height;
	[bool]$Standing;
	[datetime]$Date;
	[string]$Comment;

	ThePhoto(	[System.IO.FileInfo]$Path	) {
		$this.Path = $Path
		$metadata = Extract-Metadata -FilePath $Path.FullName -Raw
		$this.Height = $this.GetTag("Image Height", $metadata)
		$this.Width = $this.GetTag("Image Width", $metadata)
		$this.Standing = $this.Height -gt $this.Width
		$this.Comment = $this.GetTag("User Comment", $metadata)
		$dateString = $null `
			?? $this.GetTag("Date.*Original", "Exif", $metadata) `
			?? $this.GetTag("Date.*Original", "XMP", $metadata) `
			?? $this.GetTag("File Modified Date", "File", $metadata)
		$dateString | Write-Verbose

		$errors = @()
		foreach ($f in @( { [datetime]$args[0] }, { [System.DateTime]::ParseExact($args[0], 'yyyy:MM:dd HH:mm:ss', $null) })) {
			try {
				$this.Date = $f.Invoke($dateString)[0]
				break
			}
			catch [System.Exception] { $errors += $_ }
		}
		if (-not $this.Date){
			$errors | Write-Warning
		}
	}

	[string] GetTag([string]$tagPattern, [array]$metadata) {
		return $this.GetTag($tagPattern, $null, $metadata)
	}

	[string] GetTag([string]$tagPattern, [string]$directoryPattern, [array]$metadata) {
		return $metadata `
		| ? { (-not $directoryPattern) -or ($_.Directory -match $directoryPattern ) }`
		| ? { $_.Tag -match $tagPattern } `
		| Select-Object -First 1 -ExpandProperty RawValue
	}

	[int] GetOptimalWidth() {
		return [Math]::Min(110 / $this.Height * $this.Width, 160)
	}
    
	[string] GetHumanDate() {
		return Get-Date -Format "dd. MMMM yyyy" -date $this.Date
	}

	[string] ToString() {
		return $this | ConvertTo-Json
	}
}

function Write-ThePhotos {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$Path,
		$Culture = "de_de",
		$WinSize = 5
	)
	Import-MetadataExtractor
	[System.Threading.Thread]::CurrentThread.CurrentCulture = $Culture
	jhead -autorot (Join-Path $Path "*")
	$photos = @( $Path | Get-ChildItem -File | % { $p = [ThePhoto]::new($_); $p | Write-Verbose; $p } | Sort-Object -Property Date )

	$neededSpace = 0
	for ($i = 0; $i -lt $photos.Length; $i++) {
		[ThePhoto]$pmd = $photos[$i]
		if (-not $pmd) {
			continue
		}
		if ($neededSpace % 4 -eq 0) {
			"\clearpage" 
		}
		if (-not ($pmd.Standing)) {
			"\photoNouveauN{$($pmd.Path | Resolve-RelativePath)}{$($pmd.GetOptimalWidth())mm}{$($pmd.GetHumanDate());$($pmd.Comment)}{}{}{}" 
			$neededSpace += 1
			$photos[$i] = $null
		}
		else {
			$r = @()
			# $r += ($i=$WinSize..$i-1)
			# $r += $i
			$r += (($i + 1)..($i + $WinSize))
			$pairFound = $false
			foreach ($j in $r) {
				[ThePhoto]$other = $photos[$j]
				if ( (-not $other) -or (-not $other.Standing)) {
					continue
				}
				"\photoNouveauN{$($pmd.Path | Resolve-RelativePath)}{$($pmd.GetOptimalWidth())mm}{$($pmd.GetHumanDate());$($pmd.Comment)}{$($other.Path | Resolve-RelativePath)}{$($other.GetOptimalWidth())mm}{$($other.GetHumanDate());$($other.Comment)}" 
				$neededSpace += 1
				$pairFound = $true
				$photos[$j] = $null
				break
			}
			if (-not $pairFound) {
				"\photoNouveauN{$($pmd.Path | Resolve-RelativePath)}{$($pmd.GetOptimalWidth())mm}{$($pmd.GetHumanDate());$($pmd.Comment)}{}{}{}" 
				$neededSpace += 1
				$photos[$i] = $null
			}
		}
	}
}

function Import-MetadataExtractor {
	[Cmdletbinding()]
	param(
		$PublishDir = "$PSScriptRoot/metadata-extractor-dotnet/MetadataExtractor.PowerShell/bin/Debug/net40/publish"
	)
	get-childItem $PublishDir | ? { $_ -match "dll$" } | % { Add-Type -Path $_.FullName }
	Import-Module -Force "$PublishDir/MetadataExtractor.PowerShell.dll" -Global *>&1 | Out-Null
}

function Add-ThePhoto {
	[Cmdletbinding()]
	param(
		$OutputFile = "thePhotos.lst"
	)
	while ($true) {
		Read-Host -Prompt "put photo to clipboard > [ok]" | Out-Null
		$photo = Get-Clipboard
		if (-not ($photo -as [System.IO.FileInfo])?.Exists) {
			"$photo does not exist, ignoring..." | Write-Host
			continue
		}
		$photo >> $OutputFile
		"added $photo" | Write-Verbose
	}
}

Export-ModuleMember -Function Import-MetadataExtractor, Write-ThePhotos, Add-ThePhoto