from __future__ import print_function
from os import listdir, utime
from os.path import isfile, join, getmtime
import sys
import PIL.Image
import PIL.ExifTags
from PIL.ExifTags import TAGS
from datetime import datetime
from babel.dates import format_date
from PIL import ImageOps
from PIL import Image, JpegImagePlugin as JIP


def eprint(args):
    print(args, file=sys.stderr)

def oprint(args):
    print( args )

class PhotobookEntity:

    def __init__(self):
        self.photoList = []


class PhotoMetadata:

    def __init__(self, file):
        self.file = file
        img = PIL.Image.open(file)
        self.width, self.height = img.size
        self.standing = self.height > self.width
        date = None
        try:
            date = datetime.strptime(
                PhotoMetadata.get_field(img, 'DateTimeOriginal'),
                '%Y:%m:%d %H:%M:%S')
        except Exception:
            date = datetime.fromtimestamp(getmtime(file))
            pass
        self.date = date
        self.comment = PhotoMetadata.get_field(img, 'UserComment')

        self.rotate_auto(img)

    def __str__(self):
        return self.file+': '+str(self.standing)+': '+str(self.date)

    @staticmethod
    def get_field(img, field):
        exif = img.getexif()
        if exif is None:
            return None
        for (k, v) in exif.items():
            if TAGS.get(k) == field:
                ucs = {
                    None: lambda iuc: None,
                    str: lambda iuc: str(iuc).encode('latin').decode("utf8"),
                    list: lambda iuc: None,
                    int: lambda iuc: iuc,
                    bytes: lambda iuc: None
                }.get(type(v) if v is not None else None)(v)
                return ucs
        return None

    def get_optimal_width(self):
        return min (110 / self.height * self.width, 160)
    

    def get_human_date(self):
        result = format_date(self.date, format='long', locale='de_de')
        return result

    def get_comment(self):
        return '' if self.comment is None else self.comment



    def rotate_auto(self, img):
        before = PhotoMetadata.get_field(img, 'Orientation')
        beforeTime = getmtime(self.file)
        img = ImageOps.exif_transpose(img)
        if PhotoMetadata.get_field(img, 'Orientation') == before:
            return

        img.save(
            self.file,                 # copy
            format='JPEG',
            exif=img.info['exif'],              # keep EXIF info
            optimize=True,
            qtables=img.quantization,           # keep quality
            subsampling=JIP.get_sampling(img)   # keep color res
        )
        utime(self.file, (beforeTime, beforeTime))
        eprint('rotated '+self.file+' successfully')


mypath = sys.argv[1]

onlyfiles = [
    join(mypath, f)
    for f in listdir(mypath) if (isfile(join(mypath, f)) and "ignore" not in f)
]

metaList = []
for file in onlyfiles:
    p = PhotoMetadata(file)
    metaList.append(p)

errorList = []
metaList = sorted(metaList, key=lambda f: f.date)
neededSpace = 0
for i in range(0, len(metaList)):
    pmd = metaList[i]
    if pmd is None:
        continue
    if neededSpace % 4 == 0:
        oprint("\\clearpage")
    if not pmd.standing:
        try:
            oprint(
                "\\photoNouveauN{%s}{%smm}{%s;%s}{}{}{}"
                % (pmd.file, pmd.get_optimal_width(), pmd.get_human_date(), pmd.get_comment()))
            neededSpace+=1
        except Exception:
            errorList.append(pmd.file+" "+pmd.get_human_date()+" lying")
        metaList[i] = None
    else:
        winsize = 5
        r = []
#        r.append(i)
#        r += range(i-1, i-winsize)
        r += range(i+1, i+winsize)
        pairFound = False
        for j in r:
            other = None
            try:
                other = metaList[j]
            except: pass
            if not other or not other.standing:
                continue
            try:
                oprint(
                    "\\photoNouveauN{%s}{%smm}{%s;%s}{%s}{%smm}{%s;%s}"
                    % (pmd.file, pmd.get_optimal_width(), pmd.get_human_date(), pmd.get_comment(),
                        other.file, other.get_optimal_width(), other.get_human_date(), other.get_comment()))
                neededSpace+=1
            except Exception:
                errorList.append(pmd.file+" "+pmd.get_human_date()+" pair")
                errorList.append(other.file+" "+other.get_human_date()+" pair")
            pairFound = True
            metaList[j] = None
            break
        if not pairFound:
            try:
                oprint(
                    "\\photoNouveauN{%s}{%smm}{%s;%s}{}{}{}"
                    % (pmd.file, pmd.get_optimal_width(), pmd.get_human_date(), pmd.get_comment()))
                neededSpace+=1
            except Exception:
                errorList.append(pmd.file+" "+pmd.get_human_date()+" standing")
        metaList[i] = None

eprint(errorList)
