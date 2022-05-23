// stb_image - v2.27 - public domain image loader - http://nothings.org/stb
// no warranty implied; use at your own risk
//
// LICENSE
// See end of file for license information.

// original file and documentation/usage: https://github.com/nothings/stb/blob/master/stb_image.h
// ported at 5ba0baa

// everything STDIO-related was ported to fit beef (see stb_bfio.bf), but left out here. so anything STIO related is not present anywhere anymore
// there is no SSE2 currently, so the code for that is if'd out and not ported
#define STBI_NO_SIMD

using System;
using System.Diagnostics;

namespace stb_image
{
	static class stbi
	{
		[Inline]
		static void memset(void* ptr, uint8 val, int size)
		{
			Internal.MemSet(ptr, val, size);
		}

		[Inline]
		static void memcpy(void* dest, void* src, int len)
		{
			Internal.MemCpy(dest, src, len);
		}

		public const int STBI_VERSION = 1;

		public const int
			STBI_default = 0,
			STBI_grey = 1,
			STBI_grey_alpha = 2,
			STBI_rgb = 3,
			STBI_rgb_alpha = 4;

		typealias stbi_uc = uint8;
		typealias stbi_us = uint16;

		public struct stbi_io_callbacks
		{
			public function int32(void* user, uint8* data, int32 size) read;// fill 'data' with 'size' bytes.  return number of bytes actually read
			public function void(void* user, int32 n) skip;// skip the next 'n' bytes, or 'unget' the last -n bytes if negative
			public function bool(void* user) eof;// returns nonzero if we are at end of file/data
		}

#if STBI_ONLY_JPEG || STBI_ONLY_PNG || STBI_ONLY_BMP || STBI_ONLY_TGA || STBI_ONLY_GIF || STBI_ONLY_PSD || STBI_ONLY_HDR || STBI_ONLY_PIC || STBI_ONLY_PNM || STBI_ONLY_ZLIB
	 #if !STBI_ONLY_JPEG
	 #define STBI_NO_JPEG
	 #endif
	 #if !STBI_ONLY_PNG
	 #define STBI_NO_PNG
	 #endif
	 #if !STBI_ONLY_BMP
	 #define STBI_NO_BMP
	 #endif
	 #if !STBI_ONLY_PSD
	 #define STBI_NO_PSD
	 #endif
	 #if !STBI_ONLY_TGA
	 #define STBI_NO_TGA
	 #endif
	 #if !STBI_ONLY_GIF
	 #define STBI_NO_GIF
	 #endif
	 #if !STBI_ONLY_HDR
	 #define STBI_NO_HDR
	 #endif
	 #if !STBI_ONLY_PIC
	 #define STBI_NO_PIC
	 #endif
	 #if !STBI_ONLY_PNM
	 #define STBI_NO_PNM
	 #endif
#endif

		static mixin STBI_ASSERT(var x)
		{
			Runtime.Assert((bool)x);
		}

#if !STBI_NO_THREAD_LOCALS
#define STBI_THREAD_LOCAL// @PORT just a flag for us
#endif

		typealias stbi__uint16 = uint16;
		typealias stbi__int16 = int16;
		typealias stbi__uint32 = uint32;
		typealias stbi__int32 = int32;

		static mixin stbi_lrot(var x, var y)
		{
			(((x) << (y)) | ((x) >> (-(y) & 31)))
		}

		static mixin STBI_MALLOC(var size)
		{
			Internal.Malloc(size)
		}

		static mixin STBI_FREE(void* ptr)
		{
			if (ptr != null)
				Internal.Free(ptr);
		}

		/*static mixin STBI_REALLOC(void* ptr, var newSize)
		{
			if (ptr != null)
				Internal.Free(ptr);
			Internal.Malloc((int)newSize);
		}*/

		static mixin STBI_REALLOC_SIZED(void* ptr, var oldSize, var newSize)
		{
			let newPtr = Internal.Malloc((int)newSize);
			Internal.MemCpy(newPtr, ptr, newSize > oldSize ? oldSize : newSize);
			if (ptr != null)
				Internal.Free(ptr);
			newPtr
		}

#if BF_64_BIT
#define STBI__X64_TARGET
#elif BF_32_BIT
#define STBI__X86_TARGET
#endif

		const int STBI_MAX_DIMENSIONS = (1 << 24);
		
		///////////////////////////////////////////////
		//
		//  stbi__context struct and start_xxx functions

		// stbi__context structure is our basic context used by all images, so it
		// contains all the IO context, plus some basic image information
		struct stbi__context
		{
		   public stbi__uint32 img_x, img_y;
		   public int32 img_n, img_out_n;

		   public stbi_io_callbacks io;
		   public void *io_user_data;

		   public bool read_from_callbacks;
		   public int32 buflen;
		   public stbi_uc[128] buffer_start;
		   public int32 callback_already_read;

		   public stbi_uc *img_buffer, img_buffer_end;
		   public stbi_uc *img_buffer_original, img_buffer_original_end;
		}

		// initialize a memory-decode context
		static void stbi__start_mem(stbi__context *s, stbi_uc *buffer, int len)
		{
		   s.io.read = null;
		   s.read_from_callbacks = false;
		   s.callback_already_read = 0;
		   s.img_buffer = s.img_buffer_original = (stbi_uc *) buffer;
		   s.img_buffer_end = s.img_buffer_original_end = (stbi_uc *) buffer+len;
		}

		// initialize a callback-based context
		static void stbi__start_callbacks(stbi__context *s, stbi_io_callbacks *c, void *user)
		{
		   s.io = *c;
		   s.io_user_data = user;
		   s.buflen = sizeof(decltype(s.buffer_start));
		   s.read_from_callbacks = true;
		   s.callback_already_read = 0;
		   s.img_buffer = s.img_buffer_original = &s.buffer_start[0];
		   stbi__refill_buffer(s);
		   s.img_buffer_original_end = s.img_buffer_end;
		}

		static void stbi__rewind(stbi__context *s)
		{
		   // conceptually rewind SHOULD rewind to the beginning of the stream,
		   // but we just rewind to the beginning of the initial buffer, because
		   // we only use it after doing 'test', which only ever looks at at most 92 bytes
		   s.img_buffer = s.img_buffer_original;
		   s.img_buffer_end = s.img_buffer_original_end;
		}

		public const int
		   STBI_ORDER_RGB = 0,
		   STBI_ORDER_BGR = 1;

		struct stbi__result_info
		{
		   public int32 bits_per_channel;
		   public int32 num_channels;
		   public int32 channel_order;
		}

#if STBI_THREAD_LOCAL
		[ThreadStatic]
#endif
		static char8 *stbi__g_failure_reason;

		public static char8 *stbi_failure_reason()
		{
		   return stbi__g_failure_reason;
		}

#if !STBI_NO_FAILURE_STRINGS
		static bool stbi__err_f(char8 *str)  // @PORT add an extra '_f' here to better distinguish between the mixin and function while porting
		{
		   stbi__g_failure_reason = str;
		   return false;
		}
#endif

		static void *stbi__malloc(int size)
		{
		    return STBI_MALLOC!(size);
		}

		const int32 INT_MAX = int32.MaxValue;
		const uint32 UINT_MAX = uint32.MaxValue;

		// stb_image uses ints pervasively, including for offset calculations.
		// therefore the largest decoded image size we can support with the
		// current code, even on 64-bit targets, is INT_MAX. this is not a
		// significant limitation for the intended use case.
		//
		// we do, however, need to make sure our size calculations don't
		// overflow. hence a few helper functions for size calculations that
		// multiply integers together, making sure that they're non-negative
		// and no overflow occurs.

		// return 1 if the sum is valid, 0 on overflow.
		// negative terms are considered invalid.
		static bool stbi__addsizes_valid(int32 a, int32 b)
		{
		   if (b < 0) return false;
		   // now 0 <= b <= INT_MAX, hence also
		   // 0 <= INT_MAX - b <= INTMAX.
		   // And "a + b <= INT_MAX" (which might overflow) is the
		   // same as a <= INT_MAX - b (no overflow)
		   return a <= INT_MAX - b;
		}

		// returns 1 if the product is valid, 0 on overflow.
		// negative factors are considered invalid.
		static bool stbi__mul2sizes_valid(int32 a, int32 b)
		{
		   if (a < 0 || b < 0) return false;
		   if (b == 0) return true; // mul-by-0 is always safe
		   // portable way to check for no overflows in a*b
		   return a <= INT_MAX/b;
		}

		// returns 1 if "a*b + add" has no negative terms/factors and doesn't overflow
#if !STBI_NO_JPEG || !STBI_NO_PNG || !STBI_NO_TGA || !STBI_NO_HDR
		static bool stbi__mad2sizes_valid(int32 a, int32 b, int32 add)
		{
		   return stbi__mul2sizes_valid(a, b) && stbi__addsizes_valid(a*b, add);
		}
#endif

		// returns 1 if "a*b*c + add" has no negative terms/factors and doesn't overflow
		static bool stbi__mad3sizes_valid(int32 a, int32 b, int32 c, int32 add)
		{
		   return stbi__mul2sizes_valid(a, b) && stbi__mul2sizes_valid(a*b, c) &&
		      stbi__addsizes_valid(a*b*c, add);
		}

		// returns 1 if "a*b*c*d + add" has no negative terms/factors and doesn't overflow
#if !STBI_NO_LINEAR || !STBI_NO_HDR || !STBI_NO_PNM
		static bool stbi__mad4sizes_valid(int32 a, int32 b, int32 c, int32 d, int32 add)
		{
		   return stbi__mul2sizes_valid(a, b) && stbi__mul2sizes_valid(a*b, c) &&
		      stbi__mul2sizes_valid(a*b*c, d) && stbi__addsizes_valid(a*b*c*d, add);
		}
#endif

		// mallocs with size overflow checking
#if !STBI_NO_JPEG || !STBI_NO_PNG || !STBI_NO_TGA || !STBI_NO_HDR
		static void *stbi__malloc_mad2(int32 a, int32 b, int32 add)
		{
		   if (!stbi__mad2sizes_valid(a, b, add)) return null;
		   return stbi__malloc(a*b + add);
		}
#endif

		static void *stbi__malloc_mad3(int32 a, int32 b, int32 c, int32 add)
		{
		   if (!stbi__mad3sizes_valid(a, b, c, add)) return null;
		   return stbi__malloc(a*b*c + add);
		}

#if !STBI_NO_LINEAR || !STBI_NO_HDR || !STBI_NO_PNM
		static void *stbi__malloc_mad4(int32 a, int32 b, int32 c, int32 d, int32 add)
		{
		   if (!stbi__mad4sizes_valid(a, b, c, d, add)) return null;
		   return stbi__malloc(a*b*c*d + add);
		}
#endif

		// stbi__err - error
		// stbi__errpf - error returning pointer to float
		// stbi__errpuc - error returning pointer to unsigned char

		static mixin stbi__err(var x, var y)
		{
#if STBI_FAILURE_USERMSG
			stbi__err_f(y)
#elif !STBI_NO_FAILURE_STRINGS
			stbi__err_f(x)
#else
			false
#endif
		}

		static mixin stbi__errpf(var x, var y)
		{
			//((float *)(int) (stbi__err(x,y) ?null:null))
			stbi__err!(x,y);
			null
		}
		static mixin stbi__errpuc(var x, var y)
		{
			// ((uint8 *)(int) (stbi__err(x,y)?null:null))
			stbi__err!(x,y);
			null
		}

		public static void stbi_image_free(void *retval_from_stbi_load)
		{
		   STBI_FREE!(retval_from_stbi_load);
		}

		static bool stbi__vertically_flip_on_load_global = false;

		public static void stbi_set_flip_vertically_on_load(bool flag_true_if_should_flip)
		{
		   stbi__vertically_flip_on_load_global = flag_true_if_should_flip;
		}

#if !STBI_THREAD_LOCAL
		static mixin stbi__vertically_flip_on_load()
		{
			stbi__vertically_flip_on_load_global
		}
#else
		[ThreadStatic]
		static bool stbi__vertically_flip_on_load_local;
		[ThreadStatic]
		static bool stbi__vertically_flip_on_load_set;

		public static void stbi_set_flip_vertically_on_load_thread(bool flag_true_if_should_flip)
		{
		   stbi__vertically_flip_on_load_local = flag_true_if_should_flip;
		   stbi__vertically_flip_on_load_set = true;
		}

		static mixin stbi__vertically_flip_on_load()
		{
			(stbi__vertically_flip_on_load_set ? stbi__vertically_flip_on_load_local : stbi__vertically_flip_on_load_global)
		}

#endif // STBI_THREAD_LOCAL

		static void *stbi__load_main(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri, int32 bpc)
		{
		   //memset(ri, 0, sizeof(*ri)); // make sure it's initialized if we add new fields
			*ri = default;

		   ri.bits_per_channel = 8; // default is 8 so most paths don't have to be changed
		   ri.channel_order = STBI_ORDER_RGB; // all current input & output are this, but this is here so we can add BGR order
		   ri.num_channels = 0;

		   // test the formats with a very explicit header first (at least a FOURCC
		   // or distinctive magic number first)
		   #if !STBI_NO_PNG
		   if (stbi__png_test(s))  return stbi__png_load(s,x,y,comp,req_comp, ri);
		   #endif
		   #if !STBI_NO_BMP
		   if (stbi__bmp_test(s))  return stbi__bmp_load(s,x,y,comp,req_comp, ri);
		   #endif
		   #if !STBI_NO_GIF
		   if (stbi__gif_test(s))  return stbi__gif_load(s,x,y,comp,req_comp, ri);
		   #endif
		   #if !STBI_NO_PSD
		   if (stbi__psd_test(s))  return stbi__psd_load(s,x,y,comp,req_comp, ri, bpc);
		   #else
		   //STBI_NOTUSED(bpc);
		   #endif
		   #if !STBI_NO_PIC
		   if (stbi__pic_test(s))  return stbi__pic_load(s,x,y,comp,req_comp, ri);
		   #endif

		   // then the formats that can end up attempting to load with just 1 or 2
		   // bytes matching expectations; these are prone to false positives, so
		   // try them later
		   #if !STBI_NO_JPEG
		   if (stbi__jpeg_test(s)) return stbi__jpeg_load(s,x,y,comp,req_comp, ri);
		   #endif
		   #if !STBI_NO_PNM
		   if (stbi__pnm_test(s))  return stbi__pnm_load(s,x,y,comp,req_comp, ri);
		   #endif

		   #if !STBI_NO_HDR
		   if (stbi__hdr_test(s)) {
		      float *hdr = stbi__hdr_load(s, x,y,comp,req_comp, ri);
		      return stbi__hdr_to_ldr(hdr, *x, *y, req_comp != 0 ? req_comp : *comp);
		   }
		   #endif

		   #if !STBI_NO_TGA
		   // test tga last because it's a crappy test!
		   if (stbi__tga_test(s))
		      return stbi__tga_load(s,x,y,comp,req_comp, ri);
		   #endif

		   return stbi__errpuc!("unknown image type", "Image not of any known type, or corrupt");
		}

		static stbi_uc *stbi__convert_16_to_8(stbi__uint16 *orig, int32 w, int32 h, int32 channels)
		{
		   int32 i;
		   int32 img_len = w * h * channels;
		   stbi_uc *reduced;

		   reduced = (stbi_uc *) stbi__malloc(img_len);
		   if (reduced == null) return stbi__errpuc!("outofmem", "Out of memory");

		   for (i = 0; i < img_len; ++i)
		      reduced[i] = (stbi_uc)((orig[i] >> 8) & 0xFF); // top half of each byte is sufficient approx of 16.8 bit scaling

		   STBI_FREE!(orig);
		   return reduced;
		}

		static stbi__uint16 *stbi__convert_8_to_16(stbi_uc *orig, int32 w, int32 h, int32 channels)
		{
		   int32 i;
		   int32 img_len = w * h * channels;
		   stbi__uint16 *enlarged;

		   enlarged = (stbi__uint16 *) stbi__malloc(img_len*2);
		   if (enlarged == null) return (stbi__uint16 *) stbi__errpuc!("outofmem", "Out of memory");

		   for (i = 0; i < img_len; ++i)
		      enlarged[i] = (stbi__uint16)(((uint16)orig[i] << 8) + orig[i]); // replicate to high and low byte, maps 0.0, 255.0xffff

		   STBI_FREE!(orig);
		   return enlarged;
		}

		static void stbi__vertical_flip(void *image, int32 w, int32 h, int32 bytes_per_pixel)
		{
		   int32 row;
		   int bytes_per_row = (int)w * bytes_per_pixel;
		   stbi_uc[2048] temp = ?;
		   stbi_uc *bytes = (stbi_uc *)image;

		   for (row = 0; row < (h>>1); row++) {
		      stbi_uc *row0 = bytes + row*bytes_per_row;
		      stbi_uc *row1 = bytes + (h - row - 1)*bytes_per_row;
		      // swap row0 with row1
		      int bytes_left = bytes_per_row;
		      while (bytes_left != 0) {
		         int bytes_copy = (bytes_left < sizeof(decltype(temp))) ? bytes_left : sizeof(decltype(temp));
		         memcpy(&temp[0], row0, bytes_copy);
		         memcpy(row0, row1, bytes_copy);
		         memcpy(row1, &temp[0], bytes_copy);
		         row0 += bytes_copy;
		         row1 += bytes_copy;
		         bytes_left -= bytes_copy;
		      }
		   }
		}

#if !STBI_NO_GIF
		static void stbi__vertical_flip_slices(void *image, int32 w, int32 h, int32 z, int32 bytes_per_pixel)
		{
		   int32 slice;
		   int32 slice_size = w * h * bytes_per_pixel;

		   stbi_uc *bytes = (stbi_uc *)image;
		   for (slice = 0; slice < z; ++slice) {
		      stbi__vertical_flip(bytes, w, h, bytes_per_pixel);
		      bytes += slice_size;
		   }
		}
#endif

		static uint8 *stbi__load_and_postprocess_8bit(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__result_info ri = ?;
		   void *result = stbi__load_main(s, x, y, comp, req_comp, &ri, 8);

		   if (result == null)
		      return null;

		   // it is the responsibility of the loaders to make sure we get either 8 or 16 bit.
		   STBI_ASSERT!(ri.bits_per_channel == 8 || ri.bits_per_channel == 16);

		   if (ri.bits_per_channel != 8) {
		      result = stbi__convert_16_to_8((stbi__uint16 *) result, *x, *y, req_comp == 0 ? *comp : req_comp);
		      ri.bits_per_channel = 8;
		   }

		   // @TODO: move stbi__convert_format to here

		   if (stbi__vertically_flip_on_load!()) {
		      int32 channels = req_comp != 0 ? req_comp : *comp;
		      stbi__vertical_flip(result, *x, *y, channels * sizeof(stbi_uc));
		   }

		   return (uint8 *) result;
		}

		static stbi__uint16 *stbi__load_and_postprocess_16bit(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__result_info ri = ?;
		   void *result = stbi__load_main(s, x, y, comp, req_comp, &ri, 16);

		   if (result == null)
		      return null;

		   // it is the responsibility of the loaders to make sure we get either 8 or 16 bit.
		   STBI_ASSERT!(ri.bits_per_channel == 8 || ri.bits_per_channel == 16);

		   if (ri.bits_per_channel != 16) {
		      result = stbi__convert_8_to_16((stbi_uc *) result, *x, *y, req_comp == 0 ? *comp : req_comp);
		      ri.bits_per_channel = 16;
		   }

		   // @TODO: move stbi__convert_format16 to here
		   // @TODO: special case RGB-to-Y (and RGBA-to-YA) for 8-bit-to-16-bit case to keep more precision

		   if (stbi__vertically_flip_on_load!()) {
		      int32 channels = req_comp != 0 ? req_comp : *comp;
		      stbi__vertical_flip(result, *x, *y, channels * sizeof(stbi__uint16));
		   }

		   return (stbi__uint16 *) result;
		}

#if !STBI_NO_HDR && !STBI_NO_LINEAR
		static void stbi__float_postprocess(float *result, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   if (stbi__vertically_flip_on_load!() && result != null) {
		      int32 channels = req_comp != 0 ? req_comp : *comp;
		      stbi__vertical_flip(result, *x, *y, channels * sizeof(float));
		   }
		}
#endif

		public static stbi_us *stbi_load_16_from_memory(stbi_uc *buffer, int32 len, int32 *x, int32 *y, int32 *channels_in_file, int32 desired_channels)
		{
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__load_and_postprocess_16bit(&s,x,y,channels_in_file,desired_channels);
		}

		public static stbi_us *stbi_load_16_from_callbacks(stbi_io_callbacks *clbk, void *user, int32 *x, int32 *y, int32 *channels_in_file, int32 desired_channels)
		{
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *)clbk, user);
		   return stbi__load_and_postprocess_16bit(&s,x,y,channels_in_file,desired_channels);
		}

		public static stbi_uc *stbi_load_from_memory(stbi_uc *buffer, int32 len, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__load_and_postprocess_8bit(&s,x,y,comp,req_comp);
		}

		public static stbi_uc *stbi_load_from_callbacks(stbi_io_callbacks *clbk, void *user, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *) clbk, user);
		   return stbi__load_and_postprocess_8bit(&s,x,y,comp,req_comp);
		}

#if !STBI_NO_GIF
		public static stbi_uc *stbi_load_gif_from_memory(stbi_uc *buffer, int32 len, int32 **delays, int32 *x, int32 *y, int32 *z, int32 *comp, int32 req_comp)
		{
		   uint8 *result;
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);

		   result = (uint8*) stbi__load_gif_main(&s, delays, x, y, z, comp, req_comp);
		   if (stbi__vertically_flip_on_load!()) {
		      stbi__vertical_flip_slices( result, *x, *y, *z, *comp );
		   }

		   return result;
		}
#endif

#if !STBI_NO_LINEAR
		static float *stbi__loadf_main(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   uint8 *data;
		   #if !STBI_NO_HDR
		   if (stbi__hdr_test(s)) {
		      stbi__result_info ri;
		      float *hdr_data = stbi__hdr_load(s,x,y,comp,req_comp, &ri);
		      if (hdr_data != null)
		         stbi__float_postprocess(hdr_data,x,y,comp,req_comp);
		      return hdr_data;
		   }
		   #endif
		   data = stbi__load_and_postprocess_8bit(s, x, y, comp, req_comp);
		   if (data != null)
		      return stbi__ldr_to_hdr(data, *x, *y, req_comp != 0 ? req_comp : *comp);
		   return stbi__errpf!("unknown image type", "Image not of any known type, or corrupt");
		}

		public static float *stbi_loadf_from_memory(stbi_uc *buffer, int32 len, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__loadf_main(&s,x,y,comp,req_comp);
		}

		public static float *stbi_loadf_from_callbacks(stbi_io_callbacks *clbk, void *user, int32 *x, int32 *y, int32 *comp, int32 req_comp)
		{
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *) clbk, user);
		   return stbi__loadf_main(&s,x,y,comp,req_comp);
		}

#endif // !STBI_NO_LINEAR

		// these is-hdr-or-not is defined independent of whether STBI_NO_LINEAR is
		// defined, for API simplicity; if STBI_NO_LINEAR is defined, it always
		// reports false!

		public static bool stbi_is_hdr_from_memory(stbi_uc *buffer, int32 len)
		{
		   #if !STBI_NO_HDR
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__hdr_test(&s);
		   #else
		   return false;
		   #endif
		}

		public static bool stbi_is_hdr_from_callbacks(stbi_io_callbacks *clbk, void *user)
		{
		   #if !STBI_NO_HDR
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *) clbk, user);
		   return stbi__hdr_test(&s);
		   #else
		   return false;
		   #endif
		}

#if !STBI_NO_LINEAR
		static float stbi__l2h_gamma=2.2f, stbi__l2h_scale=1.0f;

		public static void   stbi_ldr_to_hdr_gamma(float gamma) { stbi__l2h_gamma = gamma; }
		public static void   stbi_ldr_to_hdr_scale(float scale) { stbi__l2h_scale = scale; }
#endif

		static float stbi__h2l_gamma_i=1.0f/2.2f, stbi__h2l_scale_i=1.0f;

		public static void   stbi_hdr_to_ldr_gamma(float gamma) { stbi__h2l_gamma_i = 1/gamma; }
		public static void   stbi_hdr_to_ldr_scale(float scale) { stbi__h2l_scale_i = 1/scale; }


		//////////////////////////////////////////////////////////////////////////////
		//
		// Common code used by all image loaders
		//

		const int
		   STBI__SCAN_load=0,
		   STBI__SCAN_type = 1,
		   STBI__SCAN_header = 2;

		static void stbi__refill_buffer(stbi__context *s)
		{
		   int32 n = s.io.read(s.io_user_data,&s.buffer_start[0],s.buflen);
		   s.callback_already_read += (int32) (s.img_buffer - s.img_buffer_original);
		   if (n == 0) {
		      // at end of file, treat same as if from memory, but need to handle case
		      // where s.img_buffer isn't pointing to safe memory, e.g. 0-byte file
		      s.read_from_callbacks = false;
		      s.img_buffer = &s.buffer_start[0];
		      s.img_buffer_end = &s.buffer_start[1];
		      *s.img_buffer = 0;
		   } else {
		      s.img_buffer = &s.buffer_start[0];
		      s.img_buffer_end = &s.buffer_start[[Unchecked]n]; // @PORT: get pointer of end, out of bounds
		   }
		}

		[Inline]
		static stbi_uc stbi__get8(stbi__context *s)
		{
		   if (s.img_buffer < s.img_buffer_end)
		      return *s.img_buffer++;
		   if (s.read_from_callbacks) {
		      stbi__refill_buffer(s);
		      return *s.img_buffer++;
		   }
		   return 0;
		}

#if STBI_NO_JPEG && STBI_NO_HDR && STBI_NO_PIC && STBI_NO_PNM
		// nothing
#else
		[Inline]
		static bool stbi__at_eof(stbi__context *s)
		{
		   if (s.io.read != null) {
		      if (!s.io.eof(s.io_user_data)) return false;
		      // if feof() is true, check if buffer = end
		      // special case: we've only got the special 0 character at the end
		      if (!s.read_from_callbacks) return true;
		   }

		   return s.img_buffer >= s.img_buffer_end;
		}
#endif

#if STBI_NO_JPEG && STBI_NO_PNG && STBI_NO_BMP && STBI_NO_PSD && STBI_NO_TGA && STBI_NO_GIF && STBI_NO_PIC
		// nothing
#else
		static void stbi__skip(stbi__context *s, int32 n)
		{
		   if (n == 0) return;  // already there!
		   if (n < 0) {
		      s.img_buffer = s.img_buffer_end;
		      return;
		   }
		   if (s.io.read != null) {
		      int32 blen = (int32) (s.img_buffer_end - s.img_buffer);
		      if (blen < n) {
		         s.img_buffer = s.img_buffer_end;
		         s.io.skip(s.io_user_data, n - blen);
		         return;
		      }
		   }
		   s.img_buffer += n;
		}
#endif

#if STBI_NO_PNG && STBI_NO_TGA && STBI_NO_HDR && STBI_NO_PNM
		// nothing
#else
		static bool stbi__getn(stbi__context *s, stbi_uc *buffer, int32 n)
		{
		   if (s.io.read != null) {
		      int32 blen = (int32) (s.img_buffer_end - s.img_buffer);
		      if (blen < n) {
		         int32 count;
				  bool res;

		         memcpy(buffer, s.img_buffer, blen);

		         count = s.io.read(s.io_user_data, buffer + blen, n - blen);
		         res = (count == (n-blen));
		         s.img_buffer = s.img_buffer_end;
		         return res;
		      }
		   }

		   if (s.img_buffer+n <= s.img_buffer_end) {
		      memcpy(buffer, s.img_buffer, n);
		      s.img_buffer += n;
		      return true;
		   } else
		      return false;
		}
#endif

#if STBI_NO_JPEG && STBI_NO_PNG && STBI_NO_PSD && STBI_NO_PIC
		// nothing
#else
		static int32 stbi__get16be(stbi__context *s)
		{
		   int32 z = stbi__get8(s);
		   return (z << 8) + stbi__get8(s);
		}
#endif

#if STBI_NO_PNG && STBI_NO_PSD && STBI_NO_PIC
		// nothing
#else
		static stbi__uint32 stbi__get32be(stbi__context *s)
		{
		   stbi__uint32 z = (.)stbi__get16be(s);
		   return (z << 16) + (uint32)stbi__get16be(s);
		}
#endif

#if STBI_NO_BMP && STBI_NO_TGA && STBI_NO_GIF
		// nothing
#else
		static int32 stbi__get16le(stbi__context *s)
		{
		   int32 z = stbi__get8(s);
		   return z + ((int32)stbi__get8(s) << 8);
		}
#endif

#if !STBI_NO_BMP
		static stbi__uint32 stbi__get32le(stbi__context *s)
		{
		   stbi__uint32 z = (.)stbi__get16le(s);
		   z += (stbi__uint32)stbi__get16le(s) << 16;
		   return z;
		}
#endif

		static mixin STBI__BYTECAST(var x)
		{
			((stbi_uc) ((x) & 255))  // truncate int to byte without warnings
		}

		
#if STBI_NO_JPEG && STBI_NO_PNG && STBI_NO_BMP && STBI_NO_PSD && STBI_NO_TGA && STBI_NO_GIF && STBI_NO_PIC && STBI_NO_PNM
		// nothing
#else
		//////////////////////////////////////////////////////////////////////////////
		//
		//  generic converter from built-in img_n to req_comp
		//    individual types do this automatically as much as possible (e.g. jpeg
		//    does all cases internally since it needs to colorspace convert anyway,
		//    and it never has alpha, so very few cases ). png can automatically
		//    interleave an alpha=255 channel, but falls back to this for other cases
		//
		//  assume data buffer is malloced, so malloc a new one and free that one
		//  only failure mode is malloc failing

		static stbi_uc stbi__compute_y(int32 r, int32 g, int32 b)
		{
		   return (stbi_uc) (((r*77) + (g*150) +  (29*b)) >> 8);
		}
#endif

#if STBI_NO_PNG && STBI_NO_BMP && STBI_NO_PSD && STBI_NO_TGA && STBI_NO_GIF && STBI_NO_PIC && STBI_NO_PNM
		// nothing
#else
		static uint8 *stbi__convert_format(uint8 *data, int32 img_n, int32 req_comp, uint32 x, uint32 y)
		{
		   int32 i,j;
		   uint8 *good;

		   if (req_comp == img_n) return data;
		   STBI_ASSERT!(req_comp >= 1 && req_comp <= 4);

		   good = (uint8 *) stbi__malloc_mad3(req_comp, (.)x, (.)y, 0);
		   if (good == null) {
		      STBI_FREE!(data);
		      return stbi__errpuc!("outofmem", "Out of memory");
		   }

		   for (j=0; j < (int32) y; ++j) {
		      uint8 *src  = data + (int)j * x * img_n   ;
		      uint8 *dest = good + (int)j * x * req_comp;

			   // STBI__COMBO: ((a)*8+(b))
		       // STBI__CASE: case STBI__COMBO(a,b): for(i=x-1; i >= 0; --i, src += a, dest += b)

		      // convert source image with img_n components to one with req_comp components;
		      // avoid switch per pixel, so use switch per scanline and massive macros
		      switch (((img_n)*8+(req_comp))) {
		         case ((1)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 2) { dest[0]=src[0]; dest[1]=255;                                     } break;
		         case ((1)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 3) { dest[0]=dest[1]=dest[2]=src[0];                                  } break;
		         case ((1)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 4) { dest[0]=dest[1]=dest[2]=src[0]; dest[3]=255;                     } break;
		         case ((2)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 1) { dest[0]=src[0];                                                  } break;
		         case ((2)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 3) { dest[0]=dest[1]=dest[2]=src[0];                                  } break;
		         case ((2)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 4) { dest[0]=dest[1]=dest[2]=src[0]; dest[3]=src[1];                  } break;
		         case ((3)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 4) { dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];dest[3]=255;        } break;
		         case ((3)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 1) { dest[0]=stbi__compute_y(src[0],src[1],src[2]);                   } break;
		         case ((3)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 2) { dest[0]=stbi__compute_y(src[0],src[1],src[2]); dest[1] = 255;    } break;
		         case ((4)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 1) { dest[0]=stbi__compute_y(src[0],src[1],src[2]);                   } break;
		         case ((4)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 2) { dest[0]=stbi__compute_y(src[0],src[1],src[2]); dest[1] = src[3]; } break;
		         case ((4)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 3) { dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];                    } break;
		         default: STBI_ASSERT!(false); STBI_FREE!(data); STBI_FREE!(good); return stbi__errpuc!("unsupported", "Unsupported format conversion");
		      }
		   }

		   STBI_FREE!(data);
		   return good;
		}
#endif

#if STBI_NO_PNG && STBI_NO_PSD
		// nothing
#else
		static stbi__uint16 stbi__compute_y_16(int32 r, int32 g, int32 b)
		{
		   return (stbi__uint16) (((r*77) + (g*150) +  (29*b)) >> 8);
		}
#endif

#if STBI_NO_PNG && STBI_NO_PSD
		// nothing
#else
		static stbi__uint16 *stbi__convert_format16(stbi__uint16 *data, int32 img_n, int32 req_comp, uint32 x, uint32 y)
		{
		   int32 i,j;
		   stbi__uint16 *good;

		   if (req_comp == img_n) return data;
		   STBI_ASSERT!(req_comp >= 1 && req_comp <= 4);

		   good = (stbi__uint16 *) stbi__malloc((int)req_comp * x * y * 2);
		   if (good == null) {
		      STBI_FREE!(data);
		      return (stbi__uint16 *) stbi__errpuc!("outofmem", "Out of memory");
		   }

		   for (j=0; j < (int32) y; ++j) {
		      stbi__uint16 *src  = data + (int)j * x * img_n   ;
		      stbi__uint16 *dest = good + (int)j * x * req_comp;

		      // STBI__COMBO(a,b): ((a)*8+(b))
		      // STBI__CASE(a,b): case STBI__COMBO(a,b): for(i=x-1; i >= 0; --i, src += a, dest += b)
		      // convert source image with img_n components to one with req_comp components;
		      // avoid switch per pixel, so use switch per scanline and massive macros
		      switch (((img_n)*8+(req_comp))) {
		         case ((1)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 2) { dest[0]=src[0]; dest[1]=0xffff;                                     } break;
		         case ((1)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 3) { dest[0]=dest[1]=dest[2]=src[0];                                     } break;
		         case ((1)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 1, dest += 4) { dest[0]=dest[1]=dest[2]=src[0]; dest[3]=0xffff;                     } break;
		         case ((2)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 1) { dest[0]=src[0];                                                     } break;
		         case ((2)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 3) { dest[0]=dest[1]=dest[2]=src[0];                                     } break;
		         case ((2)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 2, dest += 4) { dest[0]=dest[1]=dest[2]=src[0]; dest[3]=src[1];                     } break;
		         case ((3)*8+(4)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 4) { dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];dest[3]=0xffff;        } break;
		         case ((3)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 1) { dest[0]=stbi__compute_y_16(src[0],src[1],src[2]);                   } break;
		         case ((3)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 3, dest += 2) { dest[0]=stbi__compute_y_16(src[0],src[1],src[2]); dest[1] = 0xffff; } break;
		         case ((4)*8+(1)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 1) { dest[0]=stbi__compute_y_16(src[0],src[1],src[2]);                   } break;
		         case ((4)*8+(2)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 2) { dest[0]=stbi__compute_y_16(src[0],src[1],src[2]); dest[1] = src[3]; } break;
		         case ((4)*8+(3)): for(i=(int32)x-1; i >= 0; --i, src += 4, dest += 3) { dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];                       } break;
		         default: STBI_ASSERT!(false); STBI_FREE!(data); STBI_FREE!(good); return (stbi__uint16*) stbi__errpuc!("unsupported", "Unsupported format conversion");
		      }
		   }

		   STBI_FREE!(data);
		   return good;
		}
