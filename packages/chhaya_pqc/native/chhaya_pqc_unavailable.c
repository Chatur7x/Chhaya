#include "chhaya_pqc.h"
const char *chhaya_pqc_version(void) { return "unavailable/unsupported-architecture"; }
int chhaya_pqc_self_test(void) { return 0; }
void chhaya_pqc_cleanse(void *data, size_t length) {
  volatile uint8_t *p = data;
  while (length--) *p++ = 0;
}
int chhaya_pqc_run(int operation, const uint8_t *key, size_t key_len,
                  const uint8_t *input, size_t input_len, const uint8_t *extra,
                  size_t extra_len, uint8_t *output, size_t output_capacity) {
  (void)operation; (void)key; (void)key_len; (void)input; (void)input_len; (void)extra; (void)extra_len;
  if (output) chhaya_pqc_cleanse(output, output_capacity);
  return -1;
}
