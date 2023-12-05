#
# pwsh -wd (Get-Location) -command { ls ./media/working/ | %{ Write-ThePhotos -Path "$_/*" -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; make -B }
#
# pwsh -wd (Get-Location) -command { ls ./media/ordered/ | %{ Write-ThePhotos -Path "$_/*" -SortProperty Path -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; rm ./root.aux; make -B}
#

$script:MaxPicWidth = 170
$script:MaxPageHeight = 180
$script:OptimalPicHeight = 115

class AdditionalMetaData {

	[Nullable[int]]$FixedWidth
	[Nullable[int]]$NeighborsWanted
	[Nullable[bool]]$ClearBefore
}

class ThePhoto {

	[string]$Path;
	[int]$Width;
	[int]$Height;
	[bool]$Upright;
	[datetime]$Date;
	[string]$Comment;
	[int]$OrderPos;
	[AdditionalMetaData]$MetaJsonFromTitle;
	[System.Collections.ArrayList]$Messages = [System.Collections.ArrayList]::new()


	ThePhoto(	[System.IO.FileInfo]$Path	) {
		$this.Path = $Path
		try {
			$this.readTagsWithTagLib($Path)
		}
		catch {
			"problem with image $path" | Write-Error
			$_ | Write-Error
		}
	}

	[datetime] readPhotoDate($dateString) {
		$errors = @()
		foreach ($f in @( { [datetime]$args[0] }, { [System.DateTime]::ParseExact($args[0], 'yyyy:MM:dd HH:mm:ss', $null) })) {
			try {
				return $f.Invoke($dateString)[0]
			}
			catch [System.Exception] { $errors += $_ }
		}
		throw ("errors: ", $errors) 
	}