#endif

#if !STBI_NO_LINEAR
		static float *stbi__ldr_to_hdr(stbi_uc *data, int32 x, int32 y, int32 comp)
		{
		   int32 i,k,n;
		   float *output;
		   if (data == null) return null;
		   output = (float *) stbi__malloc_mad4(x, y, comp, sizeof(float), 0);
		   if (output == null) { STBI_FREE!(data); return stbi__errpf!("outofmem", "Out of memory"); }
		   // compute number of non-alpha components
		   if ((comp & 1) != 0) n = comp; else n = comp-1;
		   for (i=0; i < x*y; ++i) {
		      for (k=0; k < n; ++k) {
		         output[i*comp + k] = (float) (Math.Pow(data[i*comp+k]/255.0f, stbi__l2h_gamma) * stbi__l2h_scale);
		      }
		   }
		   if (n < comp) {
		      for (i=0; i < x*y; ++i) {
		         output[i*comp + n] = data[i*comp + n]/255.0f;
		      }
		   }
		   STBI_FREE!(data);
		   return output;
		}
#endif

#if !STBI_NO_HDR
		// @PORT .. why
		/*static mixin stbi__float2int(var x)
		{
			((int32) (x))
		}*/

		static stbi_uc *stbi__hdr_to_ldr(float   *data, int32 x, int32 y, int32 comp)
		{
		   int32 i,k,n;
		   stbi_uc *output;
		   if (data == null) return null;
		   output = (stbi_uc *) stbi__malloc_mad3(x, y, comp, 0);
		   if (output == null) { STBI_FREE!(data); return stbi__errpuc!("outofmem", "Out of memory"); }
		   // compute number of non-alpha components
		   if ((comp & 1) != 0) n = comp; else n = comp-1;
		   for (i=0; i < x*y; ++i) {
		      for (k=0; k < n; ++k) {
		         float z = (float) Math.Pow(data[i*comp+k]*stbi__h2l_scale_i, stbi__h2l_gamma_i) * 255 + 0.5f;
		         if (z < 0) z = 0;
		         if (z > 255) z = 255;
		         output[i*comp + k] = (stbi_uc) ((int32)(z));
		      }
		      if (k < comp) {
		         float z = data[i*comp+k] * 255 + 0.5f;
		         if (z < 0) z = 0;
		         if (z > 255) z = 255;
		         output[i*comp + k] = (stbi_uc) ((int32)(z));
		      }
		   }
		   STBI_FREE!(data);
		   return output;
		}
#endif

		//////////////////////////////////////////////////////////////////////////////
		//
		//  "baseline" JPEG/JFIF decoder
		//
		//    simple implementation
		//      - doesn't support delayed output of y-dimension
		//      - simple interface (only one output format: 8-bit interleaved RGB)
		//      - doesn't try to recover corrupt jpegs
		//      - doesn't allow partial loading, loading multiple at once
		//      - still fast on x86 (copying globals into locals doesn't help x86)
		//      - allocates lots of intermediate memory (full size of all components)
		//        - non-interleaved case requires this anyway
		//        - allows good upsampling (see next)
		//    high-quality
		//      - upsampled channels are bilinearly interpolated, even across blocks
		//      - quality integer IDCT derived from IJG's 'slow'
		//    performance
		//      - fast huffman; reasonable integer IDCT
		//      - some SIMD kernels for common paths on targets with SSE2/NEON
		//      - uses a lot of intermediate memory, could cache poorly

#if !STBI_NO_JPEG

		// huffman decoding acceleration
		const int FAST_BITS = 9;  // larger handles more cases; smaller stomps less cache

		struct stbi__huffman
		{
		   public stbi_uc[1 << FAST_BITS] fast;
		   // weirdly, repacking this into AoS is a 10% speed loss, instead of a win
		   public stbi__uint16[256] code;
		   public stbi_uc[256] values;
		   public stbi_uc[257] size;
		   public uint32[18] maxcode;
		   public int32[17] delta;   // old 'firstsymbol' - old 'firstcode'
		}

		struct stbi__jpeg
		{
		   public stbi__context *s;
		   public stbi__huffman[4] huff_dc;
		   public stbi__huffman[4] huff_ac;
		   public stbi__uint16[4][64] dequant;
		   public stbi__int16[4][1 << FAST_BITS] fast_ac;

		// sizes for components, interleaved MCUs
		   public int32 img_h_max, img_v_max;
		   public int32 img_mcu_x, img_mcu_y;
		   public int32 img_mcu_w, img_mcu_h;

		// definition of jpeg image component
		   public struct __img_comp
		   {
		      public int32 id;
		      public int32 h,v;
		      public int32 tq;
		      public int32 hd,ha;
		      public int32 dc_pred;

		      public int32 x,y,w2,h2;
		      public stbi_uc *data;
		      public void *raw_data, raw_coeff;
		      public stbi_uc *linebuf;
		      public int16 *coeff;   // progressive only
		      public int32 coeff_w, coeff_h; // number of 8x8 coefficient blocks
		   }
			public __img_comp[4] img_comp;

		   public stbi__uint32 code_buffer; // jpeg entropy-coded buffer
		   public int32 code_bits;   // number of valid bits
		   public uint8 marker;      // marker seen while filling entropy buffer
		   public bool nomore;      // flag if we saw a marker so must stop

		   public bool progressive;
		   public int32 spec_start;
		   public int32 spec_end;
		   public int32 succ_high;
		   public int32 succ_low;
		   public int32 eob_run;
		   public int32 jfif;
		   public int32 app14_color_transform; // Adobe APP14 tag
		   public int32 rgb;

		   public int32 scan_n;
			public int32[4] order;
		   public int32 restart_interval, todo;

		// kernels
		   public function void(stbi_uc *out_, int32 out_stride, int16* data) idct_block_kernel; // @PORT int16* was int16[64] before... but casting int16* to int16[64] when calling is problematic
		   public function void(stbi_uc *out_, stbi_uc *y, stbi_uc *pcb, stbi_uc *pcr, int32 count, int32 step) YCbCr_to_RGB_kernel;
		   public function stbi_uc*(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs) resample_row_hv_2_kernel;
		}

		static bool stbi__build_huffman(stbi__huffman *h, int32 *count)
		{
		   int32 i,j,k=0;
		   uint32 code;
		   // build size list for each symbol (from JPEG spec)
		   for (i=0; i < 16; ++i)
		      for (j=0; j < count[i]; ++j)
		         h.size[k++] = (stbi_uc) (i+1);
		   h.size[k] = 0;

		   // compute actual symbols (from jpeg spec)
		   code = 0;
		   k = 0;
		   for(j=1; j <= 16; ++j) {
		      // compute delta to add to code to compute symbol id
		      h.delta[j] = k - (.)code;
		      if (h.size[k] == j) {
		         while (h.size[k] == j)
		            h.code[k++] = (stbi__uint16) (code++);
		         if (code-1 >= (1 << j)) return stbi__err!("bad code lengths","Corrupt JPEG");
		      }
		      // compute largest code + 1 for this size, preshifted as needed later
		      h.maxcode[j] = code << (16-j);
		      code <<= 1;
		   }
		   h.maxcode[j] = 0xffffffff;

		   // build non-spec acceleration table; 255 is flag for not-accelerated
		   memset(&h.fast[0], 255, 1 << FAST_BITS);
		   for (i=0; i < k; ++i) {
		      int32 s = h.size[i];
		      if (s <= FAST_BITS) {
		         int32 c = (int32)h.code[i] << (FAST_BITS-s);
		         int32 m = 1 << (FAST_BITS-s);
		         for (j=0; j < m; ++j) {
		            h.fast[c+j] = (stbi_uc) i;
		         }
		      }
		   }
		   return true;
		}

		// build a table that decodes both magnitude and value of small ACs in
		// one go.
		static void stbi__build_fast_ac(stbi__int16 *fast_ac, stbi__huffman *h)
		{
		   int32 i;
		   for (i=0; i < (1 << FAST_BITS); ++i) {
		      stbi_uc fast = h.fast[i];
		      fast_ac[i] = 0;
		      if (fast < 255) {
		         int32 rs = h.values[fast];
		         int32 run = (rs >> 4) & 15;
		         int32 magbits = rs & 15;
		         int32 len = h.size[fast];

		         if (magbits != 0 && len + magbits <= FAST_BITS) {
		            // magnitude code followed by receive_extend code
		            int32 k = ((i << len) & ((1 << FAST_BITS) - 1)) >> (FAST_BITS - magbits);
		            int32 m = 1 << (magbits - 1);
		            if (k < m) k += (~0 << magbits) + 1;
		            // if the result is small enough, we can fit it in fast_ac table
		            if (k >= -128 && k <= 127)
		               fast_ac[i] = (stbi__int16) ((k * 256) + (run * 16) + (len + magbits));
		         }
		      }
		   }
		}

		static void stbi__grow_buffer_unsafe(stbi__jpeg *j)
		{
		   repeat {
		      uint32 b = j.nomore ? 0 : stbi__get8(j.s);
		      if (b == 0xff) {
		         int32 c = stbi__get8(j.s);
		         while (c == 0xff) c = stbi__get8(j.s); // consume fill bytes
		         if (c != 0) {
		            j.marker = (uint8) c;
		            j.nomore = true;
		            return;
		         }
		      }
		      j.code_buffer |= b << (24 - j.code_bits);
		      j.code_bits += 8;
		   } while (j.code_bits <= 24);
		}

		// (1 << n) - 1
		const stbi__uint32[17] stbi__bmask= .(0,1,3,7,15,31,63,127,255,511,1023,2047,4095,8191,16383,32767,65535);

		// decode a jpeg huffman value from the bitstream
		[Inline]
		static int32 stbi__jpeg_huff_decode(stbi__jpeg *j, stbi__huffman *h)
		{
		   uint32 temp;
		   int32 c,k;

		   if (j.code_bits < 16) stbi__grow_buffer_unsafe(j);

		   // look at the top FAST_BITS and determine what symbol ID it is,
		   // if the code is <= FAST_BITS
		   c = (int32)(j.code_buffer >> (32 - FAST_BITS)) & ((1 << FAST_BITS)-1);
		   k = h.fast[c];
		   if (k < 255) {
		      int32 s = h.size[k];
		      if (s > j.code_bits)
		         return -1;
		      j.code_buffer <<= s;
		      j.code_bits -= s;
		      return h.values[k];
		   }

		   // naive test is to shift the code_buffer down so k bits are
		   // valid, then test against maxcode. To speed this up, we've
		   // preshifted maxcode left so that it has (16-k) 0s at the
		   // end; in other words, regardless of the number of bits, it
		   // wants to be compared against something shifted to have 16;
		   // that way we don't need to shift inside the loop.
		   temp = j.code_buffer >> 16;
		   for (k=FAST_BITS+1 ; ; ++k)
		      if (temp < h.maxcode[k])
		         break;
		   if (k == 17) {
		      // error! code not found
		      j.code_bits -= 16;
		      return -1;
		   }

		   if (k > j.code_bits)
		      return -1;

		   // convert the huffman code to the symbol id
		   c = (int32)((j.code_buffer >> (32 - k)) & stbi__bmask[k]) + h.delta[k];
		   STBI_ASSERT!((((j.code_buffer) >> (32 - h.size[c])) & stbi__bmask[h.size[c]]) == h.code[c]);

		   // convert the id to a symbol
		   j.code_bits -= k;
		   j.code_buffer <<= k;
		   return h.values[c];
		}

		// bias[n] = (-1<<n) + 1
		const int32[16] stbi__jbias = .(0,-1,-3,-7,-15,-31,-63,-127,-255,-511,-1023,-2047,-4095,-8191,-16383,-32767);

		// combined JPEG 'receive' and JPEG 'extend', since baseline
		// always extends everything it receives.
		[Inline]
		static int32 stbi__extend_receive(stbi__jpeg *j, int32 n)
		{
		   uint32 k;
		   int32 sgn;
		   if (j.code_bits < n) stbi__grow_buffer_unsafe(j);

		   sgn = (int32)j.code_buffer >> 31; // sign bit always in MSB; 0 if MSB clear (positive), 1 if MSB set (negative)
		   k = stbi_lrot!(j.code_buffer, n);
		   j.code_buffer = k & ~stbi__bmask[n];
		   k &= stbi__bmask[n];
		   j.code_bits -= n;
		   return (int32)k + (stbi__jbias[n] & (sgn - 1));
		}

		// get some unsigned bits
		[Inline]
		static int32 stbi__jpeg_get_bits(stbi__jpeg *j, int32 n)
		{
		   uint32 k;
		   if (j.code_bits < n) stbi__grow_buffer_unsafe(j);
		   k = stbi_lrot!(j.code_buffer, n);
		   j.code_buffer = k & ~stbi__bmask[n];
		   k &= stbi__bmask[n];
		   j.code_bits -= n;
		   return (.)k;
		}

		[Inline]
		static int32 stbi__jpeg_get_bit(stbi__jpeg *j)
		{
		   uint32 k;
		   if (j.code_bits < 1) stbi__grow_buffer_unsafe(j);
		   k = j.code_buffer;
		   j.code_buffer <<= 1;
		   --j.code_bits;
		   return (.)(k & 0x80000000);
		}

		// given a value that's at position X in the zigzag stream,
		// where does it appear in the 8x8 matrix coded as row-major?
		const stbi_uc[64+15] stbi__jpeg_dezigzag =
		.(
		    0,  1,  8, 16,  9,  2,  3, 10,
		   17, 24, 32, 25, 18, 11,  4,  5,
		   12, 19, 26, 33, 40, 48, 41, 34,
		   27, 20, 13,  6,  7, 14, 21, 28,
		   35, 42, 49, 56, 57, 50, 43, 36,
		   29, 22, 15, 23, 30, 37, 44, 51,
		   58, 59, 52, 45, 38, 31, 39, 46,
		   53, 60, 61, 54, 47, 55, 62, 63,
		   // let corrupt input sample past end
		   63, 63, 63, 63, 63, 63, 63, 63,
		   63, 63, 63, 63, 63, 63, 63
		);

		// decode one 64-entry block--
		static bool stbi__jpeg_decode_block(stbi__jpeg *j, int16* data, stbi__huffman *hdc, stbi__huffman *hac, stbi__int16 *fac, int32 b, stbi__uint16 *dequant) // @PORT int16* was int16[64] before... but casting int16* to int16[64] when calling is problematic
		{
		   int32 diff,dc,k;
		   int32 t;

		   if (j.code_bits < 16) stbi__grow_buffer_unsafe(j);
		   t = stbi__jpeg_huff_decode(j, hdc);
		   if (t < 0 || t > 15) return stbi__err!("bad huffman code","Corrupt JPEG");

			var data;
		   // 0 all the ac values now so we can do it 32-bits at a time
		   memset(&data[0],0,64*sizeof(decltype(data[0])));

		   diff = t != 0 ? stbi__extend_receive(j, t) : 0;
		   dc = j.img_comp[b].dc_pred + diff;
		   j.img_comp[b].dc_pred = dc;
		   data[0] = (int16) (dc * dequant[0]);

		   // decode AC components, see JPEG spec
		   k = 1;
		   repeat {
		      uint32 zig;
		      int32 c,r,s;
		      if (j.code_bits < 16) stbi__grow_buffer_unsafe(j);
		      c = (int32)(j.code_buffer >> (32 - FAST_BITS)) & ((1 << FAST_BITS)-1);
		      r = fac[c];
		      if (r != 0) { // fast-AC path
		         k += (r >> 4) & 15; // run
		         s = r & 15; // combined length
		         j.code_buffer <<= s;
		         j.code_bits -= s;
		         // decode into unzigzag'd location
		         zig = stbi__jpeg_dezigzag[k++];
		         data[zig] = (int16) ((r >> 8) * dequant[zig]);
		      } else {
		         int32 rs = stbi__jpeg_huff_decode(j, hac);
		         if (rs < 0) return stbi__err!("bad huffman code","Corrupt JPEG");
		         s = rs & 15;
		         r = rs >> 4;
		         if (s == 0) {
		            if (rs != 0xf0) break; // end block
		            k += 16;
		         } else {
		            k += r;
		            // decode into unzigzag'd location
		            zig = stbi__jpeg_dezigzag[k++];
		            data[zig] = (int16) (stbi__extend_receive(j,s) * dequant[zig]);
		         }
		      }
		   } while (k < 64);
		   return true;
		}

		static bool stbi__jpeg_decode_block_prog_dc(stbi__jpeg *j, int16* data, stbi__huffman *hdc, int32 b) // @PORT int16* was int16[64] before... but casting int16* to int16[64] when calling is problematic
		{
		   int32 diff,dc;
		   int32 t;
		   if (j.spec_end != 0) return stbi__err!("can't merge dc and ac", "Corrupt JPEG");

		   if (j.code_bits < 16) stbi__grow_buffer_unsafe(j);

			var data;
		   if (j.succ_high == 0) {
		      // first scan for DC coefficient, must be first
		      memset(&data[0],0,64*sizeof(decltype(data[0]))); // 0 all the ac values now
		      t = stbi__jpeg_huff_decode(j, hdc);
		      if (t < 0 || t > 15) return stbi__err!("can't merge dc and ac", "Corrupt JPEG");
		      diff = t != 0 ? stbi__extend_receive(j, t) : 0;

		      dc = j.img_comp[b].dc_pred + diff;
		      j.img_comp[b].dc_pred = dc;
		      data[0] = (int16) (dc * (1 << j.succ_low));
		   } else {
		      // refinement scan for DC coefficient
		      if (stbi__jpeg_get_bit(j) != 0)
		         data[0] += (int16) (1 << j.succ_low);
		   }
		   return true;
		}

		// @OPTIMIZE: store non-zigzagged during the decode passes,
		// and only de-zigzag when dequantizing
		static bool stbi__jpeg_decode_block_prog_ac(stbi__jpeg *j, int16* data, stbi__huffman *hac, stbi__int16 *fac) // @PORT int16* was int16[64] before... but casting int16* to int16[64] when calling is problematic
		{
		   int32 k;
		   if (j.spec_start == 0) return stbi__err!("can't merge dc and ac", "Corrupt JPEG");
			
			var data;
		   if (j.succ_high == 0) {
		      int32 shift = j.succ_low;

		      if (j.eob_run != 0) {
		         --j.eob_run;
		         return true;
		      }

		      k = j.spec_start;
		      repeat {
		         uint32 zig;
		         int32 c,r,s;
		         if (j.code_bits < 16) stbi__grow_buffer_unsafe(j);
		         c = (int32)(j.code_buffer >> (32 - FAST_BITS)) & ((1 << FAST_BITS)-1);
		         r = fac[c];
		         if (r != 0) { // fast-AC path
		            k += (r >> 4) & 15; // run
		            s = r & 15; // combined length
		            j.code_buffer <<= s;
		            j.code_bits -= s;
		            zig = stbi__jpeg_dezigzag[k++];
		            data[zig] = (int16) ((r >> 8) * (1 << shift));
		         } else {
		            int32 rs = stbi__jpeg_huff_decode(j, hac);
		            if (rs < 0) return stbi__err!("bad huffman code","Corrupt JPEG");
		            s = rs & 15;
		            r = rs >> 4;
		            if (s == 0) {
		               if (r < 15) {
		                  j.eob_run = (1 << r);
		                  if (r != 0)
		                     j.eob_run += stbi__jpeg_get_bits(j, r);
		                  --j.eob_run;
		                  break;
		               }
		               k += 16;
		            } else {
		               k += r;
		               zig = stbi__jpeg_dezigzag[k++];
		               data[zig] = (int16) (stbi__extend_receive(j,s) * (1 << shift));
		            }
		         }
		      } while (k <= j.spec_end);
		   } else {
		      // refinement scan for these AC coefficients

		      int16 bit = (int16) (1 << j.succ_low);

		      if (j.eob_run != 0) {
		         --j.eob_run;
		         for (k = j.spec_start; k <= j.spec_end; ++k) {
		            int16 *p = &data[stbi__jpeg_dezigzag[k]];
		            if (*p != 0)
		               if (stbi__jpeg_get_bit(j) != 0)
		                  if ((*p & bit)==0) {
		                     if (*p > 0)
		                        *p = (int16)((int32)bit + *p);
		                     else
		                        *p = (int16)((int32)*p - bit);
		                  }
		         }
		      } else {
		         k = j.spec_start;
		         repeat {
		            int32 r,s;
		            int32 rs = stbi__jpeg_huff_decode(j, hac); // @OPTIMIZE see if we can use the fast path here, advance-by-r is so slow, eh
		            if (rs < 0) return stbi__err!("bad huffman code","Corrupt JPEG");
		            s = rs & 15;
		            r = rs >> 4;
		            if (s == 0) {
		               if (r < 15) {
		                  j.eob_run = (1 << r) - 1;
		                  if (r != 0)
		                     j.eob_run += stbi__jpeg_get_bits(j, r);
		                  r = 64; // force end of block
		               } else {
		                  // r=15 s=0 should write 16 0s, so we just do
		                  // a run of 15 0s and then write s (which is 0),
		                  // so we don't have to do anything special here
		               }
		            } else {
		               if (s != 1) return stbi__err!("bad huffman code", "Corrupt JPEG");
		               // sign bit
		               if (stbi__jpeg_get_bit(j) != 0)
		                  s = bit;
		               else
		                  s = -bit;
		            }

		            // advance by r
		            while (k <= j.spec_end) {
		               int16 *p = &data[stbi__jpeg_dezigzag[k++]];
		               if (*p != 0) {
		                  if (stbi__jpeg_get_bit(j) != 0)
		                     if ((*p & bit)==0) {
		                        if (*p > 0)
		                           *p = (int16)((int32)bit + *p);
		                        else
		                           *p = (int16)((int32)*p - bit);
		                     }
		               } else {
		                  if (r == 0) {
		                     *p = (int16) s;
		                     break;
		                  }
		                  --r;
		               }
		            }
		         } while (k <= j.spec_end);
		      }
		   }
		   return true;
		}

		// take a -128..127 value and stbi__clamp it and convert to 0..255
		[Inline]
		static stbi_uc stbi__clamp(int32 x)
		{
		   // trick to use a single test to catch both cases
		   if ((uint32) x > 255) {
		      if (x < 0) return 0;
		      if (x > 255) return 255;
		   }
		   return (stbi_uc) x;
		}

		static mixin stbi__f2f(var x)
		{
			((int32) (((x) * 4096 + 0.5)))
		}

		static mixin stbi__fsh(var x)
		{
			((x) * 4096)
		}

		// derived from jidctint -- DCT_ISLOW
		/*static mixin STBI__IDCT_1D(var s0,var s1,var s2,var s3,var s4,var s5,var s6,var s7)
		{
			int32 t0,t1,t2,t3,p1,p2,p3,p4,p5,x0,x1,x2,x3;
			p2 = s2;
			p3 = s6;
			p1 = (p2+p3) * stbi__f2f!(0.5411961f);
			t2 = p1 + p3*stbi__f2f!(-1.847759065f);
			t3 = p1 + p2*stbi__f2f!( 0.765366865f);
			p2 = s0;
			p3 = s4;
			t0 = stbi__fsh!(p2+p3);
			t1 = stbi__fsh!(p2-p3);
			x0 = t0+t3;
			x3 = t0-t3;
			x1 = t1+t2;
			x2 = t1-t2;
			t0 = s7;
			t1 = s5;
			t2 = s3;
			t3 = s1;
			p3 = t0+t2;
			p4 = t1+t3;
			p1 = t0+t3;
			p2 = t1+t2;
			p5 = (p3+p4)*stbi__f2f!( 1.175875602f);
			t0 = t0*stbi__f2f!( 0.298631336f);
			t1 = t1*stbi__f2f!( 2.053119869f);
			t2 = t2*stbi__f2f!( 3.072711026f);
			t3 = t3*stbi__f2f!( 1.501321110f);
			p1 = p5 + p1*stbi__f2f!(-0.899976223f);
			p2 = p5 + p2*stbi__f2f!(-2.562915447f);
			p3 = p3*stbi__f2f!(-1.961570560f);
			p4 = p4*stbi__f2f!(-0.390180644f);
			t3 += p1+p4;
			t2 += p2+p3;
			t1 += p2+p4;
			t0 += p1+p3;
		}*/

		static void stbi__idct_block(stbi_uc *out_, int32 out_stride, int16* data) // @PORT int16[64] also changed here
		{
			var data;
		   int32 i;
			int32[64] val = default;
			int32 *v=&val[0];
		   stbi_uc *o;
		   int16 *d = &data[0];

		   // columns
		   for (i=0; i < 8; ++i,++d, ++v) {
		      // if all zeroes, shortcut -- this avoids dequantizing 0s and IDCTing
		      if (d[ 8]==0 && d[16]==0 && d[24]==0 && d[32]==0
		           && d[40]==0 && d[48]==0 && d[56]==0) {
		         //    no shortcut                 0     seconds
		         //    (1|2|3|4|5|6|7)==0          0     seconds
		         //    all separate               -0.047 seconds
		         //    1 && 2|3 && 4|5 && 6|7:    -0.047 seconds
		         int32 dcterm = (int32)d[0]*4;
		         v[0] = v[8] = v[16] = v[24] = v[32] = v[40] = v[48] = v[56] = dcterm;
		      } else {
		         //STBI__IDCT_1D!(d[ 0],d[ 8],d[16],d[24],d[32],d[40],d[48],d[56]);
				  int32 s0 = d[0], s1 = d[8], s2 = d[16], s3 = d[24], s4 = d[32], s5 = d[40], s6 = d[48], s7 = d[56];
				  int32 t0,t1,t2,t3,p1,p2,p3,p4,p5,x0,x1,x2,x3;
				p2 = s2;
				p3 = s6;
				p1 = (p2+p3) * stbi__f2f!(0.5411961f);
				t2 = p1 + p3*stbi__f2f!(-1.847759065f);
				t3 = p1 + p2*stbi__f2f!( 0.765366865f);
				p2 = s0;
				p3 = s4;
				t0 = stbi__fsh!(p2+p3);
				t1 = stbi__fsh!(p2-p3);
				x0 = t0+t3;
				x3 = t0-t3;
				x1 = t1+t2;
				x2 = t1-t2;
				t0 = s7;
				t1 = s5;
				t2 = s3;
				t3 = s1;
				p3 = t0+t2;
				p4 = t1+t3;
				p1 = t0+t3;
				p2 = t1+t2;
				p5 = (p3+p4)*stbi__f2f!( 1.175875602f);
				t0 = t0*stbi__f2f!( 0.298631336f);
				t1 = t1*stbi__f2f!( 2.053119869f);
				t2 = t2*stbi__f2f!( 3.072711026f);
				t3 = t3*stbi__f2f!( 1.501321110f);
				p1 = p5 + p1*stbi__f2f!(-0.899976223f);
				p2 = p5 + p2*stbi__f2f!(-2.562915447f);
				p3 = p3*stbi__f2f!(-1.961570560f);
				p4 = p4*stbi__f2f!(-0.390180644f);
				t3 += p1+p4;
				t2 += p2+p3;
				t1 += p2+p4;
				t0 += p1+p3;

		         // constants scaled things up by 1<<12; let's bring them back
		         // down, but keep 2 extra bits of precision
		         x0 += 512; x1 += 512; x2 += 512; x3 += 512;
		         v[ 0] = (x0+t3) >> 10;
		         v[56] = (x0-t3) >> 10;
		         v[ 8] = (x1+t2) >> 10;
		         v[48] = (x1-t2) >> 10;
		         v[16] = (x2+t1) >> 10;
		         v[40] = (x2-t1) >> 10;
		         v[24] = (x3+t0) >> 10;
		         v[32] = (x3-t0) >> 10;
		      }
		   }

		   for (i=0, v=&val[0], o=out_; i < 8; ++i,v+=8,o+=out_stride) {
		      // no fast case since the first 1D IDCT spread components out
		      //STBI__IDCT_1D!(v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7]);
			   int32 s0 = v[0], s1 = v[1], s2 = v[2], s3 = v[3], s4 = v[4], s5 = v[5], s6 = v[6], s7 = v[7];
			   int32 t0,t1,t2,t3,p1,p2,p3,p4,p5,x0,x1,x2,x3;
			p2 = s2;
			p3 = s6;
			p1 = (p2+p3) * stbi__f2f!(0.5411961f);
			t2 = p1 + p3*stbi__f2f!(-1.847759065f);
			t3 = p1 + p2*stbi__f2f!( 0.765366865f);
			p2 = s0;
			p3 = s4;
			t0 = stbi__fsh!(p2+p3);
			t1 = stbi__fsh!(p2-p3);
			x0 = t0+t3;
			x3 = t0-t3;
			x1 = t1+t2;
			x2 = t1-t2;
			t0 = s7;
			t1 = s5;
			t2 = s3;
			t3 = s1;
			p3 = t0+t2;
			p4 = t1+t3;
			p1 = t0+t3;
			p2 = t1+t2;
			p5 = (p3+p4)*stbi__f2f!( 1.175875602f);
			t0 = t0*stbi__f2f!( 0.298631336f);
			t1 = t1*stbi__f2f!( 2.053119869f);
			t2 = t2*stbi__f2f!( 3.072711026f);
			t3 = t3*stbi__f2f!( 1.501321110f);
			p1 = p5 + p1*stbi__f2f!(-0.899976223f);
			p2 = p5 + p2*stbi__f2f!(-2.562915447f);
			p3 = p3*stbi__f2f!(-1.961570560f);
			p4 = p4*stbi__f2f!(-0.390180644f);
			t3 += p1+p4;
			t2 += p2+p3;
			t1 += p2+p4;
			t0 += p1+p3;

		      // constants scaled things up by 1<<12, plus we had 1<<2 from first
		      // loop, plus horizontal and vertical each scale by sqrt(8) so together
		      // we've got an extra 1<<3, so 1<<17 total we need to remove.
		      // so we want to round that, which means adding 0.5 * 1<<17,
		      // aka 65536. Also, we'll end up with -128 to 127 that we want
		      // to encode as 0..255 by adding 128, so we'll add that before the shift
		      x0 += 65536 + (128<<17);
		      x1 += 65536 + (128<<17);
		      x2 += 65536 + (128<<17);
		      x3 += 65536 + (128<<17);
		      // tried computing the shifts into temps, or'ing the temps to see
		      // if any were out of range, but that was slower
		      o[0] = stbi__clamp((x0+t3) >> 17);
		      o[7] = stbi__clamp((x0-t3) >> 17);
		      o[1] = stbi__clamp((x1+t2) >> 17);
		      o[6] = stbi__clamp((x1-t2) >> 17);
		      o[2] = stbi__clamp((x2+t1) >> 17);
		      o[5] = stbi__clamp((x2-t1) >> 17);
		      o[3] = stbi__clamp((x3+t0) >> 17);
		      o[4] = stbi__clamp((x3-t0) >> 17);
		   }
		}

