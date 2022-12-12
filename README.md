_ThePhotobook_ is a set of latex styles and scripts to fastly sketch simple photobooks ready to print from pdf.

A ```pwsh``` module is attached that stiches your photos together, ordered based on the time the photo was taken (unless present, file modification time is taken). Various style options are applied depending on e.g. your photo orientation.

The ```latex``` style sheet surrounds the photos with a little border that encloses photo date and description.

## Example

The github version includes example files. See the ```./media/``` folder that contains few files.

The ```./content/``` folder holds the final [photobook](./content/root.copy.pdf) produced from the example photos.

You see, photos with their date, the description, the style of upright shots, and the cronologic ordering.

## Usage

1. You manually populate photos into the ```/media``` folder.
1. Use your preferred photo viewer and add the photo descriptions you like to the exif comment field.
1. Import the attached ```pwsh``` module
	```
	Import-Module -Force lib/pwsh/ThePhotobook.psm1
	```
1. Call 
	```
	Write-ThePhotos ./media/ > ./content.tex
	```
	within the ```./content/``` folder.
1. Call ```make``` to compile your first version of the photobook.

## Requirements

Install latex, pwsh and jhead.

Place [MetadataExtractor](https://github.com/drewnoakes/metadata-extractor-dotnet) in ```lib/pwsh``` folder.