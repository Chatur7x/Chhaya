#ifndef CHHAYA_PQC_H
#define CHHAYA_PQC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define CHHAYA_KEM_PUBLIC 1568
#define CHHAYA_KEM_PRIVATE 3168
#define CHHAYA_KEM_CIPHERTEXT 1568
#define CHHAYA_KEM_SECRET 32
#define CHHAYA_DSA_PUBLIC 2592
#define CHHAYA_DSA_PRIVATE 4896
#define CHHAYA_DSA_SIGNATURE 4627
#define CHHAYA_PQC_MAX_OUTPUT 8192
#define CHHAYA_PQC_MAX_MESSAGE (1024 * 1024)

/* Operations: 1=KEM keypair, 2=encapsulate, 3=decapsulate,
 * 4=DSA keypair, 5=sign, 6=verify. Pair outputs are public||private;
 * encapsulation output is ciphertext||shared-secret. Verify returns one byte.
 * All lengths are checked before an upstream operation. -1 indicates failure. */
int chhaya_pqc_run(int operation, const uint8_t *key, size_t key_len,
                  const uint8_t *input, size_t input_len,
                  const uint8_t *extra, size_t extra_len,
                  uint8_t *output, size_t output_capacity);
int chhaya_pqc_self_test(void);
void chhaya_pqc_cleanse(void *data, size_t length);
const char *chhaya_pqc_version(void);

#ifdef __cplusplus
}
#endif
#endif