#if STBI_SSE2
		// sse2 integer IDCT. not the fastest possible implementation but it
		// produces bit-identical results to the generic C version so it's
		// fully "transparent".
		static void stbi__idct_simd(stbi_uc *_out, int32 out_stride, int16[64] data)
		{
		   // This is constructed to match our regular (generic) integer IDCT exactly.
		   __m128i row0, row1, row2, row3, row4, row5, row6, row7;
		   __m128i tmp;

		   // dot product constant: even elems=x, odd elems=y
		   #define dct_const(x,y)  _mm_setr_epi16((x),(y),(x),(y),(x),(y),(x),(y))

		   // out(0) = c0[even]*x + c0[odd]*y   (c0, x, y 16-bit, out 32-bit)
		   // out(1) = c1[even]*x + c1[odd]*y
		   #define dct_rot(out0,out1, x,y,c0,c1) \
		      __m128i c0##lo = _mm_unpacklo_epi16((x),(y)); \
		      __m128i c0##hi = _mm_unpackhi_epi16((x),(y)); \
		      __m128i out0##_l = _mm_madd_epi16(c0##lo, c0); \
		      __m128i out0##_h = _mm_madd_epi16(c0##hi, c0); \
		      __m128i out1##_l = _mm_madd_epi16(c0##lo, c1); \
		      __m128i out1##_h = _mm_madd_epi16(c0##hi, c1)

		   // out = in << 12  (in 16-bit, out 32-bit)
		   #define dct_widen(out, in) \
		      __m128i out##_l = _mm_srai_epi32(_mm_unpacklo_epi16(_mm_setzero_si128(), (in)), 4); \
		      __m128i out##_h = _mm_srai_epi32(_mm_unpackhi_epi16(_mm_setzero_si128(), (in)), 4)

		   // wide add
		   #define dct_wadd(out, a, b) \
		      __m128i out##_l = _mm_add_epi32(a##_l, b##_l); \
		      __m128i out##_h = _mm_add_epi32(a##_h, b##_h)

		   // wide sub
		   #define dct_wsub(out, a, b) \
		      __m128i out##_l = _mm_sub_epi32(a##_l, b##_l); \
		      __m128i out##_h = _mm_sub_epi32(a##_h, b##_h)

		   // butterfly a/b, add bias, then shift by "s" and pack
		   #define dct_bfly32o(out0, out1, a,b,bias,s) \
		      { \
		         __m128i abiased_l = _mm_add_epi32(a##_l, bias); \
		         __m128i abiased_h = _mm_add_epi32(a##_h, bias); \
		         dct_wadd(sum, abiased, b); \
		         dct_wsub(dif, abiased, b); \
		         out0 = _mm_packs_epi32(_mm_srai_epi32(sum_l, s), _mm_srai_epi32(sum_h, s)); \
		         out1 = _mm_packs_epi32(_mm_srai_epi32(dif_l, s), _mm_srai_epi32(dif_h, s)); \
		      }

		   // 8-bit interleave step (for transposes)
		   #define dct_interleave8(a, b) \
		      tmp = a; \
		      a = _mm_unpacklo_epi8(a, b); \
		      b = _mm_unpackhi_epi8(tmp, b)

		   // 16-bit interleave step (for transposes)
		   #define dct_interleave16(a, b) \
		      tmp = a; \
		      a = _mm_unpacklo_epi16(a, b); \
		      b = _mm_unpackhi_epi16(tmp, b)

		   #define dct_pass(bias,shift) \
		      { \
		         /* even part */ \
		         dct_rot(t2e,t3e, row2,row6, rot0_0,rot0_1); \
		         __m128i sum04 = _mm_add_epi16(row0, row4); \
		         __m128i dif04 = _mm_sub_epi16(row0, row4); \
		         dct_widen(t0e, sum04); \
		         dct_widen(t1e, dif04); \
		         dct_wadd(x0, t0e, t3e); \
		         dct_wsub(x3, t0e, t3e); \
		         dct_wadd(x1, t1e, t2e); \
		         dct_wsub(x2, t1e, t2e); \
		         /* odd part */ \
		         dct_rot(y0o,y2o, row7,row3, rot2_0,rot2_1); \
		         dct_rot(y1o,y3o, row5,row1, rot3_0,rot3_1); \
		         __m128i sum17 = _mm_add_epi16(row1, row7); \
		         __m128i sum35 = _mm_add_epi16(row3, row5); \
		         dct_rot(y4o,y5o, sum17,sum35, rot1_0,rot1_1); \
		         dct_wadd(x4, y0o, y4o); \
		         dct_wadd(x5, y1o, y5o); \
		         dct_wadd(x6, y2o, y5o); \
		         dct_wadd(x7, y3o, y4o); \
		         dct_bfly32o(row0,row7, x0,x7,bias,shift); \
		         dct_bfly32o(row1,row6, x1,x6,bias,shift); \
		         dct_bfly32o(row2,row5, x2,x5,bias,shift); \
		         dct_bfly32o(row3,row4, x3,x4,bias,shift); \
		      }

		   __m128i rot0_0 = dct_const(stbi__f2f(0.5411961f), stbi__f2f(0.5411961f) + stbi__f2f(-1.847759065f));
		   __m128i rot0_1 = dct_const(stbi__f2f(0.5411961f) + stbi__f2f( 0.765366865f), stbi__f2f(0.5411961f));
		   __m128i rot1_0 = dct_const(stbi__f2f(1.175875602f) + stbi__f2f(-0.899976223f), stbi__f2f(1.175875602f));
		   __m128i rot1_1 = dct_const(stbi__f2f(1.175875602f), stbi__f2f(1.175875602f) + stbi__f2f(-2.562915447f));
		   __m128i rot2_0 = dct_const(stbi__f2f(-1.961570560f) + stbi__f2f( 0.298631336f), stbi__f2f(-1.961570560f));
		   __m128i rot2_1 = dct_const(stbi__f2f(-1.961570560f), stbi__f2f(-1.961570560f) + stbi__f2f( 3.072711026f));
		   __m128i rot3_0 = dct_const(stbi__f2f(-0.390180644f) + stbi__f2f( 2.053119869f), stbi__f2f(-0.390180644f));
		   __m128i rot3_1 = dct_const(stbi__f2f(-0.390180644f), stbi__f2f(-0.390180644f) + stbi__f2f( 1.501321110f));

		   // rounding biases in column/row passes, see stbi__idct_block for explanation.
		   __m128i bias_0 = _mm_set1_epi32(512);
		   __m128i bias_1 = _mm_set1_epi32(65536 + (128<<17));

		   // load
		   row0 = _mm_load_si128((const __m128i *) (data + 0*8));
		   row1 = _mm_load_si128((const __m128i *) (data + 1*8));
		   row2 = _mm_load_si128((const __m128i *) (data + 2*8));
		   row3 = _mm_load_si128((const __m128i *) (data + 3*8));
		   row4 = _mm_load_si128((const __m128i *) (data + 4*8));
		   row5 = _mm_load_si128((const __m128i *) (data + 5*8));
		   row6 = _mm_load_si128((const __m128i *) (data + 6*8));
		   row7 = _mm_load_si128((const __m128i *) (data + 7*8));

		   // column pass
		   dct_pass(bias_0, 10);

		   {
		      // 16bit 8x8 transpose pass 1
		      dct_interleave16(row0, row4);
		      dct_interleave16(row1, row5);
		      dct_interleave16(row2, row6);
		      dct_interleave16(row3, row7);

		      // transpose pass 2
		      dct_interleave16(row0, row2);
		      dct_interleave16(row1, row3);
		      dct_interleave16(row4, row6);
		      dct_interleave16(row5, row7);

		      // transpose pass 3
		      dct_interleave16(row0, row1);
		      dct_interleave16(row2, row3);
		      dct_interleave16(row4, row5);
		      dct_interleave16(row6, row7);
		   }

		   // row pass
		   dct_pass(bias_1, 17);

		   {
		      // pack
		      __m128i p0 = _mm_packus_epi16(row0, row1); // a0a1a2a3...a7b0b1b2b3...b7
		      __m128i p1 = _mm_packus_epi16(row2, row3);
		      __m128i p2 = _mm_packus_epi16(row4, row5);
		      __m128i p3 = _mm_packus_epi16(row6, row7);

		      // 8bit 8x8 transpose pass 1
		      dct_interleave8(p0, p2); // a0e0a1e1...
		      dct_interleave8(p1, p3); // c0g0c1g1...

		      // transpose pass 2
		      dct_interleave8(p0, p1); // a0c0e0g0...
		      dct_interleave8(p2, p3); // b0d0f0h0...

		      // transpose pass 3
		      dct_interleave8(p0, p2); // a0b0c0d0...
		      dct_interleave8(p1, p3); // a4b4c4d4...

		      // store
		      _mm_storel_epi64((__m128i *) out, p0); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, _mm_shuffle_epi32(p0, 0x4e)); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, p2); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, _mm_shuffle_epi32(p2, 0x4e)); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, p1); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, _mm_shuffle_epi32(p1, 0x4e)); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, p3); out += out_stride;
		      _mm_storel_epi64((__m128i *) out, _mm_shuffle_epi32(p3, 0x4e));
		   }

#undef dct_const
#undef dct_rot
#undef dct_widen
#undef dct_wadd
#undef dct_wsub
#undef dct_bfly32o
#undef dct_interleave8
#undef dct_interleave16
#undef dct_pass
		}

#endif // STBI_SSE2

#if STBI_NEON

		// NEON integer IDCT. should produce bit-identical
		// results to the generic C version.
		static void stbi__idct_simd(stbi_uc *out, int out_stride, short data[64])
		{
		   int16x8_t row0, row1, row2, row3, row4, row5, row6, row7;

		   int16x4_t rot0_0 = vdup_n_s16(stbi__f2f(0.5411961f));
		   int16x4_t rot0_1 = vdup_n_s16(stbi__f2f(-1.847759065f));
		   int16x4_t rot0_2 = vdup_n_s16(stbi__f2f( 0.765366865f));
		   int16x4_t rot1_0 = vdup_n_s16(stbi__f2f( 1.175875602f));
		   int16x4_t rot1_1 = vdup_n_s16(stbi__f2f(-0.899976223f));
		   int16x4_t rot1_2 = vdup_n_s16(stbi__f2f(-2.562915447f));
		   int16x4_t rot2_0 = vdup_n_s16(stbi__f2f(-1.961570560f));
		   int16x4_t rot2_1 = vdup_n_s16(stbi__f2f(-0.390180644f));
		   int16x4_t rot3_0 = vdup_n_s16(stbi__f2f( 0.298631336f));
		   int16x4_t rot3_1 = vdup_n_s16(stbi__f2f( 2.053119869f));
		   int16x4_t rot3_2 = vdup_n_s16(stbi__f2f( 3.072711026f));
		   int16x4_t rot3_3 = vdup_n_s16(stbi__f2f( 1.501321110f));

#define dct_long_mul(out, inq, coeff) \
		   int32x4_t out##_l = vmull_s16(vget_low_s16(inq), coeff); \
		   int32x4_t out##_h = vmull_s16(vget_high_s16(inq), coeff)

#define dct_long_mac(out, acc, inq, coeff) \
		   int32x4_t out##_l = vmlal_s16(acc##_l, vget_low_s16(inq), coeff); \
		   int32x4_t out##_h = vmlal_s16(acc##_h, vget_high_s16(inq), coeff)

#define dct_widen(out, inq) \
		   int32x4_t out##_l = vshll_n_s16(vget_low_s16(inq), 12); \
		   int32x4_t out##_h = vshll_n_s16(vget_high_s16(inq), 12)

		// wide add
#define dct_wadd(out, a, b) \
		   int32x4_t out##_l = vaddq_s32(a##_l, b##_l); \
		   int32x4_t out##_h = vaddq_s32(a##_h, b##_h)

		// wide sub
#define dct_wsub(out, a, b) \
		   int32x4_t out##_l = vsubq_s32(a##_l, b##_l); \
		   int32x4_t out##_h = vsubq_s32(a##_h, b##_h)

		// butterfly a/b, then shift using "shiftop" by "s" and pack
#define dct_bfly32o(out0,out1, a,b,shiftop,s) \
		   { \
		      dct_wadd(sum, a, b); \
		      dct_wsub(dif, a, b); \
		      out0 = vcombine_s16(shiftop(sum_l, s), shiftop(sum_h, s)); \
		      out1 = vcombine_s16(shiftop(dif_l, s), shiftop(dif_h, s)); \
		   }

#define dct_pass(shiftop, shift) \
		   { \
		      /* even part */ \
		      int16x8_t sum26 = vaddq_s16(row2, row6); \
		      dct_long_mul(p1e, sum26, rot0_0); \
		      dct_long_mac(t2e, p1e, row6, rot0_1); \
		      dct_long_mac(t3e, p1e, row2, rot0_2); \
		      int16x8_t sum04 = vaddq_s16(row0, row4); \
		      int16x8_t dif04 = vsubq_s16(row0, row4); \
		      dct_widen(t0e, sum04); \
		      dct_widen(t1e, dif04); \
		      dct_wadd(x0, t0e, t3e); \
		      dct_wsub(x3, t0e, t3e); \
		      dct_wadd(x1, t1e, t2e); \
		      dct_wsub(x2, t1e, t2e); \
		      /* odd part */ \
		      int16x8_t sum15 = vaddq_s16(row1, row5); \
		      int16x8_t sum17 = vaddq_s16(row1, row7); \
		      int16x8_t sum35 = vaddq_s16(row3, row5); \
		      int16x8_t sum37 = vaddq_s16(row3, row7); \
		      int16x8_t sumodd = vaddq_s16(sum17, sum35); \
		      dct_long_mul(p5o, sumodd, rot1_0); \
		      dct_long_mac(p1o, p5o, sum17, rot1_1); \
		      dct_long_mac(p2o, p5o, sum35, rot1_2); \
		      dct_long_mul(p3o, sum37, rot2_0); \
		      dct_long_mul(p4o, sum15, rot2_1); \
		      dct_wadd(sump13o, p1o, p3o); \
		      dct_wadd(sump24o, p2o, p4o); \
		      dct_wadd(sump23o, p2o, p3o); \
		      dct_wadd(sump14o, p1o, p4o); \
		      dct_long_mac(x4, sump13o, row7, rot3_0); \
		      dct_long_mac(x5, sump24o, row5, rot3_1); \
		      dct_long_mac(x6, sump23o, row3, rot3_2); \
		      dct_long_mac(x7, sump14o, row1, rot3_3); \
		      dct_bfly32o(row0,row7, x0,x7,shiftop,shift); \
		      dct_bfly32o(row1,row6, x1,x6,shiftop,shift); \
		      dct_bfly32o(row2,row5, x2,x5,shiftop,shift); \
		      dct_bfly32o(row3,row4, x3,x4,shiftop,shift); \
		   }

		   // load
		   row0 = vld1q_s16(data + 0*8);
		   row1 = vld1q_s16(data + 1*8);
		   row2 = vld1q_s16(data + 2*8);
		   row3 = vld1q_s16(data + 3*8);
		   row4 = vld1q_s16(data + 4*8);
		   row5 = vld1q_s16(data + 5*8);
		   row6 = vld1q_s16(data + 6*8);
		   row7 = vld1q_s16(data + 7*8);

		   // add DC bias
		   row0 = vaddq_s16(row0, vsetq_lane_s16(1024, vdupq_n_s16(0), 0));

		   // column pass
		   dct_pass(vrshrn_n_s32, 10);

		   // 16bit 8x8 transpose
		   {
		// these three map to a single VTRN.16, VTRN.32, and VSWP, respectively.
		// whether compilers actually get this is another story, sadly.
#define dct_trn16(x, y) { int16x8x2_t t = vtrnq_s16(x, y); x = t.val[0]; y = t.val[1]; }
#define dct_trn32(x, y) { int32x4x2_t t = vtrnq_s32(vreinterpretq_s32_s16(x), vreinterpretq_s32_s16(y)); x = vreinterpretq_s16_s32(t.val[0]); y = vreinterpretq_s16_s32(t.val[1]); }
#define dct_trn64(x, y) { int16x8_t x0 = x; int16x8_t y0 = y; x = vcombine_s16(vget_low_s16(x0), vget_low_s16(y0)); y = vcombine_s16(vget_high_s16(x0), vget_high_s16(y0)); }

		      // pass 1
		      dct_trn16(row0, row1); // a0b0a2b2a4b4a6b6
		      dct_trn16(row2, row3);
		      dct_trn16(row4, row5);
		      dct_trn16(row6, row7);

		      // pass 2
		      dct_trn32(row0, row2); // a0b0c0d0a4b4c4d4
		      dct_trn32(row1, row3);
		      dct_trn32(row4, row6);
		      dct_trn32(row5, row7);

		      // pass 3
		      dct_trn64(row0, row4); // a0b0c0d0e0f0g0h0
		      dct_trn64(row1, row5);
		      dct_trn64(row2, row6);
		      dct_trn64(row3, row7);

#undef dct_trn16
#undef dct_trn32
#undef dct_trn64
		   }

		   // row pass
		   // vrshrn_n_s32 only supports shifts up to 16, we need
		   // 17. so do a non-rounding shift of 16 first then follow
		   // up with a rounding shift by 1.
		   dct_pass(vshrn_n_s32, 16);

		   {
		      // pack and round
		      uint8x8_t p0 = vqrshrun_n_s16(row0, 1);
		      uint8x8_t p1 = vqrshrun_n_s16(row1, 1);
		      uint8x8_t p2 = vqrshrun_n_s16(row2, 1);
		      uint8x8_t p3 = vqrshrun_n_s16(row3, 1);
		      uint8x8_t p4 = vqrshrun_n_s16(row4, 1);
		      uint8x8_t p5 = vqrshrun_n_s16(row5, 1);
		      uint8x8_t p6 = vqrshrun_n_s16(row6, 1);
		      uint8x8_t p7 = vqrshrun_n_s16(row7, 1);

		      // again, these can translate into one instruction, but often don't.
#define dct_trn8_8(x, y) { uint8x8x2_t t = vtrn_u8(x, y); x = t.val[0]; y = t.val[1]; }
#define dct_trn8_16(x, y) { uint16x4x2_t t = vtrn_u16(vreinterpret_u16_u8(x), vreinterpret_u16_u8(y)); x = vreinterpret_u8_u16(t.val[0]); y = vreinterpret_u8_u16(t.val[1]); }
#define dct_trn8_32(x, y) { uint32x2x2_t t = vtrn_u32(vreinterpret_u32_u8(x), vreinterpret_u32_u8(y)); x = vreinterpret_u8_u32(t.val[0]); y = vreinterpret_u8_u32(t.val[1]); }

		      // sadly can't use interleaved stores here since we only write
		      // 8 bytes to each scan line!

		      // 8x8 8-bit transpose pass 1
		      dct_trn8_8(p0, p1);
		      dct_trn8_8(p2, p3);
		      dct_trn8_8(p4, p5);
		      dct_trn8_8(p6, p7);

		      // pass 2
		      dct_trn8_16(p0, p2);
		      dct_trn8_16(p1, p3);
		      dct_trn8_16(p4, p6);
		      dct_trn8_16(p5, p7);

		      // pass 3
		      dct_trn8_32(p0, p4);
		      dct_trn8_32(p1, p5);
		      dct_trn8_32(p2, p6);
		      dct_trn8_32(p3, p7);

		      // store
		      vst1_u8(out, p0); out += out_stride;
		      vst1_u8(out, p1); out += out_stride;
		      vst1_u8(out, p2); out += out_stride;
		      vst1_u8(out, p3); out += out_stride;
		      vst1_u8(out, p4); out += out_stride;
		      vst1_u8(out, p5); out += out_stride;
		      vst1_u8(out, p6); out += out_stride;
		      vst1_u8(out, p7);

#undef dct_trn8_8
#undef dct_trn8_16
#undef dct_trn8_32
		   }

#undef dct_long_mul
#undef dct_long_mac
#undef dct_widen
#undef dct_wadd
#undef dct_wsub
#undef dct_bfly32o
#undef dct_pass
		}

