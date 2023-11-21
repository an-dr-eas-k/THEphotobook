#
# pwsh -wd (Get-Location) -command { ls ./media/working/ | %{ Write-ThePhotos -Path "$_/*" -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; make -B }
#
# pwsh -wd (Get-Location) -command { ls ./media/ordered/ | %{ Write-ThePhotos -Path "$_/*" -SortProperty Path -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; rm ./root.aux; make -B}
#

$script:MaxPicWidth = 170

class ThePhoto {

	[string]$Path;
	[int]$Width;
	[int]$Height;
	[bool]$Upright;
	[datetime]$Date;
	[string]$Comment;
	[int]$OrderPos;
	[psobject]$MetaJsonFromTitle

	ThePhoto(	[System.IO.FileInfo]$Path	) {
		$this.Path = $Path
		$this.readTagsWithTagLib($Path)
	}

	[void] readPhotoDate($dateString) {
		$errors = @()
		foreach ($f in @( { [datetime]$args[0] }, { [System.DateTime]::ParseExact($args[0], 'yyyy:MM:dd HH:mm:ss', $null) })) {
			try {
				$this.Date = $f.Invoke($dateString)[0]
				break
			}
			catch [System.Exception] { $errors += $_ }
		}
		if (-not $this.Date) {
			("errors: ", $errors) | Write-Warning
		}
	}

	[void] readTagsWithTagLib([System.IO.FileInfo]$path) {
		$metadata = $script:assembly.GetType("TagLib.File").GetMethod("Create", "String").Invoke($null, @($path.FullName))
		$this.Height = $metadata.Properties.PhotoHeight
		$this.Width = $metadata.Properties.PhotoWidth
		$this.Upright = $this.Height -gt $this.Width
		$this.Comment = ($metadata.Tag.Comment	-replace ("&", "\&") -replace ("digital camera", "")).Trim()
		$this.MetaJsonFromTitle = ($metadata.Tag.Title ?? "" ) | ConvertFrom-Json -ErrorAction Continue
		$dateString = $null `
			?? $metadata.Tag.Exif.DateTimeOriginal `
			?? ($metadata.ImageTag.Xmp.NodeTree.Children | ? { $_.Name -eq "DateTimeOriginal" } | % Value) `
			?? $path.LastWriteTime `
			?? ""
		if ($dateString -is [datetime]) {
			$this.Date = $dateString
		}
		else {
			$this.readPhotoDate($dateString)
		}
	}

	[string] GetTag([string]$tagPattern, [array]$metadata) {
		return $this.GetTag($tagPattern, $null, $metadata)
	}

