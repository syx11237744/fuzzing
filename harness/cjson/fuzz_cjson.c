#include <cJSON.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

static void touch_tree(const cJSON *item) {
    for (const cJSON *cur = item; cur != NULL; cur = cur->next) {
        (void)cJSON_IsInvalid(cur);
        (void)cJSON_IsFalse(cur);
        (void)cJSON_IsTrue(cur);
        (void)cJSON_IsNull(cur);
        (void)cJSON_IsNumber(cur);
        (void)cJSON_IsString(cur);
        (void)cJSON_IsArray(cur);
        (void)cJSON_IsObject(cur);

        if (cur->child != NULL) {
            touch_tree(cur->child);
        }
    }
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > (1u << 20)) return 0;

    cJSON *root = cJSON_ParseWithLengthOpts((const char *)data, size, NULL, 0);
    if (root != NULL) {
        touch_tree(root);

        char *printed = cJSON_PrintUnformatted(root);
        free(printed);

        cJSON_Delete(root);
    }

    return 0;
}