#endif // STBI_NEON

		const uint8 STBI__MARKER_none = 0xff;
		// if there's a pending marker from the entropy stream, return that
		// otherwise, fetch from the stream and get a marker. if there's no
		// marker, return 0xff, which is never a valid marker value
		static stbi_uc stbi__get_marker(stbi__jpeg *j)
		{
		   stbi_uc x;
		   if (j.marker != STBI__MARKER_none) { x = j.marker; j.marker = STBI__MARKER_none; return x; }
		   x = stbi__get8(j.s);
		   if (x != 0xff) return STBI__MARKER_none;
		   while (x == 0xff)
		      x = stbi__get8(j.s); // consume repeated 0xff fill bytes
		   return x;
		}

		// in each scan, we'll have scan_n components, and the order
		// of the components is specified by order[]
		static mixin STBI__RESTART(var x)
		{
			((x) >= 0xd0 && (x) <= 0xd7)
		}

		// after a restart interval, stbi__jpeg_reset the entropy decoder and
		// the dc prediction
		static void stbi__jpeg_reset(stbi__jpeg *j)
		{
		   j.code_bits = 0;
		   j.code_buffer = 0;
		   j.nomore = false;
		   j.img_comp[0].dc_pred = j.img_comp[1].dc_pred = j.img_comp[2].dc_pred = j.img_comp[3].dc_pred = 0;
		   j.marker = STBI__MARKER_none;
		   j.todo = j.restart_interval != 0 ? j.restart_interval : 0x7fffffff;
		   j.eob_run = 0;
		   // no more than 1<<31 MCUs if no restart_interal? that's plenty safe,
		   // since we don't even allow 1<<30 pixels
		}

		static bool stbi__parse_entropy_coded_data(stbi__jpeg *z)
		{
		   stbi__jpeg_reset(z);
		   if (!z.progressive) {
		      if (z.scan_n == 1) {
		         int32 i,j;
		         //STBI_SIMD_ALIGN(short, data[64]);
				  int16[] data = scope [Align(16)] int16[64]();

		         int32 n = z.order[0];
		         // non-interleaved data, we just need to process one block at a time,
		         // in trivial scanline order
		         // number of blocks to do just depends on how many actual "pixels" this
		         // component has, independent of interleaved MCU blocking and such
		         int32 w = (z.img_comp[n].x+7) >> 3;
		         int32 h = (z.img_comp[n].y+7) >> 3;
		         for (j=0; j < h; ++j) {
		            for (i=0; i < w; ++i) {
		               int32 ha = z.img_comp[n].ha;
		               if (!stbi__jpeg_decode_block(z, &data[0], &z.huff_dc[z.img_comp[n].hd], &z.huff_ac[ha], &z.fast_ac[ha], n, &z.dequant[z.img_comp[n].tq])) return false;
		               z.idct_block_kernel(z.img_comp[n].data+z.img_comp[n].w2*j*8+i*8, z.img_comp[n].w2, &data[0]);
		               // every data block is an MCU, so countdown the restart interval
		               if (--z.todo <= 0) {
		                  if (z.code_bits < 24) stbi__grow_buffer_unsafe(z);
		                  // if it's NOT a restart, then just bail, so we get corrupt data
		                  // rather than no data
		                  if (!STBI__RESTART!(z.marker)) return true;
		                  stbi__jpeg_reset(z);
		               }
		            }
		         }
		         return true;
		      } else { // interleaved
		         int32 i,j,k,x,y;
		         //STBI_SIMD_ALIGN(short, data[64]);
				  int16[] data = scope [Align(16)] int16[64]();
		         for (j=0; j < z.img_mcu_y; ++j) {
		            for (i=0; i < z.img_mcu_x; ++i) {
		               // scan an interleaved mcu... process scan_n components in order
		               for (k=0; k < z.scan_n; ++k) {
		                  int32 n = z.order[k];
		                  // scan out an mcu's worth of this component; that's just determined
		                  // by the basic H and V specified for the component
		                  for (y=0; y < z.img_comp[n].v; ++y) {
		                     for (x=0; x < z.img_comp[n].h; ++x) {
		                        int32 x2 = (i*z.img_comp[n].h + x)*8;
		                        int32 y2 = (j*z.img_comp[n].v + y)*8;
		                        int32 ha = z.img_comp[n].ha;
		                        if (!stbi__jpeg_decode_block(z, &data[0], &z.huff_dc[z.img_comp[n].hd], &z.huff_ac[ha], &z.fast_ac[ha], n, &z.dequant[z.img_comp[n].tq])) return false;
		                        z.idct_block_kernel(z.img_comp[n].data+z.img_comp[n].w2*y2+x2, z.img_comp[n].w2, &data[0]);
		                     }
		                  }
		               }
		               // after all interleaved components, that's an interleaved MCU,
		               // so now count down the restart interval
		               if (--z.todo <= 0) {
		                  if (z.code_bits < 24) stbi__grow_buffer_unsafe(z);
		                  if (!STBI__RESTART!(z.marker)) return true;
		                  stbi__jpeg_reset(z);
		               }
		            }
		         }
		         return true;
		      }
		   } else {
		      if (z.scan_n == 1) {
		         int32 i,j;
		         int32 n = z.order[0];
		         // non-interleaved data, we just need to process one block at a time,
		         // in trivial scanline order
		         // number of blocks to do just depends on how many actual "pixels" this
		         // component has, independent of interleaved MCU blocking and such
		         int32 w = (z.img_comp[n].x+7) >> 3;
		         int32 h = (z.img_comp[n].y+7) >> 3;
		         for (j=0; j < h; ++j) {
		            for (i=0; i < w; ++i) {
		               int16 *data = z.img_comp[n].coeff + 64 * (i + j * z.img_comp[n].coeff_w);
		               if (z.spec_start == 0) {
		                  if (!stbi__jpeg_decode_block_prog_dc(z, data, &z.huff_dc[z.img_comp[n].hd], n))
		                     return false;
		               } else {
		                  int32 ha = z.img_comp[n].ha;
		                  if (!stbi__jpeg_decode_block_prog_ac(z, data, &z.huff_ac[ha], &z.fast_ac[ha]))
		                     return false;
		               }
		               // every data block is an MCU, so countdown the restart interval
		               if (--z.todo <= 0) {
		                  if (z.code_bits < 24) stbi__grow_buffer_unsafe(z);
		                  if (!STBI__RESTART!(z.marker)) return true;
		                  stbi__jpeg_reset(z);
		               }
		            }
		         }
		         return true;
		      } else { // interleaved
		         int32 i,j,k,x,y;
		         for (j=0; j < z.img_mcu_y; ++j) {
		            for (i=0; i < z.img_mcu_x; ++i) {
		               // scan an interleaved mcu... process scan_n components in order
		               for (k=0; k < z.scan_n; ++k) {
		                  int32 n = z.order[k];
		                  // scan out an mcu's worth of this component; that's just determined
		                  // by the basic H and V specified for the component
		                  for (y=0; y < z.img_comp[n].v; ++y) {
		                     for (x=0; x < z.img_comp[n].h; ++x) {
		                        int32 x2 = (i*z.img_comp[n].h + x);
		                        int32 y2 = (j*z.img_comp[n].v + y);
		                        int16 *data = z.img_comp[n].coeff + 64 * (x2 + y2 * z.img_comp[n].coeff_w);
		                        if (!stbi__jpeg_decode_block_prog_dc(z, data, &z.huff_dc[z.img_comp[n].hd], n))
		                           return false;
		                     }
		                  }
		               }
		               // after all interleaved components, that's an interleaved MCU,
		               // so now count down the restart interval
		               if (--z.todo <= 0) {
		                  if (z.code_bits < 24) stbi__grow_buffer_unsafe(z);
		                  if (!STBI__RESTART!(z.marker)) return true;
		                  stbi__jpeg_reset(z);
		               }
		            }
		         }
		         return true;
		      }
		   }
		}

		static void stbi__jpeg_dequantize(int16 *data, stbi__uint16 *dequant)
		{
		   int32 i;
		   for (i=0; i < 64; ++i)
		      data[i] = (.)((int32)dequant[i] * data[i]);
		}

		static void stbi__jpeg_finish(stbi__jpeg *z)
		{
		   if (z.progressive) {
		      // dequantize and idct the data
		      int32 i,j,n;
		      for (n=0; n < z.s.img_n; ++n) {
		         int32 w = (z.img_comp[n].x+7) >> 3;
		         int32 h = (z.img_comp[n].y+7) >> 3;
		         for (j=0; j < h; ++j) {
		            for (i=0; i < w; ++i) {
		               int16 *data = z.img_comp[n].coeff + 64 * (i + j * z.img_comp[n].coeff_w);
		               stbi__jpeg_dequantize(data, &z.dequant[z.img_comp[n].tq]);
		               z.idct_block_kernel(z.img_comp[n].data+z.img_comp[n].w2*j*8+i*8, z.img_comp[n].w2, data);
		            }
		         }
		      }
		   }
		}

		const char8[5] tag_jfif = .('J','F','I','F','\0');
		const char8[6] tag_adobe = .('A','d','o','b','e','\0');
		static bool stbi__process_marker(stbi__jpeg *z, int32 m)
		{
		   int32 L;
		   switch (m) {
		      case STBI__MARKER_none: // no marker found
		         return stbi__err!("expected marker","Corrupt JPEG");

		      case 0xDD: // DRI - specify restart interval
		         if (stbi__get16be(z.s) != 4) return stbi__err!("bad DRI len","Corrupt JPEG");
		         z.restart_interval = stbi__get16be(z.s);
		         return true;

		      case 0xDB: // DQT - define quantization table
		         L = stbi__get16be(z.s)-2;
		         while (L > 0) {
		            int32 q = stbi__get8(z.s);
		            int32 p = q >> 4;
					 bool sixteen = (p != 0);
		            int32 t = q & 15;
					 int32 i;
		            if (p != 0 && p != 1) return stbi__err!("bad DQT type","Corrupt JPEG");
		            if (t > 3) return stbi__err!("bad DQT table","Corrupt JPEG");

		            for (i=0; i < 64; ++i)
		               z.dequant[t][stbi__jpeg_dezigzag[i]] = (stbi__uint16)(sixteen ? stbi__get16be(z.s) : stbi__get8(z.s));
		            L -= (sixteen ? 129 : 65);
		         }
		         return L==0;

		      case 0xC4: // DHT - define huffman table
		         L = stbi__get16be(z.s)-2;
		         while (L > 0) {
		            stbi_uc *v;
		            int32[16] sizes;
					 int32 i; int32 n=0;
		            int32 q = stbi__get8(z.s);
		            int32 tc = q >> 4;
		            int32 th = q & 15;
		            if (tc > 1 || th > 3) return stbi__err!("bad DHT header","Corrupt JPEG");
		            for (i=0; i < 16; ++i) {
		               sizes[i] = stbi__get8(z.s);
		               n += sizes[i];
		            }
		            L -= 17;
		            if (tc == 0) {
		               if (!stbi__build_huffman(&z.huff_dc[th], &sizes[0])) return false;
		               v = &z.huff_dc[th].values[0];
		            } else {
		               if (!stbi__build_huffman(&z.huff_ac[th], &sizes[0])) return false;
		               v = &z.huff_ac[th].values[0];
		            }
		            for (i=0; i < n; ++i)
		               v[i] = stbi__get8(z.s);
		            if (tc != 0)
		               stbi__build_fast_ac(&z.fast_ac[th], &z.huff_ac[th]);
		            L -= n;
		         }
		         return L==0;
		   }

		   // check for comment block or APP blocks
		   if ((m >= 0xE0 && m <= 0xEF) || m == 0xFE) {
		      L = stbi__get16be(z.s);
		      if (L < 2) {
		         if (m == 0xFE)
		            return stbi__err!("bad COM len","Corrupt JPEG");
		         else
		            return stbi__err!("bad APP len","Corrupt JPEG");
		      }
		      L -= 2;

		      if (m == 0xE0 && L >= 5) { // JFIF APP0 segment
		         int32 ok = 1;
		         int32 i;
		         for (i=0; i < 5; ++i)
		            if (stbi__get8(z.s) != tag_jfif[i])
		               ok = 0;
		         L -= 5;
		         if (ok != 0)
		            z.jfif = 1;
		      } else if (m == 0xEE && L >= 12) { // Adobe APP14 segment
		         int32 ok = 1;
		         int32 i;
		         for (i=0; i < 6; ++i)
		            if (stbi__get8(z.s) != tag_adobe[i])
		               ok = 0;
		         L -= 6;
		         if (ok != 0) {
		            stbi__get8(z.s); // version
		            stbi__get16be(z.s); // flags0
		            stbi__get16be(z.s); // flags1
		            z.app14_color_transform = stbi__get8(z.s); // color transform
		            L -= 6;
		         }
		      }

		      stbi__skip(z.s, L);
		      return true;
		   }

		   return stbi__err!("unknown marker","Corrupt JPEG");
		}

		// after we see SOS
		static bool stbi__process_scan_header(stbi__jpeg *z)
		{
		   int32 i;
		   int32 Ls = stbi__get16be(z.s);
		   z.scan_n = stbi__get8(z.s);
		   if (z.scan_n < 1 || z.scan_n > 4 || z.scan_n > (int) z.s.img_n) return stbi__err!("bad SOS component count","Corrupt JPEG");
		   if (Ls != 6+2*z.scan_n) return stbi__err!("bad SOS len","Corrupt JPEG");
		   for (i=0; i < z.scan_n; ++i) {
		      int32 id = stbi__get8(z.s), which;
		      int32 q = stbi__get8(z.s);
		      for (which = 0; which < z.s.img_n; ++which)
		         if (z.img_comp[which].id == id)
		            break;
		      if (which == z.s.img_n) return false; // no match
		      z.img_comp[which].hd = q >> 4;   if (z.img_comp[which].hd > 3) return stbi__err!("bad DC huff","Corrupt JPEG");
		      z.img_comp[which].ha = q & 15;   if (z.img_comp[which].ha > 3) return stbi__err!("bad AC huff","Corrupt JPEG");
		      z.order[i] = which;
		   }

		   {
		      int32 aa;
		      z.spec_start = stbi__get8(z.s);
		      z.spec_end   = stbi__get8(z.s); // should be 63, but might be 0
		      aa = stbi__get8(z.s);
		      z.succ_high = (aa >> 4);
		      z.succ_low  = (aa & 15);
		      if (z.progressive) {
		         if (z.spec_start > 63 || z.spec_end > 63  || z.spec_start > z.spec_end || z.succ_high > 13 || z.succ_low > 13)
		            return stbi__err!("bad SOS", "Corrupt JPEG");
		      } else {
		         if (z.spec_start != 0) return stbi__err!("bad SOS","Corrupt JPEG");
		         if (z.succ_high != 0 || z.succ_low != 0) return stbi__err!("bad SOS","Corrupt JPEG");
		         z.spec_end = 63;
		      }
		   }

		   return true;
		}

		static bool stbi__free_jpeg_components(stbi__jpeg *z, int32 ncomp, bool why)
		{
		   int32 i;
		   for (i=0; i < ncomp; ++i) {
		      if (z.img_comp[i].raw_data != null) {
		         STBI_FREE!(z.img_comp[i].raw_data);
		         z.img_comp[i].raw_data = null;
		         z.img_comp[i].data = null;
		      }
		      if (z.img_comp[i].raw_coeff != null) {
		         STBI_FREE!(z.img_comp[i].raw_coeff);
		         z.img_comp[i].raw_coeff = null;
		         z.img_comp[i].coeff = null;
		      }
		      if (z.img_comp[i].linebuf != null) {
		         STBI_FREE!(z.img_comp[i].linebuf);
		         z.img_comp[i].linebuf = null;
		      }
		   }
		   return why;
		}

		static char8[3] rgb = .( 'R', 'G', 'B' );
		static bool stbi__process_frame_header(stbi__jpeg *z, int32 scan)
		{
		   stbi__context *s = z.s;
		   int32 Lf,p,i,q, h_max=1,v_max=1,c;
		   Lf = stbi__get16be(s);         if (Lf < 11) return stbi__err!("bad SOF len","Corrupt JPEG"); // JPEG
		   p  = stbi__get8(s);            if (p != 8) return stbi__err!("only 8-bit","JPEG format not supported: 8-bit only"); // JPEG baseline
		   s.img_y = (.)stbi__get16be(s);   if (s.img_y == 0) return stbi__err!("no header height", "JPEG format not supported: delayed height"); // Legal, but we don't handle it--but neither does IJG
		   s.img_x = (.)stbi__get16be(s);   if (s.img_x == 0) return stbi__err!("0 width","Corrupt JPEG"); // JPEG requires
		   if (s.img_y > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");
		   if (s.img_x > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");
		   c = stbi__get8(s);
		   if (c != 3 && c != 1 && c != 4) return stbi__err!("bad component count","Corrupt JPEG");
		   s.img_n = c;
		   for (i=0; i < c; ++i) {
		      z.img_comp[i].data = null;
		      z.img_comp[i].linebuf = null;
		   }

		   if (Lf != 8+3*s.img_n) return stbi__err!("bad SOF len","Corrupt JPEG");

		   z.rgb = 0;
		   for (i=0; i < s.img_n; ++i) {
		      
		      z.img_comp[i].id = stbi__get8(s);
		      if (s.img_n == 3 && z.img_comp[i].id == (int32)rgb[i])
		         ++z.rgb;
		      q = stbi__get8(s);
		      z.img_comp[i].h = (q >> 4);  if (z.img_comp[i].h == 0 || z.img_comp[i].h > 4) return stbi__err!("bad H","Corrupt JPEG");
		      z.img_comp[i].v = q & 15;    if (z.img_comp[i].v == 0 || z.img_comp[i].v > 4) return stbi__err!("bad V","Corrupt JPEG");
		      z.img_comp[i].tq = stbi__get8(s);  if (z.img_comp[i].tq > 3) return stbi__err!("bad TQ","Corrupt JPEG");
		   }

		   if (scan != STBI__SCAN_load) return true;

		   if (!stbi__mad3sizes_valid((.)s.img_x, (.)s.img_y, s.img_n, 0)) return stbi__err!("too large", "Image too large to decode");

		   for (i=0; i < s.img_n; ++i) {
		      if (z.img_comp[i].h > h_max) h_max = z.img_comp[i].h;
		      if (z.img_comp[i].v > v_max) v_max = z.img_comp[i].v;
		   }

		   // check that plane subsampling factors are integer ratios; our resamplers can't deal with fractional ratios
		   // and I've never seen a non-corrupted JPEG file actually use them
		   for (i=0; i < s.img_n; ++i) {
		      if (h_max % z.img_comp[i].h != 0) return stbi__err!("bad H","Corrupt JPEG");
		      if (v_max % z.img_comp[i].v != 0) return stbi__err!("bad V","Corrupt JPEG");
		   }

		   // compute interleaved mcu info
		   z.img_h_max = h_max;
		   z.img_v_max = v_max;
		   z.img_mcu_w = h_max * 8;
		   z.img_mcu_h = v_max * 8;
		   // these sizes can't be more than 17 bits
		   z.img_mcu_x = ((.)s.img_x + z.img_mcu_w-1) / z.img_mcu_w;
		   z.img_mcu_y = ((.)s.img_y + z.img_mcu_h-1) / z.img_mcu_h;

		   for (i=0; i < s.img_n; ++i) {
		      // number of effective pixels (e.g. for non-interleaved MCU)
		      z.img_comp[i].x = ((.)s.img_x * z.img_comp[i].h + h_max-1) / h_max;
		      z.img_comp[i].y = ((.)s.img_y * z.img_comp[i].v + v_max-1) / v_max;
		      // to simplify generation, we'll allocate enough memory to decode
		      // the bogus oversized data from using interleaved MCUs and their
		      // big blocks (e.g. a 16x16 iMCU on an image of width 33); we won't
		      // discard the extra data until colorspace conversion
		      //
		      // img_mcu_x, img_mcu_y: <=17 bits; comp[i].h and .v are <=4 (checked earlier)
		      // so these muls can't overflow with 32-bit ints (which we require)
		      z.img_comp[i].w2 = z.img_mcu_x * z.img_comp[i].h * 8;
		      z.img_comp[i].h2 = z.img_mcu_y * z.img_comp[i].v * 8;
		      z.img_comp[i].coeff = null;
		      z.img_comp[i].raw_coeff = null;
		      z.img_comp[i].linebuf = null;
		      z.img_comp[i].raw_data = stbi__malloc_mad2(z.img_comp[i].w2, z.img_comp[i].h2, 15);
		      if (z.img_comp[i].raw_data == null)
		         return stbi__free_jpeg_components(z, i+1, stbi__err!("outofmem", "Out of memory"));
		      // align blocks for idct using mmx/sse
		      z.img_comp[i].data = (stbi_uc*) (void*)(((int) z.img_comp[i].raw_data + 15) & ~15);
		      if (z.progressive) {
		         // w2, h2 are multiples of 8 (see above)
		         z.img_comp[i].coeff_w = z.img_comp[i].w2 / 8;
		         z.img_comp[i].coeff_h = z.img_comp[i].h2 / 8;
		         z.img_comp[i].raw_coeff = stbi__malloc_mad3(z.img_comp[i].w2, z.img_comp[i].h2, sizeof(int16), 15);
		         if (z.img_comp[i].raw_coeff == null)
		            return stbi__free_jpeg_components(z, i+1, stbi__err!("outofmem", "Out of memory"));
		         z.img_comp[i].coeff = (int16*) (void*)(((int) z.img_comp[i].raw_coeff + 15) & ~15);
		      }
		   }

		   return true;
		}

		// use comparisons since in some cases we handle more than one case (e.g. SOF)
		static mixin stbi__DNL(var x)
		{
			((x) == 0xdc)
		}
		static mixin stbi__SOI(var x)
		{
			((x) == 0xd8)
		}
		static mixin stbi__EOI(var x)
		{
			((x) == 0xd9)
		}
		static mixin stbi__SOF(var x)
		{
			((x) == 0xc0 || (x) == 0xc1 || (x) == 0xc2)
		}
		static mixin stbi__SOS(var x)
		{
			((x) == 0xda)
		}

		static mixin stbi__SOF_progressive(var x)
		{
			((x) == 0xc2)
		}

		static bool stbi__decode_jpeg_header(stbi__jpeg *z, int32 scan)
		{
		   int32 m;
		   z.jfif = 0;
		   z.app14_color_transform = -1; // valid values are 0,1,2
		   z.marker = STBI__MARKER_none; // initialize cached marker to empty
		   m = stbi__get_marker(z);
		   if (!stbi__SOI!(m)) return stbi__err!("no SOI","Corrupt JPEG");
		   if (scan == STBI__SCAN_type) return true;
		   m = stbi__get_marker(z);
		   while (!stbi__SOF!(m)) {
		      if (!stbi__process_marker(z,m)) return false;
		      m = stbi__get_marker(z);
		      while (m == STBI__MARKER_none) {
		         // some files have extra padding after their blocks, so ok, we'll scan
		         if (stbi__at_eof(z.s)) return stbi__err!("no SOF", "Corrupt JPEG");
		         m = stbi__get_marker(z);
		      }
		   }
		   z.progressive = stbi__SOF_progressive!(m);
		   if (!stbi__process_frame_header(z, scan)) return false;
		   return true;
		}

		// decode image to YCbCr format
		static bool stbi__decode_jpeg_image(stbi__jpeg *j)
		{
		   int32 m;
		   for (m = 0; m < 4; m++) {
		      j.img_comp[m].raw_data = null;
		      j.img_comp[m].raw_coeff = null;
		   }
		   j.restart_interval = 0;
		   if (!stbi__decode_jpeg_header(j, STBI__SCAN_load)) return false;
		   m = stbi__get_marker(j);
		   while (!stbi__EOI!(m)) {
		      if (stbi__SOS!(m)) {
		         if (!stbi__process_scan_header(j)) return false;
		         if (!stbi__parse_entropy_coded_data(j)) return false;
		         if (j.marker == STBI__MARKER_none ) {
		            // handle 0s at the end of image data from IP Kamera 9060
		            while (!stbi__at_eof(j.s)) {
		               int32 x = stbi__get8(j.s);
		               if (x == 255) {
		                  j.marker = stbi__get8(j.s);
		                  break;
		               }
		            }
		            // if we reach eof without hitting a marker, stbi__get_marker() below will fail and we'll eventually return 0
		         }
		      } else if (stbi__DNL!(m)) {
		         int32 Ld = stbi__get16be(j.s);
		         stbi__uint32 NL = (.)stbi__get16be(j.s);
		         if (Ld != 4) return stbi__err!("bad DNL len", "Corrupt JPEG");
		         if (NL != j.s.img_y) return stbi__err!("bad DNL height", "Corrupt JPEG");
		      } else {
		         if (!stbi__process_marker(j, m)) return false;
		      }
		      m = stbi__get_marker(j);
		   }
		   if (j.progressive)
		      stbi__jpeg_finish(j);
		   return true;
		}

		// static jfif-centered resampling (across block boundaries)

		function stbi_uc* resample_row_func(stbi_uc *out_, stbi_uc *in0, stbi_uc *in1,int32 w, int32 hs);

		static mixin stbi__div4(var x)
		{
			((stbi_uc) ((x) >> 2))
		}

		static stbi_uc *resample_row_1(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   return in_near;
		}

		static stbi_uc* stbi__resample_row_v_2(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   // need to generate two samples vertically for every one in input
		   int32 i;
		   for (i=0; i < w; ++i)
		      out_[i] = stbi__div4!((int32)3*in_near[i] + in_far[i] + 2);
		   return out_;
		}

		static stbi_uc*  stbi__resample_row_h_2(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   // need to generate two samples horizontally for every one in input
		   int32 i;
		   stbi_uc *input = in_near;

		   if (w == 1) {
		      // if only one sample, can't do any interpolation
		      out_[0] = out_[1] = input[0];
		      return out_;
		   }

		   out_[0] = input[0];
		   out_[1] = stbi__div4!((int32)input[0]*3 + input[1] + 2);
		   for (i=1; i < w-1; ++i) {
		      int32 n = (int32)3*input[i]+2;
		      out_[i*2+0] = stbi__div4!(n+input[i-1]);
		      out_[i*2+1] = stbi__div4!(n+input[i+1]);
		   }
		   out_[i*2+0] = stbi__div4!((int32)input[w-2]*3 + input[w-1] + 2);
		   out_[i*2+1] = input[w-1];

		   return out_;
		}

		static mixin stbi__div16(var x)
		{
			((stbi_uc) ((x) >> 4))
		}

		static stbi_uc *stbi__resample_row_hv_2(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   // need to generate 2x2 samples for every one in input
		   int32 i,t0,t1;
		   if (w == 1) {
		      out_[0] = out_[1] = stbi__div4!((int32)3*in_near[0] + in_far[0] + 2);
		      return out_;
		   }

		   t1 = (int32)3*in_near[0] + in_far[0];
		   out_[0] = stbi__div4!(t1+2);
		   for (i=1; i < w; ++i) {
		      t0 = t1;
		      t1 = (int32)3*in_near[i]+in_far[i];
		      out_[i*2-1] = stbi__div16!(3*t0 + t1 + 8);
		      out_[i*2  ] = stbi__div16!(3*t1 + t0 + 8);
		   }
		   out_[w*2-1] = stbi__div4!(t1+2);

		   return out_;
		}

#if STBI_SSE2 || STBI_NEON
		static stbi_uc *stbi__resample_row_hv_2_simd(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   // need to generate 2x2 samples for every one in input
		   int i=0,t0,t1;

		   if (w == 1) {
		      out_[0] = out_[1] = stbi__div4!(3*in_near[0] + in_far[0] + 2);
		      return out_;
		   }

		   t1 = 3*in_near[0] + in_far[0];
		   // process groups of 8 pixels for as long as we can.
		   // note we can't handle the last pixel in a row in this loop
		   // because we need to handle the filter boundary conditions.
		   for (; i < ((w-1) & ~7); i += 8) {
#if STBI_SSE2
		      // load and perform the vertical filtering pass
		      // this uses 3*x + y = 4*x + (y - x)
		      __m128i zero  = _mm_setzero_si128();
		      __m128i farb  = _mm_loadl_epi64((__m128i *) (in_far + i));
		      __m128i nearb = _mm_loadl_epi64((__m128i *) (in_near + i));
		      __m128i farw  = _mm_unpacklo_epi8(farb, zero);
		      __m128i nearw = _mm_unpacklo_epi8(nearb, zero);
		      __m128i diff  = _mm_sub_epi16(farw, nearw);
		      __m128i nears = _mm_slli_epi16(nearw, 2);
		      __m128i curr  = _mm_add_epi16(nears, diff); // current row

		      // horizontal filter works the same based on shifted vers of current
		      // row. "prev" is current row shifted right by 1 pixel; we need to
		      // insert the previous pixel value (from t1).
		      // "next" is current row shifted left by 1 pixel, with first pixel
		      // of next block of 8 pixels added in.
		      __m128i prv0 = _mm_slli_si128(curr, 2);
		      __m128i nxt0 = _mm_srli_si128(curr, 2);
		      __m128i prev = _mm_insert_epi16(prv0, t1, 0);
		      __m128i next = _mm_insert_epi16(nxt0, 3*in_near[i+8] + in_far[i+8], 7);

		      // horizontal filter, polyphase implementation since it's convenient:
		      // even pixels = 3*cur + prev = cur*4 + (prev - cur)
		      // odd  pixels = 3*cur + next = cur*4 + (next - cur)
		      // note the shared term.
		      __m128i bias  = _mm_set1_epi16(8);
		      __m128i curs = _mm_slli_epi16(curr, 2);
		      __m128i prvd = _mm_sub_epi16(prev, curr);
		      __m128i nxtd = _mm_sub_epi16(next, curr);
		      __m128i curb = _mm_add_epi16(curs, bias);
		      __m128i even = _mm_add_epi16(prvd, curb);
		      __m128i odd  = _mm_add_epi16(nxtd, curb);

		      // interleave even and odd pixels, then undo scaling.
		      __m128i int0 = _mm_unpacklo_epi16(even, odd);
		      __m128i int1 = _mm_unpackhi_epi16(even, odd);
		      __m128i de0  = _mm_srli_epi16(int0, 4);
		      __m128i de1  = _mm_srli_epi16(int1, 4);

		      // pack and write output
		      __m128i outv = _mm_packus_epi16(de0, de1);
		      _mm_storeu_si128((__m128i *) (out + i*2), outv);
#elif STBI_NEON
		      // load and perform the vertical filtering pass
		      // this uses 3*x + y = 4*x + (y - x)
		      uint8x8_t farb  = vld1_u8(in_far + i);
		      uint8x8_t nearb = vld1_u8(in_near + i);
		      int16x8_t diff  = vreinterpretq_s16_u16(vsubl_u8(farb, nearb));
		      int16x8_t nears = vreinterpretq_s16_u16(vshll_n_u8(nearb, 2));
		      int16x8_t curr  = vaddq_s16(nears, diff); // current row

		      // horizontal filter works the same based on shifted vers of current
		      // row. "prev" is current row shifted right by 1 pixel; we need to
		      // insert the previous pixel value (from t1).
		      // "next" is current row shifted left by 1 pixel, with first pixel
		      // of next block of 8 pixels added in.
		      int16x8_t prv0 = vextq_s16(curr, curr, 7);
		      int16x8_t nxt0 = vextq_s16(curr, curr, 1);
		      int16x8_t prev = vsetq_lane_s16(t1, prv0, 0);
		      int16x8_t next = vsetq_lane_s16(3*in_near[i+8] + in_far[i+8], nxt0, 7);

		      // horizontal filter, polyphase implementation since it's convenient:
		      // even pixels = 3*cur + prev = cur*4 + (prev - cur)
		      // odd  pixels = 3*cur + next = cur*4 + (next - cur)
		      // note the shared term.
		      int16x8_t curs = vshlq_n_s16(curr, 2);
		      int16x8_t prvd = vsubq_s16(prev, curr);
		      int16x8_t nxtd = vsubq_s16(next, curr);
		      int16x8_t even = vaddq_s16(curs, prvd);
		      int16x8_t odd  = vaddq_s16(curs, nxtd);

		      // undo scaling and round, then store with even/odd phases interleaved
		      uint8x8x2_t o;
		      o.val[0] = vqrshrun_n_s16(even, 4);
		      o.val[1] = vqrshrun_n_s16(odd,  4);
		      vst2_u8(out + i*2, o);
#endif

		      // "previous" value for next iter
		      t1 = 3*in_near[i+7] + in_far[i+7];
		   }

		   t0 = t1;
		   t1 = 3*in_near[i] + in_far[i];
		   out_[i*2] = stbi__div16!(3*t1 + t0 + 8);

			++i;
		   for (; i < w; ++i) {
		      t0 = t1;
		      t1 = 3*in_near[i]+in_far[i];
		      out_[i*2-1] = stbi__div16!(3*t0 + t1 + 8);
		      out_[i*2  ] = stbi__div16!(3*t1 + t0 + 8);
		   }
		   out_[w*2-1] = stbi__div4!(t1+2);

		   return out_;
		}
#endif

		static stbi_uc *stbi__resample_row_generic(stbi_uc *out_, stbi_uc *in_near, stbi_uc *in_far, int32 w, int32 hs)
		{
		   // resample with nearest-neighbor
		   int32 i,j;
		   for (i=0; i < w; ++i)
		      for (j=0; j < hs; ++j)
		         out_[i*hs+j] = in_near[i];
		   return out_;
		}

		// this is a reduced-precision calculation of YCbCr-to-RGB introduced
		// to make sure the code produces the same results in both SIMD and scalar
		static mixin stbi__float2fixed(var x)
		{
			(((int32) ((x) * 4096.0f + 0.5f)) << 8)
		}

		static void stbi__YCbCr_to_RGB_row(stbi_uc *out_, stbi_uc *y, stbi_uc *pcb, stbi_uc *pcr, int32 count, int32 step)
		{
			var out_;
		   int32 i;
		   for (i=0; i < count; ++i) {
		      int32 y_fixed = ((int32)y[i] << 20) + (1<<19); // rounding
		      int32 r,g,b;
		      int32 cr = (int32)pcr[i] - 128;
		      int32 cb = (int32)pcb[i] - 128;
		      r = y_fixed +  cr* stbi__float2fixed!(1.40200f);
		      g = y_fixed + (cr*-stbi__float2fixed!(0.71414f)) + (int32)((cb*-stbi__float2fixed!(0.34414f)) & 0xffff0000);
		      b = y_fixed                                     +   cb* stbi__float2fixed!(1.77200f);
		      r >>= 20;
		      g >>= 20;
		      b >>= 20;
		      if ((uint32) r > 255) { if (r < 0) r = 0; else r = 255; }
		      if ((uint32) g > 255) { if (g < 0) g = 0; else g = 255; }
		      if ((uint32) b > 255) { if (b < 0) b = 0; else b = 255; }
		      out_[0] = (stbi_uc)r;
		      out_[1] = (stbi_uc)g;
		      out_[2] = (stbi_uc)b;
		      out_[3] = 255;
		      out_ += step;
		   }
		}

#if STBI_SSE2 || STBI_NEON
		static void stbi__YCbCr_to_RGB_simd(stbi_uc *out_, stbi_uc *y, stbi_uc *pcb, stbi_uc *pcr, int32 count, int32 step)
		{
		   int32 i = 0;
			var out_;

#if STBI_SSE2
		   // step == 3 is pretty ugly on the final interleave, and i'm not convinced
		   // it's useful in practice (you wouldn't use it for textures, for example).
		   // so just accelerate step == 4 case.
		   if (step == 4) {
		      // this is a fairly straightforward implementation and not super-optimized.
		      __m128i signflip  = _mm_set1_epi8(-0x80);
		      __m128i cr_const0 = _mm_set1_epi16(   (short) ( 1.40200f*4096.0f+0.5f));
		      __m128i cr_const1 = _mm_set1_epi16( - (short) ( 0.71414f*4096.0f+0.5f));
		      __m128i cb_const0 = _mm_set1_epi16( - (short) ( 0.34414f*4096.0f+0.5f));
		      __m128i cb_const1 = _mm_set1_epi16(   (short) ( 1.77200f*4096.0f+0.5f));
		      __m128i y_bias = _mm_set1_epi8((char) (unsigned char) 128);
		      __m128i xw = _mm_set1_epi16(255); // alpha channel

		      for (; i+7 < count; i += 8) {
		         // load
		         __m128i y_bytes = _mm_loadl_epi64((__m128i *) (y+i));
		         __m128i cr_bytes = _mm_loadl_epi64((__m128i *) (pcr+i));
		         __m128i cb_bytes = _mm_loadl_epi64((__m128i *) (pcb+i));
		         __m128i cr_biased = _mm_xor_si128(cr_bytes, signflip); // -128
		         __m128i cb_biased = _mm_xor_si128(cb_bytes, signflip); // -128

		         // unpack to short (and left-shift cr, cb by 8)
		         __m128i yw  = _mm_unpacklo_epi8(y_bias, y_bytes);
		         __m128i crw = _mm_unpacklo_epi8(_mm_setzero_si128(), cr_biased);
		         __m128i cbw = _mm_unpacklo_epi8(_mm_setzero_si128(), cb_biased);

		         // color transform
		         __m128i yws = _mm_srli_epi16(yw, 4);
		         __m128i cr0 = _mm_mulhi_epi16(cr_const0, crw);
		         __m128i cb0 = _mm_mulhi_epi16(cb_const0, cbw);
		         __m128i cb1 = _mm_mulhi_epi16(cbw, cb_const1);
		         __m128i cr1 = _mm_mulhi_epi16(crw, cr_const1);
		         __m128i rws = _mm_add_epi16(cr0, yws);
		         __m128i gwt = _mm_add_epi16(cb0, yws);
		         __m128i bws = _mm_add_epi16(yws, cb1);
		         __m128i gws = _mm_add_epi16(gwt, cr1);

		         // descale
		         __m128i rw = _mm_srai_epi16(rws, 4);
		         __m128i bw = _mm_srai_epi16(bws, 4);
		         __m128i gw = _mm_srai_epi16(gws, 4);

		         // back to byte, set up for transpose
		         __m128i brb = _mm_packus_epi16(rw, bw);
		         __m128i gxb = _mm_packus_epi16(gw, xw);

		         // transpose to interleave channels
		         __m128i t0 = _mm_unpacklo_epi8(brb, gxb);
		         __m128i t1 = _mm_unpackhi_epi8(brb, gxb);
		         __m128i o0 = _mm_unpacklo_epi16(t0, t1);
		         __m128i o1 = _mm_unpackhi_epi16(t0, t1);

		         // store
		         _mm_storeu_si128((__m128i *) (out + 0), o0);
		         _mm_storeu_si128((__m128i *) (out + 16), o1);
		         out += 32;
		      }
		   }
#endif

#if STBI_NEON
		   // in this version, step=3 support would be easy to add. but is there demand?
		   if (step == 4) {
		      // this is a fairly straightforward implementation and not super-optimized.
		      uint8x8_t signflip = vdup_n_u8(0x80);
		      int16x8_t cr_const0 = vdupq_n_s16(   (short) ( 1.40200f*4096.0f+0.5f));
		      int16x8_t cr_const1 = vdupq_n_s16( - (short) ( 0.71414f*4096.0f+0.5f));
		      int16x8_t cb_const0 = vdupq_n_s16( - (short) ( 0.34414f*4096.0f+0.5f));
		      int16x8_t cb_const1 = vdupq_n_s16(   (short) ( 1.77200f*4096.0f+0.5f));

		      for (; i+7 < count; i += 8) {
		         // load
		         uint8x8_t y_bytes  = vld1_u8(y + i);
		         uint8x8_t cr_bytes = vld1_u8(pcr + i);
		         uint8x8_t cb_bytes = vld1_u8(pcb + i);
		         int8x8_t cr_biased = vreinterpret_s8_u8(vsub_u8(cr_bytes, signflip));
		         int8x8_t cb_biased = vreinterpret_s8_u8(vsub_u8(cb_bytes, signflip));

		         // expand to s16
		         int16x8_t yws = vreinterpretq_s16_u16(vshll_n_u8(y_bytes, 4));
		         int16x8_t crw = vshll_n_s8(cr_biased, 7);
		         int16x8_t cbw = vshll_n_s8(cb_biased, 7);

		         // color transform
		         int16x8_t cr0 = vqdmulhq_s16(crw, cr_const0);
		         int16x8_t cb0 = vqdmulhq_s16(cbw, cb_const0);
		         int16x8_t cr1 = vqdmulhq_s16(crw, cr_const1);
		         int16x8_t cb1 = vqdmulhq_s16(cbw, cb_const1);
		         int16x8_t rws = vaddq_s16(yws, cr0);
		         int16x8_t gws = vaddq_s16(vaddq_s16(yws, cb0), cr1);
		         int16x8_t bws = vaddq_s16(yws, cb1);

		         // undo scaling, round, convert to byte
		         uint8x8x4_t o;
		         o.val[0] = vqrshrun_n_s16(rws, 4);
		         o.val[1] = vqrshrun_n_s16(gws, 4);
		         o.val[2] = vqrshrun_n_s16(bws, 4);
		         o.val[3] = vdup_n_u8(255);

		         // store, interleaving r/g/b/a
		         vst4_u8(out, o);
		         out += 8*4;
		      }
		   }
#endif

		   for (; i < count; ++i) {
		      int32 y_fixed = ((int32)y[i] << 20) + (1<<19); // rounding
		      int32 r,g,b;
		      int32 cr = pcr[i] - 128;
		      int32 cb = pcb[i] - 128;
		      r = y_fixed + cr* stbi__float2fixed!(1.40200f);
		      g = y_fixed + cr*-stbi__float2fixed!(0.71414f) + (int32)((cb*-stbi__float2fixed!(0.34414f)) & 0xffff0000);
		      b = y_fixed                                   +   cb* stbi__float2fixed!(1.77200f);
		      r >>= 20;
		      g >>= 20;
		      b >>= 20;
		      if ((uint32) r > 255) { if (r < 0) r = 0; else r = 255; }
		      if ((uint32) g > 255) { if (g < 0) g = 0; else g = 255; }
		      if ((uint32) b > 255) { if (b < 0) b = 0; else b = 255; }
		      out_[0] = (stbi_uc)r;
		      out_[1] = (stbi_uc)g;
		      out_[2] = (stbi_uc)b;
		      out_[3] = 255;
		      out_ += step;
		   }
		}
#endif

		// set up the kernels
		static void stbi__setup_jpeg(stbi__jpeg *j)
		{
		   j.idct_block_kernel = => stbi__idct_block;
		   j.YCbCr_to_RGB_kernel = => stbi__YCbCr_to_RGB_row;
		   j.resample_row_hv_2_kernel = => stbi__resample_row_hv_2;

#if STBI_SSE2
		   if (stbi__sse2_available()) {
		      j.idct_block_kernel = stbi__idct_simd;
		      j.YCbCr_to_RGB_kernel = stbi__YCbCr_to_RGB_simd;
		      j.resample_row_hv_2_kernel = stbi__resample_row_hv_2_simd;
		   }
#endif

#if STBI_NEON
		   j.idct_block_kernel = stbi__idct_simd;
		   j.YCbCr_to_RGB_kernel = stbi__YCbCr_to_RGB_simd;
		   j.resample_row_hv_2_kernel = stbi__resample_row_hv_2_simd;
#endif
		}

		// clean up the temporary component buffers
		static void stbi__cleanup_jpeg(stbi__jpeg *j)
		{
		   stbi__free_jpeg_components(j, j.s.img_n, false);
		}

		struct stbi__resample
		{
		   public resample_row_func resample;
		   public stbi_uc *line0,line1;
		   public int32 hs,vs;   // expansion factor in each axis
		   public int32 w_lores; // horizontal pixels pre-expansion
		   public int32 ystep;   // how far through vertical expansion we are
		   public int32 ypos;    // which pre-expansion row we're on
		}

		// fast 0..255 * 0..255 => 0..255 rounded multiplication
		static stbi_uc stbi__blinn_8x8(stbi_uc x, stbi_uc y)
		{
		   uint32 t = (uint32)x*y + 128;
		   return (stbi_uc) ((t + (t >>8)) >> 8);
		}

		static stbi_uc *load_jpeg_image(stbi__jpeg *z, int32 *out_x, int32 *out_y, int32 *comp, int32 req_comp)
		{
		   int32 n, decode_n; bool is_rgb;
		   z.s.img_n = 0; // make stbi__cleanup_jpeg safe

		   // validate req_comp
		   if (req_comp < 0 || req_comp > 4) return stbi__errpuc!("bad req_comp", "Internal error");

		   // load a jpeg image from whichever source, but leave in YCbCr format
		   if (!stbi__decode_jpeg_image(z)) { stbi__cleanup_jpeg(z); return null; }

		   // determine actual number of components to generate
		   n = req_comp != 0 ? req_comp : z.s.img_n >= 3 ? 3 : 1;

		   is_rgb = z.s.img_n == 3 && (z.rgb == 3 || (z.app14_color_transform == 0 && z.jfif == 0));

		   if (z.s.img_n == 3 && n < 3 && !is_rgb)
		      decode_n = 1;
		   else
		      decode_n = z.s.img_n;

		   // nothing to do if no components requested; check this now to avoid
		   // accessing uninitialized coutput[0] later
		   if (decode_n <= 0) { stbi__cleanup_jpeg(z); return null; }

		   // resample and color-convert
		   {
		      int32 k;
		      uint32 i,j;
		      stbi_uc *output;
		      stbi_uc*[4] coutput = .( null, null, null, null );

		      stbi__resample[4] res_comp;

		      for (k=0; k < decode_n; ++k) {
		         stbi__resample *r = &res_comp[k];

		         // allocate line buffer big enough for upsampling off the edges
		         // with upsample factor of 4
		         z.img_comp[k].linebuf = (stbi_uc *) stbi__malloc(z.s.img_x + 3);
		         if (z.img_comp[k].linebuf == null) { stbi__cleanup_jpeg(z); return stbi__errpuc!("outofmem", "Out of memory"); }

		         r.hs      = z.img_h_max / z.img_comp[k].h;
		         r.vs      = z.img_v_max / z.img_comp[k].v;
		         r.ystep   = r.vs >> 1;
		         r.w_lores = ((int32)z.s.img_x + r.hs-1) / r.hs;
		         r.ypos    = 0;
		         r.line0   = r.line1 = z.img_comp[k].data;

		         if      (r.hs == 1 && r.vs == 1) r.resample = => resample_row_1;
		         else if (r.hs == 1 && r.vs == 2) r.resample = => stbi__resample_row_v_2;
		         else if (r.hs == 2 && r.vs == 1) r.resample = => stbi__resample_row_h_2;
		         else if (r.hs == 2 && r.vs == 2) r.resample = => z.resample_row_hv_2_kernel;
		         else                               r.resample = => stbi__resample_row_generic;
		      }

		      // can't error after this so, this is safe
		      output = (stbi_uc *) stbi__malloc_mad3(n, (.)z.s.img_x, (.)z.s.img_y, 1);
		      if (output == null) { stbi__cleanup_jpeg(z); return stbi__errpuc!("outofmem", "Out of memory"); }

		      // now go ahead and resample
		      for (j=0; j < z.s.img_y; ++j) {
		         stbi_uc *out_ = &output[n * (.)(z.s.img_x * j)];
		         for (k=0; k < decode_n; ++k) {
		            stbi__resample *r = &res_comp[k];
		            bool y_bot = r.ystep >= (r.vs >> 1);
		            coutput[k] = r.resample(z.img_comp[k].linebuf,
		                                     y_bot ? r.line1 : r.line0,
		                                     y_bot ? r.line0 : r.line1,
		                                     r.w_lores, r.hs);
		            if (++r.ystep >= r.vs) {
		               r.ystep = 0;
		               r.line0 = r.line1;
		               if (++r.ypos < z.img_comp[k].y)
		                  r.line1 += z.img_comp[k].w2;
		            }
		         }
		         if (n >= 3) {
		            stbi_uc *y = coutput[0];
		            if (z.s.img_n == 3) {
		               if (is_rgb) {
		                  for (i=0; i < z.s.img_x; ++i) {
		                     out_[0] = y[i];
		                     out_[1] = coutput[1][i];
		                     out_[2] = coutput[2][i];
		                     out_[3] = 255;
		                     out_ += n;
		                  }
		               } else {
		                  z.YCbCr_to_RGB_kernel(out_, y, coutput[1], coutput[2], (.)z.s.img_x, n);
		               }
		            } else if (z.s.img_n == 4) {
		               if (z.app14_color_transform == 0) { // CMYK
		                  for (i=0; i < z.s.img_x; ++i) {
		                     stbi_uc m = coutput[3][i];
		                     out_[0] = stbi__blinn_8x8(coutput[0][i], m);
		                     out_[1] = stbi__blinn_8x8(coutput[1][i], m);
		                     out_[2] = stbi__blinn_8x8(coutput[2][i], m);
		                     out_[3] = 255;
		                     out_ += n;
		                  }
		               } else if (z.app14_color_transform == 2) { // YCCK
		                  z.YCbCr_to_RGB_kernel(out_, y, coutput[1], coutput[2], (.)z.s.img_x, n);
		                  for (i=0; i < z.s.img_x; ++i) {
		                     stbi_uc m = coutput[3][i];
		                     out_[0] = stbi__blinn_8x8((.)((int32)255 - out_[0]), m);
		                     out_[1] = stbi__blinn_8x8((.)((int32)255 - out_[1]), m);
		                     out_[2] = stbi__blinn_8x8((.)((int32)255 - out_[2]), m);
		                     out_ += n;
		                  }
		               } else { // YCbCr + alpha?  Ignore the fourth channel for now
		                  z.YCbCr_to_RGB_kernel(out_, y, coutput[1], coutput[2], (.)z.s.img_x, n);
		               }
		            } else
		               for (i=0; i < z.s.img_x; ++i) {
		                  out_[0] = out_[1] = out_[2] = y[i];
		                  out_[3] = 255; // not used if n==3
		                  out_ += n;
		               }
		         } else {
		            if (is_rgb) {
		               if (n == 1)
		                  for (i=0; i < z.s.img_x; ++i)
		                     *out_++ = stbi__compute_y(coutput[0][i], coutput[1][i], coutput[2][i]);
		               else {
		                  for (i=0; i < z.s.img_x; ++i, out_ += 2) {
		                     out_[0] = stbi__compute_y(coutput[0][i], coutput[1][i], coutput[2][i]);
		                     out_[1] = 255;
		                  }
		               }
		            } else if (z.s.img_n == 4 && z.app14_color_transform == 0) {
		               for (i=0; i < z.s.img_x; ++i) {
		                  stbi_uc m = coutput[3][i];
		                  stbi_uc r = stbi__blinn_8x8(coutput[0][i], m);
		                  stbi_uc g = stbi__blinn_8x8(coutput[1][i], m);
		                  stbi_uc b = stbi__blinn_8x8(coutput[2][i], m);
		                  out_[0] = stbi__compute_y(r, g, b);
		                  out_[1] = 255;
		                  out_ += n;
		               }
		            } else if (z.s.img_n == 4 && z.app14_color_transform == 2) {
		               for (i=0; i < z.s.img_x; ++i) {
		                  out_[0] = stbi__blinn_8x8((.)((int32)255 - coutput[0][i]), coutput[3][i]);
		                  out_[1] = 255;
		                  out_ += n;
		               }
		            } else {
		               stbi_uc *y = coutput[0];
		               if (n == 1)
		                  for (i=0; i < z.s.img_x; ++i) out_[i] = y[i];
		               else
		                  for (i=0; i < z.s.img_x; ++i) { *out_++ = y[i]; *out_++ = 255; }
		            }
		         }
		      }
		      stbi__cleanup_jpeg(z);
		      *out_x = (.)z.s.img_x;
		      *out_y = (.)z.s.img_y;
		      if (comp != null) *comp = z.s.img_n >= 3 ? 3 : 1; // report original components, not output
		      return output;
		   }
		}

		static void *stbi__jpeg_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   uint8* result;
		   stbi__jpeg* j = (stbi__jpeg*) stbi__malloc(sizeof(stbi__jpeg));
		   if (j == null) return (void*)stbi__errpuc!("outofmem", "Out of memory");
		   j.s = s;
		   stbi__setup_jpeg(j);
		   result = load_jpeg_image(j, x,y,comp,req_comp);
		   STBI_FREE!(j);
		   return result;
		}

		static bool stbi__jpeg_test(stbi__context *s)
		{
		   bool r;
		   stbi__jpeg* j = (stbi__jpeg*)stbi__malloc(sizeof(stbi__jpeg));
		   if (j == null) return stbi__err!("outofmem", "Out of memory");
		   j.s = s;
		   stbi__setup_jpeg(j);
		   r = stbi__decode_jpeg_header(j, STBI__SCAN_type);
		   stbi__rewind(s);
		   STBI_FREE!(j);
		   return r;
		}

		static bool stbi__jpeg_info_raw(stbi__jpeg *j, int32 *x, int32 *y, int32 *comp)
		{
		   if (!stbi__decode_jpeg_header(j, STBI__SCAN_header)) {
		      stbi__rewind( j.s );
		      return false;
		   }
		   if (x != null) *x = (.)j.s.img_x;
		   if (y != null) *y = (.)j.s.img_y;
		   if (comp != null) *comp = j.s.img_n >= 3 ? 3 : 1;
		   return true;
		}

		static bool stbi__jpeg_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   bool result;
		   stbi__jpeg* j = (stbi__jpeg*) (stbi__malloc(sizeof(stbi__jpeg)));
		   if (j == null) return stbi__err!("outofmem", "Out of memory");
		   j.s = s;
		   result = stbi__jpeg_info_raw(j, x, y, comp);
		   STBI_FREE!(j);
		   return result;
		}
#endif

		// public domain zlib decode    v0.2  Sean Barrett 2006-11-18
		//    simple implementation
		//      - all input must be provided in an upfront buffer
		//      - all output is written to a single output buffer (can malloc/realloc)
		//    performance
		//      - fast huffman

