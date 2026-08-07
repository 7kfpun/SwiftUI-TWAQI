# Uncomment the next line to define a global platform for your project
use_frameworks!

target 'TWAQI' do
  # Comment the next line if you don't want to use dynamic frameworks
  platform :ios, '15.0'

  # Pods for TWAQI
  pod 'Alamofire', '~> 5.2.0'
  pod 'GoogleMaps', '~> 9.4'
  pod 'SDWebImageSwiftUI', '~> 1.4.0'
  pod 'SnapKit', '~> 5.0'
  pod 'SwiftDate', '~> 6.1'
  pod 'SwiftyJSON', '~> 5.0'

  pod 'Firebase', '~> 12.17'
  pod 'Firebase/Analytics'
  pod 'Firebase/Messaging'
  pod 'Firebase/Crashlytics'
  # Google decoupled AdMob from the Firebase pod bundle; it's a standalone pod now.
  pod 'Google-Mobile-Ads-SDK', '~> 12.5'

  pod 'Amplitude-iOS', '~> 4.10'
  pod 'Bugsnag', '~> 5.23'
  pod 'OneSignalXCFramework', '>= 3.0.0', '< 4.0'
  pod 'Sentry', :git => 'https://github.com/getsentry/sentry-cocoa.git', :tag => '5.0.4'

end

target 'OneSignalNotificationServiceExtension' do
  platform :ios, '15.0'

  pod 'OneSignalXCFramework', '>= 3.0.0', '< 4.0'
end

target 'watch Extension' do
  platform :watchos, '6.0'

  pod 'Alamofire', '~> 5.2.0'
  pod 'SwiftDate', '~> 6.1'
  pod 'SwiftyJSON', '~> 5.0'
end

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings.delete("EXCLUDED_ARCHS[sdk=iphonesimulator*]")
  end

  # Pods targeting an older iOS than the app fail to link against libarclite
  # (removed in Xcode 14.3) or otherwise mismatch. Raise them to match the
  # app's deployment target.
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      target_version = config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"]
      if target_version && target_version.to_f < 15.0
        config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
      end
    end
  end
end
