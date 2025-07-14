//
// This file was auto-generated using the following command:
//
// jai generate.jai
//



MAX_MEM_LEVEL :: 9;

MAX_WBITS :: 15;

SEEK_SET :: 0;
SEEK_CUR :: 1;
SEEK_END :: 2;

ZLIB_VERSION :: "1.2.5";
ZLIB_VERNUM :: 0x1250;
ZLIB_VER_MAJOR :: 1;
ZLIB_VER_MINOR :: 2;
ZLIB_VER_REVISION :: 5;
ZLIB_VER_SUBREVISION :: 0;

Z_NO_FLUSH :: 0;
Z_PARTIAL_FLUSH :: 1;
Z_SYNC_FLUSH :: 2;
Z_FULL_FLUSH :: 3;
Z_FINISH :: 4;
Z_BLOCK :: 5;
Z_TREES :: 6;

Z_OK :: 0;
Z_STREAM_END :: 1;
Z_NEED_DICT :: 2;
Z_ERRNO :: -1;
Z_STREAM_ERROR :: -2;
Z_DATA_ERROR :: -3;
Z_MEM_ERROR :: -4;
Z_BUF_ERROR :: -5;
Z_VERSION_ERROR :: -6;

Z_NO_COMPRESSION :: 0;
Z_BEST_SPEED :: 1;
Z_BEST_COMPRESSION :: 9;
Z_DEFAULT_COMPRESSION :: -1;

Z_FILTERED :: 1;
Z_HUFFMAN_ONLY :: 2;
Z_RLE :: 3;
Z_FIXED :: 4;
Z_DEFAULT_STRATEGY :: 0;

Z_BINARY :: 0;
Z_TEXT :: 1;
Z_ASCII :: Z_TEXT;
Z_UNKNOWN :: 2;

Z_DEFLATED :: 8;

Z_NULL :: 0;

DEF_WBITS :: MAX_WBITS;

DEF_MEM_LEVEL :: 8;

STORED_BLOCK :: 0;
STATIC_TREES :: 1;
DYN_TREES :: 2;

MIN_MATCH :: 3;
MAX_MATCH :: 258;

PRESET_DICT :: 0x20;

OS_CODE :: 0x0b;

GZBUFSIZE :: 8192;

GZ_NONE :: 0;
GZ_READ :: 7247;
GZ_WRITE :: 31153;
GZ_APPEND :: 1;

LOOK :: 0;
COPY :: 1;
GZIP :: 2;

Byte :: u8;

uInt :: u32;
uLong :: u32;

Bytef :: Byte;

charf :: u8;
intf :: s32;
uIntf :: uInt;
uLongf :: uLong;

voidpc :: *void;
voidpf :: *void;
voidp :: *void;

/*
The 'zlib' compression library provides in-memory compression and
decompression functions, including integrity checks of the uncompressed data.
This version of the library supports only one compression method (deflation)
but other algorithms will be added later and will have the same stream
interface.

Compression can be done in a single step if the buffers are large enough,
or can be done by repeated calls of the compression function.  In the latter
case, the application must provide more input and/or consume the output
(providing more output space) before each call.

The compressed data format used by default by the in-memory functions is
the zlib format, which is a zlib wrapper documented in RFC 1950, wrapped
around a deflate stream, which is itself documented in RFC 1951.

The library also supports reading and writing files in gzip (.gz) format
with an interface similar to that of stdio using the functions that start
with "gz".  The gzip format is different from the zlib format.  gzip is a
gzip wrapper, documented in RFC 1952, wrapped around a deflate stream.

This library can optionally read and write gzip streams in memory as well.

The zlib format was designed to be compact and fast for use in memory
and on communications channels.  The gzip format was designed for single-
file compression on file systems, has a larger header than zlib to maintain
directory information, and uses a different, slower check method than zlib.

The library does not install any signal handler.  The decoder checks
the consistency of the compressed data, so the library should never crash
even in case of corrupted input.
*/
alloc_func :: #type (opaque: voidpf, items: uInt, size: uInt) -> voidpf #c_call;
free_func :: #type (opaque: voidpf, address: voidpf) -> void #c_call;

z_stream_s :: struct {
    next_in:   *Bytef; /* next input byte */
    avail_in:  uInt; /* number of bytes available at next_in */
    total_in:  uLong; /* total nb of input bytes read so far */

    next_out:  *Bytef; /* next output byte should be put there */
    avail_out: uInt; /* remaining free space at next_out */
    total_out: uLong; /* total nb of bytes output so far */

    msg:       *u8; /* last error message, NULL if no error */
    state:     *internal_state; /* not visible by applications */

    zalloc:    alloc_func; /* used to allocate the internal state */
    zfree:     free_func; /* used to free the internal state */
    opaque:    voidpf; /* private data object passed to zalloc and zfree */

    data_type: s32; /* best guess about the data type: binary or text */
    adler:     uLong; /* adler32 value of the uncompressed data */
    reserved:  uLong; /* reserved for future use */
}

z_stream :: z_stream_s;

z_streamp :: *z_stream;

/*
gzip header information passed to and from zlib routines.  See RFC 1952
for more details on the meanings of these fields.
*/
gz_header_s :: struct {
    text:      s32; /* true if compressed data believed to be text */
    time:      uLong; /* modification time */
    xflags:    s32; /* extra flags (not used when writing a gzip file) */
    os:        s32; /* operating system */
    extra:     *Bytef; /* pointer to extra field or Z_NULL if none */
    extra_len: uInt; /* extra field length (valid if extra != Z_NULL) */
    extra_max: uInt; /* space at extra (only when reading header) */
    name:      *Bytef; /* pointer to zero-terminated file name or Z_NULL */
    name_max:  uInt; /* space at name (only when reading header) */
    comment:   *Bytef; /* pointer to zero-terminated comment or Z_NULL */
    comm_max:  uInt; /* space at comment (only when reading header) */
    hcrc:      s32; /* true if there was or will be a header crc */
    /* true when done reading gzip header (not used
    when writing a gzip file) */
    done:      s32;
}

/*
gzip header information passed to and from zlib routines.  See RFC 1952
for more details on the meanings of these fields.
*/
gz_header :: gz_header_s;

gz_headerp :: *gz_header;

/* basic functions */
zlibVersion :: () -> *u8 #foreign zlib;

/*
ZEXTERN int ZEXPORT deflateInit OF((z_streamp strm, int level));

Initializes the internal stream state for compression.  The fields
zalloc, zfree and opaque must be initialized before by the caller.  If
zalloc and zfree are set to Z_NULL, deflateInit updates them to use default
allocation functions.

The compression level must be Z_DEFAULT_COMPRESSION, or between 0 and 9:
1 gives best speed, 9 gives best compression, 0 gives no compression at all
(the input data is simply copied a block at a time).  Z_DEFAULT_COMPRESSION
requests a default compromise between speed and compression (currently
equivalent to level 6).

deflateInit returns Z_OK if success, Z_MEM_ERROR if there was not enough
memory, Z_STREAM_ERROR if level is not a valid compression level, or
Z_VERSION_ERROR if the zlib library version (zlib_version) is incompatible
with the version assumed by the caller (ZLIB_VERSION).  msg is set to null
if there is no error message.  deflateInit does not perform any compression:
this will be done by deflate().
*/
deflate :: (strm: z_streamp, flush: s32) -> s32 #foreign zlib;