#if !STBI_NO_ZLIB

		// fast-way is faster to check than jpeg huffman, but slow way is slower
		const int STBI__ZFAST_BITS = 9; // accelerate all cases in default tables
		const int STBI__ZFAST_MASK = ((1 << STBI__ZFAST_BITS) - 1);
		const int STBI__ZNSYMS = 288; // number of symbols in literal/length alphabet

		// zlib-style huffman encoding
		// (jpegs packs from left, zlib from right, so can't share code)
		struct stbi__zhuffman
		{
		   public stbi__uint16[1 << STBI__ZFAST_BITS] fast;
		   public stbi__uint16[16] firstcode;
		   public int32[17] maxcode;
		   public stbi__uint16[16] firstsymbol;
		   public stbi_uc[STBI__ZNSYMS] size;
		   public stbi__uint16[STBI__ZNSYMS] value;
		}

		[Inline]
		static int32 stbi__bitreverse16(int32 n)
		{
			var n;
		  n = ((n & 0xAAAA) >>  1) | ((n & 0x5555) << 1);
		  n = ((n & 0xCCCC) >>  2) | ((n & 0x3333) << 2);
		  n = ((n & 0xF0F0) >>  4) | ((n & 0x0F0F) << 4);
		  n = ((n & 0xFF00) >>  8) | ((n & 0x00FF) << 8);
		  return n;
		}

		[Inline]
		static int32 stbi__bit_reverse(int32 v, int32 bits)
		{
		   STBI_ASSERT!(bits <= 16);
		   // to bit reverse n bits, reverse 16 and shift
		   // e.g. 11 bits, bit reverse and shift away 5
		   return stbi__bitreverse16(v) >> (16-bits);
		}

		static bool stbi__zbuild_huffman(stbi__zhuffman *z, stbi_uc *sizelist, int32 num)
		{
		   int32 i,k=0;
		   int32 code;
			int32[16] next_code = ?;
			int32[17] sizes = default;

		   // DEFLATE spec for generating codes
		   //memset(sizes, 0, sizeof(sizes));
		   memset(&z.fast[0], 0, sizeof(decltype(z.fast)));
		   for (i=0; i < num; ++i)
		      ++sizes[sizelist[i]];
		   sizes[0] = 0;
		   for (i=1; i < 16; ++i)
		      if (sizes[i] > (1 << i))
		         return stbi__err!("bad sizes", "Corrupt PNG");
		   code = 0;
		   for (i=1; i < 16; ++i) {
		      next_code[i] = code;
		      z.firstcode[i] = (stbi__uint16) code;
		      z.firstsymbol[i] = (stbi__uint16) k;
		      code = (code + sizes[i]);
		      if (sizes[i] != 0)
		         if (code-1 >= (1 << i)) return stbi__err!("bad codelengths","Corrupt PNG");
		      z.maxcode[i] = code << (16-i); // preshift for inner loop
		      code <<= 1;
		      k += sizes[i];
		   }
		   z.maxcode[16] = 0x10000; // sentinel
		   for (i=0; i < num; ++i) {
		      int32 s = sizelist[i];
		      if (s != 0) {
		         int32 c = next_code[s] - z.firstcode[s] + z.firstsymbol[s];
		         stbi__uint16 fastv = (stbi__uint16) ((s << 9) | i);
		         z.size [c] = (stbi_uc     ) s;
		         z.value[c] = (stbi__uint16) i;
		         if (s <= STBI__ZFAST_BITS) {
		            int32 j = stbi__bit_reverse(next_code[s],s);
		            while (j < (1 << STBI__ZFAST_BITS)) {
		               z.fast[j] = fastv;
		               j += (1 << s);
		            }
		         }
		         ++next_code[s];
		      }
		   }
		   return true;
		}

		// zlib-from-memory implementation for PNG reading
		//    because PNG allows splitting the zlib stream arbitrarily,
		//    and it's annoying structurally to have PNG call ZLIB call PNG,
		//    we require PNG read all the IDATs and combine them into a single
		//    memory buffer

		struct stbi__zbuf
		{
		   public stbi_uc *zbuffer, zbuffer_end;
		   public int32 num_bits;
		   public stbi__uint32 code_buffer;

		   public uint8 *zout;
		   public uint8 *zout_start;
		   public uint8 *zout_end;
		   public bool z_expandable;

		   public stbi__zhuffman z_length, z_distance;
		}

		[Inline]
		static bool stbi__zeof(stbi__zbuf *z)
		{
		   return (z.zbuffer >= z.zbuffer_end);
		}

		[Inline]
		static stbi_uc stbi__zget8(stbi__zbuf *z)
		{
		   return stbi__zeof(z) ? 0 : *z.zbuffer++;
		}

		static void stbi__fill_bits(stbi__zbuf *z)
		{
		   repeat {
		      if (z.code_buffer >= (1 << z.num_bits)) {
		        z.zbuffer = z.zbuffer_end;  /* treat this as EOF so we fail. */
		        return;
		      }
		      z.code_buffer |= (uint32) stbi__zget8(z) << z.num_bits;
		      z.num_bits += 8;
		   } while (z.num_bits <= 24);
		}

		[Inline]
		static uint32 stbi__zreceive(stbi__zbuf *z, int32 n)
		{
		   uint32 k;
		   if (z.num_bits < n) stbi__fill_bits(z);
		   k = z.code_buffer & ((1 << n) - 1);
		   z.code_buffer >>= n;
		   z.num_bits -= n;
		   return k;
		}

		static int32 stbi__zhuffman_decode_slowpath(stbi__zbuf *a, stbi__zhuffman *z)
		{
		   int32 b,s,k;
		   // not resolved by fast table, so compute it the slow way
		   // use jpeg approach, which requires MSbits at top
		   k = stbi__bit_reverse((.)a.code_buffer, 16);
		   for (s=STBI__ZFAST_BITS+1; ; ++s)
		      if (k < z.maxcode[s])
		         break;
		   if (s >= 16) return -1; // invalid code!
		   // code size is s, so:
		   b = (k >> (16-s)) - z.firstcode[s] + z.firstsymbol[s];
		   if (b >= STBI__ZNSYMS) return -1; // some data was corrupt somewhere!
		   if (z.size[b] != s) return -1;  // was originally an assert, but report failure instead.
		   a.code_buffer >>= s;
		   a.num_bits -= s;
		   return z.value[b];
		}

		[Inline]
		static int32 stbi__zhuffman_decode(stbi__zbuf *a, stbi__zhuffman *z)
		{
		   int32 b,s;
		   if (a.num_bits < 16) {
		      if (stbi__zeof(a)) {
		         return -1;   /* report error for unexpected end of data. */
		      }
		      stbi__fill_bits(a);
		   }
		   b = z.fast[a.code_buffer & STBI__ZFAST_MASK];
		   if (b != 0) {
		      s = b >> 9;
		      a.code_buffer >>= s;
		      a.num_bits -= s;
		      return b & 511;
		   }
		   return stbi__zhuffman_decode_slowpath(a, z);
		}

		static bool stbi__zexpand(stbi__zbuf *z, uint8 *zout, int32 n)  // need to make room for n bytes
		{
		   uint8 *q;
		   uint32 cur, limit, old_limit;
		   z.zout = zout;
		   if (!z.z_expandable) return stbi__err!("output buffer limit","Corrupt PNG");
		   cur   = (uint32) (z.zout - z.zout_start);
		   limit = old_limit = (uint32) (z.zout_end - z.zout_start);
		   if (UINT_MAX - cur < (uint32) n) return stbi__err!("outofmem", "Out of memory");
		   while (cur + (.)n > limit) {
		      if(limit > UINT_MAX / 2) return stbi__err!("outofmem", "Out of memory");
		      limit *= 2;
		   }
		   q = (uint8 *) STBI_REALLOC_SIZED!(z.zout_start, old_limit, limit);
		   if (q == null) return stbi__err!("outofmem", "Out of memory");
		   z.zout_start = q;
		   z.zout       = q + cur;
		   z.zout_end   = q + limit;
		   return true;
		}

		const int32[31] stbi__zlength_base = .(
		   3,4,5,6,7,8,9,10,11,13,
		   15,17,19,23,27,31,35,43,51,59,
		   67,83,99,115,131,163,195,227,258,0,0 );

		const int32[31] stbi__zlength_extra =
		.( 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0 );

		const int32[32] stbi__zdist_base = .( 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
		257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0);

		const int32[32] stbi__zdist_extra =
		.( 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13, );

		static bool stbi__parse_huffman_block(stbi__zbuf *a)
		{
		   uint8 *zout = a.zout;
		   for(;;) {
		      int32 z = stbi__zhuffman_decode(a, &a.z_length);
		      if (z < 256) {
		         if (z < 0) return stbi__err!("bad huffman code","Corrupt PNG"); // error in huffman codes
		         if (zout >= a.zout_end) {
		            if (!stbi__zexpand(a, zout, 1)) return false;
		            zout = a.zout;
		         }
		         *zout++ = (uint8) z;
		      } else {
		         stbi_uc *p;
		         int32 len,dist;
		         if (z == 256) {
		            a.zout = zout;
		            return true;
		         }
		         z -= 257;
		         len = stbi__zlength_base[z];
		         if (stbi__zlength_extra[z] != 0) len += (.)stbi__zreceive(a, stbi__zlength_extra[z]);
		         z = stbi__zhuffman_decode(a, &a.z_distance);
		         if (z < 0) return stbi__err!("bad huffman code","Corrupt PNG");
		         dist = stbi__zdist_base[z];
		         if (stbi__zdist_extra[z] != 0) dist += (.)stbi__zreceive(a, stbi__zdist_extra[z]);
		         if (zout - a.zout_start < dist) return stbi__err!("bad dist","Corrupt PNG");
		         if (zout + len > a.zout_end) {
		            if (!stbi__zexpand(a, zout, len)) return false;
		            zout = a.zout;
		         }
		         p = (stbi_uc *) (zout - dist);
		         if (dist == 1) { // run of one byte; common in images.
		            stbi_uc v = *p;
		            if (len != 0) { repeat { *zout++ = v; } while ((--len) != 0); }
		         } else {
		            if (len != 0) { repeat { *zout++ = *p++; } while ((--len) != 0); }
		         }
		      }
		   }
		}

		const stbi_uc[19] length_dezigzag = .( 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 );
		static bool stbi__compute_huffman_codes(stbi__zbuf *a)
		{
		   stbi__zhuffman z_codelength;
		   stbi_uc[286+32+137] lencodes = ?;//padding for maximum single op
		   stbi_uc[19] codelength_sizes = default;
		   int32 i,n;

		   int32 hlit  = (.)stbi__zreceive(a,5) + 257;
		   int32 hdist = (.)stbi__zreceive(a,5) + 1;
		   int32 hclen = (.)stbi__zreceive(a,4) + 4;
		   int32 ntot  = hlit + hdist;

		   //memset(codelength_sizes, 0, sizeof(codelength_sizes));
		   for (i=0; i < hclen; ++i) {
		      int32 s = (.)stbi__zreceive(a,3);
		      codelength_sizes[length_dezigzag[i]] = (stbi_uc) s;
		   }
		   if (!stbi__zbuild_huffman(&z_codelength, &codelength_sizes[0], 19)) return false;

		   n = 0;
		   while (n < ntot) {
		      int32 c = stbi__zhuffman_decode(a, &z_codelength);
		      if (c < 0 || c >= 19) return stbi__err!("bad codelengths", "Corrupt PNG");
		      if (c < 16)
		         lencodes[n++] = (stbi_uc) c;
		      else {
		         stbi_uc fill = 0;
		         if (c == 16) {
		            c = (.)stbi__zreceive(a,2)+3;
		            if (n == 0) return stbi__err!("bad codelengths", "Corrupt PNG");
		            fill = lencodes[n-1];
		         } else if (c == 17) {
		            c = (.)stbi__zreceive(a,3)+3;
		         } else if (c == 18) {
		            c = (.)stbi__zreceive(a,7)+11;
		         } else {
		            return stbi__err!("bad codelengths", "Corrupt PNG");
		         }
		         if (ntot - n < c) return stbi__err!("bad codelengths", "Corrupt PNG");
		         memset(&lencodes[n], fill, c);
		         n += c;
		      }
		   }
		   if (n != ntot) return stbi__err!("bad codelengths","Corrupt PNG");
		   if (!stbi__zbuild_huffman(&a.z_length, &lencodes[0], hlit)) return false;
		   if (!stbi__zbuild_huffman(&a.z_distance, &lencodes[hlit], hdist)) return false;
		   return true;
		}

		static bool stbi__parse_uncompressed_block(stbi__zbuf *a)
		{
		   stbi_uc[4] header = ?;
		   int32 len,nlen,k;
		   if ((a.num_bits & 7) != 0)
		      stbi__zreceive(a, a.num_bits & 7); // discard
		   // drain the bit-packed data into header
		   k = 0;
		   while (a.num_bits > 0) {
		      header[k++] = (stbi_uc) (a.code_buffer & 255); // suppress MSVC run-time check
		      a.code_buffer >>= 8;
		      a.num_bits -= 8;
		   }
		   if (a.num_bits < 0) return stbi__err!("zlib corrupt","Corrupt PNG");
		   // now fill header the normal way
		   while (k < 4)
		      header[k++] = stbi__zget8(a);
		   len  = (int32)header[1] * 256 + header[0];
		   nlen = (int32)header[3] * 256 + header[2];
		   if (nlen != (len ^ 0xffff)) return stbi__err!("zlib corrupt","Corrupt PNG");
		   if (a.zbuffer + len > a.zbuffer_end) return stbi__err!("read past buffer","Corrupt PNG");
		   if (a.zout + len > a.zout_end)
		      if (!stbi__zexpand(a, a.zout, len)) return false;
		   memcpy(a.zout, a.zbuffer, len);
		   a.zbuffer += len;
		   a.zout += len;
		   return true;
		}

		static bool stbi__parse_zlib_header(stbi__zbuf *a)
		{
		   int32 cmf   = stbi__zget8(a);
		   int32 cm    = cmf & 15;
		   /* int cinfo = cmf >> 4; */
		   int32 flg   = stbi__zget8(a);
		   if (stbi__zeof(a)) return stbi__err!("bad zlib header","Corrupt PNG"); // zlib spec
		   if ((cmf*256+flg) % 31 != 0) return stbi__err!("bad zlib header","Corrupt PNG"); // zlib spec
		   if ((flg & 32) != 0) return stbi__err!("no preset dict","Corrupt PNG"); // preset dictionary not allowed in png
		   if (cm != 8) return stbi__err!("bad compression","Corrupt PNG"); // DEFLATE required for png
		   // window = 1 << (8 + cinfo)... but who cares, we fully buffer output
		   return true;
		}

		static stbi_uc[STBI__ZNSYMS] stbi__zdefault_length =
		.(
		   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
		   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
		   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
		   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
		   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
		   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
		   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
		   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
		   7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, 7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8
		);
		static stbi_uc[32] stbi__zdefault_distance =
		.(
		   5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
		);
		/*
		Init algorithm:
		{
		   int i;   // use <= to match clearly with spec
		   for (i=0; i <= 143; ++i)     stbi__zdefault_length[i]   = 8;
		   for (   ; i <= 255; ++i)     stbi__zdefault_length[i]   = 9;
		   for (   ; i <= 279; ++i)     stbi__zdefault_length[i]   = 7;
		   for (   ; i <= 287; ++i)     stbi__zdefault_length[i]   = 8;
		   for (i=0; i <=  31; ++i)     stbi__zdefault_distance[i] = 5;
		}
		*/

		static bool stbi__parse_zlib(stbi__zbuf *a, bool parse_header)
		{
		   int32 final, type;
		   if (parse_header)
		      if (!stbi__parse_zlib_header(a)) return false;
		   a.num_bits = 0;
		   a.code_buffer = 0;
		   repeat {
		      final = (.)stbi__zreceive(a,1);
		      type = (.)stbi__zreceive(a,2);
		      if (type == 0) {
		         if (!stbi__parse_uncompressed_block(a)) return false;
		      } else if (type == 3) {
		         return false;
		      } else {
		         if (type == 1) {
		            // use fixed code lengths
		            if (!stbi__zbuild_huffman(&a.z_length  , &stbi__zdefault_length[0]  , STBI__ZNSYMS)) return false;
		            if (!stbi__zbuild_huffman(&a.z_distance, &stbi__zdefault_distance[0],  32)) return false;
		         } else {
		            if (!stbi__compute_huffman_codes(a)) return false;
		         }
		         if (!stbi__parse_huffman_block(a)) return false;
		      }
		   } while (final == 0);
		   return true;
		}

		static bool stbi__do_zlib(stbi__zbuf *a, uint8 *obuf, int32 olen, bool exp, bool parse_header)
		{
		   a.zout_start = obuf;
		   a.zout       = obuf;
		   a.zout_end   = obuf + olen;
		   a.z_expandable = exp;

		   return stbi__parse_zlib(a, parse_header);
		}

		public static uint8 *stbi_zlib_decode_malloc_guesssize(uint8 *buffer, int32 len, int32 initial_size, int32 *outlen)
		{
		   stbi__zbuf a = ?;
		   uint8 *p = (uint8*) stbi__malloc(initial_size);
		   if (p == null) return null;
		   a.zbuffer = (stbi_uc *) buffer;
		   a.zbuffer_end = (stbi_uc *) buffer + len;
		   if (stbi__do_zlib(&a, p, initial_size, true, true)) {
		      if (outlen != null) *outlen = (int32) (a.zout - a.zout_start);
		      return a.zout_start;
		   } else {
		      STBI_FREE!(a.zout_start);
		      return null;
		   }
		}

		public static uint8 *stbi_zlib_decode_malloc(uint8 *buffer, int32 len, int32 *outlen)
		{
		   return stbi_zlib_decode_malloc_guesssize(buffer, len, 16384, outlen);
		}

		public static uint8 *stbi_zlib_decode_malloc_guesssize_headerflag(uint8 *buffer, int32 len, int32 initial_size, int32 *outlen, bool parse_header)
		{
		   stbi__zbuf a = ?;
		   uint8 *p = (uint8*) stbi__malloc(initial_size);
		   if (p == null) return null;
		   a.zbuffer = (stbi_uc *) buffer;
		   a.zbuffer_end = (stbi_uc *) buffer + len;
		   if (stbi__do_zlib(&a, p, initial_size, true, parse_header)) {
		      if (outlen != null) *outlen = (int32) (a.zout - a.zout_start);
		      return a.zout_start;
		   } else {
		      STBI_FREE!(a.zout_start);
		      return null;
		   }
		}

		public static int32 stbi_zlib_decode_buffer(uint8 *obuffer, int32 olen, uint8 *ibuffer, int32 ilen)
		{
		   stbi__zbuf a = ?;
		   a.zbuffer = (stbi_uc *) ibuffer;
		   a.zbuffer_end = (stbi_uc *) ibuffer + ilen;
		   if (stbi__do_zlib(&a, obuffer, olen, false, true))
		      return (int32) (a.zout - a.zout_start);
		   else
		      return -1;
		}

		public static uint8 *stbi_zlib_decode_noheader_malloc(uint8 *buffer, int32 len, int32 *outlen)
		{
		   stbi__zbuf a = ?;
		   uint8 *p = (uint8*) stbi__malloc(16384);
		   if (p == null) return null;
		   a.zbuffer = (stbi_uc *) buffer;
		   a.zbuffer_end = (stbi_uc *) buffer+len;
		   if (stbi__do_zlib(&a, p, 16384, true, false)) {
		      if (outlen != null) *outlen = (int32) (a.zout - a.zout_start);
		      return a.zout_start;
		   } else {
		      STBI_FREE!(a.zout_start);
		      return null;
		   }
		}

		public static int32 stbi_zlib_decode_noheader_buffer(uint8 *obuffer, int32 olen, uint8 *ibuffer, int32 ilen)
		{
		   stbi__zbuf a = ?;
		   a.zbuffer = (stbi_uc *) ibuffer;
		   a.zbuffer_end = (stbi_uc *) ibuffer + ilen;
		   if (stbi__do_zlib(&a, obuffer, olen, false, false))
		      return (int32) (a.zout - a.zout_start);
		   else
		      return -1;
		}
#endif

		// public domain "baseline" PNG decoder   v0.10  Sean Barrett 2006-11-18
		//    simple implementation
		//      - only 8-bit samples
		//      - no CRC checking
		//      - allocates lots of intermediate memory
		//        - avoids problem of streaming data between subsystems
		//        - avoids explicit window management
		//    performance
		//      - uses stb_zlib, a PD zlib implementation with fast huffman decoding

#if !STBI_NO_PNG
		struct stbi__pngchunk
		{
		   public stbi__uint32 length;
		   public stbi__uint32 type;
		}

		static stbi__pngchunk stbi__get_chunk_header(stbi__context *s)
		{
		   stbi__pngchunk c;
		   c.length = stbi__get32be(s);
		   c.type   = stbi__get32be(s);
		   return c;
		}
		
		const stbi_uc[8] png_sig = .( 137,80,78,71,13,10,26,10 );
		static bool stbi__check_png_header(stbi__context *s)
		{
		   int32 i;
		   for (i=0; i < 8; ++i)
		      if (stbi__get8(s) != png_sig[i]) return stbi__err!("bad png sig","Not a PNG");
		   return true;
		}

		struct stbi__png
		{
		   public stbi__context *s;
		   public stbi_uc *idata, expanded, out_;
		   public int32 depth;
		}


		const int
		   STBI__F_none=0,
		   STBI__F_sub=1,
		   STBI__F_up=2,
		   STBI__F_avg=3,
		   STBI__F_paeth=4,
		   // synthetic filters used for first scanline to avoid needing a dummy row of 0s
		   STBI__F_avg_first = 5,
		   STBI__F_paeth_first = 6;

		const stbi_uc[5] first_row_filter =
		.(
		   STBI__F_none,
		   STBI__F_sub,
		   STBI__F_none,
		   STBI__F_avg_first,
		   STBI__F_paeth_first
		);

		[Inline]
		static int32 abs(int32 val)
		{
			return Math.Abs(val);
		}	

		static int32 stbi__paeth(int32 a, int32 b, int32 c)
		{
		   int32 p = a + b - c;
		   int32 pa = abs(p-a);
		   int32 pb = abs(p-b);
		   int32 pc = abs(p-c);
		   if (pa <= pb && pa <= pc) return a;
		   if (pb <= pc) return b;
		   return c;
		}

		const stbi_uc[9] stbi__depth_scale_table = .( 0, 0xff, 0x55, 0, 0x11, 0,0,0, 0x01 );

		// create the png data from post-deflated data
		static bool stbi__create_png_image_raw(stbi__png *a, stbi_uc *raw, stbi__uint32 raw_len, int32 out_n, stbi__uint32 x, stbi__uint32 y, int32 depth, int32 color)
		{
		   int32 bytes = (depth == 16? 2 : 1);
		   stbi__context *s = a.s;
		   stbi__uint32 i,j,stride = x*(uint32)out_n*(uint32)bytes;
		   stbi__uint32 img_len, img_width_bytes;
		   int32 k;
		   int32 img_n = s.img_n; // copy it into a local for later

		   int32 output_bytes = out_n*bytes;
		   int32 filter_bytes = img_n*bytes;
		   int32 width = (.)x;

		   STBI_ASSERT!(out_n == s.img_n || out_n == s.img_n+1);
		   a.out_ = (stbi_uc *) stbi__malloc_mad3((.)x, (.)y, output_bytes, 0); // extra bytes to write off the end into
		   if (a.out_ == null) return stbi__err!("outofmem", "Out of memory");

		   if (!stbi__mad3sizes_valid(img_n, (.)x, depth, 7)) return stbi__err!("too large", "Corrupt PNG");
		   img_width_bytes = ((((uint32)img_n * x * (uint32)depth) + 7) >> 3);
		   img_len = (img_width_bytes + 1) * y;

		   // we used to check for exact match between raw_len and img_len on non-interlaced PNGs,
		   // but issue #276 reported a PNG in the wild that had extra data at the end (all zeros),
		   // so just check for raw_len < img_len always.
		   if (raw_len < img_len) return stbi__err!("not enough pixels","Corrupt PNG");

			var raw;
		   for (j=0; j < y; ++j) {
		      stbi_uc *cur = &a.out_[stride*j];
		      stbi_uc *prior;
		      int32 filter = *raw++;

		      if (filter > 4)
		         return stbi__err!("invalid filter","Corrupt PNG");

		      if (depth < 8) {
		         if (img_width_bytes > x) return stbi__err!("invalid width","Corrupt PNG");
		         cur += x*(uint32)out_n - img_width_bytes; // store output to the rightmost img_len bytes, so we can decode in place
		         filter_bytes = 1;
		         width = (int32)img_width_bytes;
		      }
		      prior = cur - stride; // bugfix: need to compute this after 'cur +=' computation above

		      // if first row, use special filter that doesn't sample previous row
		      if (j == 0) filter = first_row_filter[filter];

		      // handle first byte explicitly
		      for (k=0; k < filter_bytes; ++k) {
		         switch (filter) {
		            case STBI__F_none       : cur[k] = raw[k]; break;
		            case STBI__F_sub        : cur[k] = raw[k]; break;
		            case STBI__F_up         : cur[k] = STBI__BYTECAST!((int32)raw[k] + prior[k]); break;
		            case STBI__F_avg        : cur[k] = STBI__BYTECAST!((int32)raw[k] + (prior[k]>>1)); break;
		            case STBI__F_paeth      : cur[k] = STBI__BYTECAST!((int32)raw[k] + stbi__paeth(0,prior[k],0)); break;
		            case STBI__F_avg_first  : cur[k] = raw[k]; break;
		            case STBI__F_paeth_first: cur[k] = raw[k]; break;
		         }
		      }

		      if (depth == 8) {
		         if (img_n != out_n)
		            cur[img_n] = 255; // first pixel
		         raw += img_n;
		         cur += out_n;
		         prior += out_n;
		      } else if (depth == 16) {
		         if (img_n != out_n) {
		            cur[filter_bytes]   = 255; // first pixel top byte
		            cur[filter_bytes+1] = 255; // first pixel bottom byte
		         }
		         raw += filter_bytes;
		         cur += output_bytes;
		         prior += output_bytes;
		      } else {
		         raw += 1;
		         cur += 1;
		         prior += 1;
		      }

		      // this is a little gross, so that we don't switch per-pixel or per-component
		      if (depth < 8 || img_n == out_n) {
		         int32 nk = (width - 1)*filter_bytes;
		         // STBI__CASE(f): case f: for (k=0; k < nk; ++k)
		         switch (filter) {
		            // "none" filter turns into a memcpy here; make that explicit.
		            case STBI__F_none:         memcpy(cur, raw, nk); break;
		            case STBI__F_sub: for (k=0; k < nk; ++k)          { cur[k] = STBI__BYTECAST!((int32)raw[k] + cur[k-filter_bytes]); } break;
		            case STBI__F_up: for (k=0; k < nk; ++k)           { cur[k] = STBI__BYTECAST!((int32)raw[k] + prior[k]); } break;
		            case STBI__F_avg: for (k=0; k < nk; ++k)          { cur[k] = STBI__BYTECAST!((int32)raw[k] + (((int32)prior[k] + cur[k-filter_bytes])>>1)); } break;
		            case STBI__F_paeth: for (k=0; k < nk; ++k)        { cur[k] = STBI__BYTECAST!((int32)raw[k] + stbi__paeth(cur[k-filter_bytes],prior[k],prior[k-filter_bytes])); } break;
		            case STBI__F_avg_first: for (k=0; k < nk; ++k)    { cur[k] = STBI__BYTECAST!((int32)raw[k] + (cur[k-filter_bytes] >> 1)); } break;
		            case STBI__F_paeth_first: for (k=0; k < nk; ++k)  { cur[k] = STBI__BYTECAST!((int32)raw[k] + stbi__paeth(cur[k-filter_bytes],0,0)); } break;
		         }
		         raw += nk;
		      } else {
		         STBI_ASSERT!(img_n+1 == out_n);
		         // STBI__CASE(f): case f: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)
		         switch (filter) {
		            case STBI__F_none: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)         { cur[k] = raw[k]; } break;
		            case STBI__F_sub: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)          { cur[k] = STBI__BYTECAST!((int32)raw[k] + cur[k- output_bytes]); } break;
		            case STBI__F_up: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)           { cur[k] = STBI__BYTECAST!((int32)raw[k] + prior[k]); } break;
		            case STBI__F_avg: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)          { cur[k] = STBI__BYTECAST!((int32)raw[k] + (((int32)prior[k] + cur[k- output_bytes])>>1)); } break;
		            case STBI__F_paeth: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)        { cur[k] = STBI__BYTECAST!((int32)raw[k] + stbi__paeth(cur[k- output_bytes],prior[k],prior[k- output_bytes])); } break;
		            case STBI__F_avg_first: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)    { cur[k] = STBI__BYTECAST!((int32)raw[k] + (cur[k- output_bytes] >> 1)); } break;
		            case STBI__F_paeth_first: for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes) for (k=0; k < filter_bytes; ++k)  { cur[k] = STBI__BYTECAST!((int32)raw[k] + stbi__paeth(cur[k- output_bytes],0,0)); } break;
		         }

		         // the loop above sets the high byte of the pixels' alpha, but for
		         // 16 bit png files we also need the low byte set. we'll do that here.
		         if (depth == 16) {
		            cur = &a.out_[stride*j]; // start at the beginning of the row again
		            for (i=0; i < x; ++i,cur+=output_bytes) {
		               cur[filter_bytes+1] = 255;
		            }
		         }
		      }
		   }

		   // we make a separate pass to expand bits to pixels; for performance,
		   // this could run two scanlines behind the above code, so it won't
		   // intefere with filtering but will still be in the cache.
		   if (depth < 8) {
		      for (j=0; j < y; ++j) {
		         stbi_uc *cur = &a.out_[stride*j];
		         stbi_uc *in_  = &a.out_[stride*j + x*(uint32)out_n - img_width_bytes];
		         // unpack 1/2/4-bit into a 8-bit buffer. allows us to keep the common 8-bit path optimal at minimal cost for 1/2/4-bit
		         // png guarante byte alignment, if width is not multiple of 8/4/2 we'll decode dummy trailing data that will be skipped in the later loop
		         stbi_uc scale = (color == 0) ? stbi__depth_scale_table[depth] : 1; // scale grayscale values to 0..255 range

		         // note that the final byte might overshoot and write more data than desired.
		         // we can allocate enough data that this never writes out of memory, but it
		         // could also overwrite the next scanline. can it overwrite non-empty data
		         // on the next scanline? yes, consider 1-pixel-wide scanlines with 1-bit-per-pixel.
		         // so we need to explicitly clamp the final ones

		         if (depth == 4) {
		            for (k=(.)x*img_n; k >= 2; k-=2, ++in_) {
		               *cur++ = (.)((int32)scale * ((*in_ >> 4)       ));
		               *cur++ = (.)((int32)scale * ((*in_     ) & 0x0f));
		            }
		            if (k > 0) *cur++ = (.)((int32)scale * ((*in_ >> 4)       ));
		         } else if (depth == 2) {
		            for (k=(.)x*img_n; k >= 4; k-=4, ++in_) {
		               *cur++ = (.)((int32)scale * ((*in_ >> 6)       ));
		               *cur++ = (.)((int32)scale * ((*in_ >> 4) & 0x03));
		               *cur++ = (.)((int32)scale * ((*in_ >> 2) & 0x03));
		               *cur++ = (.)((int32)scale * ((*in_     ) & 0x03));
		            }
		            if (k > 0) *cur++ = (.)((int32)scale * ((*in_ >> 6)       ));
		            if (k > 1) *cur++ = (.)((int32)scale * ((*in_ >> 4) & 0x03));
		            if (k > 2) *cur++ = (.)((int32)scale * ((*in_ >> 2) & 0x03));
		         } else if (depth == 1) {
		            for (k=(.)x*img_n; k >= 8; k-=8, ++in_) {
		               *cur++ = (.)((int32)scale * ((*in_ >> 7)       ));
		               *cur++ = (.)((int32)scale * ((*in_ >> 6) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_ >> 5) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_ >> 4) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_ >> 3) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_ >> 2) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_ >> 1) & 0x01));
		               *cur++ = (.)((int32)scale * ((*in_     ) & 0x01));
		            }
		            if (k > 0) *cur++ = (.)((int32)scale * ((*in_ >> 7)       ));
		            if (k > 1) *cur++ = (.)((int32)scale * ((*in_ >> 6) & 0x01));
		            if (k > 2) *cur++ = (.)((int32)scale * ((*in_ >> 5) & 0x01));
		            if (k > 3) *cur++ = (.)((int32)scale * ((*in_ >> 4) & 0x01));
		            if (k > 4) *cur++ = (.)((int32)scale * ((*in_ >> 3) & 0x01));
		            if (k > 5) *cur++ = (.)((int32)scale * ((*in_ >> 2) & 0x01));
		            if (k > 6) *cur++ = (.)((int32)scale * ((*in_ >> 1) & 0x01));
		         }
		         if (img_n != out_n) {
		            int32 q;
		            // insert alpha = 255
		            cur = &a.out_[stride*j];
		            if (img_n == 1) {
		               for (q=(.)x-1; q >= 0; --q) {
		                  cur[q*2+1] = 255;
		                  cur[q*2+0] = cur[q];
		               }
		            } else {
		               STBI_ASSERT!(img_n == 3);
		               for (q=(.)x-1; q >= 0; --q) {
		                  cur[q*4+3] = 255;
		                  cur[q*4+2] = cur[q*3+2];
		                  cur[q*4+1] = cur[q*3+1];
		                  cur[q*4+0] = cur[q*3+0];
		               }
		            }
		         }
		      }
		   } else if (depth == 16) {
		      // force the image data from big-endian to platform-native.
		      // this is done in a separate pass due to the decoding relying
		      // on the data being untouched, but could probably be done
		      // per-line during decode if care is taken.
		      stbi_uc *cur = a.out_;
		      stbi__uint16 *cur16 = (stbi__uint16*)cur;

		      for(i=0; i < x*y*(uint32)out_n; ++i,cur16++,cur+=2) {
		         *cur16 = ((uint16)cur[0] << 8) | cur[1];
		      }
		   }

		   return true;
		}

		static bool stbi__create_png_image(stbi__png *a, stbi_uc *image_data, stbi__uint32 image_data_len, int32 out_n, int32 depth, int32 color, int32 interlaced)
		{
			var image_data, image_data_len;
		   int32 bytes = (depth == 16 ? 2 : 1);
		   int32 out_bytes = out_n * bytes;
		   stbi_uc *final;
		   int32 p;
		   if (interlaced == 0)
		      return stbi__create_png_image_raw(a, image_data, image_data_len, out_n, a.s.img_x, a.s.img_y, depth, color);

		   // de-interlacing
		   final = (stbi_uc *) stbi__malloc_mad3((.)a.s.img_x, (.)a.s.img_y, out_bytes, 0);
		   if (final == null) return stbi__err!("outofmem", "Out of memory");
		   for (p=0; p < 7; ++p) {
		      int32[?] xorig = .( 0,4,0,2,0,1,0 );
		      int32[?] yorig = .( 0,0,4,0,2,0,1 );
		      int32[?] xspc  = .( 8,8,4,4,2,2,1 );
		      int32[?] yspc  = .( 8,8,8,4,4,2,2 );
		      int32 i,j,x,y;
		      // pass1_x[4] = 0, pass1_x[5] = 1, pass1_x[12] = 1
		      x = ((int32)a.s.img_x - xorig[p] + xspc[p]-1) / xspc[p];
		      y = ((int32)a.s.img_y - yorig[p] + yspc[p]-1) / yspc[p];
		      if (x != 0 && y != 0) {
		         stbi__uint32 img_len = (uint32)(((((a.s.img_n * x * depth) + 7) >> 3) + 1) * y);
		         if (!stbi__create_png_image_raw(a, image_data, image_data_len, out_n, (.)x, (.)y, depth, color)) {
		            STBI_FREE!(final);
		            return false;
		         }
		         for (j=0; j < y; ++j) {
		            for (i=0; i < x; ++i) {
		               int32 out_y = j*yspc[p]+yorig[p];
		               int32 out_x = i*xspc[p]+xorig[p];
		               memcpy(&final[out_y*(.)a.s.img_x*out_bytes + out_x*out_bytes],
		                      &a.out_[(j*x+i)*out_bytes], out_bytes);
		            }
		         }
		         STBI_FREE!(a.out_);
		         image_data += img_len;
		         image_data_len -= img_len;
		      }
		   }
		   a.out_ = final;

		   return true;
		}

		static bool stbi__compute_transparency(stbi__png *z, stbi_uc[3] tc, int32 out_n)
		{
		   stbi__context *s = z.s;
		   stbi__uint32 i, pixel_count = s.img_x * s.img_y;
		   stbi_uc *p = z.out_;

		   // compute color-based transparency, assuming we've
		   // already got 255 as the alpha value in the output
		   STBI_ASSERT!(out_n == 2 || out_n == 4);

		   if (out_n == 2) {
		      for (i=0; i < pixel_count; ++i) {
		         p[1] = (p[0] == tc[0] ? 0 : 255);
		         p += 2;
		      }
		   } else {
		      for (i=0; i < pixel_count; ++i) {
		         if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2])
		            p[3] = 0;
		         p += 4;
		      }
		   }
		   return true;
		}

		static bool stbi__compute_transparency16(stbi__png *z, stbi__uint16[3] tc, int32 out_n)
		{
		   stbi__context *s = z.s;
		   stbi__uint32 i, pixel_count = s.img_x * s.img_y;
		   stbi__uint16 *p = (stbi__uint16*) z.out_;

		   // compute color-based transparency, assuming we've
		   // already got 65535 as the alpha value in the output
		   STBI_ASSERT!(out_n == 2 || out_n == 4);

		   if (out_n == 2) {
		      for (i = 0; i < pixel_count; ++i) {
		         p[1] = (p[0] == tc[0] ? 0 : 65535);
		         p += 2;
		      }
		   } else {
		      for (i = 0; i < pixel_count; ++i) {
		         if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2])
		            p[3] = 0;
		         p += 4;
		      }
		   }
		   return true;
		}

		static bool stbi__expand_png_palette(stbi__png *a, stbi_uc *palette, int32 len, int32 pal_img_n)
		{
		   stbi__uint32 i, pixel_count = a.s.img_x * a.s.img_y;
		   stbi_uc *p, temp_out, orig = a.out_;

		   p = (stbi_uc *) stbi__malloc_mad2((.)pixel_count, pal_img_n, 0);
		   if (p == null) return stbi__err!("outofmem", "Out of memory");

		   // between here and free(out) below, exitting would leak
		   temp_out = p;

		   if (pal_img_n == 3) {
		      for (i=0; i < pixel_count; ++i) {
		         int32 n = (int32)orig[i]*4;
		         p[0] = palette[n  ];
		         p[1] = palette[n+1];
		         p[2] = palette[n+2];
		         p += 3;
		      }
		   } else {
		      for (i=0; i < pixel_count; ++i) {
		         int32 n = (int32)orig[i]*4;
		         p[0] = palette[n  ];
		         p[1] = palette[n+1];
		         p[2] = palette[n+2];
		         p[3] = palette[n+3];
		         p += 4;
		      }
		   }
		   STBI_FREE!(a.out_);
		   a.out_ = temp_out;

		   return true;
		}

		static bool stbi__unpremultiply_on_load_global = false;
		static bool stbi__de_iphone_flag_global = false;

		public static void stbi_set_unpremultiply_on_load(bool flag_true_if_should_unpremultiply)
		{
		   stbi__unpremultiply_on_load_global = flag_true_if_should_unpremultiply;
		}

		public static void stbi_convert_iphone_png_to_rgb(bool flag_true_if_should_convert)
		{
		   stbi__de_iphone_flag_global = flag_true_if_should_convert;
		}

