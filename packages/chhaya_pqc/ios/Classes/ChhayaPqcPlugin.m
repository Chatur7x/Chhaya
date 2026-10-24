#import "ChhayaPqcPlugin.h"
#include "chhaya_pqc.h"

@interface ChhayaPqcPlugin ()
@property(nonatomic) dispatch_queue_t worker;
@property(nonatomic) NSNumber *passed;
@end

@implementation ChhayaPqcPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"org.chhaya/pqc"
    binaryMessenger:[registrar messenger]];
  ChhayaPqcPlugin *instance = [[ChhayaPqcPlugin alloc] init];
  instance.worker = dispatch_queue_create("org.chhaya.pqc", DISPATCH_QUEUE_SERIAL);
  [registrar addMethodCallDelegate:instance channel:channel];
}
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (![call.method isEqualToString:@"capabilities"] && ![call.method isEqualToString:@"run"]) {
    result(FlutterMethodNotImplemented); return;
  }
  dispatch_async(self.worker, ^{
    @autoreleasepool {
      if (!self.passed) self.passed = @(chhaya_pqc_self_test() == 1);
      if ([call.method isEqualToString:@"capabilities"]) {
        NSDictionary *data = @{@"available": self.passed, @"provider": [NSString stringWithUTF8String:chhaya_pqc_version()]};
        dispatch_async(dispatch_get_main_queue(), ^{ result(data); }); return;
      }
      if (![self.passed boolValue]) {
        dispatch_async(dispatch_get_main_queue(), ^{ result([FlutterError errorWithCode:@"PQC_UNAVAILABLE"
          message:@"Native provider is unavailable" details:nil]); }); return;
      }
      NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
      NSNumber *operation = args[@"operation"];
      id k = args[@"key"], m = args[@"input"], e = args[@"extra"];
      BOOL valid = [operation isKindOfClass:[NSNumber class]] &&
        (!k || [k isKindOfClass:[FlutterStandardTypedData class]]) &&
        (!m || [m isKindOfClass:[FlutterStandardTypedData class]]) &&
        (!e || [e isKindOfClass:[FlutterStandardTypedData class]]);
      NSData *key = valid && k ? ((FlutterStandardTypedData*)k).data : [NSData data];
      NSData *input = valid && m ? ((FlutterStandardTypedData*)m).data : [NSData data];
      NSData *extra = valid && e ? ((FlutterStandardTypedData*)e).data : [NSData data];
      uint8_t output[CHHAYA_PQC_MAX_OUTPUT] = {0};
      int length = valid ? chhaya_pqc_run([operation intValue], key.bytes, key.length,
        input.bytes, input.length, extra.bytes, extra.length, output, sizeof(output)) : -1;
      if (length < 0 || length > CHHAYA_PQC_MAX_OUTPUT) {
        chhaya_pqc_cleanse(output, sizeof(output));
        dispatch_async(dispatch_get_main_queue(), ^{ result([FlutterError errorWithCode:@"PQC_OPERATION_FAILED"
          message:@"Post-quantum operation failed" details:nil]); }); return;
      }
      NSMutableData *data = [NSMutableData dataWithBytes:output length:(NSUInteger)length];
      chhaya_pqc_cleanse(output, sizeof(output));
      dispatch_async(dispatch_get_main_queue(), ^{
        result([FlutterStandardTypedData typedDataWithBytes:data]);
        [data resetBytesInRange:NSMakeRange(0, data.length)];
      });
    }
  });
}
@end