/*
deflate compresses as much data as possible, and stops when the input
buffer becomes empty or the output buffer becomes full.  It may introduce
some output latency (reading input without producing any output) except when
forced to flush.

The detailed semantics are as follows.  deflate performs one or both of the
following actions:

- Compress more input starting at next_in and update next_in and avail_in
accordingly.  If not all input can be processed (because there is not
enough room in the output buffer), next_in and avail_in are updated and
processing will resume at this point for the next call of deflate().

- Provide more output starting at next_out and update next_out and avail_out
accordingly.  This action is forced if the parameter flush is non zero.
Forcing flush frequently degrades the compression ratio, so this parameter
should be set only when necessary (in interactive applications).  Some
output may be provided even if flush is not set.

Before the call of deflate(), the application should ensure that at least
one of the actions is possible, by providing more input and/or consuming more
output, and updating avail_in or avail_out accordingly; avail_out should
never be zero before the call.  The application can consume the compressed
output when it wants, for example when the output buffer is full (avail_out
== 0), or after each call of deflate().  If deflate returns Z_OK and with
zero avail_out, it must be called again after making room in the output
buffer because there might be more output pending.

Normally the parameter flush is set to Z_NO_FLUSH, which allows deflate to
decide how much data to accumulate before producing output, in order to
maximize compression.

If the parameter flush is set to Z_SYNC_FLUSH, all pending output is
flushed to the output buffer and the output is aligned on a byte boundary, so
that the decompressor can get all input data available so far.  (In
particular avail_in is zero after the call if enough output space has been
provided before the call.) Flushing may degrade compression for some
compression algorithms and so it should be used only when necessary.  This
completes the current deflate block and follows it with an empty stored block
that is three bits plus filler bits to the next byte, followed by four bytes
(00 00 ff ff).

If flush is set to Z_PARTIAL_FLUSH, all pending output is flushed to the
output buffer, but the output is not aligned to a byte boundary.  All of the
input data so far will be available to the decompressor, as for Z_SYNC_FLUSH.
This completes the current deflate block and follows it with an empty fixed
codes block that is 10 bits long.  This assures that enough bytes are output
in order for the decompressor to finish the block before the empty fixed code
block.

If flush is set to Z_BLOCK, a deflate block is completed and emitted, as
for Z_SYNC_FLUSH, but the output is not aligned on a byte boundary, and up to
seven bits of the current block are held to be written as the next byte after
the next deflate block is completed.  In this case, the decompressor may not
be provided enough bits at this point in order to complete decompression of
the data provided so far to the compressor.  It may need to wait for the next
block to be emitted.  This is for advanced applications that need to control
the emission of deflate blocks.

If flush is set to Z_FULL_FLUSH, all output is flushed as with
Z_SYNC_FLUSH, and the compression state is reset so that decompression can
restart from this point if previous compressed data has been damaged or if
random access is desired.  Using Z_FULL_FLUSH too often can seriously degrade
compression.

If deflate returns with avail_out == 0, this function must be called again
with the same value of the flush parameter and more output space (updated
avail_out), until the flush is complete (deflate returns with non-zero
avail_out).  In the case of a Z_FULL_FLUSH or Z_SYNC_FLUSH, make sure that
avail_out is greater than six to avoid repeated flush markers due to
avail_out == 0 on return.

If the parameter flush is set to Z_FINISH, pending input is processed,
pending output is flushed and deflate returns with Z_STREAM_END if there was
enough output space; if deflate returns with Z_OK, this function must be
called again with Z_FINISH and more output space (updated avail_out) but no
more input data, until it returns with Z_STREAM_END or an error.  After
deflate has returned Z_STREAM_END, the only possible operations on the stream
are deflateReset or deflateEnd.

Z_FINISH can be used immediately after deflateInit if all the compression
is to be done in a single step.  In this case, avail_out must be at least the
value returned by deflateBound (see below).  If deflate does not return
Z_STREAM_END, then it must be called again as described above.

deflate() sets strm->adler to the adler32 checksum of all input read
so far (that is, total_in bytes).

deflate() may update strm->data_type if it can make a good guess about
the input data type (Z_BINARY or Z_TEXT).  In doubt, the data is considered
binary.  This field is only for information purposes and does not affect the
compression algorithm in any manner.

deflate() returns Z_OK if some progress has been made (more input
processed or more output produced), Z_STREAM_END if all input has been
consumed and all output has been produced (only when flush is set to
Z_FINISH), Z_STREAM_ERROR if the stream state was inconsistent (for example
if next_in or next_out was Z_NULL), Z_BUF_ERROR if no progress is possible
(for example avail_in or avail_out was zero).  Note that Z_BUF_ERROR is not
fatal, and deflate() can be called again with more input and more output
space to continue compressing.
*/
deflateEnd :: (strm: z_streamp) -> s32 #foreign zlib;

/*
ZEXTERN int ZEXPORT inflateInit OF((z_streamp strm));

Initializes the internal stream state for decompression.  The fields
next_in, avail_in, zalloc, zfree and opaque must be initialized before by
the caller.  If next_in is not Z_NULL and avail_in is large enough (the
exact value depends on the compression method), inflateInit determines the
compression method from the zlib header and allocates all data structures
accordingly; otherwise the allocation will be deferred to the first call of
inflate.  If zalloc and zfree are set to Z_NULL, inflateInit updates them to
use default allocation functions.

inflateInit returns Z_OK if success, Z_MEM_ERROR if there was not enough
memory, Z_VERSION_ERROR if the zlib library version is incompatible with the
version assumed by the caller, or Z_STREAM_ERROR if the parameters are
invalid, such as a null pointer to the structure.  msg is set to null if
there is no error message.  inflateInit does not perform any decompression
apart from possibly reading the zlib header if present: actual decompression
will be done by inflate().  (So next_in and avail_in may be modified, but
next_out and avail_out are unused and unchanged.) The current implementation
of inflateInit() does not process any header information -- that is deferred
until inflate() is called.
*/
inflate :: (strm: z_streamp, flush: s32) -> s32 #foreign zlib;

