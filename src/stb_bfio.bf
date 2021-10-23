using System;
using System.IO;

// stbi IO handling for beef is here for maintaining purposes
// stb_image.bf was ported without io code. (STBI_NO_STDIO)
// stb_image_write.bf was ported without io code. (STBI_WRITE_NO_STDIO)

#if !STB_NO_BFIO
namespace stb_image
{
	extension stbi
	{
		static int32 bf_stbi__bfio_read(void *user, uint8 *data, int32 size)
		{
			var stream = (Stream)Internal.UnsafeCastToObject(user);
			// fread(data,1,size,(FILE*) user);
			let res = stream.TryRead(Span<uint8>(data, size));
			switch (res)
			{
			case .Ok(let val):
				return (int32)val;
			case .Err:
				return -1;
			}
		}

		static void bf_stbi__bfio_skip(void *user, int32 n)
		{
			var stream = (Stream)Internal.UnsafeCastToObject(user);
			// fseek((FILE*) user, n, SEEK_CUR);

			// Not sure if using seek is better overall, but it also just errors sometimes.
			if (stream.Position + n > stream.Length)
			{
				stream.Position = stream.Length;
			}
			else stream.Position += n;

		   //int32 ch;
		   //fseek((FILE*) user, n, SEEK_CUR);
		   //ch = fgetc((FILE*) user);  /* have to read a byte to reset feof()'s flag */
		   //if (ch != EOF) {
		   //   ungetc(ch, (FILE *) user);  /* push byte back onto stream if valid. */
		   //}
		}

		static bool bf_stbi__bfio_eof(void *user)
		{
			var stream = (Stream)Internal.UnsafeCastToObject(user);
			return stream.Length == stream.Position;
		   //return feof((FILE*) user) || ferror((FILE *) user);
		}

		static stbi_io_callbacks bf_stbi__bfio_callbacks = .()
		{
		   read = => bf_stbi__bfio_read,
		   skip = => bf_stbi__bfio_skip,
		   eof = => bf_stbi__bfio_eof,
		};

		static void bf_stbi__start_file(stbi__context *s, void *f)
		{
		   stbi__start_callbacks(s, &bf_stbi__bfio_callbacks, (void *) f);
		}

/*#if BF_PLATFORM_WINDOWS && !STBI_WINDOWS_UTF8
		[CallingConvention(.Stdcall),Import("kernel32.lib")]
		static extern int32 MultiByteToWideChar(uint32 cp, uint64 flags, char8 *str, int32 cbmb, char16 *widestr, int32 cchwide);
		static extern int32 WideCharToMultiByte(uint32 cp, uint64 flags, char16 *widestr, int32 cchwide, char8 *str, int32 cbmb, char8 *defchar, int32 *used_default);

		public static int32 stbi_convert_wchar_to_utf8(char8 *buffer, int bufferlen, char16* input)
		{
			return WideCharToMultiByte(65001 /* UTF8 */, 0, input, -1, buffer, (int32) bufferlen, null, null);
		}
