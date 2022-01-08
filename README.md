# STB for Beef
This is a pure port of the stb headers. For maintainability, the files remain very close to the c headers, but with unsupported parts stripped out (i.e. stio). All names have stayed the same.

Every file / "header" has it's own namespace ("stb_image") and the main content is contained inside a static class inside that namespace ("stb_image.stbi"). So you may choose to either do ``using stb_image;`` or ``using static stb_image.stbi;`` depending on how much seperation you prefer.

For more info, see the comments at the top of each file.

Original: [STB](https://github.com/nothings/stb)

## Maintaining
At the top of each file is the commit at which the port was performed.
Changes i deemed to be meaningful are sometimes annotated with "@PORT". Casts between number sizes i had to add are sometimes explicit when it's required, but otherwise often inferred with "(.)".

## Early stages
Please note that, while the ports in here are technically complete, errors may have occured while porting (it's usually something related to number math with differing int sizes). Most code is untested. Please report (or fix and pull) those.

**Known problems**:
- stbi bigger pngs return "zlib corrupt"
- stbi smaller pngs may have weird artifacts / shifts. Some also just work
- stbi jpgs return "bad huffman code"

**Untested**:
- other stbi formats than PNG & JPG
- less common stbtt functionality (what you don't typically use for bitmap baking / displaying)
