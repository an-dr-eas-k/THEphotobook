#
# pwsh -wd (Get-Location) -command { ls ./media/working/ | %{ Write-ThePhotos -Path "$_/*" -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; make -B }
#
# pwsh -wd (Get-Location) -command { ls ./media/ordered/ | %{ Write-ThePhotos -Path "$_/*" -SortProperty Path -Verbose > "./content.$($_.name.ToLower() -replace ' ','' ).tex" }; rm ./root.aux; make -B}
#

$script:MaxPicWidth = 170
$script:MaxPageHeight = 180

class AdditionalMetaData {

	[Nullable[int]]$FixedWidth
	[Nullable[int]]$NeighborsWanted
}

class ThePhoto {

	[string]$Path;
	[int]$Width;
	[int]$Height;
	[bool]$Upright;
	[datetime]$Date;
	[string]$Comment;
	[int]$OrderPos;
	[AdditionalMetaData]$MetaJsonFromTitle

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

		@{
			"exif"          = $metadata.Tag.Exif.DateTimeOriginal
			"xmp"           = $metadata.ImageTag.Xmp.NodeTree.Children 
			"xmpParsed"     = ($metadata.ImageTag.Xmp.NodeTree.Children | ? { $_.Name -eq "DateTimeOriginal" } | % Value) 
			"lastwritetime" = $path.LastWriteTime 
		} | ConvertTo-Json | Write-Debug
		$dateString = $null `
			?? $metadata.Tag.Exif.DateTimeOriginal `
			?? ($metadata.ImageTag.Xmp.NodeTree.Children | ? { $_.Name -eq "DateTimeOriginal" } | % Value) `
			?? $path.LastWriteTime `
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

	[int] GetOptimalHeight() {
		return $this.GetOptimalWidth() / $this.Width * $this.Height
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

	$neededSpace = 0
	for ($i = 0; $i -lt $photos.Length; $i++) {
		[ThePhoto]$pmd = $photos[$i]
		if (-not $pmd) {
			continue
		}
		$photos[$i] = $null
		if ($neededSpace -gt $script:MaxPageHeight) {
			"\clearpage  % $neededSpace"
			$neededSpace = 0
		}
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
		if ($third) {
			Write-PhotoSegment -Photo $pmd -Other $other -Third $third
			$neededSpace += [System.Math]::Max([System.Math]::Max($pmd.GetOptimalHeight(), $other.GetOptimalHeight()), $third.GetOptimalHeight())
		}
		elseif ($other) {
			Write-PhotoSegment -Photo $pmd -Other $other
			$neededSpace += [System.Math]::Max($pmd.GetOptimalHeight(), $other.GetOptimalHeight())
		}
		else {
			Write-PhotoSegment -Photo $pmd
			$neededSpace += $pmd.GetOptimalHeight()
		}
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
	
	if ($Third) {
		$prefix = "\photoNouveauM{$($script:MaxPicWidth)mm}"

		$firstSegment = ( "" `
				+ "{ $($Photo.Path | Resolve-RelativePath) }" `
				+ "{ $($Photo.GetHumanDate()); " `
				+ "$($Photo.Comment) }" )

		$secondSegment = ( "" `
				+ "{ $($Other.Path | Resolve-RelativePath) }" `
				+ "{ $($Other.GetHumanDate()); " `
				+ "$($Other.Comment) }" )

		$thirdSegment = ( "" `
				+ "{ $($Third.Path | Resolve-RelativePath) }" `
				+ "{ $($Third.GetHumanDate()); " `
				+ "$($Third.Comment) }" )

		return ($prefix, $firstSegment, $secondSegment, $thirdSegment -join "" )
	}
	elseif ($Photo.GetHumanDate()) {
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
 else {
		return ( "" `
				+ "\photoFC" `
				+ "{$($Photo.GetOptimalWidth())}" `
				+ "{$($Photo.Path | Resolve-RelativePath)}" `
				+ "{}" `
				+ "{0}" `
				+ "{0}" )
	}

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

Import-TagLibSharp

Export-ModuleMember -Function Write-ThePhotos, Add-ThePhoto, Read-ThePhotos, New-ThePhotoSymbolicLink