/*
inflate decompresses as much data as possible, and stops when the input
buffer becomes empty or the output buffer becomes full.  It may introduce
some output latency (reading input without producing any output) except when
forced to flush.

The detailed semantics are as follows.  inflate performs one or both of the
following actions:

- Decompress more input starting at next_in and update next_in and avail_in
accordingly.  If not all input can be processed (because there is not
enough room in the output buffer), next_in is updated and processing will
resume at this point for the next call of inflate().

- Provide more output starting at next_out and update next_out and avail_out
accordingly.  inflate() provides as much output as possible, until there is
no more input data or no more space in the output buffer (see below about
the flush parameter).

Before the call of inflate(), the application should ensure that at least
one of the actions is possible, by providing more input and/or consuming more
output, and updating the next_* and avail_* values accordingly.  The
application can consume the uncompressed output when it wants, for example
when the output buffer is full (avail_out == 0), or after each call of
inflate().  If inflate returns Z_OK and with zero avail_out, it must be
called again after making room in the output buffer because there might be
more output pending.

The flush parameter of inflate() can be Z_NO_FLUSH, Z_SYNC_FLUSH, Z_FINISH,
Z_BLOCK, or Z_TREES.  Z_SYNC_FLUSH requests that inflate() flush as much
output as possible to the output buffer.  Z_BLOCK requests that inflate()
stop if and when it gets to the next deflate block boundary.  When decoding
the zlib or gzip format, this will cause inflate() to return immediately
after the header and before the first block.  When doing a raw inflate,
inflate() will go ahead and process the first block, and will return when it
gets to the end of that block, or when it runs out of data.

The Z_BLOCK option assists in appending to or combining deflate streams.
Also to assist in this, on return inflate() will set strm->data_type to the
number of unused bits in the last byte taken from strm->next_in, plus 64 if
inflate() is currently decoding the last block in the deflate stream, plus
128 if inflate() returned immediately after decoding an end-of-block code or
decoding the complete header up to just before the first byte of the deflate
stream.  The end-of-block will not be indicated until all of the uncompressed
data from that block has been written to strm->next_out.  The number of
unused bits may in general be greater than seven, except when bit 7 of
data_type is set, in which case the number of unused bits will be less than
eight.  data_type is set as noted here every time inflate() returns for all
flush options, and so can be used to determine the amount of currently
consumed input in bits.

The Z_TREES option behaves as Z_BLOCK does, but it also returns when the
end of each deflate block header is reached, before any actual data in that
block is decoded.  This allows the caller to determine the length of the
deflate block header for later use in random access within a deflate block.
256 is added to the value of strm->data_type when inflate() returns
immediately after reaching the end of the deflate block header.

inflate() should normally be called until it returns Z_STREAM_END or an
error.  However if all decompression is to be performed in a single step (a
single call of inflate), the parameter flush should be set to Z_FINISH.  In
this case all pending input is processed and all pending output is flushed;
avail_out must be large enough to hold all the uncompressed data.  (The size
of the uncompressed data may have been saved by the compressor for this
purpose.) The next operation on this stream must be inflateEnd to deallocate
the decompression state.  The use of Z_FINISH is never required, but can be
used to inform inflate that a faster approach may be used for the single
inflate() call.

In this implementation, inflate() always flushes as much output as
possible to the output buffer, and always uses the faster approach on the
first call.  So the only effect of the flush parameter in this implementation
is on the return value of inflate(), as noted below, or when it returns early
because Z_BLOCK or Z_TREES is used.

If a preset dictionary is needed after this call (see inflateSetDictionary
below), inflate sets strm->adler to the adler32 checksum of the dictionary
chosen by the compressor and returns Z_NEED_DICT; otherwise it sets
strm->adler to the adler32 checksum of all output produced so far (that is,
total_out bytes) and returns Z_OK, Z_STREAM_END or an error code as described
below.  At the end of the stream, inflate() checks that its computed adler32
checksum is equal to that saved by the compressor and returns Z_STREAM_END
only if the checksum is correct.

inflate() can decompress and check either zlib-wrapped or gzip-wrapped
deflate data.  The header type is detected automatically, if requested when
initializing with inflateInit2().  Any information contained in the gzip
header is not retained, so applications that need that information should
instead use raw inflate, see inflateInit2() below, or inflateBack() and
perform their own processing of the gzip header and trailer.

inflate() returns Z_OK if some progress has been made (more input processed
or more output produced), Z_STREAM_END if the end of the compressed data has
been reached and all uncompressed output has been produced, Z_NEED_DICT if a
preset dictionary is needed at this point, Z_DATA_ERROR if the input data was
corrupted (input stream not conforming to the zlib format or incorrect check
value), Z_STREAM_ERROR if the stream structure was inconsistent (for example
next_in or next_out was Z_NULL), Z_MEM_ERROR if there was not enough memory,
Z_BUF_ERROR if no progress is possible or if there was not enough room in the
output buffer when Z_FINISH is used.  Note that Z_BUF_ERROR is not fatal, and
inflate() can be called again with more input and more output space to
continue decompressing.  If Z_DATA_ERROR is returned, the application may
then call inflateSync() to look for a good compression block if a partial
recovery of the data is desired.
*/
inflateEnd :: (strm: z_streamp) -> s32 #foreign zlib;

/*
ZEXTERN int ZEXPORT deflateInit2 OF((z_streamp strm,
int  level,
int  method,
int  windowBits,
int  memLevel,
int  strategy));

This is another version of deflateInit with more compression options.  The
fields next_in, zalloc, zfree and opaque must be initialized before by the
caller.

The method parameter is the compression method.  It must be Z_DEFLATED in
this version of the library.

The windowBits parameter is the base two logarithm of the window size
(the size of the history buffer).  It should be in the range 8..15 for this
version of the library.  Larger values of this parameter result in better
compression at the expense of memory usage.  The default value is 15 if
deflateInit is used instead.

windowBits can also be -8..-15 for raw deflate.  In this case, -windowBits
determines the window size.  deflate() will then generate raw deflate data
with no zlib header or trailer, and will not compute an adler32 check value.

windowBits can also be greater than 15 for optional gzip encoding.  Add
16 to windowBits to write a simple gzip header and trailer around the
compressed data instead of a zlib wrapper.  The gzip header will have no
file name, no extra data, no comment, no modification time (set to zero), no
header crc, and the operating system will be set to 255 (unknown).  If a
gzip stream is being written, strm->adler is a crc32 instead of an adler32.

The memLevel parameter specifies how much memory should be allocated
for the internal compression state.  memLevel=1 uses minimum memory but is
slow and reduces compression ratio; memLevel=9 uses maximum memory for
optimal speed.  The default value is 8.  See zconf.h for total memory usage
as a function of windowBits and memLevel.

The strategy parameter is used to tune the compression algorithm.  Use the
value Z_DEFAULT_STRATEGY for normal data, Z_FILTERED for data produced by a
filter (or predictor), Z_HUFFMAN_ONLY to force Huffman encoding only (no
string match), or Z_RLE to limit match distances to one (run-length
encoding).  Filtered data consists mostly of small values with a somewhat
random distribution.  In this case, the compression algorithm is tuned to
compress them better.  The effect of Z_FILTERED is to force more Huffman
coding and less string matching; it is somewhat intermediate between
Z_DEFAULT_STRATEGY and Z_HUFFMAN_ONLY.  Z_RLE is designed to be almost as
fast as Z_HUFFMAN_ONLY, but give better compression for PNG image data.  The
strategy parameter only affects the compression ratio but not the
correctness of the compressed output even if it is not set appropriately.
Z_FIXED prevents the use of dynamic Huffman codes, allowing for a simpler
decoder for special applications.

deflateInit2 returns Z_OK if success, Z_MEM_ERROR if there was not enough
memory, Z_STREAM_ERROR if any parameter is invalid (such as an invalid
method), or Z_VERSION_ERROR if the zlib library version (zlib_version) is
incompatible with the version assumed by the caller (ZLIB_VERSION).  msg is
set to null if there is no error message.  deflateInit2 does not perform any
compression: this will be done by deflate().
*/
deflateSetDictionary :: (strm: z_streamp, dictionary: *Bytef, dictLength: uInt) -> s32 #foreign zlib;