#if !STBI_THREAD_LOCAL
		static mixin stbi__unpremultiply_on_load()
		{
			stbi__unpremultiply_on_load_global
		}
		static mixin stbi__de_iphone_flag()
		{
			stbi__de_iphone_flag_global
		}
#else
		[ThreadStatic]
		static bool stbi__unpremultiply_on_load_local;
		[ThreadStatic]
		static bool stbi__unpremultiply_on_load_set;
		[ThreadStatic]
		static bool stbi__de_iphone_flag_local;
		[ThreadStatic]
		static bool stbi__de_iphone_flag_set;

		public static void stbi__unpremultiply_on_load_thread(bool flag_true_if_should_unpremultiply)
		{
		   stbi__unpremultiply_on_load_local = flag_true_if_should_unpremultiply;
		   stbi__unpremultiply_on_load_set = true;
		}

		public static void stbi_convert_iphone_png_to_rgb_thread(bool flag_true_if_should_convert)
		{
		   stbi__de_iphone_flag_local = flag_true_if_should_convert;
		   stbi__de_iphone_flag_set = true;
		}

		static mixin stbi__unpremultiply_on_load()
		{
			(stbi__unpremultiply_on_load_set
				? stbi__unpremultiply_on_load_local
				: stbi__unpremultiply_on_load_global)
		}
		static mixin stbi__de_iphone_flag()
		{
			(stbi__de_iphone_flag_set
				? stbi__de_iphone_flag_local
				: stbi__de_iphone_flag_global)
		}
