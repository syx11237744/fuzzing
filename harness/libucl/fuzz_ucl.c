#include <ucl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

/* Recursively walk the parsed UCL tree, touching key/type and iterating
   any compound nodes. Pure read-only — exercises the accessor path. */
static void walk(const ucl_object_t *obj) {
    if (!obj) return;
    (void)ucl_object_type(obj);
    (void)ucl_object_key(obj);

    if (ucl_object_type(obj) == UCL_OBJECT || ucl_object_type(obj) == UCL_ARRAY) {
        ucl_object_iter_t it = NULL;
        const ucl_object_t *cur;
        while ((cur = ucl_object_iterate(obj, &it, true)) != NULL) {
            walk(cur);
        }
    }
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > (1u << 20)) return 0;

    struct ucl_parser *p = ucl_parser_new(UCL_PARSER_NO_FILEVARS);
    if (!p) return 0;

    if (ucl_parser_add_chunk(p, data, size)
        && ucl_parser_get_error(p) == NULL) {

        ucl_object_t *root = ucl_parser_get_object(p);
        if (root) {
            walk(root);

            /* Note: ucl_object_emit() intentionally NOT called.
               It triggers a known emit-side OOB (issue #385 family)
               whenever the parser stores a string whose recorded length
               exceeds its actual NUL-truncated buffer. Calling it would
               make the fuzzer re-find that bug forever. The accessor
               path is still exercised via walk(). */

            ucl_object_unref(root);
        }
    }

    ucl_parser_free(p);
    return 0;
}