/*
Initializes the compression dictionary from the given byte sequence
without producing any compressed output.  This function must be called
immediately after deflateInit, deflateInit2 or deflateReset, before any call
of deflate.  The compressor and decompressor must use exactly the same
dictionary (see inflateSetDictionary).

The dictionary should consist of strings (byte sequences) that are likely
to be encountered later in the data to be compressed, with the most commonly
used strings preferably put towards the end of the dictionary.  Using a
dictionary is most useful when the data to be compressed is short and can be
predicted with good accuracy; the data can then be compressed better than
with the default empty dictionary.

Depending on the size of the compression data structures selected by
deflateInit or deflateInit2, a part of the dictionary may in effect be
discarded, for example if the dictionary is larger than the window size
provided in deflateInit or deflateInit2.  Thus the strings most likely to be
useful should be put at the end of the dictionary, not at the front.  In
addition, the current implementation of deflate will use at most the window
size minus 262 bytes of the provided dictionary.

Upon return of this function, strm->adler is set to the adler32 value
of the dictionary; the decompressor may later use this value to determine
which dictionary has been used by the compressor.  (The adler32 value
applies to the whole dictionary even if only a subset of the dictionary is
actually used by the compressor.) If a raw deflate was requested, then the
adler32 value is not computed and strm->adler is not set.

deflateSetDictionary returns Z_OK if success, or Z_STREAM_ERROR if a
parameter is invalid (e.g.  dictionary being Z_NULL) or the stream state is
inconsistent (for example if deflate has already been called for this stream
or if the compression method is bsort).  deflateSetDictionary does not
perform any compression: this will be done by deflate().
*/
deflateCopy :: (dest: z_streamp, source: z_streamp) -> s32 #foreign zlib;

/*
Sets the destination stream as a complete copy of the source stream.

This function can be useful when several compression strategies will be
tried, for example when there are several ways of pre-processing the input
data with a filter.  The streams that will be discarded should then be freed
by calling deflateEnd.  Note that deflateCopy duplicates the internal
compression state which can be quite large, so this strategy is slow and can
consume lots of memory.

deflateCopy returns Z_OK if success, Z_MEM_ERROR if there was not
enough memory, Z_STREAM_ERROR if the source stream state was inconsistent
(such as zalloc being Z_NULL).  msg is left unchanged in both source and
destination.
*/
deflateReset :: (strm: z_streamp) -> s32 #foreign zlib;

/*
This function is equivalent to deflateEnd followed by deflateInit,
but does not free and reallocate all the internal compression state.  The
stream will keep the same compression level and any other attributes that
may have been set by deflateInit2.

deflateReset returns Z_OK if success, or Z_STREAM_ERROR if the source
stream state was inconsistent (such as zalloc or state being Z_NULL).
*/
deflateParams :: (strm: z_streamp, level: s32, strategy: s32) -> s32 #foreign zlib;

/*
Dynamically update the compression level and compression strategy.  The
interpretation of level and strategy is as in deflateInit2.  This can be
used to switch between compression and straight copy of the input data, or
to switch to a different kind of input data requiring a different strategy.
If the compression level is changed, the input available so far is
compressed with the old level (and may be flushed); the new level will take
effect only at the next call of deflate().

Before the call of deflateParams, the stream state must be set as for
a call of deflate(), since the currently available input may have to be
compressed and flushed.  In particular, strm->avail_out must be non-zero.

deflateParams returns Z_OK if success, Z_STREAM_ERROR if the source
stream state was inconsistent or if a parameter was invalid, Z_BUF_ERROR if
strm->avail_out was zero.
*/
deflateTune :: (strm: z_streamp, good_length: s32, max_lazy: s32, nice_length: s32, max_chain: s32) -> s32 #foreign zlib;

/*
Fine tune deflate's internal compression parameters.  This should only be
used by someone who understands the algorithm used by zlib's deflate for
searching for the best matching string, and even then only by the most
fanatic optimizer trying to squeeze out the last compressed bit for their
specific input data.  Read the deflate.c source code for the meaning of the
max_lazy, good_length, nice_length, and max_chain parameters.

deflateTune() can be called after deflateInit() or deflateInit2(), and
returns Z_OK on success, or Z_STREAM_ERROR for an invalid deflate stream.
*/
deflateBound :: (strm: z_streamp, sourceLen: uLong) -> uLong #foreign zlib;

/*
deflateBound() returns an upper bound on the compressed size after
deflation of sourceLen bytes.  It must be called after deflateInit() or
deflateInit2(), and after deflateSetHeader(), if used.  This would be used
to allocate an output buffer for deflation in a single pass, and so would be
called before deflate().
*/
deflatePrime :: (strm: z_streamp, bits: s32, value: s32) -> s32 #foreign zlib;

/*
deflatePrime() inserts bits in the deflate output stream.  The intent
is that this function is used to start off the deflate output with the bits
leftover from a previous deflate stream when appending to it.  As such, this
function can only be used for raw deflate, and must be used before the first
deflate() call after a deflateInit2() or deflateReset().  bits must be less
than or equal to 16, and that many of the least significant bits of value
will be inserted in the output.

deflatePrime returns Z_OK if success, or Z_STREAM_ERROR if the source
stream state was inconsistent.
*/
deflateSetHeader :: (strm: z_streamp, head: gz_headerp) -> s32 #foreign zlib;

