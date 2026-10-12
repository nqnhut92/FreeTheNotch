// Zstandard v1.5.7, BSD-3-Clause: public decoder declarations from lib/zstd.h.
#include <stddef.h>
size_t ZSTD_findFrameCompressedSize(const void *src, size_t srcSize);
size_t ZSTD_decompress(void *dst, size_t dstCapacity, const void *src, size_t compressedSize);
unsigned ZSTD_isError(size_t code);
