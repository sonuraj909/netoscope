#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint netoscope_native.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'netoscope_native'
  s.version          = '0.1.0'
  s.summary          = 'Native URLSession capture for Netoscope.'
  s.description      = <<-DESC
Captures HTTP calls made through URLSession and forwards them to Netoscope.
                       DESC
  s.homepage         = 'https://github.com/sonuraj909/netoscope'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Netoscope contributors' => 'sonuraj909@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'netoscope_native/Sources/netoscope_native/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest, shared with the Swift package in netoscope_native/.
  s.resource_bundles = {'netoscope_native_privacy' => ['netoscope_native/Sources/netoscope_native/PrivacyInfo.xcprivacy']}
end