/*
ZEXTERN int ZEXPORT inflateInit2 OF((z_streamp strm,
int  windowBits));

This is another version of inflateInit with an extra parameter.  The
fields next_in, avail_in, zalloc, zfree and opaque must be initialized
before by the caller.

The windowBits parameter is the base two logarithm of the maximum window
size (the size of the history buffer).  It should be in the range 8..15 for
this version of the library.  The default value is 15 if inflateInit is used
instead.  windowBits must be greater than or equal to the windowBits value
provided to deflateInit2() while compressing, or it must be equal to 15 if
deflateInit2() was not used.  If a compressed stream with a larger window
size is given as input, inflate() will return with the error code
Z_DATA_ERROR instead of trying to allocate a larger window.

windowBits can also be zero to request that inflate use the window size in
the zlib header of the compressed stream.

windowBits can also be -8..-15 for raw inflate.  In this case, -windowBits
determines the window size.  inflate() will then process raw deflate data,
not looking for a zlib or gzip header, not generating a check value, and not
looking for any check values for comparison at the end of the stream.  This
is for use with other formats that use the deflate compressed data format
such as zip.  Those formats provide their own check values.  If a custom
format is developed using the raw deflate format for compressed data, it is
recommended that a check value such as an adler32 or a crc32 be applied to
the uncompressed data as is done in the zlib, gzip, and zip formats.  For
most applications, the zlib format should be used as is.  Note that comments
above on the use in deflateInit2() applies to the magnitude of windowBits.

windowBits can also be greater than 15 for optional gzip decoding.  Add
32 to windowBits to enable zlib and gzip decoding with automatic header
detection, or add 16 to decode only the gzip format (the zlib format will
return a Z_DATA_ERROR).  If a gzip stream is being decoded, strm->adler is a
crc32 instead of an adler32.

inflateInit2 returns Z_OK if success, Z_MEM_ERROR if there was not enough
memory, Z_VERSION_ERROR if the zlib library version is incompatible with the
version assumed by the caller, or Z_STREAM_ERROR if the parameters are
invalid, such as a null pointer to the structure.  msg is set to null if
there is no error message.  inflateInit2 does not perform any decompression
apart from possibly reading the zlib header if present: actual decompression
will be done by inflate().  (So next_in and avail_in may be modified, but
next_out and avail_out are unused and unchanged.) The current implementation
of inflateInit2() does not process any header information -- that is
deferred until inflate() is called.
*/
inflateSetDictionary :: (strm: z_streamp, dictionary: *Bytef, dictLength: uInt) -> s32 #foreign zlib;

/*
Initializes the decompression dictionary from the given uncompressed byte
sequence.  This function must be called immediately after a call of inflate,
if that call returned Z_NEED_DICT.  The dictionary chosen by the compressor
can be determined from the adler32 value returned by that call of inflate.
The compressor and decompressor must use exactly the same dictionary (see
deflateSetDictionary).  For raw inflate, this function can be called
immediately after inflateInit2() or inflateReset() and before any call of
inflate() to set the dictionary.  The application must insure that the
dictionary that was used for compression is provided.

inflateSetDictionary returns Z_OK if success, Z_STREAM_ERROR if a
parameter is invalid (e.g.  dictionary being Z_NULL) or the stream state is
inconsistent, Z_DATA_ERROR if the given dictionary doesn't match the
expected one (incorrect adler32 value).  inflateSetDictionary does not
perform any decompression: this will be done by subsequent calls of
inflate().
*/
inflateSync :: (strm: z_streamp) -> s32 #foreign zlib;

/*
Skips invalid compressed data until a full flush point (see above the
description of deflate with Z_FULL_FLUSH) can be found, or until all
available input is skipped.  No output is provided.

inflateSync returns Z_OK if a full flush point has been found, Z_BUF_ERROR
if no more input was provided, Z_DATA_ERROR if no flush point has been
found, or Z_STREAM_ERROR if the stream structure was inconsistent.  In the
success case, the application may save the current current value of total_in
which indicates where valid compressed data was found.  In the error case,
the application may repeatedly call inflateSync, providing more input each
time, until success or end of the input data.
*/
inflateCopy :: (dest: z_streamp, source: z_streamp) -> s32 #foreign zlib;

/*
Sets the destination stream as a complete copy of the source stream.

This function can be useful when randomly accessing a large stream.  The
first pass through the stream can periodically record the inflate state,
allowing restarting inflate at those points when randomly accessing the
stream.

inflateCopy returns Z_OK if success, Z_MEM_ERROR if there was not
enough memory, Z_STREAM_ERROR if the source stream state was inconsistent
(such as zalloc being Z_NULL).  msg is left unchanged in both source and
destination.
*/
inflateReset :: (strm: z_streamp) -> s32 #foreign zlib;

/*
This function is equivalent to inflateEnd followed by inflateInit,
but does not free and reallocate all the internal decompression state.  The
stream will keep attributes that may have been set by inflateInit2.

inflateReset returns Z_OK if success, or Z_STREAM_ERROR if the source
stream state was inconsistent (such as zalloc or state being Z_NULL).
*/
inflateReset2 :: (strm: z_streamp, windowBits: s32) -> s32 #foreign zlib;

/*
This function is the same as inflateReset, but it also permits changing
the wrap and window size requests.  The windowBits parameter is interpreted
the same as it is for inflateInit2.

inflateReset2 returns Z_OK if success, or Z_STREAM_ERROR if the source
stream state was inconsistent (such as zalloc or state being Z_NULL), or if
the windowBits parameter is invalid.
*/
inflatePrime :: (strm: z_streamp, bits: s32, value: s32) -> s32 #foreign zlib;

/*
This function inserts bits in the inflate input stream.  The intent is
that this function is used to start inflating at a bit position in the
middle of a byte.  The provided bits will be used before any bytes are used
from next_in.  This function should only be used with raw inflate, and
should be used before the first inflate() call after inflateInit2() or
inflateReset().  bits must be less than or equal to 16, and that many of the
least significant bits of value will be inserted in the input.

If bits is negative, then the input stream bit buffer is emptied.  Then
inflatePrime() can be called again to put bits in the buffer.  This is used
to clear out bits leftover after feeding inflate a block description prior
to feeding inflate codes.

inflatePrime returns Z_OK if success, or Z_STREAM_ERROR if the source
stream state was inconsistent.
*/
inflateMark :: (strm: z_streamp) -> s32 #foreign zlib;

/*
This function returns two values, one in the lower 16 bits of the return
value, and the other in the remaining upper bits, obtained by shifting the
return value down 16 bits.  If the upper value is -1 and the lower value is
zero, then inflate() is currently decoding information outside of a block.
If the upper value is -1 and the lower value is non-zero, then inflate is in
the middle of a stored block, with the lower value equaling the number of
bytes from the input remaining to copy.  If the upper value is not -1, then
it is the number of bits back from the current bit position in the input of
the code (literal or length/distance pair) currently being processed.  In
that case the lower value is the number of bytes already emitted for that
code.

A code is being processed if inflate is waiting for more input to complete
decoding of the code, or if it has completed decoding but is waiting for
more output space to write the literal or match data.

inflateMark() is used to mark locations in the input data for random
access, which may be at bit positions, and to note those cases where the
output of a code may span boundaries of random access blocks.  The current
location in the input stream can be determined from avail_in and data_type
as noted in the description for the Z_BLOCK flush parameter for inflate.

inflateMark returns the value noted above or -1 << 16 if the provided
source stream state was inconsistent.
*/
inflateGetHeader :: (strm: z_streamp, head: gz_headerp) -> s32 #foreign zlib;

