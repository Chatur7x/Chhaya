#include "chhaya_pqc.h"
#include <openssl/evp.h>
#include <openssl/err.h>
#include <openssl/mem.h>
#include <openssl/nid.h>
#include <string.h>

const char *chhaya_pqc_version(void) { return "AWS-LC/5.11.0/fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6"; }
void chhaya_pqc_cleanse(void *data, size_t length) { if (data && length) OPENSSL_cleanse(data, length); }

static EVP_PKEY *new_pair(int operation) {
  EVP_PKEY *key = NULL;
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(operation == 1 ? EVP_PKEY_KEM : EVP_PKEY_PQDSA, NULL);
  if (!ctx) return NULL;
  int ok = operation == 1 ? EVP_PKEY_CTX_kem_set_params(ctx, NID_MLKEM1024)
                          : EVP_PKEY_CTX_pqdsa_set_params(ctx, NID_MLDSA87);
  if (!ok || !EVP_PKEY_keygen_init(ctx) || !EVP_PKEY_keygen(ctx, &key)) {
    EVP_PKEY_free(key); key = NULL;
  }
  EVP_PKEY_CTX_free(ctx);
  return key;
}

int chhaya_pqc_run(int operation, const uint8_t *key, size_t key_len,
                  const uint8_t *input, size_t input_len,
                  const uint8_t *extra, size_t extra_len,
                  uint8_t *output, size_t output_capacity) {
  EVP_PKEY *pkey = NULL;
  EVP_PKEY_CTX *ctx = NULL;
  EVP_MD_CTX *md = NULL;
  int result = -1;
  size_t a = 0, b = 0;
  if (!output || output_capacity < CHHAYA_PQC_MAX_OUTPUT ||
      key_len > CHHAYA_DSA_PRIVATE || input_len > CHHAYA_PQC_MAX_MESSAGE ||
      extra_len > CHHAYA_DSA_SIGNATURE || (key_len && !key) ||
      (input_len && !input) || (extra_len && !extra)) return -1;
  memset(output, 0, output_capacity);

  switch (operation) {
    case 1:
    case 4:
      if (key_len || input_len || extra_len) break;
      pkey = new_pair(operation);
      if (!pkey) break;
      a = operation == 1 ? CHHAYA_KEM_PUBLIC : CHHAYA_DSA_PUBLIC;
      b = operation == 1 ? CHHAYA_KEM_PRIVATE : CHHAYA_DSA_PRIVATE;
      if (!EVP_PKEY_get_raw_public_key(pkey, output, &a) ||
          !EVP_PKEY_get_raw_private_key(pkey, output + a, &b)) break;
      if (a != (operation == 1 ? CHHAYA_KEM_PUBLIC : CHHAYA_DSA_PUBLIC) ||
          b != (operation == 1 ? CHHAYA_KEM_PRIVATE : CHHAYA_DSA_PRIVATE)) break;
      result = (int)(a + b);
      break;
    case 2:
      if (key_len != CHHAYA_KEM_PUBLIC || input_len || extra_len) break;
      pkey = EVP_PKEY_kem_new_raw_public_key(NID_MLKEM1024, key, key_len);
      if (!pkey || !(ctx = EVP_PKEY_CTX_new(pkey, NULL))) break;
      a = CHHAYA_KEM_CIPHERTEXT; b = CHHAYA_KEM_SECRET;
      if (EVP_PKEY_encapsulate(ctx, output, &a, output + CHHAYA_KEM_CIPHERTEXT, &b) &&
          a == CHHAYA_KEM_CIPHERTEXT && b == CHHAYA_KEM_SECRET) result = (int)(a + b);
      break;
    case 3:
      if (key_len != CHHAYA_KEM_PRIVATE || input_len != CHHAYA_KEM_CIPHERTEXT || extra_len) break;
      pkey = EVP_PKEY_kem_new_raw_secret_key(NID_MLKEM1024, key, key_len);
      if (!pkey || !(ctx = EVP_PKEY_CTX_new(pkey, NULL))) break;
      a = CHHAYA_KEM_SECRET;
      if (EVP_PKEY_decapsulate(ctx, output, &a, input, input_len) && a == CHHAYA_KEM_SECRET) result = (int)a;
      break;
    case 5:
      if (key_len != CHHAYA_DSA_PRIVATE || extra_len) break;
      pkey = EVP_PKEY_pqdsa_new_raw_private_key(NID_MLDSA87, key, key_len);
      if (!pkey || !(md = EVP_MD_CTX_new())) break;
      a = CHHAYA_DSA_SIGNATURE;
      if (EVP_DigestSignInit(md, NULL, NULL, NULL, pkey) &&
          EVP_DigestSign(md, output, &a, input, input_len) && a == CHHAYA_DSA_SIGNATURE) result = (int)a;
      break;
    case 6:
      if (key_len != CHHAYA_DSA_PUBLIC || extra_len != CHHAYA_DSA_SIGNATURE) break;
      pkey = EVP_PKEY_pqdsa_new_raw_public_key(NID_MLDSA87, key, key_len);
      if (!pkey || !(md = EVP_MD_CTX_new()) || !EVP_DigestVerifyInit(md, NULL, NULL, NULL, pkey)) break;
      a = EVP_DigestVerify(md, extra, extra_len, input, input_len) == 1;
      output[0] = (uint8_t)a; result = 1;
      break;
    default: break;
  }
  EVP_MD_CTX_free(md);
  EVP_PKEY_CTX_free(ctx);
  EVP_PKEY_free(pkey);
  ERR_clear_error();
  if (result < 0) chhaya_pqc_cleanse(output, output_capacity);
  return result;
}