#endif*/

		// TODO rewrite this for beef, use functions as skeletons, but content will need to change as well as args (and thus parts of the name)

		static void *stbi__fopen(char8 *filename, char8 *mode)
		{
			// TODO

			return null;

		   /*FILE *f;
#if BF_PLATFORM_WINDOWS && !STBI_WINDOWS_UTF8
		   char16[64] wMode;
		   char16[1024] wFilename;
			if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, filename, -1, &wFilename[0], sizeof(decltype(wFilename))/sizeof(char16)))
		      return 0;

			if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, mode, -1, &wMode, sizeof(decltype(wMode))/sizeof(char16)))
		      return 0;

			if (0 != _wfopen_s(&f, wFilename, wMode))
				f = 0;

#elif defined(_MSC_VER) && _MSC_VER >= 1400
		   if (0 != fopen_s(&f, filename, mode))
		      f=0;
#else
		   f = fopen(filename, mode);
#endif
		   return f;*/
		}


		/*public static stbi_uc *stbi_load(char const *filename, int *x, int *y, int *comp, int req_comp)
		{
		   FILE *f = stbi__fopen(filename, "rb");
		   unsigned char *result;
		   if (!f) return stbi__errpuc("can't fopen", "Unable to open file");
		   result = stbi_load_from_file(f,x,y,comp,req_comp);
		   fclose(f);
		   return result;
		}

		public static stbi_uc *stbi_load_from_file(FILE *f, int *x, int *y, int *comp, int req_comp)
		{
		   unsigned char *result;
		   stbi__context s;
		   stbi__start_file(&s,f);
		   result = stbi__load_and_postprocess_8bit(&s,x,y,comp,req_comp);
		   if (result) {
		      // need to 'unget' all the characters in the IO buffer
		      fseek(f, - (int) (s.img_buffer_end - s.img_buffer), SEEK_CUR);
		   }
		   return result;
		}

		public static stbi__uint16 *stbi_load_from_file_16(FILE *f, int *x, int *y, int *comp, int req_comp)
		{
		   stbi__uint16 *result;
		   stbi__context s;
		   stbi__start_file(&s,f);
		   result = stbi__load_and_postprocess_16bit(&s,x,y,comp,req_comp);
		   if (result) {
		      // need to 'unget' all the characters in the IO buffer
		      fseek(f, - (int) (s.img_buffer_end - s.img_buffer), SEEK_CUR);
		   }
		   return result;
		}

		public static stbi_us *stbi_load_16(char const *filename, int *x, int *y, int *comp, int req_comp)
		{
		   FILE *f = stbi__fopen(filename, "rb");
		   stbi__uint16 *result;
		   if (!f) return (stbi_us *) stbi__errpuc("can't fopen", "Unable to open file");
		   result = stbi_load_from_file_16(f,x,y,comp,req_comp);
		   fclose(f);
		   return result;
		}*/

		/** @PORT: keep in mind that defines are local to files, so we need the same enable/disable mechanisms here

		#if !STBI_NO_STDIO




#endif //!STBI_NO_STDIO

		#if !STBI_NO_LINEAR
		#if !STBI_NO_STDIO
		public static float *stbi_loadf(char const *filename, int *x, int *y, int *comp, int req_comp)
		{
		   float *result;
		   FILE *f = stbi__fopen(filename, "rb");
		   if (!f) return stbi__errpf("can't fopen", "Unable to open file");
		   result = stbi_loadf_from_file(f,x,y,comp,req_comp);
		   fclose(f);
		   return result;
		}

		public static float *stbi_loadf_from_file(FILE *f, int *x, int *y, int *comp, int req_comp)
		{
		   stbi__context s;
		   stbi__start_file(&s,f);
		   return stbi__loadf_main(&s,x,y,comp,req_comp);
		}
#endif // !STBI_NO_STDIO
		#endif


		#if !STBI_NO_STDIO
		public static int      stbi_is_hdr          (char const *filename)
		{
		   FILE *f = stbi__fopen(filename, "rb");
		   int result=0;
		   if (f) {
		      result = stbi_is_hdr_from_file(f);
		      fclose(f);
		   }
		   return result;
		}

		public static int stbi_is_hdr_from_file(FILE *f)
		{
		   #ifndef STBI_NO_HDR
		   long pos = ftell(f);
		   int res;
		   stbi__context s;
		   stbi__start_file(&s,f);
		   res = stbi__hdr_test(&s);
		   fseek(f, pos, SEEK_SET);
		   return res;
		   #else
		   STBI_NOTUSED(f);
		   return 0;
		   #endif
		}
#endif // !STBI_NO_STDIO


		#if !STBI_NO_STDIO
		public static int stbi_info(char const *filename, int *x, int *y, int *comp)
		{
		    FILE *f = stbi__fopen(filename, "rb");
		    int result;
		    if (!f) return stbi__err("can't fopen", "Unable to open file");
		    result = stbi_info_from_file(f, x, y, comp);
		    fclose(f);
		    return result;
		}

		public static int stbi_info_from_file(FILE *f, int *x, int *y, int *comp)
		{
		   int r;
		   stbi__context s;
		   long pos = ftell(f);
		   stbi__start_file(&s, f);
		   r = stbi__info_main(&s,x,y,comp);
		   fseek(f,pos,SEEK_SET);
		   return r;
		}

		public static int stbi_is_16_bit(char const *filename)
		{
		    FILE *f = stbi__fopen(filename, "rb");
		    int result;
		    if (!f) return stbi__err("can't fopen", "Unable to open file");
		    result = stbi_is_16_bit_from_file(f);
		    fclose(f);
		    return result;
		}

		public static int stbi_is_16_bit_from_file(FILE *f)
		{
		   int r;
		   stbi__context s;
		   long pos = ftell(f);
		   stbi__start_file(&s, f);
		   r = stbi__is_16_main(&s);
		   fseek(f,pos,SEEK_SET);
		   return r;
		}
#endif // !STBI_NO_STDIO
		*/
	}
}
#endif

