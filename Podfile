# Podfile for KittenTTS
platform :ios, '15.0'

target 'KittenTTS' do
  use_frameworks!

  # ONNX Runtime for KittenTTS model inference
  pod 'onnxruntime-objc', '~> 1.19.0'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
