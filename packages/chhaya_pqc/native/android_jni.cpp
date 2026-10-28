#include <jni.h>
#include <vector>
#include "chhaya_pqc.h"

namespace {
struct Input {
  std::vector<uint8_t> bytes;
  Input(JNIEnv *env, jbyteArray value) {
    if (!value) return;
    const jsize length = env->GetArrayLength(value);
    if (length < 0 || length > CHHAYA_PQC_MAX_MESSAGE) throw 1;
    bytes.resize(static_cast<size_t>(length));
    if (length) env->GetByteArrayRegion(value, 0, length, reinterpret_cast<jbyte *>(bytes.data()));
  }
  ~Input() { chhaya_pqc_cleanse(bytes.data(), bytes.size()); }
};
void fail(JNIEnv *env) {
  jclass error = env->FindClass("java/lang/IllegalArgumentException");
  if (error) env->ThrowNew(error, "Post-quantum operation failed");
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_chhaya_pqc_ChhayaPqcPlugin_nativeVersion(JNIEnv *env, jclass) {
  return env->NewStringUTF(chhaya_pqc_version());
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_chhaya_pqc_ChhayaPqcPlugin_nativeSelfTest(JNIEnv *, jclass) {
  return chhaya_pqc_self_test() ? JNI_TRUE : JNI_FALSE;
}
extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_chhaya_pqc_ChhayaPqcPlugin_nativeRun(JNIEnv *env, jclass, jint operation,
                                          jbyteArray key, jbyteArray input, jbyteArray extra) {
  uint8_t output[CHHAYA_PQC_MAX_OUTPUT] = {0};
  jbyteArray result = nullptr;
  try {
    Input k(env, key), m(env, input), e(env, extra);
    if (env->ExceptionCheck()) throw 1;
    const int length = chhaya_pqc_run(operation, k.bytes.data(), k.bytes.size(),
      m.bytes.data(), m.bytes.size(), e.bytes.data(), e.bytes.size(), output, sizeof(output));
    if (length < 0 || length > CHHAYA_PQC_MAX_OUTPUT) throw 1;
    result = env->NewByteArray(length);
    if (result) env->SetByteArrayRegion(result, 0, length, reinterpret_cast<const jbyte *>(output));
  } catch (...) { if (!env->ExceptionCheck()) fail(env); }
  chhaya_pqc_cleanse(output, sizeof(output));
  return result;
}