int chhaya_pqc_self_test(void) {
  uint8_t pair[CHHAYA_PQC_MAX_OUTPUT], encrypted[CHHAYA_PQC_MAX_OUTPUT], decoded[CHHAYA_PQC_MAX_OUTPUT];
  uint8_t signature[CHHAYA_PQC_MAX_OUTPUT];
  const uint8_t message[] = "Chhaya provider self-test";
  int ok = 0;
  if (chhaya_pqc_run(1, NULL, 0, NULL, 0, NULL, 0, pair, sizeof(pair)) != CHHAYA_KEM_PUBLIC + CHHAYA_KEM_PRIVATE) goto done;
  if (chhaya_pqc_run(2, pair, CHHAYA_KEM_PUBLIC, NULL, 0, NULL, 0, encrypted, sizeof(encrypted)) != CHHAYA_KEM_CIPHERTEXT + CHHAYA_KEM_SECRET) goto done;
  if (chhaya_pqc_run(3, pair + CHHAYA_KEM_PUBLIC, CHHAYA_KEM_PRIVATE, encrypted, CHHAYA_KEM_CIPHERTEXT, NULL, 0, decoded, sizeof(decoded)) != CHHAYA_KEM_SECRET) goto done;
  if (CRYPTO_memcmp(decoded, encrypted + CHHAYA_KEM_CIPHERTEXT, CHHAYA_KEM_SECRET)) goto done;
  if (chhaya_pqc_run(4, NULL, 0, NULL, 0, NULL, 0, pair, sizeof(pair)) != CHHAYA_DSA_PUBLIC + CHHAYA_DSA_PRIVATE) goto done;
  if (chhaya_pqc_run(5, pair + CHHAYA_DSA_PUBLIC, CHHAYA_DSA_PRIVATE, message, sizeof(message)-1, NULL, 0, signature, sizeof(signature)) != CHHAYA_DSA_SIGNATURE) goto done;
  if (chhaya_pqc_run(6, pair, CHHAYA_DSA_PUBLIC, message, sizeof(message)-1, signature, CHHAYA_DSA_SIGNATURE, decoded, sizeof(decoded)) != 1 || decoded[0] != 1) goto done;
  signature[0] ^= 1;
  if (chhaya_pqc_run(6, pair, CHHAYA_DSA_PUBLIC, message, sizeof(message)-1, signature, CHHAYA_DSA_SIGNATURE, decoded, sizeof(decoded)) != 1 || decoded[0] != 0) goto done;
  ok = 1;
done:
  chhaya_pqc_cleanse(pair, sizeof(pair)); chhaya_pqc_cleanse(encrypted, sizeof(encrypted));
  chhaya_pqc_cleanse(decoded, sizeof(decoded)); chhaya_pqc_cleanse(signature, sizeof(signature));
  return ok;
}