/*
ZEXTERN int ZEXPORT inflateBackInit OF((z_streamp strm, int windowBits,
unsigned char FAR *window));

Initialize the internal stream state for decompression using inflateBack()
calls.  The fields zalloc, zfree and opaque in strm must be initialized
before the call.  If zalloc and zfree are Z_NULL, then the default library-
derived memory allocation routines are used.  windowBits is the base two
logarithm of the window size, in the range 8..15.  window is a caller
supplied buffer of that size.  Except for special applications where it is
assured that deflate was used with small window sizes, windowBits must be 15
and a 32K byte window must be supplied to be able to decompress general
deflate streams.

See inflateBack() for the usage of these routines.

inflateBackInit will return Z_OK on success, Z_STREAM_ERROR if any of
the paramaters are invalid, Z_MEM_ERROR if the internal state could not be
allocated, or Z_VERSION_ERROR if the version of the library does not match
the version of the header file.
*/
in_func :: #type (unknown0: *void, unknown1: **u8) -> u32 #c_call;
out_func :: #type (unknown0: *void, unknown1: *u8, unknown2: u32) -> s32 #c_call;

inflateBack :: (strm: z_streamp, in: in_func, in_desc: *void, out: out_func, out_desc: *void) -> s32 #foreign zlib;

/*
inflateBack() does a raw inflate with a single call using a call-back
interface for input and output.  This is more efficient than inflate() for
file i/o applications in that it avoids copying between the output and the
sliding window by simply making the window itself the output buffer.  This
function trusts the application to not change the output buffer passed by
the output function, at least until inflateBack() returns.

inflateBackInit() must be called first to allocate the internal state
and to initialize the state with the user-provided window buffer.
inflateBack() may then be used multiple times to inflate a complete, raw
deflate stream with each call.  inflateBackEnd() is then called to free the
allocated state.

A raw deflate stream is one with no zlib or gzip header or trailer.
This routine would normally be used in a utility that reads zip or gzip
files and writes out uncompressed files.  The utility would decode the
header and process the trailer on its own, hence this routine expects only
the raw deflate stream to decompress.  This is different from the normal
behavior of inflate(), which expects either a zlib or gzip header and
trailer around the deflate stream.

inflateBack() uses two subroutines supplied by the caller that are then
called by inflateBack() for input and output.  inflateBack() calls those
routines until it reads a complete deflate stream and writes out all of the
uncompressed data, or until it encounters an error.  The function's
parameters and return types are defined above in the in_func and out_func
typedefs.  inflateBack() will call in(in_desc, &buf) which should return the
number of bytes of provided input, and a pointer to that input in buf.  If
there is no input available, in() must return zero--buf is ignored in that
case--and inflateBack() will return a buffer error.  inflateBack() will call
out(out_desc, buf, len) to write the uncompressed data buf[0..len-1].  out()
should return zero on success, or non-zero on failure.  If out() returns
non-zero, inflateBack() will return with an error.  Neither in() nor out()
are permitted to change the contents of the window provided to
inflateBackInit(), which is also the buffer that out() uses to write from.
The length written by out() will be at most the window size.  Any non-zero
amount of input may be provided by in().

For convenience, inflateBack() can be provided input on the first call by
setting strm->next_in and strm->avail_in.  If that input is exhausted, then
in() will be called.  Therefore strm->next_in must be initialized before
calling inflateBack().  If strm->next_in is Z_NULL, then in() will be called
immediately for input.  If strm->next_in is not Z_NULL, then strm->avail_in
must also be initialized, and then if strm->avail_in is not zero, input will
initially be taken from strm->next_in[0 ..  strm->avail_in - 1].

The in_desc and out_desc parameters of inflateBack() is passed as the
first parameter of in() and out() respectively when they are called.  These
descriptors can be optionally used to pass any information that the caller-
supplied in() and out() functions need to do their job.

On return, inflateBack() will set strm->next_in and strm->avail_in to
pass back any unused input that was provided by the last in() call.  The
return values of inflateBack() can be Z_STREAM_END on success, Z_BUF_ERROR
if in() or out() returned an error, Z_DATA_ERROR if there was a format error
in the deflate stream (in which case strm->msg is set to indicate the nature
of the error), or Z_STREAM_ERROR if the stream was not properly initialized.
In the case of Z_BUF_ERROR, an input or output error can be distinguished
using strm->next_in which will be Z_NULL only if in() returned an error.  If
strm->next_in is not Z_NULL, then the Z_BUF_ERROR was due to out() returning
non-zero.  (in() will always be called before out(), so strm->next_in is
assured to be defined if out() returns non-zero.) Note that inflateBack()
cannot return Z_OK.
*/
inflateBackEnd :: (strm: z_streamp) -> s32 #foreign zlib;

/*
All memory allocated by inflateBackInit() is freed.

inflateBackEnd() returns Z_OK on success, or Z_STREAM_ERROR if the stream
state was inconsistent.
*/
zlibCompileFlags :: () -> uLong #foreign zlib;

/*
The following utility functions are implemented on top of the basic
stream-oriented functions.  To simplify the interface, some default options
are assumed (compression level and memory usage, standard memory allocation
functions).  The source code of these utility functions can be modified if
you need special options.
*/
compress :: (dest: *Bytef, destLen: *uLongf, source: *Bytef, sourceLen: uLong) -> s32 #foreign zlib;

/*
Compresses the source buffer into the destination buffer.  sourceLen is
the byte length of the source buffer.  Upon entry, destLen is the total size
of the destination buffer, which must be at least the value returned by
compressBound(sourceLen).  Upon exit, destLen is the actual size of the
compressed buffer.

compress returns Z_OK if success, Z_MEM_ERROR if there was not
enough memory, Z_BUF_ERROR if there was not enough room in the output
buffer.
*/
compress2 :: (dest: *Bytef, destLen: *uLongf, source: *Bytef, sourceLen: uLong, level: s32) -> s32 #foreign zlib;

/*
Compresses the source buffer into the destination buffer.  The level
parameter has the same meaning as in deflateInit.  sourceLen is the byte
length of the source buffer.  Upon entry, destLen is the total size of the
destination buffer, which must be at least the value returned by
compressBound(sourceLen).  Upon exit, destLen is the actual size of the
compressed buffer.

compress2 returns Z_OK if success, Z_MEM_ERROR if there was not enough
memory, Z_BUF_ERROR if there was not enough room in the output buffer,
Z_STREAM_ERROR if the level parameter is invalid.
*/
compressBound :: (sourceLen: uLong) -> uLong #foreign zlib;

/*
compressBound() returns an upper bound on the compressed size after
compress() or compress2() on sourceLen bytes.  It would be used before a
compress() or compress2() call to allocate the destination buffer.
*/
uncompress :: (dest: *Bytef, destLen: *uLongf, source: *Bytef, sourceLen: uLong) -> s32 #foreign zlib;

/*
This library supports reading and writing files in gzip (.gz) format with
an interface similar to that of stdio, using the functions that start with
"gz".  The gzip format is different from the zlib format.  gzip is a gzip
wrapper, documented in RFC 1952, wrapped around a deflate stream.
*/
gzFile :: voidp;