#if !STBI_WRITE_NO_BFIO
namespace stb_image_write
{
	/*extension stbiw
	{
		/**
		#if !STBI_WRITE_NO_STDIO

		static void stbi__stdio_write(void *context, void *data, int size)
		{
		   fwrite(data,1,size,(FILE*) context);
		}

#if defined(_WIN32) && defined(STBIW_WINDOWS_UTF8)
#ifdef __cplusplus
#define STBIW_EXTERN extern "C"
#else
#define STBIW_EXTERN extern
#endif
		STBIW_EXTERN __declspec(dllimport) int __stdcall MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *str, int cbmb, wchar_t *widestr, int cchwide);
		STBIW_EXTERN __declspec(dllimport) int __stdcall WideCharToMultiByte(unsigned int cp, unsigned long flags, const wchar_t *widestr, int cchwide, char *str, int cbmb, const char *defchar, int *used_default);

		public static int stbiw_convert_wchar_to_utf8(char *buffer, size_t bufferlen, const wchar_t* input)
		{
		   return WideCharToMultiByte(65001 /* UTF8 */, 0, input, -1, buffer, (int) bufferlen, NULL, NULL);
		}
#endif

		static FILE *stbiw__fopen(char const *filename, char const *mode)
		{
		   FILE *f;
#if defined(_WIN32) && defined(STBIW_WINDOWS_UTF8)
		   wchar_t wMode[64];
		   wchar_t wFilename[1024];
		   if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, filename, -1, wFilename, sizeof(wFilename)/sizeof(*wFilename)))
		      return 0;

		   if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, mode, -1, wMode, sizeof(wMode)/sizeof(*wMode)))
		      return 0;

#if defined(_MSC_VER) && _MSC_VER >= 1400
		   if (0 != _wfopen_s(&f, wFilename, wMode))
		      f = 0;
#else
		   f = _wfopen(wFilename, wMode);
#endif

#elif defined(_MSC_VER) && _MSC_VER >= 1400
		   if (0 != fopen_s(&f, filename, mode))
		      f=0;
#else
		   f = fopen(filename, mode);
#endif
		   return f;
		}

		static int stbi__start_write_file(stbi__write_context *s, const char *filename)
		{
		   FILE *f = stbiw__fopen(filename, "wb");
		   stbi__start_write_callbacks(s, stbi__stdio_write, (void *) f);
		   return f != NULL;
		}

		static void stbi__end_write_file(stbi__write_context *s)
		{
		   fclose((FILE *)s.context);
		}

#endif // !STBI_WRITE_NO_STDIO

		#if !STBI_WRITE_NO_STDIO
		public static int stbi_write_bmp(char const *filename, int x, int y, int comp, const void *data)
		{
		   stbi__write_context s = { 0 };
		   if (stbi__start_write_file(&s,filename)) {
		      int r = stbi_write_bmp_core(&s, x, y, comp, data);
		      stbi__end_write_file(&s);
		      return r;
		   } else
		      return 0;
		}
#endif //!STBI_WRITE_NO_STDIO

		#if !STBI_WRITE_NO_STDIO
		public static int stbi_write_tga(char const *filename, int x, int y, int comp, const void *data)
		{
		   stbi__write_context s = { 0 };
		   if (stbi__start_write_file(&s,filename)) {
		      int r = stbi_write_tga_core(&s, x, y, comp, (void *) data);
		      stbi__end_write_file(&s);
		      return r;
		   } else
		      return 0;
		}