#endif // STBI_THREAD_LOCAL

		static void stbi__de_iphone(stbi__png *z)
		{
		   stbi__context *s = z.s;
		   stbi__uint32 i, pixel_count = s.img_x * s.img_y;
		   stbi_uc *p = z.out_;

		   if (s.img_out_n == 3) {  // convert bgr to rgb
		      for (i=0; i < pixel_count; ++i) {
		         stbi_uc t = p[0];
		         p[0] = p[2];
		         p[2] = t;
		         p += 3;
		      }
		   } else {
		      STBI_ASSERT!(s.img_out_n == 4);
		      if (stbi__unpremultiply_on_load!()) {
		         // convert bgr to rgb and unpremultiply
		         for (i=0; i < pixel_count; ++i) {
		            stbi_uc a = p[3];
		            stbi_uc t = p[0];
		            if (a != 0) {
		               stbi_uc half = a / 2;
		               p[0] = (.)(((int32)p[2] * 255 + half) / a);
		               p[1] = (.)(((int32)p[1] * 255 + half) / a);
		               p[2] = (.)(((int32) t   * 255 + half) / a);
		            } else {
		               p[0] = p[2];
		               p[2] = t;
		            }
		            p += 4;
		         }
		      } else {
		         // convert bgr to rgb
		         for (i=0; i < pixel_count; ++i) {
		            stbi_uc t = p[0];
		            p[0] = p[2];
		            p[2] = t;
		            p += 4;
		         }
		      }
		   }
		}

		static mixin STBI__PNG_TYPE(var a, var b, var c, var d)
		{
			(((uint32) (a) << 24) + ((uint32) (b) << 16) + ((uint32) (c) << 8) + (uint32) (d))
		}

		// @PORT For error report later in the following function
		#if !STBI_NO_FAILURE_STRINGS
		static char8* invalid_chunk = "XXXX PNG chunk not known";
		#endif

		static bool stbi__parse_png_file(stbi__png *z, int32 scan, int32 req_comp)
		{
		   stbi_uc[1024] palette = ?; stbi_uc pal_img_n=0;
		   bool has_trans=false; stbi_uc[3] tc= default;
		   stbi__uint16[3] tc16 = ?;
		   stbi__uint32 ioff=0, idata_limit=0, i, pal_len=0;
		   int32 first=1,k,interlace=0, color=0; bool is_iphone=false;
		   stbi__context *s = z.s;

		   z.expanded = null;
		   z.idata = null;
		   z.out_ = null;

		   if (!stbi__check_png_header(s)) return false;

		   if (scan == STBI__SCAN_type) return true;

		   for (;;) {
		      stbi__pngchunk c = stbi__get_chunk_header(s);
		      switch (c.type) {
		         case STBI__PNG_TYPE!('C','g','B','I'):
		            is_iphone = true;
		            stbi__skip(s, (.)c.length);
		            break;
		         case STBI__PNG_TYPE!('I','H','D','R'): {
		            int32 comp,filter;
		            if (first == 0) return stbi__err!("multiple IHDR","Corrupt PNG");
		            first = 0;
		            if (c.length != 13) return stbi__err!("bad IHDR len","Corrupt PNG");
		            s.img_x = stbi__get32be(s);
		            s.img_y = stbi__get32be(s);
		            if (s.img_y > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");
		            if (s.img_x > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");
		            z.depth = stbi__get8(s);  if (z.depth != 1 && z.depth != 2 && z.depth != 4 && z.depth != 8 && z.depth != 16)  return stbi__err!("1/2/4/8/16-bit only","PNG not supported: 1/2/4/8/16-bit only");
		            color = stbi__get8(s);  if (color > 6)         return stbi__err!("bad ctype","Corrupt PNG");
		            if (color == 3 && z.depth == 16)                  return stbi__err!("bad ctype","Corrupt PNG");
		            if (color == 3) pal_img_n = 3; else if ((color & 1) != 0) return stbi__err!("bad ctype","Corrupt PNG");
		            comp  = stbi__get8(s);  if (comp != 0) return stbi__err!("bad comp method","Corrupt PNG");
		            filter= stbi__get8(s);  if (filter != 0) return stbi__err!("bad filter method","Corrupt PNG");
		            interlace = stbi__get8(s); if (interlace>1) return stbi__err!("bad interlace method","Corrupt PNG");
		            if (s.img_x == 0 || s.img_y == 0) return stbi__err!("0-pixel image","Corrupt PNG");
		            if (pal_img_n == 0) {
		               s.img_n = ((color & 2) != 0 ? 3 : 1) + ((color & 4) != 0 ? 1 : 0);
		               if ((1 << 30) / s.img_x / s.img_n < s.img_y) return stbi__err!("too large", "Image too large to decode");
		               if (scan == STBI__SCAN_header) return true;
		            } else {
		               // if paletted, then pal_n is our final components, and
		               // img_n is # components to decompress/filter.
		               s.img_n = 1;
		               if ((1 << 30) / s.img_x / 4 < s.img_y) return stbi__err!("too large","Corrupt PNG");
		               // if SCAN_header, have to scan to see if we have a tRNS
		            }
		            break;
		         }

		         case STBI__PNG_TYPE!('P','L','T','E'):  {
		            if (first != 0) return stbi__err!("first not IHDR", "Corrupt PNG");
		            if (c.length > 256*3) return stbi__err!("invalid PLTE","Corrupt PNG");
		            pal_len = c.length / 3;
		            if (pal_len * 3 != c.length) return stbi__err!("invalid PLTE","Corrupt PNG");
		            for (i=0; i < pal_len; ++i) {
		               palette[i*4+0] = stbi__get8(s);
		               palette[i*4+1] = stbi__get8(s);
		               palette[i*4+2] = stbi__get8(s);
		               palette[i*4+3] = 255;
		            }
		            break;
		         }

		         case STBI__PNG_TYPE!('t','R','N','S'): {
		            if (first != 0) return stbi__err!("first not IHDR", "Corrupt PNG");
		            if (z.idata != null) return stbi__err!("tRNS after IDAT","Corrupt PNG");
		            if (pal_img_n != 0) {
		               if (scan == STBI__SCAN_header) { s.img_n = 4; return true; }
		               if (pal_len == 0) return stbi__err!("tRNS before PLTE","Corrupt PNG");
		               if (c.length > pal_len) return stbi__err!("bad tRNS len","Corrupt PNG");
		               pal_img_n = 4;
		               for (i=0; i < c.length; ++i)
		                  palette[i*4+3] = stbi__get8(s);
		            } else {
		               if ((s.img_n & 1) == 0) return stbi__err!("tRNS with alpha","Corrupt PNG");
		               if (c.length != (stbi__uint32) s.img_n*2) return stbi__err!("bad tRNS len","Corrupt PNG");
		               has_trans = true;
		               if (z.depth == 16) {
		                  for (k = 0; k < s.img_n; ++k) tc16[k] = (stbi__uint16)stbi__get16be(s); // copy the values as-is
		               } else {
		                  for (k = 0; k < s.img_n; ++k) tc[k] = (stbi_uc)((int32)stbi__get16be(s) & 255) * stbi__depth_scale_table[z.depth]; // non 8-bit images will be larger
		               }
		            }
		            break;
		         }

		         case STBI__PNG_TYPE!('I','D','A','T'): {
		            if (first != 0) return stbi__err!("first not IHDR", "Corrupt PNG");
		            if (pal_img_n != 0 && pal_len == 0) return stbi__err!("no PLTE","Corrupt PNG");
		            if (scan == STBI__SCAN_header) { s.img_n = pal_img_n; return true; }
		            if ((int32)(ioff + c.length) < (int32)ioff) return false;
		            if (ioff + c.length > idata_limit) {
		               stbi__uint32 idata_limit_old = idata_limit;
		               stbi_uc *p;
		               if (idata_limit == 0) idata_limit = c.length > 4096 ? c.length : 4096;
		               while (ioff + c.length > idata_limit)
		                  idata_limit *= 2;
		               p = (stbi_uc *) STBI_REALLOC_SIZED!(z.idata, idata_limit_old, idata_limit); if (p == null) return stbi__err!("outofmem", "Out of memory");
		               z.idata = p;
		            }
		            if (!stbi__getn(s, z.idata+ioff,(.)c.length)) return stbi__err!("outofdata","Corrupt PNG");
		            ioff += c.length;
		            break;
		         }

		         case STBI__PNG_TYPE!('I','E','N','D'): {
		            stbi__uint32 raw_len, bpl;
		            if (first != 0) return stbi__err!("first not IHDR", "Corrupt PNG");
		            if (scan != STBI__SCAN_load) return true;
		            if (z.idata == null) return stbi__err!("no IDAT","Corrupt PNG");
		            // initial guess for decoded data size to avoid unnecessary reallocs
		            bpl = (s.img_x * (.)z.depth + 7) / 8; // bytes per line, per component
		            raw_len = bpl * s.img_y * (.)s.img_n /* pixels */ + s.img_y /* filter mode per row */;
		            z.expanded = (stbi_uc *) stbi_zlib_decode_malloc_guesssize_headerflag((uint8 *) z.idata, (.)ioff, (.)raw_len, (int32 *) &raw_len, !is_iphone);
		            if (z.expanded == null) return false; // zlib should set error
		            STBI_FREE!(z.idata); z.idata = null;
		            if ((req_comp == s.img_n+1 && req_comp != 3 && pal_img_n == 0) || has_trans)
		               s.img_out_n = s.img_n+1;
		            else
		               s.img_out_n = s.img_n;
		            if (!stbi__create_png_image(z, z.expanded, raw_len, s.img_out_n, z.depth, color, interlace)) return false;
		            if (has_trans) {
		               if (z.depth == 16) {
		                  if (!stbi__compute_transparency16(z, tc16, s.img_out_n)) return false;
		               } else {
		                  if (!stbi__compute_transparency(z, tc, s.img_out_n)) return false;
		               }
		            }
		            if (is_iphone && stbi__de_iphone_flag!() && s.img_out_n > 2)
		               stbi__de_iphone(z);
		            if (pal_img_n != 0) {
		               // pal_img_n == 3 or 4
		               s.img_n = pal_img_n; // record the actual colors we had
		               s.img_out_n = pal_img_n;
		               if (req_comp >= 3) s.img_out_n = req_comp;
		               if (!stbi__expand_png_palette(z, &palette[0], (.)pal_len, s.img_out_n))
		                  return false;
		            } else if (has_trans) {
		               // non-paletted image with tRNS . source image has (constant) alpha
		               ++s.img_n;
		            }
		            STBI_FREE!(z.expanded); z.expanded = null;
		            // end of PNG chunk, read and skip CRC
		            stbi__get32be(s);
		            return true;
		         }

		         default:
		            // if critical, fail
		            if (first != 0) return stbi__err!("first not IHDR", "Corrupt PNG");
		            if ((c.type & (1 << 29)) == 0) {
		               #if !STBI_NO_FAILURE_STRINGS
		               invalid_chunk[0] = (char8)STBI__BYTECAST!(c.type >> 24);
		               invalid_chunk[1] = (char8)STBI__BYTECAST!(c.type >> 16);
		               invalid_chunk[2] = (char8)STBI__BYTECAST!(c.type >>  8);
		               invalid_chunk[3] = (char8)STBI__BYTECAST!(c.type >>  0);
		               #endif
		               return stbi__err!(invalid_chunk, "PNG not supported: unknown PNG chunk type");
		            }
		            stbi__skip(s, (.)c.length);
		            break;
		      }
		      // end of PNG chunk, read and skip CRC
		      stbi__get32be(s);
		   }
		}

		static void *stbi__do_png(stbi__png *p, int32 *x, int32 *y, int32 *n, int32 req_comp, stbi__result_info *ri)
		{
		   void *result=null;
		   if (req_comp < 0 || req_comp > 4) return stbi__errpuc!("bad req_comp", "Internal error");
		   if (stbi__parse_png_file(p, STBI__SCAN_load, req_comp)) {
		      if (p.depth <= 8)
		         ri.bits_per_channel = 8;
		      else if (p.depth == 16)
		         ri.bits_per_channel = 16;
		      else
		         return stbi__errpuc!("bad bits_per_channel", "PNG not supported: unsupported color depth");
		      result = p.out_;
		      p.out_ = null;
		      if (req_comp != 0 && req_comp != p.s.img_out_n) {
		         if (ri.bits_per_channel == 8)
		            result = stbi__convert_format((uint8 *) result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
		         else
		            result = stbi__convert_format16((stbi__uint16 *) result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
		         p.s.img_out_n = req_comp;
		         if (result == null) return result;
		      }
		      *x = (.)p.s.img_x;
		      *y = (.)p.s.img_y;
		      if (n != null) *n = p.s.img_n;
		   }
		   STBI_FREE!(p.out_);     p.out_     = null;
		   STBI_FREE!(p.expanded); p.expanded = null;
		   STBI_FREE!(p.idata);    p.idata    = null;

		   return result;
		}

		static void *stbi__png_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   stbi__png p;
		   p.s = s;
		   return stbi__do_png(&p, x,y,comp,req_comp, ri);
		}

		static bool stbi__png_test(stbi__context *s)
		{
		   bool r;
		   r = stbi__check_png_header(s);
		   stbi__rewind(s);
		   return r;
		}

		static bool stbi__png_info_raw(stbi__png *p, int32 *x, int32 *y, int32 *comp)
		{
		   if (!stbi__parse_png_file(p, STBI__SCAN_header, 0)) {
		      stbi__rewind( p.s );
		      return false;
		   }
		   if (x != null) *x = (.)p.s.img_x;
		   if (y != null) *y = (.)p.s.img_y;
		   if (comp != null) *comp = p.s.img_n;
		   return true;
		}

		static bool stbi__png_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   stbi__png p;
		   p.s = s;
		   return stbi__png_info_raw(&p, x, y, comp);
		}

		static bool stbi__png_is16(stbi__context *s)
		{
		   stbi__png p = ?;
		   p.s = s;
		   if (!stbi__png_info_raw(&p, null, null, null))
			   return false;
		   if (p.depth != 16) {
		      stbi__rewind(p.s);
		      return false;
		   }
		   return true;
		}
#endif

		// Microsoft/Windows BMP image

#if !STBI_NO_BMP
		static bool stbi__bmp_test_raw(stbi__context *s)
		{
		   bool r;
		   int32 sz;
		   if (stbi__get8(s) != 'B') return false;
		   if (stbi__get8(s) != 'M') return false;
		   stbi__get32le(s); // discard filesize
		   stbi__get16le(s); // discard reserved
		   stbi__get16le(s); // discard reserved
		   stbi__get32le(s); // discard data offset
		   sz = (.)stbi__get32le(s);
		   r = (sz == 12 || sz == 40 || sz == 56 || sz == 108 || sz == 124);
		   return r;
		}

		static bool stbi__bmp_test(stbi__context *s)
		{
		   bool r = stbi__bmp_test_raw(s);
		   stbi__rewind(s);
		   return r;
		}


		// returns 0..31 for the highest set bit
		static int32 stbi__high_bit(uint32 z)
		{
			var z;
		   int32 n=0;
		   if (z == 0) return -1;
		   if (z >= 0x10000) { n += 16; z >>= 16; }
		   if (z >= 0x00100) { n +=  8; z >>=  8; }
		   if (z >= 0x00010) { n +=  4; z >>=  4; }
		   if (z >= 0x00004) { n +=  2; z >>=  2; }
		   if (z >= 0x00002) { n +=  1;/* >>=  1;*/ }
		   return n;
		}

		static int32 stbi__bitcount(uint32 a)
		{
			var a;
		   a = (a & 0x55555555) + ((a >>  1) & 0x55555555); // max 2
		   a = (a & 0x33333333) + ((a >>  2) & 0x33333333); // max 4
		   a = (a + (a >> 4)) & 0x0f0f0f0f; // max 8 per 4, now 8 bits
		   a = (a + (a >> 8)); // max 16 per 8 bits
		   a = (a + (a >> 16)); // max 32 per 8 bits
		   return (int32)a & 0xff;
		}

		const uint32[9] mul_table = .(
		   0,
		   0xff/*0b11111111*/, 0x55/*0b01010101*/, 0x49/*0b01001001*/, 0x11/*0b00010001*/,
		   0x21/*0b00100001*/, 0x41/*0b01000001*/, 0x81/*0b10000001*/, 0x01/*0b00000001*/,
		);
		const uint32[9] shift_table = .(
		   0, 0,0,1,0,2,4,6,0,
		);

		// extract an arbitrarily-aligned N-bit value (N=bits)
		// from v, and then make it 8-bits long and fractionally
		// extend it to full full range.
		static int32 stbi__shiftsigned(uint32 v, int32 shift, int32 bits)
		{
		   	var v;
		   if (shift < 0)
		      v <<= -shift;
		   else
		      v >>= shift;
		   STBI_ASSERT!(v < 256);
		   v >>= (8-bits);
		   STBI_ASSERT!(bits >= 0 && bits <= 8);
		   return (int32) ((uint32) v * mul_table[bits]) >> shift_table[bits];
		}

		struct stbi__bmp_data
		{
		   public int32 bpp, offset, hsz;
		   public uint32 mr,mg,mb,ma, all_a;
		   public int32 extra_read;
		}

		static bool stbi__bmp_set_mask_defaults(stbi__bmp_data *info, int32 compress)
		{
		   // BI_BITFIELDS specifies masks explicitly, don't override
		   if (compress == 3)
		      return true;

		   if (compress == 0) {
		      if (info.bpp == 16) {
		         info.mr = 31 << 10;
		         info.mg = 31 <<  5;
		         info.mb = 31 <<  0;
		      } else if (info.bpp == 32) {
		         info.mr = 0xff << 16;
		         info.mg = 0xff <<  8;
		         info.mb = 0xff <<  0;
		         info.ma = 0xff << 24;
		         info.all_a = 0; // if all_a is 0 at end, then we loaded alpha channel but it was all 0
		      } else {
		         // otherwise, use defaults, which is all-0
		         info.mr = info.mg = info.mb = info.ma = 0;
		      }
		      return true;
		   }
		   return false; // error
		}

		// @PORT: this returned void*.. but really just used it like a bool for some reason..
		static bool stbi__bmp_parse_header(stbi__context *s, stbi__bmp_data *info)
		{
		   int32 hsz;
		   if (stbi__get8(s) != 'B' || stbi__get8(s) != 'M') return stbi__err!("not BMP", "Corrupt BMP");
		   stbi__get32le(s); // discard filesize
		   stbi__get16le(s); // discard reserved
		   stbi__get16le(s); // discard reserved
		   info.offset = (.)stbi__get32le(s);
		   info.hsz = hsz = (.)stbi__get32le(s);
		   info.mr = info.mg = info.mb = info.ma = 0;
		   info.extra_read = 14;

		   if (info.offset < 0) return stbi__err!("bad BMP", "bad BMP");

		   if (hsz != 12 && hsz != 40 && hsz != 56 && hsz != 108 && hsz != 124) return stbi__err!("unknown BMP", "BMP type not supported: unknown");
		   if (hsz == 12) {
		      s.img_x = (.)stbi__get16le(s);
		      s.img_y = (.)stbi__get16le(s);
		   } else {
		      s.img_x = stbi__get32le(s);
		      s.img_y = stbi__get32le(s);
		   }
		   if (stbi__get16le(s) != 1) return stbi__err!("bad BMP", "bad BMP");
		   info.bpp = stbi__get16le(s);
		   if (hsz != 12) {
		      int32 compress = (.)stbi__get32le(s);
		      if (compress == 1 || compress == 2) return stbi__err!("BMP RLE", "BMP type not supported: RLE");
		      if (compress >= 4) return stbi__err!("BMP JPEG/PNG", "BMP type not supported: unsupported compression"); // this includes PNG/JPEG modes
		      if (compress == 3 && info.bpp != 16 && info.bpp != 32) return stbi__err!("bad BMP", "bad BMP"); // bitfields requires 16 or 32 bits/pixel
		      stbi__get32le(s); // discard sizeof
		      stbi__get32le(s); // discard hres
		      stbi__get32le(s); // discard vres
		      stbi__get32le(s); // discard colorsused
		      stbi__get32le(s); // discard max important
		      if (hsz == 40 || hsz == 56) {
		         if (hsz == 56) {
		            stbi__get32le(s);
		            stbi__get32le(s);
		            stbi__get32le(s);
		            stbi__get32le(s);
		         }
		         if (info.bpp == 16 || info.bpp == 32) {
		            if (compress == 0) {
		               stbi__bmp_set_mask_defaults(info, compress);
		            } else if (compress == 3) {
		               info.mr = stbi__get32le(s);
		               info.mg = stbi__get32le(s);
		               info.mb = stbi__get32le(s);
		               info.extra_read += 12;
		               // not documented, but generated by photoshop and handled by mspaint
		               if (info.mr == info.mg && info.mg == info.mb) {
		                  // ?!?!?
		                  return stbi__err!("bad BMP", "bad BMP");
		               }
		            } else
		               return stbi__err!("bad BMP", "bad BMP");
		         }
		      } else {
		         // V4/V5 header
		         int32 i;
		         if (hsz != 108 && hsz != 124)
		            return stbi__err!("bad BMP", "bad BMP");
		         info.mr = stbi__get32le(s);
		         info.mg = stbi__get32le(s);
		         info.mb = stbi__get32le(s);
		         info.ma = stbi__get32le(s);
		         if (compress != 3) // override mr/mg/mb unless in BI_BITFIELDS mode, as per docs
		            stbi__bmp_set_mask_defaults(info, compress);
		         stbi__get32le(s); // discard color space
		         for (i=0; i < 12; ++i)
		            stbi__get32le(s); // discard color space parameters
		         if (hsz == 124) {
		            stbi__get32le(s); // discard rendering intent
		            stbi__get32le(s); // discard offset of profile data
		            stbi__get32le(s); // discard size of profile data
		            stbi__get32le(s); // discard reserved
		         }
		      }
		   }
		   return true;
		}


		static void *stbi__bmp_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   stbi_uc *out_;
		   uint32 mr=0,mg=0,mb=0,ma=0, all_a;
		   stbi_uc[256][4] pal = ?;
		   int32 psize=0,i,j,width;
		   bool flip_vertically; int32 target, pad;
		   stbi__bmp_data info = ?;

		   info.all_a = 255;
		   if (!stbi__bmp_parse_header(s, &info)) // @PORT: this returned a pointer for no reason, so now it doesn't
		      return null; // error code already set

		   flip_vertically = ((int32) s.img_y) > 0;
		   s.img_y = (.)abs((int32) s.img_y);

		   if (s.img_y > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");
		   if (s.img_x > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");

		   mr = info.mr;
		   mg = info.mg;
		   mb = info.mb;
		   ma = info.ma;
		   all_a = info.all_a;

		   if (info.hsz == 12) {
		      if (info.bpp < 24)
		         psize = (info.offset - info.extra_read - 24) / 3;
		   } else {
		      if (info.bpp < 16)
		         psize = (info.offset - info.extra_read - info.hsz) >> 2;
		   }
		   if (psize == 0) {
		      if (info.offset != s.callback_already_read + (s.img_buffer - s.img_buffer_original)) {
		        return stbi__errpuc!("bad offset", "Corrupt BMP");
		      }
		   }

		   if (info.bpp == 24 && ma == 0xff000000)
		      s.img_n = 3;
		   else
		      s.img_n = ma != 0 ? 4 : 3;
		   if (req_comp != 0 && req_comp >= 3) // we can directly decode 3 or 4
		      target = req_comp;
		   else
		      target = s.img_n; // if they want monochrome, we'll post-convert

		   // sanity-check size
		   if (!stbi__mad3sizes_valid(target, (.)s.img_x, (.)s.img_y, 0))
		      return stbi__errpuc!("too large", "Corrupt BMP");

		   out_ = (stbi_uc *) stbi__malloc_mad3(target, (.)s.img_x, (.)s.img_y, 0);
		   if (out_ == null) return stbi__errpuc!("outofmem", "Out of memory");
		   if (info.bpp < 16) {
		      int32 z=0;
		      if (psize == 0 || psize > 256) { STBI_FREE!(out_); return stbi__errpuc!("invalid", "Corrupt BMP"); }
		      for (i=0; i < psize; ++i) {
		         pal[i][2] = stbi__get8(s);
		         pal[i][1] = stbi__get8(s);
		         pal[i][0] = stbi__get8(s);
		         if (info.hsz != 12) stbi__get8(s);
		         pal[i][3] = 255;
		      }
		      stbi__skip(s, info.offset - info.extra_read - info.hsz - psize * (info.hsz == 12 ? 3 : 4));
		      if (info.bpp == 1) width = (.)(s.img_x + 7) >> 3;
		      else if (info.bpp == 4) width = (.)(s.img_x + 1) >> 1;
		      else if (info.bpp == 8) width = (.)s.img_x;
		      else { STBI_FREE!(out_); return stbi__errpuc!("bad bpp", "Corrupt BMP"); }
		      pad = (-width)&3;
		      if (info.bpp == 1) {
		         for (j=0; j < (int32) s.img_y; ++j) {
		            int32 bit_offset = 7, v = stbi__get8(s);
		            for (i=0; i < (int32) s.img_x; ++i) {
		               int32 color = (v>>bit_offset)&0x1;
		               out_[z++] = pal[color][0];
		               out_[z++] = pal[color][1];
		               out_[z++] = pal[color][2];
		               if (target == 4) out_[z++] = 255;
		               if (i+1 == (int32) s.img_x) break;
		               if((--bit_offset) < 0) {
		                  bit_offset = 7;
		                  v = stbi__get8(s);
		               }
		            }
		            stbi__skip(s, pad);
		         }
		      } else {
		         for (j=0; j < (int32) s.img_y; ++j) {
		            for (i=0; i < (int32) s.img_x; i += 2) {
		               int32 v=stbi__get8(s),v2=0;
		               if (info.bpp == 4) {
		                  v2 = v & 15;
		                  v >>= 4;
		               }
		               out_[z++] = pal[v][0];
		               out_[z++] = pal[v][1];
		               out_[z++] = pal[v][2];
		               if (target == 4) out_[z++] = 255;
		               if (i+1 == (int32) s.img_x) break;
		               v = (info.bpp == 8) ? stbi__get8(s) : v2;
		               out_[z++] = pal[v][0];
		               out_[z++] = pal[v][1];
		               out_[z++] = pal[v][2];
		               if (target == 4) out_[z++] = 255;
		            }
		            stbi__skip(s, pad);
		         }
		      }
		   } else {
		      int32 rshift=0,gshift=0,bshift=0,ashift=0,rcount=0,gcount=0,bcount=0,acount=0;
		      int32 z = 0;
		      int32 easy=0;
		      stbi__skip(s, info.offset - info.extra_read - info.hsz);
		      if (info.bpp == 24) width = 3 * (.)s.img_x;
		      else if (info.bpp == 16) width = 2*(.)s.img_x;
		      else /* bpp = 32 and pad = 0 */ width=0;
		      pad = (-width) & 3;
		      if (info.bpp == 24) {
		         easy = 1;
		      } else if (info.bpp == 32) {
		         if (mb == 0xff && mg == 0xff00 && mr == 0x00ff0000 && ma == 0xff000000)
		            easy = 2;
		      }
		      if (easy == 0) {
		         if (mr == 0 || mg == 0 || mb == 0) { STBI_FREE!(out_); return stbi__errpuc!("bad masks", "Corrupt BMP"); }
		         // right shift amt to put high bit in position #7
		         rshift = stbi__high_bit(mr)-7; rcount = stbi__bitcount(mr);
		         gshift = stbi__high_bit(mg)-7; gcount = stbi__bitcount(mg);
		         bshift = stbi__high_bit(mb)-7; bcount = stbi__bitcount(mb);
		         ashift = stbi__high_bit(ma)-7; acount = stbi__bitcount(ma);
		         if (rcount > 8 || gcount > 8 || bcount > 8 || acount > 8) { STBI_FREE!(out_); return stbi__errpuc!("bad masks", "Corrupt BMP"); }
		      }
		      for (j=0; j < (int32) s.img_y; ++j) {
		         if (easy != 0) {
		            for (i=0; i < (int32) s.img_x; ++i) {
		               uint8 a;
		               out_[z+2] = stbi__get8(s);
		               out_[z+1] = stbi__get8(s);
		               out_[z+0] = stbi__get8(s);
		               z += 3;
		               a = (easy == 2 ? stbi__get8(s) : 255);
		               all_a |= a;
		               if (target == 4) out_[z++] = a;
		            }
		         } else {
		            int32 bpp = info.bpp;
		            for (i=0; i < (int32) s.img_x; ++i) {
		               stbi__uint32 v = (bpp == 16 ? (stbi__uint32) stbi__get16le(s) : stbi__get32le(s));
		               uint32 a;
		               out_[z++] = STBI__BYTECAST!(stbi__shiftsigned(v & mr, rshift, rcount));
		               out_[z++] = STBI__BYTECAST!(stbi__shiftsigned(v & mg, gshift, gcount));
		               out_[z++] = STBI__BYTECAST!(stbi__shiftsigned(v & mb, bshift, bcount));
		               a = (.)(ma != 0 ? stbi__shiftsigned(v & ma, ashift, acount) : 255);
		               all_a |= a;
		               if (target == 4) out_[z++] = STBI__BYTECAST!(a);
		            }
		         }
		         stbi__skip(s, pad);
		      }
		   }

		   // if alpha channel is all 0s, replace with all 255s
		   if (target == 4 && all_a == 0)
		      for (i=(.)(4*s.img_x*s.img_y-1); i >= 0; i -= 4)
		         out_[i] = 255;

		   if (flip_vertically) {
		      stbi_uc t;
		      for (j=0; j < (int32) s.img_y>>1; ++j) {
		         stbi_uc *p1 = &out_[      j     *(.)s.img_x*target];
		         stbi_uc *p2 = &out_[(s.img_y-1-j)*s.img_x*target];
		         for (i=0; i < (int32) s.img_x*target; ++i) {
		            t = p1[i]; p1[i] = p2[i]; p2[i] = t;
		         }
		      }
		   }

		   if (req_comp != 0 && req_comp != target) {
		      out_ = stbi__convert_format(out_, target, req_comp, s.img_x, s.img_y);
		      if (out_ == null) return out_; // stbi__convert_format frees input on failure
		   }

		   *x = (.)s.img_x;
		   *y = (.)s.img_y;
		   if (comp != null) *comp = s.img_n;
		   return out_;
		}
#endif

		// Targa Truevision - TGA
		// by Jonathan Dummer
#if !STBI_NO_TGA
		// returns STBI_rgb or whatever, 0 on error
		static int32 stbi__tga_get_comp(int32 bits_per_pixel, bool is_grey, bool* is_rgb16)
		{
		   // only RGB or RGBA (incl. 16bit) or grey allowed
		   if (is_rgb16 != null) *is_rgb16 = false;
		   switch(bits_per_pixel) {
		      case 8:  return STBI_grey;
		      case 16: if(is_grey) return STBI_grey_alpha;
		               fallthrough;
		      case 15: if(is_rgb16 != null) *is_rgb16 = true;
		               return STBI_rgb;
		      case 24, 32: return bits_per_pixel/8;
		      default: return 0;
		   }
		}

		static bool stbi__tga_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		    int32 tga_w, tga_h, tga_comp, tga_image_type, tga_bits_per_pixel, tga_colormap_bpp;
		    int32 sz, tga_colormap_type;
		    stbi__get8(s);                   // discard Offset
		    tga_colormap_type = stbi__get8(s); // colormap type
		    if( tga_colormap_type > 1 ) {
		        stbi__rewind(s);
		        return false;      // only RGB or indexed allowed
		    }
		    tga_image_type = stbi__get8(s); // image type
		    if ( tga_colormap_type == 1 ) { // colormapped (paletted) image
		        if (tga_image_type != 1 && tga_image_type != 9) {
		            stbi__rewind(s);
		            return false;
		        }
		        stbi__skip(s,4);       // skip index of first colormap entry and number of entries
		        sz = stbi__get8(s);    //   check bits per palette color entry
		        if ( (sz != 8) && (sz != 15) && (sz != 16) && (sz != 24) && (sz != 32) ) {
		            stbi__rewind(s);
		            return false;
		        }
		        stbi__skip(s,4);       // skip image x and y origin
		        tga_colormap_bpp = sz;
		    } else { // "normal" image w/o colormap - only RGB or grey allowed, +/- RLE
		        if ( (tga_image_type != 2) && (tga_image_type != 3) && (tga_image_type != 10) && (tga_image_type != 11) ) {
		            stbi__rewind(s);
		            return false; // only RGB or grey allowed, +/- RLE
		        }
		        stbi__skip(s,9); // skip colormap specification and image x/y origin
		        tga_colormap_bpp = 0;
		    }
		    tga_w = stbi__get16le(s);
		    if( tga_w < 1 ) {
		        stbi__rewind(s);
		        return false;   // test width
		    }
		    tga_h = stbi__get16le(s);
		    if( tga_h < 1 ) {
		        stbi__rewind(s);
		        return false;   // test height
		    }
		    tga_bits_per_pixel = stbi__get8(s); // bits per pixel
		    stbi__get8(s); // ignore alpha bits
		    if (tga_colormap_bpp != 0) {
		        if((tga_bits_per_pixel != 8) && (tga_bits_per_pixel != 16)) {
		            // when using a colormap, tga_bits_per_pixel is the size of the indexes
		            // I don't think anything but 8 or 16bit indexes makes sense
		            stbi__rewind(s);
		            return false;
		        }
		        tga_comp = stbi__tga_get_comp(tga_colormap_bpp, false, null);
		    } else {
		        tga_comp = stbi__tga_get_comp(tga_bits_per_pixel, (tga_image_type == 3) || (tga_image_type == 11), null);
		    }
		    if(tga_comp == 0) {
		      stbi__rewind(s);
		      return false;
		    }
		    if (x != null) *x = tga_w;
		    if (y != null) *y = tga_h;
		    if (comp != null) *comp = tga_comp;
		    return true;                   // seems to have passed everything
		}

		static bool stbi__tga_test(stbi__context *s)
		{
			bool res = false;
			do
			{
				int32 sz, tga_color_type;
				stbi__get8(s);      //   discard Offset
				tga_color_type = stbi__get8(s);   //   color type
				if ( tga_color_type > 1 ) break; //goto errorEnd;   //   only RGB or indexed allowed
				sz = stbi__get8(s);   //   image type
				if ( tga_color_type == 1 ) { // colormapped (paletted) image
				   if (sz != 1 && sz != 9) break; //goto errorEnd; // colortype 1 demands image type 1 or 9
				   stbi__skip(s,4);       // skip index of first colormap entry and number of entries
				   sz = stbi__get8(s);    //   check bits per palette color entry
				   if ( (sz != 8) && (sz != 15) && (sz != 16) && (sz != 24) && (sz != 32) ) break; //goto errorEnd;
				   stbi__skip(s,4);       // skip image x and y origin
				} else { // "normal" image w/o colormap
				   if ( (sz != 2) && (sz != 3) && (sz != 10) && (sz != 11) ) break; //goto errorEnd; // only RGB or grey allowed, +/- RLE
				   stbi__skip(s,9); // skip colormap specification and image x/y origin
				}
				if ( stbi__get16le(s) < 1 ) break; //goto errorEnd;      //   test width
				if ( stbi__get16le(s) < 1 ) break; //goto errorEnd;      //   test height
				sz = stbi__get8(s);   //   bits per pixel
				if ( (tga_color_type == 1) && (sz != 8) && (sz != 16) ) break; //goto errorEnd; // for colormapped images, bpp is size of an index
				if ( (sz != 8) && (sz != 15) && (sz != 16) && (sz != 24) && (sz != 32) ) break;//goto errorEnd;

				res = true; // if we got this far, everything's good and we can return 1 instead of 0
			}

		//errorEnd:
		   stbi__rewind(s);
		   return res;
		}

		// read 16bit value and convert to 24bit RGB
		static void stbi__tga_read_rgb16(stbi__context *s, stbi_uc* out_)
		{
		   stbi__uint16 px = (stbi__uint16)stbi__get16le(s);
		   stbi__uint16 fiveBitMask = 31;
		   // we have 3 channels with 5bits each
		   int32 r = (px >> 10) & fiveBitMask;
		   int32 g = (px >> 5) & fiveBitMask;
		   int32 b = px & fiveBitMask;
		   // Note that this saves the data in RGB(A) order, so it doesn't need to be swapped later
		   out_[0] = (stbi_uc)((r * 255)/31);
		   out_[1] = (stbi_uc)((g * 255)/31);
		   out_[2] = (stbi_uc)((b * 255)/31);

		   // some people claim that the most significant bit might be used for alpha
		   // (possibly if an alpha-bit is set in the "image descriptor byte")
		   // but that only made 16bit test images completely translucent..
		   // so let's treat all 15 and 16bit TGAs as RGB with no alpha.
		}

		static void *stbi__tga_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   //   read in the TGA header stuff
		   int32 tga_offset = stbi__get8(s);
		   bool tga_indexed = stbi__get8(s) != 0;
		   int32 tga_image_type = stbi__get8(s);
			bool tga_is_RLE = false;
		   int32 tga_palette_start = stbi__get16le(s);
		   int32 tga_palette_len = stbi__get16le(s);
		   int32 tga_palette_bits = stbi__get8(s);
		   int32 tga_x_origin = stbi__get16le(s);
		   int32 tga_y_origin = stbi__get16le(s);
		   int32 tga_width = stbi__get16le(s);
		   int32 tga_height = stbi__get16le(s);
		   int32 tga_bits_per_pixel = stbi__get8(s);
		   int32 tga_comp; bool tga_rgb16=false;
		   int32 tga_inverted = stbi__get8(s);
		   // int tga_alpha_bits = tga_inverted & 15; // the 4 lowest bits - unused (useless?)
		   //   image data
		   uint8 *tga_data;
		   uint8 *tga_palette = null;
		   int32 i, j;
		   uint8[4] raw_data = default;
		   int32 RLE_count = 0;
		   bool RLE_repeating = false;
		   bool read_next_pixel = true;

		   if (tga_height > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");
		   if (tga_width > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");

		   //   do a tiny bit of precessing
		   if ( tga_image_type >= 8 )
		   {
		      tga_image_type -= 8;
		      tga_is_RLE = true;
		   }
		   tga_inverted = 1 - ((tga_inverted >> 5) & 1);

		   //   If I'm paletted, then I'll use the number of bits from the palette
		   if ( tga_indexed ) tga_comp = stbi__tga_get_comp(tga_palette_bits, false, &tga_rgb16);
		   else tga_comp = stbi__tga_get_comp(tga_bits_per_pixel, (tga_image_type == 3), &tga_rgb16);

		   if(tga_comp == 0) // shouldn't really happen, stbi__tga_test() should have ensured basic consistency
		      return stbi__errpuc!("bad format", "Can't find out TGA pixelformat");

		   //   tga info
		   *x = tga_width;
		   *y = tga_height;
		   if (comp != null) *comp = tga_comp;

		   if (!stbi__mad3sizes_valid(tga_width, tga_height, tga_comp, 0))
		      return stbi__errpuc!("too large", "Corrupt TGA");

		   tga_data = (uint8*)stbi__malloc_mad3(tga_width, tga_height, tga_comp, 0);
		   if (tga_data == null) return stbi__errpuc!("outofmem", "Out of memory");

		   // skip to the data's starting position (offset usually = 0)
		   stbi__skip(s, tga_offset );

		   if ( !tga_indexed && !tga_is_RLE && !tga_rgb16 ) {
		      for (i=0; i < tga_height; ++i) {
		         int32 row = tga_inverted != 0 ? tga_height -i - 1 : i;
		         stbi_uc *tga_row = tga_data + row*tga_width*tga_comp;
		         stbi__getn(s, tga_row, tga_width * tga_comp);
		      }
		   } else  {
		      //   do I need to load a palette?
		      if ( tga_indexed)
		      {
		         if (tga_palette_len == 0) {  /* you have to have at least one entry! */
		            STBI_FREE!(tga_data);
		            return stbi__errpuc!("bad palette", "Corrupt TGA");
		         }

		         //   any data to skip? (offset usually = 0)
		         stbi__skip(s, tga_palette_start );
		         //   load the palette
		         tga_palette = (uint8*)stbi__malloc_mad2(tga_palette_len, tga_comp, 0);
		         if (tga_palette == null) {
		            STBI_FREE!(tga_data);
		            return stbi__errpuc!("outofmem", "Out of memory");
		         }
		         if (tga_rgb16) {
		            stbi_uc *pal_entry = tga_palette;
		            STBI_ASSERT!(tga_comp == STBI_rgb);
		            for (i=0; i < tga_palette_len; ++i) {
		               stbi__tga_read_rgb16(s, pal_entry);
		               pal_entry += tga_comp;
		            }
		         } else if (!stbi__getn(s, tga_palette, tga_palette_len * tga_comp)) {
		               STBI_FREE!(tga_data);
		               STBI_FREE!(tga_palette);
		               return stbi__errpuc!("bad palette", "Corrupt TGA");
		         }
		      }
		      //   load the data
		      for (i=0; i < tga_width * tga_height; ++i)
		      {
		         //   if I'm in RLE mode, do I need to get a RLE stbi__pngchunk?
		         if ( tga_is_RLE )
		         {
		            if ( RLE_count == 0 )
		            {
		               //   yep, get the next byte as a RLE command
		               int32 RLE_cmd = stbi__get8(s);
		               RLE_count = 1 + (RLE_cmd & 127);
		               RLE_repeating = (RLE_cmd >> 7) != 0;
		               read_next_pixel = true;
		            } else if ( !RLE_repeating )
		            {
		               read_next_pixel = true;
		            }
		         } else
		         {
		            read_next_pixel = true;
		         }
		         //   OK, if I need to read a pixel, do it now
		         if ( read_next_pixel )
		         {
		            //   load however much data we did have
		            if ( tga_indexed )
		            {
		               // read in index, then perform the lookup
		               int32 pal_idx = (tga_bits_per_pixel == 8) ? stbi__get8(s) : stbi__get16le(s);
		               if ( pal_idx >= tga_palette_len ) {
		                  // invalid index
		                  pal_idx = 0;
		               }
		               pal_idx *= tga_comp;
		               for (j = 0; j < tga_comp; ++j) {
		                  raw_data[j] = tga_palette[pal_idx+j];
		               }
		            } else if(tga_rgb16) {
		               STBI_ASSERT!(tga_comp == STBI_rgb);
		               stbi__tga_read_rgb16(s, &raw_data[0]);
		            } else {
		               //   read in the data raw
		               for (j = 0; j < tga_comp; ++j) {
		                  raw_data[j] = stbi__get8(s);
		               }
		            }
		            //   clear the reading flag for the next pixel
		            read_next_pixel = false;
		         } // end of reading a pixel

		         // copy data
		         for (j = 0; j < tga_comp; ++j)
		           tga_data[i*tga_comp+j] = raw_data[j];

		         //   in case we're in RLE mode, keep counting down
		         --RLE_count;
		      }
		      //   do I need to invert the image?
		      if ( tga_inverted != 0 )
		      {
		         for (j = 0; j*2 < tga_height; ++j)
		         {
		            int32 index1 = j * tga_width * tga_comp;
		            int32 index2 = (tga_height - 1 - j) * tga_width * tga_comp;
		            for (i = tga_width * tga_comp; i > 0; --i)
		            {
		               uint8 temp = tga_data[index1];
		               tga_data[index1] = tga_data[index2];
		               tga_data[index2] = temp;
		               ++index1;
		               ++index2;
		            }
		         }
		      }
		      //   clear my palette, if I had one
		      if ( tga_palette != null )
		      {
		         STBI_FREE!( tga_palette );
		      }
		   }

		   // swap RGB - if the source data was RGB16, it already is in the right order
		   if (tga_comp >= 3 && !tga_rgb16)
		   {
		      uint8* tga_pixel = tga_data;
		      for (i=0; i < tga_width * tga_height; ++i)
		      {
		         uint8 temp = tga_pixel[0];
		         tga_pixel[0] = tga_pixel[2];
		         tga_pixel[2] = temp;
		         tga_pixel += tga_comp;
		      }
		   }

		   // convert to target component count
		   if (req_comp != 0 && req_comp != tga_comp)
		      tga_data = stbi__convert_format(tga_data, tga_comp, req_comp, (.)tga_width, (.)tga_height);

		   //   the things I do to get rid of an error message, and yet keep
		   //   Microsoft's C compilers happy... [8^(
		   tga_palette_start = tga_palette_len = tga_palette_bits =
		         tga_x_origin = tga_y_origin = 0;
		   //   OK, done
		   return tga_data;
		}
#endif

		// *************************************************************************************************
		// Photoshop PSD loader -- PD by Thatcher Ulrich, integration by Nicolas Schulz, tweaked by STB

#if !STBI_NO_PSD
		static bool stbi__psd_test(stbi__context *s)
		{
		   bool r = (stbi__get32be(s) == 0x38425053);
		   stbi__rewind(s);
		   return r;
		}

		static bool stbi__psd_decode_rle(stbi__context *s, stbi_uc *p, int32 pixelCount)
		{
			var p;
		   int32 count, nleft, len;

		   count = 0;
		   while ((nleft = pixelCount - count) > 0) {
		      len = stbi__get8(s);
		      if (len == 128) {
		         // No-op.
		      } else if (len < 128) {
		         // Copy next len+1 bytes literally.
		         len++;
		         if (len > nleft) return false; // corrupt data
		         count += len;
		         while (len != 0) {
		            *p = stbi__get8(s);
		            p += 4;
		            len--;
		         }
		      } else if (len > 128) {
		         stbi_uc   val;
		         // Next -len+1 bytes in the dest are replicated from next source byte.
		         // (Interpret len as a negative 8-bit int.)
		         len = 257 - len;
		         if (len > nleft) return false; // corrupt data
		         val = stbi__get8(s);
		         count += len;
		         while (len != 0) {
		            *p = val;
		            p += 4;
		            len--;
		         }
		      }
		   }

		   return true;
		}

		static void *stbi__psd_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri, int32 bpc)
		{
		   int32 pixelCount;
		   int32 channelCount, compression;
		   int32 channel, i;
		   int32 bitdepth;
		   int32 w,h;
		   stbi_uc *out_;

		   // Check identifier
		   if (stbi__get32be(s) != 0x38425053)   // "8BPS"
		      return stbi__errpuc!("not PSD", "Corrupt PSD image");

		   // Check file type version.
		   if (stbi__get16be(s) != 1)
		      return stbi__errpuc!("wrong version", "Unsupported version of PSD image");

		   // Skip 6 reserved bytes.
		   stbi__skip(s, 6 );

		   // Read the number of channels (R, G, B, A, etc).
		   channelCount = stbi__get16be(s);
		   if (channelCount < 0 || channelCount > 16)
		      return stbi__errpuc!("wrong channel count", "Unsupported number of channels in PSD image");

		   // Read the rows and columns of the image.
		   h = (.)stbi__get32be(s);
		   w = (.)stbi__get32be(s);

		   if (h > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");
		   if (w > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");

		   // Make sure the depth is 8 bits.
		   bitdepth = stbi__get16be(s);
		   if (bitdepth != 8 && bitdepth != 16)
		      return stbi__errpuc!("unsupported bit depth", "PSD bit depth is not 8 or 16 bit");

		   // Make sure the color mode is RGB.
		   // Valid options are:
		   //   0: Bitmap
		   //   1: Grayscale
		   //   2: Indexed color
		   //   3: RGB color
		   //   4: CMYK color
		   //   7: Multichannel
		   //   8: Duotone
		   //   9: Lab color
		   if (stbi__get16be(s) != 3)
		      return stbi__errpuc!("wrong color format", "PSD is not in RGB color format");

		   // Skip the Mode Data.  (It's the palette for indexed color; other info for other modes.)
		   stbi__skip(s,(.)stbi__get32be(s) );

		   // Skip the image resources.  (resolution, pen tool paths, etc)
		   stbi__skip(s, (.)stbi__get32be(s) );

		   // Skip the reserved data.
		   stbi__skip(s, (.)stbi__get32be(s) );

		   // Find out if the data is compressed.
		   // Known values:
		   //   0: no compression
		   //   1: RLE compressed
		   compression = stbi__get16be(s);
		   if (compression > 1)
		      return stbi__errpuc!("bad compression", "PSD has an unknown compression format");

		   // Check size
		   if (!stbi__mad3sizes_valid(4, w, h, 0))
		      return stbi__errpuc!("too large", "Corrupt PSD");

		   // Create the destination image.

		   if (compression == 0 && bitdepth == 16 && bpc == 16) {
		      out_ = (stbi_uc *) stbi__malloc_mad3(8, w, h, 0);
		      ri.bits_per_channel = 16;
		   } else
		      out_ = (stbi_uc *) stbi__malloc(4 * w*h);

		   if (out_ == null) return stbi__errpuc!("outofmem", "Out of memory");
		   pixelCount = w*h;

		   // Initialize the data to zero.
		   //memset( out, 0, pixelCount * 4 );

		   // Finally, the image data.
		   if (compression != 0) {
		      // RLE as used by .PSD and .TIFF
		      // Loop until you get the number of unpacked bytes you are expecting:
		      //     Read the next source byte into n.
		      //     If n is between 0 and 127 inclusive, copy the next n+1 bytes literally.
		      //     Else if n is between -127 and -1 inclusive, copy the next byte -n+1 times.
		      //     Else if n is 128, noop.
		      // Endloop

		      // The RLE-compressed data is preceded by a 2-byte data count for each row in the data,
		      // which we're going to just skip.
		      stbi__skip(s, h * channelCount * 2 );

		      // Read the RLE data by channel.
		      for (channel = 0; channel < 4; channel++) {
		         stbi_uc *p;

		         p = &out_[channel];
		         if (channel >= channelCount) {
		            // Fill this channel with default data.
		            for (i = 0; i < pixelCount; i++, p += 4)
		               *p = (channel == 3 ? 255 : 0);
		         } else {
		            // Read the RLE data.
		            if (!stbi__psd_decode_rle(s, p, pixelCount)) {
		               STBI_FREE!(out_);
		               return stbi__errpuc!("corrupt", "bad RLE data");
		            }
		         }
		      }

		   } else {
		      // We're at the raw image data.  It's each channel in order (Red, Green, Blue, Alpha, ...)
		      // where each channel consists of an 8-bit (or 16-bit) value for each pixel in the image.

		      // Read the data by channel.
		      for (channel = 0; channel < 4; channel++) {
		         if (channel >= channelCount) {
		            // Fill this channel with default data.
		            if (bitdepth == 16 && bpc == 16) {
		               stbi__uint16 *q = ((stbi__uint16 *) out_) + channel;
		               stbi__uint16 val = channel == 3 ? 65535 : 0;
		               for (i = 0; i < pixelCount; i++, q += 4)
		                  *q = val;
		            } else {
		               stbi_uc *p = &out_[channel];
		               stbi_uc val = channel == 3 ? 255 : 0;
		               for (i = 0; i < pixelCount; i++, p += 4)
		                  *p = val;
		            }
		         } else {
		            if (ri.bits_per_channel == 16) {    // output bpc
		               stbi__uint16 *q = ((stbi__uint16 *) out_) + channel;
		               for (i = 0; i < pixelCount; i++, q += 4)
		                  *q = (stbi__uint16) stbi__get16be(s);
		            } else {
		               stbi_uc *p = &out_[channel];
		               if (bitdepth == 16) {  // input bpc
		                  for (i = 0; i < pixelCount; i++, p += 4)
		                     *p = (stbi_uc) (stbi__get16be(s) >> 8);
		               } else {
		                  for (i = 0; i < pixelCount; i++, p += 4)
		                     *p = stbi__get8(s);
		               }
		            }
		         }
		      }
		   }

		   // remove weird white matte from PSD
		   if (channelCount >= 4) {
		      if (ri.bits_per_channel == 16) {
		         for (i=0; i < w*h; ++i) {
		            stbi__uint16 *pixel = (stbi__uint16 *) &out_[4*i];
		            if (pixel[3] != 0 && pixel[3] != 65535) {
		               float a = pixel[3] / 65535.0f;
		               float ra = 1.0f / a;
		               float inv_a = 65535.0f * (1 - ra);
		               pixel[0] = (stbi__uint16) (pixel[0]*ra + inv_a);
		               pixel[1] = (stbi__uint16) (pixel[1]*ra + inv_a);
		               pixel[2] = (stbi__uint16) (pixel[2]*ra + inv_a);
		            }
		         }
		      } else {
		         for (i=0; i < w*h; ++i) {
		            uint8 *pixel = &out_[4*i];
		            if (pixel[3] != 0 && pixel[3] != 255) {
		               float a = pixel[3] / 255.0f;
		               float ra = 1.0f / a;
		               float inv_a = 255.0f * (1 - ra);
		               pixel[0] = (uint8) (pixel[0]*ra + inv_a);
		               pixel[1] = (uint8) (pixel[1]*ra + inv_a);
		               pixel[2] = (uint8) (pixel[2]*ra + inv_a);
		            }
		         }
		      }
		   }

		   // convert to desired output format
		   if (req_comp != 0 && req_comp != 4) {
		      if (ri.bits_per_channel == 16)
		         out_ = (stbi_uc *) stbi__convert_format16((stbi__uint16 *) out_, 4, req_comp, (.)w, (.)h);
		      else
		         out_ = stbi__convert_format(out_, 4, req_comp, (.)w, (.)h);
		      if (out_ == null) return out_; // stbi__convert_format frees input on failure
		   }

		   if (comp != null) *comp = 4;
		   *y = h;
		   *x = w;

		   return out_;
		}
#endif

		// *************************************************************************************************
		// Softimage PIC loader
		// by Tom Seddon
		//
		// See http://softimage.wiki.softimage.com/index.php/INFO:_PIC_file_format
		// See http://ozviz.wasp.uwa.edu.au/~pbourke/dataformats/softimagepic/

#if !STBI_NO_PIC
		static bool stbi__pic_is4(stbi__context *s, char8 *str)
		{
		   int32 i;
		   for (i=0; i<4; ++i)
		      if (stbi__get8(s) != (stbi_uc)str[i])
		         return false;

		   return true;
		}

		static bool stbi__pic_test_core(stbi__context *s)
		{
		   int32 i;

		   if (!stbi__pic_is4(s,"\x53\x80\xF6\x34"))
		      return false;

		   for(i=0;i<84;++i)
		      stbi__get8(s);

		   if (!stbi__pic_is4(s,"PICT"))
		      return false;

		   return true;
		}

		struct stbi__pic_packet
		{
		   public stbi_uc size,type,channel;
		}

		static stbi_uc *stbi__readval(stbi__context *s, int32 channel, stbi_uc *dest)
		{
		   int32 mask=0x80, i;

		   for (i=0; i<4; ++i, mask>>=1) {
		      if ((channel & mask) != 0) {
		         if (stbi__at_eof(s)) return stbi__errpuc!("bad file","PIC file too short");
		         dest[i]=stbi__get8(s);
		      }
		   }

		   return dest;
		}

		static void stbi__copyval(int32 channel,stbi_uc *dest,stbi_uc *src)
		{
		   int32 mask=0x80,i;

		   for (i=0;i<4; ++i, mask>>=1)
		      if ((channel&mask) != 0)
		         dest[i]=src[i];
		}

		static stbi_uc *stbi__pic_load_core(stbi__context *s,int32 width,int32 height,int32 *comp, stbi_uc *result)
		{
		   int32 act_comp=0,num_packets=0,y,chained;
		   stbi__pic_packet[10] packets;

		   // this will (should...) cater for even some bizarre stuff like having data
		    // for the same channel in multiple packets.
		   repeat {
		      stbi__pic_packet *packet;

		      if (num_packets==sizeof(decltype(packets))/sizeof(decltype(packets[0])))
		         return stbi__errpuc!("bad format","too many packets");

		      packet = &packets[num_packets++];

		      chained = stbi__get8(s);
		      packet.size    = stbi__get8(s);
		      packet.type    = stbi__get8(s);
		      packet.channel = stbi__get8(s);

		      act_comp |= packet.channel;

		      if (stbi__at_eof(s))          return stbi__errpuc!("bad file","file too short (reading packets)");
		      if (packet.size != 8)  return stbi__errpuc!("bad format","packet isn't 8bpp");
		   } while (chained != 0);

		   *comp = ((act_comp & 0x10) != 0 ? 4 : 3); // has alpha channel?

		   for(y=0; y<height; ++y) {
		      int32 packet_idx;

		      for(packet_idx=0; packet_idx < num_packets; ++packet_idx) {
		         stbi__pic_packet *packet = &packets[packet_idx];
		         stbi_uc *dest = result+y*width*4;

		         switch (packet.type) {

		            case 0: {//uncompressed
		               int32 x;

		               for(x=0;x<width;++x, dest+=4)
		                  if (stbi__readval(s,packet.channel,dest) == null)
		                     return null;
		               break;
		            }

		            case 1://Pure RLE
		               {
		                  int32 left=width, i;

		                  while (left>0) {
		                     stbi_uc count;stbi_uc[4] value = ?;

		                     count=stbi__get8(s);
		                     if (stbi__at_eof(s))   return stbi__errpuc!("bad file","file too short (pure read count)");

		                     if (count > left)
		                        count = (stbi_uc) left;

		                     if (stbi__readval(s,packet.channel,&value[0]) == null)  return null;

		                     for(i=0; i<count; ++i,dest+=4)
		                        stbi__copyval(packet.channel,dest,&value[0]);
		                     left -= count;
		                  }
		               }
		               break;

		            case 2: {//Mixed RLE
		               int32 left=width;
		               while (left>0) {
		                  int32 count = stbi__get8(s), i;
		                  if (stbi__at_eof(s))  return stbi__errpuc!("bad file","file too short (mixed read count)");

		                  if (count >= 128) { // Repeated
		                     stbi_uc[4] value;

		                     if (count==128)
		                        count = stbi__get16be(s);
		                     else
		                        count -= 127;
		                     if (count > left)
		                        return stbi__errpuc!("bad file","scanline overrun");

		                     if (stbi__readval(s,packet.channel,&value[0]) == null)
		                        return null;

		                     for(i=0;i<count;++i, dest += 4)
		                        stbi__copyval(packet.channel,dest,&value[0]);
		                  } else { // Raw
		                     ++count;
		                     if (count>left) return stbi__errpuc!("bad file","scanline overrun");

		                     for(i=0;i<count;++i, dest+=4)
		                        if (stbi__readval(s,packet.channel,dest) == null)
		                           return null;
		                  }
		                  left-=count;
		               }
		               break;
		            }

				 default:
					return stbi__errpuc!("bad format","packet has bad compression type");
		         }
		      }
		   }

		   return result;
		}

		static void *stbi__pic_load(stbi__context *s,int32 *px,int32 *py,int32 *comp,int32 req_comp, stbi__result_info *ri)
		{
		   stbi_uc *result;
		   int32 i, x,y, internal_comp;

			var req_comp;
			var comp;
		   if (comp == null) comp = &internal_comp;

		   for (i=0; i<92; ++i)
		      stbi__get8(s);

		   x = stbi__get16be(s);
		   y = stbi__get16be(s);

		   if (y > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");
		   if (x > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");

		   if (stbi__at_eof(s))  return stbi__errpuc!("bad file","file too short (pic header)");
		   if (!stbi__mad3sizes_valid(x, y, 4, 0)) return stbi__errpuc!("too large", "PIC image too large to decode");

		   stbi__get32be(s); //skip `ratio'
		   stbi__get16be(s); //skip `fields'
		   stbi__get16be(s); //skip `pad'

		   // intermediate buffer is RGBA
		   result = (stbi_uc *) stbi__malloc_mad3(x, y, 4, 0);
		   if (result == null) return stbi__errpuc!("outofmem", "Out of memory");
		   memset(result, 0xff, x*y*4);

		   if (stbi__pic_load_core(s,x,y,comp, result) == null) {
		      STBI_FREE!(result);
		      result=null;
		   }
		   *px = x;
		   *py = y;
		   if (req_comp == 0) req_comp = *comp;
		   result=stbi__convert_format(result,4,req_comp,(.)x,(.)y);

		   return result;
		}

		static bool stbi__pic_test(stbi__context *s)
		{
		   bool r = stbi__pic_test_core(s);
		   stbi__rewind(s);
		   return r;
		}
#endif

		// *************************************************************************************************
		// GIF loader -- public domain by Jean-Marc Lienher -- simplified/shrunk by stb

#if !STBI_NO_GIF
		struct stbi__gif_lzw
		{
		   public stbi__int16 prefix;
		   public stbi_uc first;
		   public stbi_uc suffix;
		}

		struct stbi__gif
		{
		   public int32 w,h;
		   public stbi_uc *out_;                 // output buffer (always 4 components)
		   public stbi_uc *background;          // The current "background" as far as a gif is concerned
		   public stbi_uc *history;
		   public int32 flags, bgindex, ratio, transparent, eflags;
		   public stbi_uc[256][4]  pal;
		   public stbi_uc[256][4] lpal;
		   public stbi__gif_lzw[8192] codes;
		   public stbi_uc *color_table;
		   public int32 parse, step;
		   public int32 lflags;
		   public int32 start_x, start_y;
		   public int32 max_x, max_y;
		   public int32 cur_x, cur_y;
		   public int32 line_size;
		   public int32 delay;
		}

		static bool stbi__gif_test_raw(stbi__context *s)
		{
		   int32 sz;
		   if (stbi__get8(s) != 'G' || stbi__get8(s) != 'I' || stbi__get8(s) != 'F' || stbi__get8(s) != '8') return false;
		   sz = stbi__get8(s);
		   if ((char8)sz != '9' && (char8)sz != '7') return false;
		   if (stbi__get8(s) != 'a') return false;
		   return true;
		}

		static bool stbi__gif_test(stbi__context *s)
		{
		   bool r = stbi__gif_test_raw(s);
		   stbi__rewind(s);
		   return r;
		}

		static void stbi__gif_parse_colortable(stbi__context *s, ref stbi_uc[256][4] pal, int32 num_entries, int32 transp) // @PORT: pal needs to be reffed here, since arrays are part of the type for us stbi_uc[256][4] is not a pointer
		{
		   int32 i;
		   for (i=0; i < num_entries; ++i) {
		      pal[i][2] = stbi__get8(s);
		      pal[i][1] = stbi__get8(s);
		      pal[i][0] = stbi__get8(s);
		      pal[i][3] = transp == i ? 0 : 255;
		   }
		}

		static bool stbi__gif_header(stbi__context *s, stbi__gif *g, int32 *comp, bool is_info)
		{
		   stbi_uc version;
		   if (stbi__get8(s) != 'G' || stbi__get8(s) != 'I' || stbi__get8(s) != 'F' || stbi__get8(s) != '8')
		      return stbi__err!("not GIF", "Corrupt GIF");

		   version = stbi__get8(s);
		   if (version != '7' && version != '9')    return stbi__err!("not GIF", "Corrupt GIF");
		   if (stbi__get8(s) != 'a')                return stbi__err!("not GIF", "Corrupt GIF");

		   stbi__g_failure_reason = "";
		   g.w = stbi__get16le(s);
		   g.h = stbi__get16le(s);
		   g.flags = stbi__get8(s);
		   g.bgindex = stbi__get8(s);
		   g.ratio = stbi__get8(s);
		   g.transparent = -1;

		   if (g.w > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");
		   if (g.h > STBI_MAX_DIMENSIONS) return stbi__err!("too large","Very large image (corrupt?)");

		   if (comp != null) *comp = 4;  // can't actually tell whether it's 3 or 4 until we parse the comments

		   if (is_info) return true;

		   if ((g.flags & 0x80) != 0)
		      stbi__gif_parse_colortable(s,ref g.pal, 2 << (g.flags & 7), -1);

		   return true;
		}

		static bool stbi__gif_info_raw(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   stbi__gif* g = (stbi__gif*) stbi__malloc(sizeof(stbi__gif));
		   if (g == null) return stbi__err!("outofmem", "Out of memory");
		   if (!stbi__gif_header(s, g, comp, true)) {
		      STBI_FREE!(g);
		      stbi__rewind( s );
		      return false;
		   }
		   if (x != null) *x = g.w;
		   if (y != null) *y = g.h;
		   STBI_FREE!(g);
		   return true;
		}

		static void stbi__out_gif_code(stbi__gif *g, stbi__uint16 code)
		{
		   stbi_uc *p, c;
		   int32 idx;

		   // recurse to decode the prefixes, since the linked-list is backwards,
		   // and working backwards through an interleaved image would be nasty
		   if (g.codes[code].prefix >= 0)
		      stbi__out_gif_code(g, (.)g.codes[code].prefix);

		   if (g.cur_y >= g.max_y) return;

		   idx = g.cur_x + g.cur_y;
		   p = &g.out_[idx];
		   g.history[idx / 4] = 1;

		   c = &g.color_table[(int32)g.codes[code].suffix * 4];
		   if (c[3] > 128) { // don't render transparent pixels;
		      p[0] = c[2];
		      p[1] = c[1];
		      p[2] = c[0];
		      p[3] = c[3];
		   }
		   g.cur_x += 4;

		   if (g.cur_x >= g.max_x) {
		      g.cur_x = g.start_x;
		      g.cur_y += g.step;

		      while (g.cur_y >= g.max_y && g.parse > 0) {
		         g.step = (1 << g.parse) * g.line_size;
		         g.cur_y = g.start_y + (g.step >> 1);
		         --g.parse;
		      }
		   }
		}

		static stbi_uc *stbi__process_gif_raster(stbi__context *s, stbi__gif *g)
		{
		   stbi_uc lzw_cs;
		   stbi__int32 len, init_code;
		   bool first;
		   stbi__int32 codesize, codemask, avail, oldcode, bits, valid_bits, clear;
		   stbi__gif_lzw *p;

		   lzw_cs = stbi__get8(s);
		   if (lzw_cs > 12) return null;
		   clear = 1 << lzw_cs;
		   first = true;
		   codesize = (int32)lzw_cs + 1;
		   codemask = (1 << codesize) - 1;
		   bits = 0;
		   valid_bits = 0;
		   for (init_code = 0; init_code < clear; init_code++) {
		      g.codes[init_code].prefix = -1;
		      g.codes[init_code].first = (stbi_uc) init_code;
		      g.codes[init_code].suffix = (stbi_uc) init_code;
		   }

		   // support no starting clear code
		   avail = clear+2;
		   oldcode = -1;

		   len = 0;
		   for(;;) {
		      if (valid_bits < codesize) {
		         if (len == 0) {
		            len = stbi__get8(s); // start new block
		            if (len == 0)
		               return g.out_;
		         }
		         --len;
		         bits |= (stbi__int32) stbi__get8(s) << valid_bits;
		         valid_bits += 8;
		      } else {
		         stbi__int32 code = bits & codemask;
		         bits >>= codesize;
		         valid_bits -= codesize;
		         // @OPTIMIZE: is there some way we can accelerate the non-clear path?
		         if (code == clear) {  // clear code
		            codesize = (int32)lzw_cs + 1;
		            codemask = (1 << codesize) - 1;
		            avail = clear + 2;
		            oldcode = -1;
		            first = false;
		         } else if (code == clear + 1) { // end of stream code
		            stbi__skip(s, len);
		            while ((len = stbi__get8(s)) > 0)
		               stbi__skip(s,len);
		            return g.out_;
		         } else if (code <= avail) {
		            if (first) {
		               return stbi__errpuc!("no clear code", "Corrupt GIF");
		            }

		            if (oldcode >= 0) {
		               p = &g.codes[avail++];
		               if (avail > 8192) {
		                  return stbi__errpuc!("too many codes", "Corrupt GIF");
		               }

		               p.prefix = (stbi__int16) oldcode;
		               p.first = g.codes[oldcode].first;
		               p.suffix = (code == avail) ? p.first : g.codes[code].first;
		            } else if (code == avail)
		               return stbi__errpuc!("illegal code in raster", "Corrupt GIF");

		            stbi__out_gif_code(g, (stbi__uint16) code);

		            if ((avail & codemask) == 0 && avail <= 0x0FFF) {
		               codesize++;
		               codemask = (1 << codesize) - 1;
		            }

		            oldcode = code;
		         } else {
		            return stbi__errpuc!("illegal code in raster", "Corrupt GIF");
		         }
		      }
		   }
		}

		// this function is designed to support animated gifs, although stb_image doesn't support it
		// two back is the image from two frames ago, used for a very specific disposal format
		static stbi_uc *stbi__gif_load_next(stbi__context *s, stbi__gif *g, int32 *comp, int32 req_comp, stbi_uc *two_back)
		{
		   int32 dispose;
		   bool first_frame;
		   int32 pi;
		   int32 pcount;

		   // on first frame, any non-written pixels get the background colour (non-transparent)
		   first_frame = false;
		   if (g.out_ == null) {
		      if (!stbi__gif_header(s, g, comp,false)) return null; // stbi__g_failure_reason set by stbi__gif_header
		      if (!stbi__mad3sizes_valid(4, g.w, g.h, 0))
		         return stbi__errpuc!("too large", "GIF image is too large");
		      pcount = g.w * g.h;
		      g.out_ = (stbi_uc *) stbi__malloc(4 * pcount);
		      g.background = (stbi_uc *) stbi__malloc(4 * pcount);
		      g.history = (stbi_uc *) stbi__malloc(pcount);
		      if (g.out_ == null || g.background == null || g.history == null)
		         return stbi__errpuc!("outofmem", "Out of memory");

		      // image is treated as "transparent" at the start - ie, nothing overwrites the current background;
		      // background colour is only used for pixels that are not rendered first frame, after that "background"
		      // color refers to the color that was there the previous frame.
		      memset(g.out_, 0x00, 4 * pcount);
		      memset(g.background, 0x00, 4 * pcount); // state of the background (starts transparent)
		      memset(g.history, 0x00, pcount);        // pixels that were affected previous frame
		      first_frame = true;
		   } else {
		      // second frame - how do we dispose of the previous one?
		      dispose = (g.eflags & 0x1C) >> 2;
		      pcount = g.w * g.h;

		      if ((dispose == 3) && (two_back == null)) {
		         dispose = 2; // if I don't have an image to revert back to, default to the old background
		      }

		      if (dispose == 3) { // use previous graphic
		         for (pi = 0; pi < pcount; ++pi) {
		            if (g.history[pi] != 0) {
		               memcpy( &g.out_[pi * 4], &two_back[pi * 4], 4 );
		            }
		         }
		      } else if (dispose == 2) {
		         // restore what was changed last frame to background before that frame;
		         for (pi = 0; pi < pcount; ++pi) {
		            if (g.history[pi] != 0) {
		               memcpy( &g.out_[pi * 4], &g.background[pi * 4], 4 );
		            }
		         }
		      } else {
		         // This is a non-disposal case eithe way, so just
		         // leave the pixels as is, and they will become the new background
		         // 1: do not dispose
		         // 0:  not specified.
		      }

		      // background is what out is after the undoing of the previou frame;
		      memcpy( g.background, g.out_, 4 * g.w * g.h );
		   }

		   // clear my history;
		   memset( g.history, 0x00, g.w * g.h );        // pixels that were affected previous frame

		   for (;;) {
		      int32 tag = stbi__get8(s);
		      switch (tag) {
		         case 0x2C: /* Image Descriptor */
		         {
		            stbi__int32 x, y, w, h;
		            stbi_uc *o;

		            x = stbi__get16le(s);
		            y = stbi__get16le(s);
		            w = stbi__get16le(s);
		            h = stbi__get16le(s);
		            if (((x + w) > (g.w)) || ((y + h) > (g.h)))
		               return stbi__errpuc!("bad Image Descriptor", "Corrupt GIF");

		            g.line_size = g.w * 4;
		            g.start_x = x * 4;
		            g.start_y = y * g.line_size;
		            g.max_x   = g.start_x + w * 4;
		            g.max_y   = g.start_y + h * g.line_size;
		            g.cur_x   = g.start_x;
		            g.cur_y   = g.start_y;

		            // if the width of the specified rectangle is 0, that means
		            // we may not see *any* pixels or the image is malformed;
		            // to make sure this is caught, move the current y down to
		            // max_y (which is what out_gif_code checks).
		            if (w == 0)
		               g.cur_y = g.max_y;

		            g.lflags = stbi__get8(s);

		            if ((g.lflags & 0x40) != 0) {
		               g.step = 8 * g.line_size; // first interlaced spacing
		               g.parse = 3;
		            } else {
		               g.step = g.line_size;
		               g.parse = 0;
		            }

		            if ((g.lflags & 0x80) != 0) {
		               stbi__gif_parse_colortable(s,ref g.lpal, 2 << (g.lflags & 7), (g.eflags & 0x01) != 0 ? g.transparent : -1);
		               g.color_table = (stbi_uc *) &g.lpal[0][0];
		            } else if ((g.flags & 0x80) != 0) {
		               g.color_table = (stbi_uc *) &g.pal[0][0];
		            } else
		               return stbi__errpuc!("missing color table", "Corrupt GIF");

		            o = stbi__process_gif_raster(s, g);
		            if (o == null) return null;

		            // if this was the first frame,
		            pcount = g.w * g.h;
		            if (first_frame && (g.bgindex > 0)) {
		               // if first frame, any pixel not drawn to gets the background color
		               for (pi = 0; pi < pcount; ++pi) {
		                  if (g.history[pi] == 0) {
		                     g.pal[g.bgindex][3] = 255; // just in case it was made transparent, undo that; It will be reset next frame if need be;
		                     memcpy( &g.out_[pi * 4], &g.pal[g.bgindex], 4 );
		                  }
		               }
		            }

		            return o;
		         }

		         case 0x21: // Comment Extension.
		         {
		            int32 len;
		            int32 ext = stbi__get8(s);
		            if (ext == 0xF9) { // Graphic Control Extension.
		               len = stbi__get8(s);
		               if (len == 4) {
		                  g.eflags = stbi__get8(s);
		                  g.delay = 10 * stbi__get16le(s); // delay - 1/100th of a second, saving as 1/1000ths.

		                  // unset old transparent
		                  if (g.transparent >= 0) {
		                     g.pal[g.transparent][3] = 255;
		                  }
		                  if ((g.eflags & 0x01) != 0) {
		                     g.transparent = stbi__get8(s);
		                     if (g.transparent >= 0) {
		                        g.pal[g.transparent][3] = 0;
		                     }
		                  } else {
		                     // don't need transparent
		                     stbi__skip(s, 1);
		                     g.transparent = -1;
		                  }
		               } else {
		                  stbi__skip(s, len);
		                  break;
		               }
		            }
		            while ((len = stbi__get8(s)) != 0) {
		               stbi__skip(s, len);
		            }
		            break;
		         }

		         case 0x3B: // gif stream termination code
		            return (stbi_uc *) s; // using '1' causes warning on some compilers

		         default:
		            return stbi__errpuc!("unknown code", "Corrupt GIF");
		      }
		   }
		}

		static void *stbi__load_gif_main_outofmem(stbi__gif *g, stbi_uc *out_, int32 **delays)
		{
		   STBI_FREE!(g.out_);
		   STBI_FREE!(g.history);
		   STBI_FREE!(g.background);

		   if (out_ != null) STBI_FREE!(out_);
		   if (delays != null && *delays != null) STBI_FREE!(*delays);
		   return stbi__errpuc!("outofmem", "Out of memory");
		}

		static void *stbi__load_gif_main(stbi__context *s, int32 **delays, int32 *x, int32 *y, int32 *z, int32 *comp, int32 req_comp)
		{
		   if (stbi__gif_test(s)) {
		      int32 layers = 0;
		      stbi_uc *u = null;
		      stbi_uc *out_ = null;
		      stbi_uc *two_back = null;
		      stbi__gif g = ?;
		      int32 stride;
		      int32 out_size = 0;
		      int32 delays_size = 0;

		      memset(&g, 0, sizeof(decltype(g)));
		      if (delays != null) {
		         *delays = null;
		      }

		      repeat {
		         u = stbi__gif_load_next(s, &g, comp, req_comp, two_back);
		         if (u == (stbi_uc *) s) u = null;  // end of animated gif marker

		         if (u != null) {
		            *x = g.w;
		            *y = g.h;
		            ++layers;
		            stride = g.w * g.h * 4;

		            if (out_ != null) {
		               void *tmp = (stbi_uc*) STBI_REALLOC_SIZED!( out_, out_size, layers * stride );
		               if (tmp == null)
		                  return stbi__load_gif_main_outofmem(&g, out_, delays);
		               else {
		                   out_ = (stbi_uc*) tmp;
		                   out_size = layers * stride;
		               }

		               if (delays != null) {
		                  int32 *new_delays = (int32*) STBI_REALLOC_SIZED!( *delays, delays_size, sizeof(int32) * layers );
		                  if (new_delays == null)
		                     return stbi__load_gif_main_outofmem(&g, out_, delays);
		                  *delays = new_delays;
		                  delays_size = layers * sizeof(int32);
		               }
		            } else {
		               out_ = (stbi_uc*)stbi__malloc( layers * stride );
		               if (out_ == null)
		                  return stbi__load_gif_main_outofmem(&g, out_, delays);
		               out_size = layers * stride;
		               if (delays != null) {
		                  *delays = (int32*) stbi__malloc( layers * sizeof(int32) );
		                  if (*delays == null)
		                     return stbi__load_gif_main_outofmem(&g, out_, delays);
		                  delays_size = layers * sizeof(int32);
		               }
		            }
		            memcpy( &out_[((layers - 1) * stride)], u, stride );
		            if (layers >= 2) {
		               two_back = out_ - 2 * stride;
		            }

		            if (delays != null) {
		               (*delays)[layers - 1] = g.delay;
		            }
		         }
		      } while (u != null);

		      // free temp buffer;
		      STBI_FREE!(g.out_);
		      STBI_FREE!(g.history);
		      STBI_FREE!(g.background);

		      // do the final conversion after loading everything;
		      if (req_comp != 0 && req_comp != 4)
		         out_ = stbi__convert_format(out_, 4, req_comp, (.)layers * (.)g.w, (.)g.h);

		      *z = layers;
		      return out_;
		   } else {
		      return stbi__errpuc!("not GIF", "Image was not as a gif type.");
		   }
		}

		static void *stbi__gif_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   stbi_uc *u = null;
		   stbi__gif g = ?;
		   memset(&g, 0, sizeof(decltype(g)));

		   u = stbi__gif_load_next(s, &g, comp, req_comp, null);
		   if (u == (stbi_uc *) s) u = null;  // end of animated gif marker
		   if (u != null) {
		      *x = g.w;
		      *y = g.h;

		      // moved conversion to after successful load so that the same
		      // can be done for multiple frames.
		      if (req_comp != 0 && req_comp != 4)
		         u = stbi__convert_format(u, 4, req_comp, (.)g.w, (.)g.h);
		   } else if (g.out_ != null) {
		      // if there was an error and we allocated an image buffer, free it!
		      STBI_FREE!(g.out_);
		   }

		   // free buffers needed for multiple frame loading;
		   STBI_FREE!(g.history);
		   STBI_FREE!(g.background);

		   return u;
		}

		static bool stbi__gif_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   return stbi__gif_info_raw(s,x,y,comp);
		}
#endif

		// *************************************************************************************************
		// Radiance RGBE HDR loader
		// originally by Nicolas Schulz
#if !STBI_NO_HDR
		static bool stbi__hdr_test_core(stbi__context *s, char8 *signature)
		{
		   int32 i;
		   for (i=0; signature[i] != 0; ++i)
		      if (stbi__get8(s) != signature[i])
		          return false;
		   stbi__rewind(s);
		   return true;
		}

		static bool stbi__hdr_test(stbi__context* s)
		{
		   bool r = stbi__hdr_test_core(s, "#?RADIANCE\n");
		   stbi__rewind(s);
		   if(!r) {
		       r = stbi__hdr_test_core(s, "#?RGBE\n");
		       stbi__rewind(s);
		   }
		   return r;
		}

		const int STBI__HDR_BUFLEN = 1024;
		static char8 *stbi__hdr_gettoken(stbi__context *z, char8 *buffer)
		{
		   int32 len=0;
		   char8 c = '\0';

		   c = (char8) stbi__get8(z);

		   while (!stbi__at_eof(z) && c != '\n') {
		      buffer[len++] = c;
		      if (len == STBI__HDR_BUFLEN-1) {
		         // flush to end of line
		         while (!stbi__at_eof(z) && stbi__get8(z) != '\n')
		            NOP!();
		         break;
		      }
		      c = (char8) stbi__get8(z);
		   }

		   buffer[len] = 0;
		   return buffer;
		}

		static void stbi__hdr_convert(float *output, stbi_uc *input, int32 req_comp)
		{
		   if ( input[3] != 0 ) {
		      float f1;
		      // Exponent
			  //f1 = (float) ldexp(1.0f, input[3] - (int)(128 + 8));
		      f1 = (float) Math.Pow(2, (int32)input[3] - (int32)(128 + 8));
		      if (req_comp <= 2)
		         output[0] = ((int32)input[0] + input[1] + input[2]) * f1 / 3;
		      else {
		         output[0] = input[0] * f1;
		         output[1] = input[1] * f1;
		         output[2] = input[2] * f1;
		      }
		      if (req_comp == 2) output[1] = 1;
		      if (req_comp == 4) output[3] = 1;
		   } else {
		      switch (req_comp) {
		         case 4: output[3] = 1;
				  fallthrough;
		         case 3: output[0] = output[1] = output[2] = 0;
		                 break;
		         case 2: output[1] = 1;
				  fallthrough;
		         case 1: output[0] = 0;
		                 break;
		      }
		   }
		}

		// @PORT AAHHHH
		static int32 strcmp(char8* a, char8* b)
		{
			int32 sumA = 0, sumB = 0;
			while (true)
			{
				sumA += (uint8)*a;
				sumB += (uint8)*b;

				if (*a == '\0' || *b == '\0')
					return sumA - sumB;
			}
		}

		// @PORT AAAAAHHHHH
		static int32 strncmp(char8* a, char8* b, int32 n)
		{
			int32 sumA = 0, sumB = 0;
			for (int32 i = 0; i < n; i++)
			{
				sumA += (uint8)*a;
				sumB += (uint8)*b;

				if (*a == '\0' || *b == '\0')
					break;
			}
			return sumA - sumB;
		}

		// @PORT AAAAAAAHHHHHHHHH
		static int32 strtol(char8* str, char8** endptr, int32 n)
		{
			STBI_ASSERT!(n == 10);

			var str;
			while (*str != '\0')
			{
				if (!(*str).IsDigit)
					break;

				str++;
			}
			if (endptr != null)
				*endptr = str;

			let res = int32.Parse(.(@str, str - @str), .Number);
			return (res case .Err) ? -1 : res.Get();
		}

		static float *stbi__hdr_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   char8[STBI__HDR_BUFLEN] buffer;
		   char8 *token;
		   bool valid = false;
		   int32 width, height;
		   stbi_uc *scanline;
		   float *hdr_data;
		   int32 len;
		   uint8 count, value;
		   int32 i, j, k, c1,c2, z;
		   char8 *headerToken;
			var req_comp;

		   // Check identifier
		   headerToken = stbi__hdr_gettoken(s,&buffer[0]);
		   if (strcmp(headerToken, "#?RADIANCE") != 0 && strcmp(headerToken, "#?RGBE") != 0)
		      return stbi__errpf!("not HDR", "Corrupt HDR image");

		   // Parse header
		   for(;;) {
		      token = stbi__hdr_gettoken(s,&buffer[0]);
		      if (token[0] == 0) break;
		      if (strcmp(token, "FORMAT=32-bit_rle_rgbe") == 0) valid = true;
		   }

		   if (!valid)    return stbi__errpf!("unsupported format", "Unsupported HDR format");

		   // Parse width and height
		   // can't use sscanf() if we're not using stdio!
		   token = stbi__hdr_gettoken(s,&buffer[0]);
		   if (strncmp(token, "-Y ", 3) != 0)  return stbi__errpf!("unsupported data layout", "Unsupported HDR format");
		   token += 3;
		   height = (int32) strtol(token, &token, 10);
		   while (*token == ' ') ++token;
		   if (strncmp(token, "+X ", 3) != 0)  return stbi__errpf!("unsupported data layout", "Unsupported HDR format");
		   token += 3;
		   width = (int32) strtol(token, null, 10);

		   if (height > STBI_MAX_DIMENSIONS) return stbi__errpf!("too large","Very large image (corrupt?)");
		   if (width > STBI_MAX_DIMENSIONS) return stbi__errpf!("too large","Very large image (corrupt?)");

		   *x = width;
		   *y = height;

		   if (comp != null) *comp = 3;
		   if (req_comp == 0) req_comp = 3;

		   if (!stbi__mad4sizes_valid(width, height, req_comp, sizeof(float), 0))
		      return stbi__errpf!("too large", "HDR image is too large");

		   // Read data
		   hdr_data = (float *) stbi__malloc_mad4(width, height, req_comp, sizeof(float), 0);
		   if (hdr_data == null)
		      return stbi__errpf!("outofmem", "Out of memory");

		   // Load image data
		   // image data is stored as some number of sca
			IF:do {
		   if ( width < 8 || width >= 32768) {
		      // Read flat data
		      for (j=0; j < height; ++j) {
		         for (i=0; i < width; ++i) {
		            stbi_uc[4] rgbe;
		           //main_decode_loop:
		            stbi__getn(s, &rgbe[0], 4);
		            stbi__hdr_convert(&hdr_data[j * width * req_comp + i * req_comp], &rgbe[0], req_comp);
		         }
		      }
		   } else {
		      // Read RLE-encoded data
		      scanline = null;

		      for (j = 0; j < height; ++j) {
		         c1 = stbi__get8(s);
		         c2 = stbi__get8(s);
		         len = stbi__get8(s);
		         if (c1 != 2 || c2 != 2 || (len & 0x80) != 0) {
		            // not run-length encoded, so we have to actually use THIS data as a decoded
		            // pixel (note this can't be a valid pixel--one of RGB must be >= 128)
		            stbi_uc[4] rgbe;
		            rgbe[0] = (stbi_uc) c1;
		            rgbe[1] = (stbi_uc) c2;
		            rgbe[2] = (stbi_uc) len;
		            rgbe[3] = (stbi_uc) stbi__get8(s);
		            stbi__hdr_convert(hdr_data, &rgbe[0], req_comp);
		            i = 1;
		            j = 0;
		            STBI_FREE!(scanline);

		            //goto main_decode_loop; // yes, this makes no sense
					 {
						 for (j=0; j < height; ++j) {
						   for (i=0; i < width; ++i) {
						      stbi_uc[4] rgbe_;
						     //main_decode_loop:
						      stbi__getn(s, &rgbe_[0], 4);
						      stbi__hdr_convert(&hdr_data[j * width * req_comp + i * req_comp], &rgbe_[0], req_comp);
						   }
						}

						 break IF; // @PORT act as if we really jumped up there... and now exit this statement........
					}
		         }
		         len <<= 8;
		         len |= stbi__get8(s);
		         if (len != width) { STBI_FREE!(hdr_data); STBI_FREE!(scanline); return stbi__errpf!("invalid decoded scanline length", "corrupt HDR"); }
		         if (scanline == null) {
		            scanline = (stbi_uc *) stbi__malloc_mad2(width, 4, 0);
		            if (scanline == null) {
		               STBI_FREE!(hdr_data);
		               return stbi__errpf!("outofmem", "Out of memory");
		            }
		         }

		         for (k = 0; k < 4; ++k) {
		            int32 nleft;
		            i = 0;
		            while ((nleft = width - i) > 0) {
		               count = stbi__get8(s);
		               if (count > 128) {
		                  // Run
		                  value = stbi__get8(s);
		                  count = (.)((int32)count - 128);
		                  if (count > nleft) { STBI_FREE!(hdr_data); STBI_FREE!(scanline); return stbi__errpf!("corrupt", "bad RLE data in HDR"); }
		                  for (z = 0; z < count; ++z)
		                     scanline[i++ * 4 + k] = value;
		               } else {
		                  // Dump
		                  if (count > nleft) { STBI_FREE!(hdr_data); STBI_FREE!(scanline); return stbi__errpf!("corrupt", "bad RLE data in HDR"); }
		                  for (z = 0; z < count; ++z)
		                     scanline[i++ * 4 + k] = stbi__get8(s);
		               }
		            }
		         }
		         for (i=0; i < width; ++i)
		            stbi__hdr_convert(hdr_data+(j*width + i)*req_comp, scanline + i*4, req_comp);
		      }
		      if (scanline != null)
		         STBI_FREE!(scanline);
		   }} // do {

		   return hdr_data;
		}

		static bool stbi__hdr_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   char8[STBI__HDR_BUFLEN] buffer;
		   char8 *token;
		   bool valid = false;
		   int32 dummy;

			var x, y, comp;
		   if (x == null) x = &dummy;
		   if (y == null) y = &dummy;
		   if (comp == null) comp = &dummy;

		   if (!stbi__hdr_test(s)) {
		       stbi__rewind( s );
		       return false;
		   }

		   for(;;) {
		      token = stbi__hdr_gettoken(s,&buffer[0]);
		      if (token[0] == 0) break;
		      if (strcmp(token, "FORMAT=32-bit_rle_rgbe") == 0) valid = true;
		   }

		   if (!valid) {
		       stbi__rewind( s );
		       return false;
		   }
		   token = stbi__hdr_gettoken(s,&buffer[0]);
		   if (strncmp(token, "-Y ", 3) != 0) {
		       stbi__rewind( s );
		       return false;
		   }
		   token += 3;
		   *y = (int32) strtol(token, &token, 10);
		   while (*token == ' ') ++token;
		   if (strncmp(token, "+X ", 3) != 0) {
		       stbi__rewind( s );
		       return false;
		   }
		   token += 3;
		   *x = (int32) strtol(token, null, 10);
		   *comp = 3;
		   return true;
		}
#endif // STBI_NO_HDR

#if !STBI_NO_BMP
		static bool stbi__bmp_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   bool p; // @PORT: again... this was a void*, but really should be a bool
		   stbi__bmp_data info = ?;

		   info.all_a = 255;
		   p = stbi__bmp_parse_header(s, &info);
		   if (!p) {
		      stbi__rewind( s );
		      return false;
		   }
		   if (x != null) *x = (.)s.img_x;
		   if (y != null) *y = (.)s.img_y;
		   if (comp != null) {
		      if (info.bpp == 24 && info.ma == 0xff000000)
		         *comp = 3;
		      else
		         *comp = info.ma != 0 ? 4 : 3;
		   }
		   return true;
		}
#endif

#if !STBI_NO_PSD
		static bool stbi__psd_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   int32 channelCount, dummy, depth;
			var x, y, comp;
		   if (x == null) x = &dummy;
		   if (y == null) y = &dummy;
		   if (comp == null) comp = &dummy;
		   if (stbi__get32be(s) != 0x38425053) {
		       stbi__rewind( s );
		       return false;
		   }
		   if (stbi__get16be(s) != 1) {
		       stbi__rewind( s );
		       return false;
		   }
		   stbi__skip(s, 6);
		   channelCount = stbi__get16be(s);
		   if (channelCount < 0 || channelCount > 16) {
		       stbi__rewind( s );
		       return false;
		   }
		   *y = (.)stbi__get32be(s);
		   *x = (.)stbi__get32be(s);
		   depth = stbi__get16be(s);
		   if (depth != 8 && depth != 16) {
		       stbi__rewind( s );
		       return false;
		   }
		   if (stbi__get16be(s) != 3) {
		       stbi__rewind( s );
		       return false;
		   }
		   *comp = 4;
		   return true;
		}

		static bool stbi__psd_is16(stbi__context *s)
		{
		   int32 channelCount, depth;
		   if (stbi__get32be(s) != 0x38425053) {
		       stbi__rewind( s );
		       return false;
		   }
		   if (stbi__get16be(s) != 1) {
		       stbi__rewind( s );
		       return false;
		   }
		   stbi__skip(s, 6);
		   channelCount = stbi__get16be(s);
		   if (channelCount < 0 || channelCount > 16) {
		       stbi__rewind( s );
		       return false;
		   }
		   stbi__get32be(s);
		   stbi__get32be(s);
		   depth = stbi__get16be(s);
		   if (depth != 16) {
		       stbi__rewind( s );
		       return false;
		   }
		   return true;
		}
#endif

#if !STBI_NO_PIC
		static bool stbi__pic_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   int32 act_comp=0,num_packets=0,chained,dummy;
		   stbi__pic_packet[10] packets;

			var x, y, comp;
		   if (x == null) x = &dummy;
		   if (y == null) y = &dummy;
		   if (comp == null) comp = &dummy;

		   if (!stbi__pic_is4(s,"\x53\x80\xF6\x34")) {
		      stbi__rewind(s);
		      return false;
		   }

		   stbi__skip(s, 88);

		   *x = stbi__get16be(s);
		   *y = stbi__get16be(s);
		   if (stbi__at_eof(s)) {
		      stbi__rewind( s);
		      return false;
		   }
		   if ( (*x) != 0 && (1 << 28) / (*x) < (*y)) {
		      stbi__rewind( s );
		      return false;
		   }

		   stbi__skip(s, 8);

		   repeat {
		      stbi__pic_packet *packet;

		      if (num_packets==sizeof(decltype(packets))/sizeof(decltype(packets[0])))
		         return false;

		      packet = &packets[num_packets++];
		      chained = stbi__get8(s);
		      packet.size    = stbi__get8(s);
		      packet.type    = stbi__get8(s);
		      packet.channel = stbi__get8(s);
		      act_comp |= packet.channel;

		      if (stbi__at_eof(s)) {
		          stbi__rewind( s );
		          return false;
		      }
		      if (packet.size != 8) {
		          stbi__rewind( s );
		          return false;
		      }
		   } while (chained != 0);

		   *comp = ((act_comp & 0x10) != 0 ? 4 : 3);

		   return true;
		}
