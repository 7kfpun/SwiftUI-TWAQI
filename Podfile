# Uncomment the next line to define a global platform for your project
use_frameworks!

target 'TWAQI' do
  # Comment the next line if you don't want to use dynamic frameworks
  platform :ios, '13.0'

  # Pods for TWAQI
  pod 'Alamofire', '~> 5.2.0'
  pod 'GoogleMaps', '~> 3.8'
  pod 'SDWebImageSwiftUI', '~> 1.4.0'
  pod 'SnapKit', '~> 5.0'
  pod 'SwiftDate', '~> 6.1'
  pod 'SwiftyJSON', '~> 5.0'

  pod 'Firebase', '~> 6.34'
  pod 'Firebase/AdMob'
  pod 'Firebase/Analytics'
  pod 'Firebase/InAppMessaging'
  pod 'Firebase/Messaging'
  pod 'Firebase/Crashlytics'


  pod 'Amplitude-iOS', '~> 4.10'
  pod 'AppCenter', '~> 3.1'
  pod 'AppCenter/Push'
  pod 'Bugsnag', '~> 5.23'
  pod 'OneSignalXCFramework', '>= 3.0.0', '< 4.0'
  pod 'Sentry', :git => 'https://github.com/getsentry/sentry-cocoa.git', :tag => '5.0.4'

end

target 'OneSignalNotificationServiceExtension' do
  platform :ios, '13.0'

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
    config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
  end
end
