_ThePhotobook_ is a set of latex styles and scripts to fastly sketch simple photobooks ready to print from pdf.

A ```pwsh``` module is attached that stiches your photos together, ordered based on the time the photo was taken (unless present, file modification time is taken). Various style options are applied depending on e.g. your photo orientation.

The ```latex``` style sheet surrounds the photos with a little border that encloses photo date and description.

## Example

The github version includes example files. See the ```./media/``` folder that contains few files.

The ```./content/``` folder holds the final [photobook](./content/root.copy.pdf) produced from the example photos.

You see, photos with their date, the description, the style of upright shots, and the cronologic ordering.

## Usage

1. You manually populate photos into the ```/media``` folder.
1. You create symbolic links to content/media folder with `new-ThePhotoSymbolicLink`
1. Use your preferred photo viewer and add exif metadata to coordinate the generation process
   * the photo descriptions/comments to annotate the photos
   * use the following tags in the title exif tag
     * FixedWidth (int): width of the photo, if original should be shrinked e.g to allow three rows of photos
	 * NeighborsWanted (int): number of neighbors to search for upright pics. Default: 1
	 * ClearBefore (bool): clears the page before adding the picture
	 example to allow easy pasting in your project:
	 ```
	 {'FixedWidth': 100}
	 {'NeighborsWanted': 0}
	 {'ClearBefore': true}
	 ```
   * Set Picture time to 00:00:00 if you want to omit the date tag. 
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