#endif

		// *************************************************************************************************
		// Portable Gray Map and Portable Pixel Map loader
		// by Ken Miller
		//
		// PGM: http://netpbm.sourceforge.net/doc/pgm.html
		// PPM: http://netpbm.sourceforge.net/doc/ppm.html
		//
		// Known limitations:
		//    Does not support comments in the header section
		//    Does not support ASCII image data (formats P2 and P3)

#if !STBI_NO_PNM

		static bool      stbi__pnm_test(stbi__context *s)
		{
		   uint8 p, t;
		   p = stbi__get8(s);
		   t = stbi__get8(s);
		   if (p != 'P' || (t != '5' && t != '6')) {
		       stbi__rewind( s );
		       return false;
		   }
		   return true;
		}

		static void *stbi__pnm_load(stbi__context *s, int32 *x, int32 *y, int32 *comp, int32 req_comp, stbi__result_info *ri)
		{
		   stbi_uc *out_;

		   ri.bits_per_channel = stbi__pnm_info(s, (int32 *)&s.img_x, (int32 *)&s.img_y, (int32 *)&s.img_n);
		   if (ri.bits_per_channel == 0)
		      return null;

		   if (s.img_y > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");
		   if (s.img_x > STBI_MAX_DIMENSIONS) return stbi__errpuc!("too large","Very large image (corrupt?)");

		   *x = (.)s.img_x;
		   *y = (.)s.img_y;
		   if (comp != null) *comp = s.img_n;

		   if (!stbi__mad4sizes_valid(s.img_n, (.)s.img_x, (.)s.img_y, ri.bits_per_channel / 8, 0))
		      return stbi__errpuc!("too large", "PNM too large");

		   out_ = (stbi_uc *) stbi__malloc_mad4(s.img_n, (.)s.img_x, (.)s.img_y, ri.bits_per_channel / 8, 0);
		   if (out_ == null) return stbi__errpuc!("outofmem", "Out of memory");
		   stbi__getn(s, out_, s.img_n * (.)s.img_x * (.)s.img_y * (ri.bits_per_channel / 8));

		   if (req_comp != 0 && req_comp != s.img_n) {
		      out_ = stbi__convert_format(out_, s.img_n, req_comp, s.img_x, s.img_y);
		      if (out_ == null) return out_; // stbi__convert_format frees input on failure
		   }
		   return out_;
		}

		static bool      stbi__pnm_isspace(char8 c)
		{
		   return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
		}

		static void     stbi__pnm_skip_whitespace(stbi__context *s, char8 *c)
		{
		   for (;;) {
		      while (!stbi__at_eof(s) && stbi__pnm_isspace(*c))
		         *c = (char8) stbi__get8(s);

		      if (stbi__at_eof(s) || *c != '#')
		         break;

		      while (!stbi__at_eof(s) && *c != '\n' && *c != '\r' )
		         *c = (char8) stbi__get8(s);
		   }
		}

		static bool      stbi__pnm_isdigit(char8 c)
		{
		   return c >= '0' && c <= '9';
		}

		static int32      stbi__pnm_getinteger(stbi__context *s, char8 *c)
		{
		   int32 value = 0;

		   while (!stbi__at_eof(s) && stbi__pnm_isdigit(*c)) {
		      value = value*10 + (*c - '0');
		      *c = (char8) stbi__get8(s);
		   }

		   return value;
		}

		static int32      stbi__pnm_info(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   int32 maxv, dummy;
		   char8 c, p, t;

			var x, y, comp;
		   if (x == null) x = &dummy;
		   if (y == null) y = &dummy;
		   if (comp == null) comp = &dummy;

		   stbi__rewind(s);

		   // Get identifier
		   p = (char8) stbi__get8(s);
		   t = (char8) stbi__get8(s);
		   if (p != 'P' || (t != '5' && t != '6')) {
		       stbi__rewind(s);
		       return 0;
		   }

		   *comp = (t == '6') ? 3 : 1;  // '5' is 1-component .pgm; '6' is 3-component .ppm

		   c = (char8) stbi__get8(s);
		   stbi__pnm_skip_whitespace(s, &c);

		   *x = stbi__pnm_getinteger(s, &c); // read width
		   stbi__pnm_skip_whitespace(s, &c);

		   *y = stbi__pnm_getinteger(s, &c); // read height
		   stbi__pnm_skip_whitespace(s, &c);

		   maxv = stbi__pnm_getinteger(s, &c);  // read max value
		   if (maxv > 65535)
		    {
				stbi__err!("max value > 65535", "PPM image supports only 8-bit and 16-bit images");
				return 0;
			}  
		   else if (maxv > 255)
		      return 16;
		   else
		      return 8;
		}

		static bool stbi__pnm_is16(stbi__context *s)
		{
		   if (stbi__pnm_info(s, null, null, null) == 16)
			   return true;
		   return false;
		}
#endif

		static bool stbi__info_main(stbi__context *s, int32 *x, int32 *y, int32 *comp)
		{
		   #if !STBI_NO_JPEG
		   if (stbi__jpeg_info(s, x, y, comp)) return true;
		   #endif

		   #if !STBI_NO_PNG
		   if (stbi__png_info(s, x, y, comp))  return true;
		   #endif

		   #if !STBI_NO_GIF
		   if (stbi__gif_info(s, x, y, comp))  return true;
		   #endif

		   #if !STBI_NO_BMP
		   if (stbi__bmp_info(s, x, y, comp))  return true;
		   #endif

		   #if !STBI_NO_PSD
		   if (stbi__psd_info(s, x, y, comp))  return true;
		   #endif

		   #if !STBI_NO_PIC
		   if (stbi__pic_info(s, x, y, comp))  return true;
		   #endif

		   #if !STBI_NO_PNM
		   if (stbi__pnm_info(s, x, y, comp) != 0)  return true;
		   #endif

		   #if !STBI_NO_HDR
		   if (stbi__hdr_info(s, x, y, comp))  return true;
		   #endif

		   // test tga last because it's a crappy test!
		   #if !STBI_NO_TGA
		   if (stbi__tga_info(s, x, y, comp))
		       return true;
		   #endif
		   return stbi__err!("unknown image type", "Image not of any known type, or corrupt");
		}

		static bool stbi__is_16_main(stbi__context *s)
		{
		   #if !STBI_NO_PNG
		   if (stbi__png_is16(s))  return true;
		   #endif

		   #if !STBI_NO_PSD
		   if (stbi__psd_is16(s))  return true;
		   #endif

		   #if !STBI_NO_PNM
		   if (stbi__pnm_is16(s))  return true;
		   #endif
		   return false;
		}

		public static bool stbi_info_from_memory(stbi_uc *buffer, int32 len, int32 *x, int32 *y, int32 *comp)
		{
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__info_main(&s,x,y,comp);
		}

		public static bool stbi_info_from_callbacks(stbi_io_callbacks *c, void *user, int32 *x, int32 *y, int32 *comp)
		{
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *) c, user);
		   return stbi__info_main(&s,x,y,comp);
		}

		public static bool stbi_is_16_bit_from_memory(stbi_uc *buffer, int32 len)
		{
		   stbi__context s;
		   stbi__start_mem(&s,buffer,len);
		   return stbi__is_16_main(&s);
		}

		public static bool stbi_is_16_bit_from_callbacks(stbi_io_callbacks *c, void *user)
		{
		   stbi__context s;
		   stbi__start_callbacks(&s, (stbi_io_callbacks *) c, user);
		   return stbi__is_16_main(&s);
		}
	}
}

/*
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (www.unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------
*/