#endif

		#ifndef STBI_WRITE_NO_STDIO

		static void stbiw__linear_to_rgbe(unsigned char *rgbe, float *linear)
		{
		   int exponent;
		   float maxcomp = stbiw__max(linear[0], stbiw__max(linear[1], linear[2]));

		   if (maxcomp < 1e-32f) {
		      rgbe[0] = rgbe[1] = rgbe[2] = rgbe[3] = 0;
		   } else {
		      float normalize = (float) frexp(maxcomp, &exponent) * 256.0f/maxcomp;

		      rgbe[0] = (unsigned char)(linear[0] * normalize);
		      rgbe[1] = (unsigned char)(linear[1] * normalize);
		      rgbe[2] = (unsigned char)(linear[2] * normalize);
		      rgbe[3] = (unsigned char)(exponent + 128);
		   }
		}

		static void stbiw__write_run_data(stbi__write_context *s, int length, unsigned char databyte)
		{
		   unsigned char lengthbyte = STBIW_UCHAR(length+128);
		   STBIW_ASSERT(length+128 <= 255);
		   s.func(s.context, &lengthbyte, 1);
		   s.func(s.context, &databyte, 1);
		}

		static void stbiw__write_dump_data(stbi__write_context *s, int length, unsigned char *data)
		{
		   unsigned char lengthbyte = STBIW_UCHAR(length);
		   STBIW_ASSERT(length <= 128); // inconsistent with spec but consistent with official code
		   s.func(s.context, &lengthbyte, 1);
		   s.func(s.context, data, length);
		}

		static void stbiw__write_hdr_scanline(stbi__write_context *s, int width, int ncomp, unsigned char *scratch, float *scanline)
		{
		   unsigned char scanlineheader[4] = { 2, 2, 0, 0 };
		   unsigned char rgbe[4];
		   float linear[3];
		   int x;

		   scanlineheader[2] = (width&0xff00)>>8;
		   scanlineheader[3] = (width&0x00ff);

		   /* skip RLE for images too small or large */
		   if (width < 8 || width >= 32768) {
		      for (x=0; x < width; x++) {
		         switch (ncomp) {
		            case 4: /* fallthrough */
		            case 3: linear[2] = scanline[x*ncomp + 2];
		                    linear[1] = scanline[x*ncomp + 1];
		                    linear[0] = scanline[x*ncomp + 0];
		                    break;
		            default:
		                    linear[0] = linear[1] = linear[2] = scanline[x*ncomp + 0];
		                    break;
		         }
		         stbiw__linear_to_rgbe(rgbe, linear);
		         s.func(s.context, rgbe, 4);
		      }
		   } else {
		      int c,r;
		      /* encode into scratch buffer */
		      for (x=0; x < width; x++) {
		         switch(ncomp) {
		            case 4: /* fallthrough */
		            case 3: linear[2] = scanline[x*ncomp + 2];
		                    linear[1] = scanline[x*ncomp + 1];
		                    linear[0] = scanline[x*ncomp + 0];
		                    break;
		            default:
		                    linear[0] = linear[1] = linear[2] = scanline[x*ncomp + 0];
		                    break;
		         }
		         stbiw__linear_to_rgbe(rgbe, linear);
		         scratch[x + width*0] = rgbe[0];
		         scratch[x + width*1] = rgbe[1];
		         scratch[x + width*2] = rgbe[2];
		         scratch[x + width*3] = rgbe[3];
		      }

		      s.func(s.context, scanlineheader, 4);

		      /* RLE each component separately */
		      for (c=0; c < 4; c++) {
		         unsigned char *comp = &scratch[width*c];

		         x = 0;
		         while (x < width) {
		            // find first run
		            r = x;
		            while (r+2 < width) {
		               if (comp[r] == comp[r+1] && comp[r] == comp[r+2])
		                  break;
		               ++r;
		            }
		            if (r+2 >= width)
		               r = width;
		            // dump up to first run
		            while (x < r) {
		               int len = r-x;
		               if (len > 128) len = 128;
		               stbiw__write_dump_data(s, len, &comp[x]);
		               x += len;
		            }
		            // if there's a run, output it
		            if (r+2 < width) { // same test as what we break out of in search loop, so only true if we break'd
		               // find next byte after run
		               while (r < width && comp[r] == comp[x])
		                  ++r;
		               // output run up to r
		               while (x < r) {
		                  int len = r-x;
		                  if (len > 127) len = 127;
		                  stbiw__write_run_data(s, len, comp[x]);
		                  x += len;
		               }
		            }
		         }
		      }
		   }
		}

		static int stbi_write_hdr_core(stbi__write_context *s, int x, int y, int comp, float *data)
		{
		   if (y <= 0 || x <= 0 || data == NULL)
		      return 0;
		   else {
		      // Each component is stored separately. Allocate scratch space for full output scanline.
		      unsigned char *scratch = (unsigned char *) STBIW_MALLOC(x*4);
		      int i, len;
		      char buffer[128];
		      char header[] = "#?RADIANCE\n# Written by stb_image_write.h\nFORMAT=32-bit_rle_rgbe\n";
		      s.func(s.context, header, sizeof(header)-1);

#ifdef __STDC_LIB_EXT1__
		      len = sprintf_s(buffer, sizeof(buffer), "EXPOSURE=          1.0000000000000\n\n-Y %d +X %d\n", y, x);
#else
		      len = sprintf(buffer, "EXPOSURE=          1.0000000000000\n\n-Y %d +X %d\n", y, x);
#endif
		      s.func(s.context, buffer, len);

		      for(i=0; i < y; i++)
		         stbiw__write_hdr_scanline(s, x, comp, scratch, data + comp*x*(stbi__flip_vertically_on_write ? y-1-i : i));
		      STBIW_FREE(scratch);
		      return 1;
		   }
		}

		public static int stbi_write_hdr_to_func(stbi_write_func *func, void *context, int x, int y, int comp, const float *data)
		{
		   stbi__write_context s = { 0 };
		   stbi__start_write_callbacks(&s, func, context);
		   return stbi_write_hdr_core(&s, x, y, comp, (float *) data);
		}

		public static int stbi_write_hdr(char const *filename, int x, int y, int comp, const float *data)
		{
		   stbi__write_context s = { 0 };
		   if (stbi__start_write_file(&s,filename)) {
		      int r = stbi_write_hdr_core(&s, x, y, comp, (float *) data);
		      stbi__end_write_file(&s);
		      return r;
		   } else
		      return 0;
		}
#endif // STBI_WRITE_NO_STDIO
		*/
	}*/
}
#endif
