Pod::Spec.new do |s|
  s.name = 'chhaya_pqc'
  s.version = '0.1.0'
  s.summary = 'Chhaya native AWS-LC post-quantum primitive provider'
  s.homepage = 'https://github.com/Chatur7x/Chhaya'
  s.author = 'Chhaya contributors'
  s.license = { :type => 'Apache-2.0 OR ISC with upstream component notices', :file => '../AWS-LC-LICENSE.txt' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../native/include"',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "$(DERIVED_FILE_DIR)/chhaya-pqc/$(SDK_NAME)-$(CURRENT_ARCH)/libchhaya_pqc_combined.a"'
  }
  s.script_phase = {
    :name => 'Build pinned AWS-LC for Chhaya',
    :script => 'sh "${PODS_TARGET_SRCROOT}/../native/build_ios.sh"',
    :execution_position => :before_compile,
    :input_files => [
      '${PODS_TARGET_SRCROOT}/../native/CMakeLists.txt',
      '${PODS_TARGET_SRCROOT}/../native/chhaya_pqc.c',
      '${PODS_TARGET_SRCROOT}/../native/include/chhaya_pqc.h',
      '${PODS_TARGET_SRCROOT}/../tool/prepare.py'
    ],
    :output_files => ['$(DERIVED_FILE_DIR)/chhaya-pqc/$(SDK_NAME)-$(CURRENT_ARCH)/libchhaya_pqc_combined.a']
  }
end
