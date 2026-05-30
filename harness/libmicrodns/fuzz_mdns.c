#include "mdns.h"
#include <stddef.h>
#include <stdint.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < sizeof(struct mdns_hdr) || size > 4096) return 0;

    struct mdns_hdr hdr;
    struct rr_entry *entries = NULL;
    if (mdns_parse(&hdr, &entries, data, size) == 0) {
        uint8_t out[4096] = {0};
        size_t out_len = 0;
        (void)mdns_write(&hdr, entries, out, sizeof(out), &out_len);
    }

    mdns_free(entries);
    return 0;
}
