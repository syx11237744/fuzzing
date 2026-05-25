#include <expat.h>
#include <stddef.h>
#include <stdint.h>

static void XMLCALL on_start(void *ud, const XML_Char *name, const XML_Char **atts) {
    (void)ud; (void)name; (void)atts;
}

static void XMLCALL on_end(void *ud, const XML_Char *name) {
    (void)ud; (void)name;
}

static void XMLCALL on_chars(void *ud, const XML_Char *s, int len) {
    (void)ud; (void)s; (void)len;
}

static void XMLCALL on_comment(void *ud, const XML_Char *data) {
    (void)ud; (void)data;
}

static void XMLCALL on_pi(void *ud, const XML_Char *target, const XML_Char *data) {
    (void)ud; (void)target; (void)data;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    XML_Parser p = XML_ParserCreate(NULL);
    if (!p) return 0;

    XML_SetElementHandler(p, on_start, on_end);
    XML_SetCharacterDataHandler(p, on_chars);
    XML_SetCommentHandler(p, on_comment);
    XML_SetProcessingInstructionHandler(p, on_pi);

    XML_Parse(p, (const char *)data, (int)size, /*isFinal=*/1);
    XML_ParserFree(p);
    return 0;
}