	[void] readDateWithTagLib($metadata, [System.IO.FileInfo]$path) {
		# [TagLib.IFD.Tags.IFDEntryTag]::DateTime = 306, see below
		$dateString = $null `
			?? $metadata.Tag.Exif.DateTimeOriginal `
			?? $metadata.ImageTag.Xmp.DateTime `
			?? $metadata.ImageTag.Exif.Structure.GetDateTimeValue(0, 306) `
			?? $( `
				$this.Messages.Add( "using imagemagick") | Out-Null; 
				(& convert $path.FullName json: ) | ConvertFrom-Json | % { $_.Image.properties."exif:DateTime" } ) `
			?? $( `
				$this.Messages.Add( "using LastWriteTime") | Out-Null; 
				($path.LastWriteTime ) ) `
			?? ""
		if ($dateString -is [datetime]) {
			$this.Date = $dateString
		}
		else {
			$this.Date = $this.readPhotoDate($dateString)
		}
	}

	[void] readTagsWithTagLib([System.IO.FileInfo]$path) {
		$metadata = $script:assembly.GetType("TagLib.File").GetMethod("Create", "String").Invoke($null, @($path.FullName))
		$this.Height = $metadata.Properties.PhotoHeight
		$this.Width = $metadata.Properties.PhotoWidth
		$this.Upright = $this.Height -gt $this.Width
		$this.Comment = ($metadata.Tag.Comment	-replace ("&", "\&") -replace ("digital camera", "")).Trim()
		$this.MetaJsonFromTitle = ($metadata.Tag.Title ?? "" ) | ConvertFrom-Json -ErrorAction Continue
		$this.readDateWithTagLib($metadata, $path)
	}

	[int] GetOptimalWidth() {

		$fixedWidth = $this.MetaJsonFromTitle.FixedWidth
		if ($fixedWidth) {
			return $fixedWidth
		}

		return [Math]::Min($script:OptimalPicHeight / $this.Height * $this.Width, $script:MaxPicWidth)
	}

	[int] GetOptimalHeight() {
		return $this.GetOptimalWidth() / $this.Width * $this.Height
	}

	[bool] ClearBefore() {
		return $this.MetaJsonFromTitle.ClearBefore
	}
	
	[bool] RequestThirdNeighbor() {
		if ($this.MetaJsonFromTitle.NeighborsWanted -eq 2) {
			return $true
		}
		return $false
		# -and ($pmd.GetOptimalWidth() + $other.GetOptimalWidth() -lt $script:MaxPicWidth)) {
	}

	[bool] IsNeighborPossible() {
		if ($this.MetaJsonFromTitle.NeighborsWanted -eq 0) {
			return $false
		}
		if ($this.GetOptimalWidth() -gt ($script:MaxPicWidth / 3 * 2)) {
			return $false
		}

		return $this.Upright
	}
	
	[string] GetHumanDate() {
		if ($this.Date.ToLongTimeString() -eq "00:00:00") {
			return ""
		}
		return Get-Date -Format "dd. MMMM yyyy" -date $this.Date
	}

	[string] ToString() {
		$validProperties = $this.GetType().GetProperties() | % Name | ? { $this.psobject.Properties[$_].Value }
		return $this | Select-Object $validProperties | ConvertTo-Json -Compress
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

	$neededSpace = 0
	for ($i = 0; $i -lt $photos.Length; $i++) {
		[ThePhoto]$pmd = $photos[$i]
		if (-not $pmd) {
			continue
		}
		$photos[$i] = $null
		[ThePhoto]$other = $null
		[ThePhoto]$third = $null
		if ($pmd.IsNeighborPossible()) {
			$other = Find-Neighbor -StartPos $i -WinSize $WinSize -PhotoList ([ref]$photos)
			if ($true `
					-and $other `
					-and $pmd.RequestThirdNeighbor()) {
				"%% searching for third neighbor primary is $($pmd.Path)"
				$third = Find-Neighbor -StartPos ($i + 1) -WinSize $WinSize -PhotoList ([ref]$photos)
			}
		}

		if ($false `
				-or ($neededSpace -gt $script:MaxPageHeight) `
				-or ($pmd.ClearBefore() || ((!!$other) ? $other.ClearBefore() : $false) || ((!!$third) ? $third.ClearBefore() : $false))) {
			"\clearpage  % neededSpace: $neededSpace"
			$neededSpace = 0
		}
		"% neededSpace: $neededSpace" 

		$neededSpace += `
		($pmd.GetOptimalHeight(), ((!!$other) ? $other.GetOptimalHeight() : 0), ((!!$third) ? $third.GetOptimalHeight() : 0)) `
		| Sort-Object -Descending `
		| Select-Object -First 1

		Write-PhotoSegment -Photo $pmd -Other $other -Third $third
	}
}

function Find-Neighbor {
	[CmdletBinding()]
	param (
		$StartPos,
		$WinSize,
		$PhotoList
	)
	$r = @()
	$r += (($StartPos + 1)..($StartPos + $WinSize))
	foreach ($j in $r) {
		[ThePhoto]$other = $PhotoList.Value[$j]
		if ( ($other) -and ($other.IsNeighborPossible())) {
			$PhotoList.Value[$j] = $null
			return $other
		}
	}
}

function Write-PhotoSegment {
	param(
		[ThePhoto]$Photo,
		[ThePhoto]$Other = $null,
		[ThePhoto]$Third = $null
	)
	$segment = ""
	
	if ($Third) {
		$prefix = "\photoNouveauM{$($script:MaxPicWidth)mm}"

		$firstSegment = ( "" `
				+ "{$($Photo.Path | Resolve-RelativePath)}" `
				+ "{$($Photo.GetHumanDate()); " `
				+ "$($Photo.Comment)}" `
				+ "`n% ThePhoto: " + ($Photo.ToString())
		)

		$secondSegment = ( "" `
				+ "{$($Other.Path | Resolve-RelativePath)}" `
				+ "{$($Other.GetHumanDate()); " `
				+ "$($Other.Comment)}" `
				+ "`n% ThePhoto: " + ($Other.ToString())
		)

		$thirdSegment = ( "" `
				+ "{$($Third.Path | Resolve-RelativePath)}" `
				+ "{$($Third.GetHumanDate()); " `
				+ "$($Third.Comment)}" `
				+ "`n% ThePhoto: " + ($Third.ToString())
		)

		$segment = ($prefix, $firstSegment, $secondSegment, $thirdSegment -join "`n  " )
	}
	elseif ((!!($Photo.GetHumanDate())) || (!!$Other)) {
		$prefix = "\photoNouveauN"

		$first = ( "" `
				+ "{$($Photo.Path | Resolve-RelativePath)}" `
				+ "{$($Photo.GetOptimalWidth())mm}" `
				+ "{$($Photo.GetHumanDate()); " `
				+ "$($Photo.Comment)}" `
				+ "`n% ThePhoto: " + ($Photo.ToString())
		)

		$second = "{}{}{}"
		if ($Other) {
			$second = ( "" `
					+ "{$($Other.Path | Resolve-RelativePath)}" `
					+ "{$($Other.GetOptimalWidth())mm}" `
					+ "{$($Other.GetHumanDate()); " `
					+ "$($Other.Comment)}" `
					+ "`n% ThePhoto: " + ($Other.ToString())
			)
		}
		$segment = ($prefix, $first, $second -join "`n  " )
	}
	else {
		$segment = ( "" `
				+ "\photoFC" `
				+ "{$($Photo.GetOptimalWidth())}" `
				+ "{$($Photo.Path | Resolve-RelativePath)}" `
				+ "{}" `
				+ "{0}" `
				+ "{0}" `
				+ "`n% ThePhoto: " + ($Photo.ToString())
		)
	}
	$segment	| Write-Output
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
		Register-PackageSource -Name MyNuGet -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -Force
		Find-Package -Provider NuGet -Name $NugetLibrary | Save-Package -Path $libDir
		Expand-Archive "$libDir/*.nupkg" -DestinationPath $libDir
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

function Read-ThePhotoTags {
	[Cmdletbinding()]
	param(
		[Parameter(Mandatory)]
		$InputFile
	)
	$InputFile = $InputFile | Get-Item
	$InputFile.FullName | Write-Verbose
	$script:assembly.GetType("TagLib.File").GetMethod("Create", "String").Invoke($null, @(($InputFile.FullName)))
}

Import-TagLibSharp

Export-ModuleMember -Function Write-ThePhotos, Add-ThePhoto, Read-ThePhotos, New-ThePhotoSymbolicLink, Read-ThePhotoTags