/*
These functions are not related to compression but are exported
anyway because they might be useful in applications using the compression
library.
*/
adler32 :: (adler: uLong, buf: *Bytef, len: uInt) -> uLong #foreign zlib;

/*
ZEXTERN uLong ZEXPORT adler32_combine OF((uLong adler1, uLong adler2,
z_off_t len2));

Combine two Adler-32 checksums into one.  For two sequences of bytes, seq1
and seq2 with lengths len1 and len2, Adler-32 checksums were calculated for
each, adler1 and adler2.  adler32_combine() returns the Adler-32 checksum of
seq1 and seq2 concatenated, requiring only adler1, adler2, and len2.
*/
crc32 :: (crc: uLong, buf: *Bytef, len: uInt) -> uLong #foreign zlib;

/* deflateInit and inflateInit are macros to allow checking the zlib version
* and the compiler's view of z_stream:
*/
deflateInit_ :: (strm: z_streamp, level: s32, version: *u8, stream_size: s32) -> s32 #foreign zlib;

inflateInit_ :: (strm: z_streamp, version: *u8, stream_size: s32) -> s32 #foreign zlib;

deflateInit2_ :: (strm: z_streamp, level: s32, method: s32, windowBits: s32, memLevel: s32, strategy: s32, version: *u8, stream_size: s32) -> s32 #foreign zlib;

inflateInit2_ :: (strm: z_streamp, windowBits: s32, version: *u8, stream_size: s32) -> s32 #foreign zlib;

inflateBackInit_ :: (strm: z_streamp, windowBits: s32, window: *u8, version: *u8, stream_size: s32) -> s32 #foreign zlib;

adler32_combine :: (unknown0: uLong, unknown1: uLong, unknown2: s32) -> uLong #foreign zlib;
crc32_combine :: (unknown0: uLong, unknown1: uLong, unknown2: s32) -> uLong #foreign zlib;

internal_state :: struct {
    dummy: s32;
}

/* undocumented functions */
zError :: (unknown0: s32) -> *u8 #foreign zlib;
inflateSyncPoint :: (unknown0: z_streamp) -> s32 #foreign zlib;
get_crc_table :: () -> *uLongf #foreign zlib;
inflateUndermine :: (unknown0: z_streamp, unknown1: s32) -> s32 #foreign zlib;

/* compile with -Dlocal if your debugger can't find static symbols */
uch :: u8;
uchf :: uch;
ush :: u16;
ushf :: ush;
ulg :: u32;

/* internal gzip file state data structure */
gz_state :: struct {
    mode:     s32; /* see gzip modes above */
    fd:       s32; /* file descriptor */
    path:     *u8; /* path or fd for error messages */
    pos:      s32; /* current position in uncompressed data */
    size:     u32; /* buffer size, zero if not allocated yet */
    want:     u32; /* requested buffer size, default is GZBUFSIZE */
    in:       *u8; /* input buffer */
    out:      *u8; /* output buffer (double-sized when reading) */
    next:     *u8; /* next output data to deliver or write */

    have:     u32; /* amount of output data unused at next */
    eof:      s32; /* true if end of input file reached */
    start:    s32; /* where the gzip data started, for rewinding */
    raw:      s32; /* where the raw data started, for seeking */
    how:      s32; /* 0: get header, 1: copy, 2: decompress */
    direct:   s32; /* true if last read direct, false if gzip */

    level:    s32; /* compression level */
    strategy: s32; /* compression strategy */

    skip:     s32; /* amount to skip (already rewound if backwards) */
    seek:     s32; /* true if seek request pending */

    err:      s32; /* error code */
    msg:      *u8; /* error message */

    strm:     z_stream; /* stream structure in-place (not a pointer) */
}

gz_statep :: *gz_state;

#scope_file

#import "Basic"; // For assert

zlib :: #library,no_dll "lib/windows/x64/zlib";