	[string] GetTag([string]$tagPattern, [string]$directoryPattern, [array]$metadata) {
		return $metadata `
		| ? { (-not $directoryPattern) -or ($_.Directory -match $directoryPattern ) }`
		| ? { $_.Tag -match $tagPattern } `
		| ? { $_.RawValue -isnot [System.Byte[]] } `
		| Select-Object -First 1 -ExpandProperty RawValue `
		| % { "tag '$tagPattern' $(if ( $directoryPattern){ "(directory: '$directoryPattern') "})has value '$_'" | Write-Verbose; $_ }
	}

	[int] GetOptimalWidth() {

		$fixedWidth = $this.MetaJsonFromTitle.FixedWidth
		if ($fixedWidth) {
			return $fixedWidth
		}

		return [Math]::Min(110 / $this.Height * $this.Width, $script:MaxPicWidth)
	}
	
	[string] GetHumanDate() {
		if ($this.Date.ToLongTimeString() -eq "00:00:00") {
			return ""
		}
		return Get-Date -Format "dd. MMMM yyyy" -date $this.Date
	}

	[string] ToString() {
		return $this | ConvertTo-Json
	}

	[System.IO.FileInfo] GetPath() {
		return $this.Path -as [System.IO.FileInfo]
	}

	[string] GetOrderPos() {
		return '{0:d4}' -f $this.OrderPos
	}
}

function Read-ThePhotos {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$Path,
		$SortProperty = "Date"
	)
	$OrderPos = 0
	$OrderIncrement = 10
	@( 
		$Path `
		| Get-ChildItem -File `
		| % { $p = [ThePhoto]::new($_); $p | Write-Verbose; $p } `
		| Sort-Object -Property $SortProperty `
		| % { 
			$OrderPos += $OrderIncrement; 
			$_.OrderPos = $OrderPos;
			$_ 
		}
	)
}

function Write-ThePhotos {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$Path,
		$SortProperty = "Date",
		$Culture = "de_de",
		$WinSize = 5
	)
	[System.Threading.Thread]::CurrentThread.CurrentCulture = $Culture

	$jheadInput = $Path
	if ((($Path | Get-Item) -as [System.IO.DirectoryInfo])?.Exists) {
		$jheadInput = (Join-Path $Path "*")
	}

	$jheadCmd = "jhead -autorot '$jheadInput' *>&1"
	$jheadCmd | Write-Verbose
	Invoke-Expression $jheadCmd | Write-Verbose
	$photos = @(Read-ThePhotos -Path $Path -SortProperty $SortProperty)

	$neededSpace = 2
	for ($i = 0; $i -lt $photos.Length; $i++) {
		[ThePhoto]$pmd = $photos[$i]
		if (-not $pmd) {
			continue
		}
		if ($neededSpace % 4 -eq 0) {
			"\clearpage" 
		}
		if (-not ($pmd.Upright)) {
			Write-PhotoSegment -Photo $pmd
			$neededSpace += 1
			$photos[$i] = $null
		}
		else {
			$r = @()
			$r += (($i + 1)..($i + $WinSize))
			$pairFound = $false
			foreach ($j in $r) {
				[ThePhoto]$other = $photos[$j]
				if ( (-not $other) -or (-not $other.Upright)) {
					continue
				}
				Write-PhotoSegment -Photo $pmd -Other $other
				$neededSpace += 1
				$pairFound = $true
				$photos[$j] = $null
				break
			}
			if (-not $pairFound) {
				Write-PhotoSegment -Photo $pmd
				$neededSpace += 1
				$photos[$i] = $null
			}
		}
	}
}

function Write-PhotoSegment {
	param(
		[ThePhoto]$Photo,
		[ThePhoto]$Other = $null
	)
	if ($true `
			-and (-not $Other) `
			-and (-not $Photo.GetHumanDate())) {
		return ( "" `
				+ "\photoFC" `
				+ "{$($Photo.GetOptimalWidth())}" `
				+ "{$($Photo.Path | Resolve-RelativePath)}" `
				+ "{}" `
				+ "{0}" `
				+ "{0}" )
	}
	
	$prefix = "\photoNouveauN"

	$first = ( "" `
			+ "{ $($Photo.Path | Resolve-RelativePath) }" `
			+ "{ $($Photo.GetOptimalWidth())mm }" `
			+ "{ $($Photo.GetHumanDate()); " `
			+ "$($Photo.Comment) }" )

	$second = "{}{}{}"
	if ($Other) {
		$second = ( "" `
				+ "{ $($Other.Path | Resolve-RelativePath) }" `
				+ "{ $($Other.GetOptimalWidth())mm }" `
				+ "{ $($Other.GetHumanDate()); " `
				+ "$($Other.Comment) }" )
	}

	return ($prefix, $first, $second -join "" )
}

function Import-TagLibSharp {
	[Cmdletbinding()]
	param(
		$NugetLibrary = "TagLibSharp",
		$LibrarySegment = "taglibsharp/lib/netstandard2.0/TagLibSharp.dll"
	)
	$LibrarySegment = Join-Path $PSScriptRoot $LibrarySegment | Get-Item
	if (-not (Test-Path $LibrarySegment)) {
		$libDir = New-Item -ItemType Directory -Force "$($PSScriptRoot)/taglibsharp"
		Register-PackageSource -Name MyNuGet -Location https: / / www.nuget.org / api / v2 -ProviderName NuGet -Force
		Find-Package -Provider NuGet -Name $NugetLibrary | Save-Package -Path $libDir
		Expand-Archive $libDir / * .nupkg -DestinationPath $libDir
	}
	Add-Type -Path $LibrarySegment
	$script:assembly = [System.Reflection.Assembly]::LoadFrom($LibrarySegment)
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


function New-ThePhotoSymbolicLink {
	[Cmdletbinding()]
	param(
		$InputFiles = "*",
		[Parameter(Mandatory)]
		$OutputDir
	)
	if (-not (Test-Path -Path $OutputDir)) {
		throw "Output directory $OutputDir does not exist"
	}
	Read-ThePhotos -Path $InputFiles `
	| % { 
		New-Item `
			-ItemType SymbolicLink `
			-Value $_.Path `
			-Path "./$($OutputDir)/$($_.GetOrderPos())__$($_.GetPath().Name)" `
		| Out-Null
	} 
}

Import-TagLibSharp

Export-ModuleMember -Function Write-ThePhotos, Add-ThePhoto, Read-ThePhotos, New-ThePhotoSymbolicLink
