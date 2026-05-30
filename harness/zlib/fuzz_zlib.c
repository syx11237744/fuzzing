#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

static void try_inflate(const uint8_t *data, size_t size, int window_bits) {
    z_stream strm;
    unsigned char out[64 * 1024];

    memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, window_bits) != Z_OK) return;

    strm.next_in = (Bytef *)data;
    strm.avail_in = (uInt)size;

    for (int i = 0; i < 256; i++) {
        strm.next_out = out;
        strm.avail_out = (uInt)sizeof(out);

        int ret = inflate(&strm, Z_NO_FLUSH);
        if (ret == Z_STREAM_END) break;
        if (ret != Z_OK && ret != Z_BUF_ERROR) break;
        if (strm.avail_in == 0 && strm.avail_out != 0) break;
    }

    inflateEnd(&strm);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > (1u << 20)) return 0;

    try_inflate(data, size, 15 + 32); /* zlib or gzip wrapper */
    try_inflate(data, size, -15);     /* raw deflate */

    return 0;
}
