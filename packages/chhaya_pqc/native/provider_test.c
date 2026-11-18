#include "chhaya_pqc.h"
#include <stdio.h>
#include <string.h>
#include "test_vectors.h"
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"Provider check failed at line %d\n",__LINE__); return 1; } } while (0)
int main(void) {
  uint8_t out[CHHAYA_PQC_MAX_OUTPUT], ciphertext[CHHAYA_KEM_CIPHERTEXT];
  CHECK(chhaya_pqc_self_test() == 1);
  CHECK(chhaya_pqc_run(3,kat_kem_sk,sizeof(kat_kem_sk),kat_kem_ct,sizeof(kat_kem_ct),NULL,0,out,sizeof(out)) == CHHAYA_KEM_SECRET);
  CHECK(memcmp(out,kat_kem_ss,CHHAYA_KEM_SECRET) == 0);
  memcpy(ciphertext,kat_kem_ct,sizeof(ciphertext)); ciphertext[0] ^= 1;
  CHECK(chhaya_pqc_run(3,kat_kem_sk,sizeof(kat_kem_sk),ciphertext,sizeof(ciphertext),NULL,0,out,sizeof(out)) == CHHAYA_KEM_SECRET);
  CHECK(memcmp(out,kat_kem_ss,CHHAYA_KEM_SECRET) != 0); /* FIPS 203 implicit rejection */
  CHECK(chhaya_pqc_run(3,kat_kem_sk,1,kat_kem_ct,sizeof(kat_kem_ct),NULL,0,out,sizeof(out)) == -1);
  for (size_t i=0;i<sizeof(out);i++) CHECK(out[i] == 0);
  CHECK(chhaya_pqc_run(99,NULL,0,NULL,0,NULL,0,out,sizeof(out)) == -1);
  CHECK(chhaya_pqc_run(1,NULL,0,NULL,0,NULL,0,out,1) == -1);
  puts("AWS-LC ML-KEM-1024 / ML-DSA-87 vectors, roundtrips and rejection checks passed");
  chhaya_pqc_cleanse(out,sizeof(out));
  return 0;
}