#run {
    {
        info := type_info(z_stream_s);
        for info.members {
            if it.name == {
                case "next_in";
                    assert(it.offset_in_bytes == 0, "z_stream_s.next_in has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.next_in has unexpected size % instead of 8", it.type.runtime_size);
                case "avail_in";
                    assert(it.offset_in_bytes == 8, "z_stream_s.avail_in has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.avail_in has unexpected size % instead of 4", it.type.runtime_size);
                case "total_in";
                    assert(it.offset_in_bytes == 12, "z_stream_s.total_in has unexpected offset % instead of 12", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.total_in has unexpected size % instead of 4", it.type.runtime_size);
                case "next_out";
                    assert(it.offset_in_bytes == 16, "z_stream_s.next_out has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.next_out has unexpected size % instead of 8", it.type.runtime_size);
                case "avail_out";
                    assert(it.offset_in_bytes == 24, "z_stream_s.avail_out has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.avail_out has unexpected size % instead of 4", it.type.runtime_size);
                case "total_out";
                    assert(it.offset_in_bytes == 28, "z_stream_s.total_out has unexpected offset % instead of 28", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.total_out has unexpected size % instead of 4", it.type.runtime_size);
                case "msg";
                    assert(it.offset_in_bytes == 32, "z_stream_s.msg has unexpected offset % instead of 32", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.msg has unexpected size % instead of 8", it.type.runtime_size);
                case "state";
                    assert(it.offset_in_bytes == 40, "z_stream_s.state has unexpected offset % instead of 40", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.state has unexpected size % instead of 8", it.type.runtime_size);
                case "zalloc";
                    assert(it.offset_in_bytes == 48, "z_stream_s.zalloc has unexpected offset % instead of 48", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.zalloc has unexpected size % instead of 8", it.type.runtime_size);
                case "zfree";
                    assert(it.offset_in_bytes == 56, "z_stream_s.zfree has unexpected offset % instead of 56", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.zfree has unexpected size % instead of 8", it.type.runtime_size);
                case "opaque";
                    assert(it.offset_in_bytes == 64, "z_stream_s.opaque has unexpected offset % instead of 64", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "z_stream_s.opaque has unexpected size % instead of 8", it.type.runtime_size);
                case "data_type";
                    assert(it.offset_in_bytes == 72, "z_stream_s.data_type has unexpected offset % instead of 72", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.data_type has unexpected size % instead of 4", it.type.runtime_size);
                case "adler";
                    assert(it.offset_in_bytes == 76, "z_stream_s.adler has unexpected offset % instead of 76", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.adler has unexpected size % instead of 4", it.type.runtime_size);
                case "reserved";
                    assert(it.offset_in_bytes == 80, "z_stream_s.reserved has unexpected offset % instead of 80", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "z_stream_s.reserved has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(z_stream_s) == 88, "z_stream_s has size % instead of 88", size_of(z_stream_s));
    }

    {
        info := type_info(gz_header_s);
        for info.members {
            if it.name == {
                case "text";
                    assert(it.offset_in_bytes == 0, "gz_header_s.text has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.text has unexpected size % instead of 4", it.type.runtime_size);
                case "time";
                    assert(it.offset_in_bytes == 4, "gz_header_s.time has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.time has unexpected size % instead of 4", it.type.runtime_size);
                case "xflags";
                    assert(it.offset_in_bytes == 8, "gz_header_s.xflags has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.xflags has unexpected size % instead of 4", it.type.runtime_size);
                case "os";
                    assert(it.offset_in_bytes == 12, "gz_header_s.os has unexpected offset % instead of 12", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.os has unexpected size % instead of 4", it.type.runtime_size);
                case "extra";
                    assert(it.offset_in_bytes == 16, "gz_header_s.extra has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_header_s.extra has unexpected size % instead of 8", it.type.runtime_size);
                case "extra_len";
                    assert(it.offset_in_bytes == 24, "gz_header_s.extra_len has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.extra_len has unexpected size % instead of 4", it.type.runtime_size);
                case "extra_max";
                    assert(it.offset_in_bytes == 28, "gz_header_s.extra_max has unexpected offset % instead of 28", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.extra_max has unexpected size % instead of 4", it.type.runtime_size);
                case "name";
                    assert(it.offset_in_bytes == 32, "gz_header_s.name has unexpected offset % instead of 32", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_header_s.name has unexpected size % instead of 8", it.type.runtime_size);
                case "name_max";
                    assert(it.offset_in_bytes == 40, "gz_header_s.name_max has unexpected offset % instead of 40", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.name_max has unexpected size % instead of 4", it.type.runtime_size);
                case "comment";
                    assert(it.offset_in_bytes == 48, "gz_header_s.comment has unexpected offset % instead of 48", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_header_s.comment has unexpected size % instead of 8", it.type.runtime_size);
                case "comm_max";
                    assert(it.offset_in_bytes == 56, "gz_header_s.comm_max has unexpected offset % instead of 56", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.comm_max has unexpected size % instead of 4", it.type.runtime_size);
                case "hcrc";
                    assert(it.offset_in_bytes == 60, "gz_header_s.hcrc has unexpected offset % instead of 60", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.hcrc has unexpected size % instead of 4", it.type.runtime_size);
                case "done";
                    assert(it.offset_in_bytes == 64, "gz_header_s.done has unexpected offset % instead of 64", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_header_s.done has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(gz_header_s) == 72, "gz_header_s has size % instead of 72", size_of(gz_header_s));
    }

    {
        info := type_info(internal_state);
        for info.members {
            if it.name == {
                case "dummy";
                    assert(it.offset_in_bytes == 0, "internal_state.dummy has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "internal_state.dummy has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(internal_state) == 4, "internal_state has size % instead of 4", size_of(internal_state));
    }

    {
        info := type_info(gz_state);
        for info.members {
            if it.name == {
                case "mode";
                    assert(it.offset_in_bytes == 0, "gz_state.mode has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.mode has unexpected size % instead of 4", it.type.runtime_size);
                case "fd";
                    assert(it.offset_in_bytes == 4, "gz_state.fd has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.fd has unexpected size % instead of 4", it.type.runtime_size);
                case "path";
                    assert(it.offset_in_bytes == 8, "gz_state.path has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_state.path has unexpected size % instead of 8", it.type.runtime_size);
                case "pos";
                    assert(it.offset_in_bytes == 16, "gz_state.pos has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.pos has unexpected size % instead of 4", it.type.runtime_size);
                case "size";
                    assert(it.offset_in_bytes == 20, "gz_state.size has unexpected offset % instead of 20", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.size has unexpected size % instead of 4", it.type.runtime_size);
                case "want";
                    assert(it.offset_in_bytes == 24, "gz_state.want has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.want has unexpected size % instead of 4", it.type.runtime_size);
                case "in";
                    assert(it.offset_in_bytes == 32, "gz_state.in has unexpected offset % instead of 32", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_state.in has unexpected size % instead of 8", it.type.runtime_size);
                case "out";
                    assert(it.offset_in_bytes == 40, "gz_state.out has unexpected offset % instead of 40", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_state.out has unexpected size % instead of 8", it.type.runtime_size);
                case "next";
                    assert(it.offset_in_bytes == 48, "gz_state.next has unexpected offset % instead of 48", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_state.next has unexpected size % instead of 8", it.type.runtime_size);
                case "have";
                    assert(it.offset_in_bytes == 56, "gz_state.have has unexpected offset % instead of 56", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.have has unexpected size % instead of 4", it.type.runtime_size);
                case "eof";
                    assert(it.offset_in_bytes == 60, "gz_state.eof has unexpected offset % instead of 60", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.eof has unexpected size % instead of 4", it.type.runtime_size);
                case "start";
                    assert(it.offset_in_bytes == 64, "gz_state.start has unexpected offset % instead of 64", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.start has unexpected size % instead of 4", it.type.runtime_size);
                case "raw";
                    assert(it.offset_in_bytes == 68, "gz_state.raw has unexpected offset % instead of 68", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.raw has unexpected size % instead of 4", it.type.runtime_size);
                case "how";
                    assert(it.offset_in_bytes == 72, "gz_state.how has unexpected offset % instead of 72", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.how has unexpected size % instead of 4", it.type.runtime_size);
                case "direct";
                    assert(it.offset_in_bytes == 76, "gz_state.direct has unexpected offset % instead of 76", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.direct has unexpected size % instead of 4", it.type.runtime_size);
                case "level";
                    assert(it.offset_in_bytes == 80, "gz_state.level has unexpected offset % instead of 80", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.level has unexpected size % instead of 4", it.type.runtime_size);
                case "strategy";
                    assert(it.offset_in_bytes == 84, "gz_state.strategy has unexpected offset % instead of 84", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.strategy has unexpected size % instead of 4", it.type.runtime_size);
                case "skip";
                    assert(it.offset_in_bytes == 88, "gz_state.skip has unexpected offset % instead of 88", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.skip has unexpected size % instead of 4", it.type.runtime_size);
                case "seek";
                    assert(it.offset_in_bytes == 92, "gz_state.seek has unexpected offset % instead of 92", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.seek has unexpected size % instead of 4", it.type.runtime_size);
                case "err";
                    assert(it.offset_in_bytes == 96, "gz_state.err has unexpected offset % instead of 96", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "gz_state.err has unexpected size % instead of 4", it.type.runtime_size);
                case "msg";
                    assert(it.offset_in_bytes == 104, "gz_state.msg has unexpected offset % instead of 104", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "gz_state.msg has unexpected size % instead of 8", it.type.runtime_size);
                case "strm";
                    assert(it.offset_in_bytes == 112, "gz_state.strm has unexpected offset % instead of 112", it.offset_in_bytes);
                    assert(it.type.runtime_size == 88, "gz_state.strm has unexpected size % instead of 88", it.type.runtime_size);
            }
        }
        assert(size_of(gz_state) == 200, "gz_state has size % instead of 200", size_of(gz_state));
    }
}

