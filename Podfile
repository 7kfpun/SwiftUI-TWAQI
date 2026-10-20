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
  pod 'Firebase/Crashlytics'
  # Google decoupled AdMob from the Firebase pod bundle; it's a standalone pod now.
  pod 'Google-Mobile-Ads-SDK', '~> 12.5'

  pod 'Bugsnag', '~> 5.23'
  pod 'OneSignalXCFramework', '>= 3.0.0', '< 4.0'
  pod 'Sentry', :git => 'https://github.com/getsentry/sentry-cocoa.git', :tag => '5.0.4'

  # Host-app tests: they link against the app, so they only need the pods'
  # header and framework search paths, not another copy of every pod.
  target 'TWAQITests' do
    inherit! :search_paths
  end
end

target 'OneSignalNotificationServiceExtension' do
  platform :ios, '15.0'

  pod 'OneSignalXCFramework', '>= 3.0.0', '< 4.0'
end

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings.delete("EXCLUDED_ARCHS[sdk=iphonesimulator*]")
  end

  # Sentry is pinned to the 5.0.4 tag from 2020 and does not compile against a
  # current SDK: these files reached system types through headers that no longer
  # include them transitively. Patching here rather than by hand because Pods/
  # is gitignored, so a manual edit is lost on the next reinstall.
  #
  # This is a stopgap. The app already ships Firebase Crashlytics *and* Bugsnag,
  # so Sentry is a third crash reporter — the durable fix is to drop it or move
  # to a supported release, not to keep chasing missing includes.
  {
    "Sentry/Sources/SentryCrash/Recording/Monitors/SentryCrashMonitor_CPPException.cpp" =>
      ["#include <typeinfo>", "#include <exception>"],
    "Sentry/Sources/SentryCrash/Recording/Tools/SentryCrashMachineContext.c" =>
      ["#include \"SentryCrashMachineContext.h\"", "#include <sys/_types/_ucontext64.h>"],
  }.each do |relative, (anchor, include_line)|
    file = File.join(installer.sandbox.root, relative)
    next unless File.exist?(file)

    source = File.read(file)
    next if source.include?(include_line)
    next unless source.include?(anchor)

    # Pods fetched from git are checked out read-only.
    File.chmod(0o644, file)
    File.write(file, source.sub(anchor, "#{include_line}\n#{anchor}"))
    Pod::UI.puts "Patched #{File.basename(file)}: added #{include_line}"
  end

  # App Store Connect rejects any binary containing bitcode (error 90482).
  # OneSignal 3.9.1 predates that change and ships device slices built with it,
  # so an archive is refused at upload even though nothing here enables bitcode.
  # Strip it after every `pod install`, since a manual strip would be undone the
  # next time the pods are reinstalled.
  #
  # Only iOS *device* slices: those are the ones that end up in an archive, and
  # `bitcode_strip` fails outright on some simulator/catalyst/tvOS binaries.
  # Output goes to a temporary file and replaces the original only on success,
  # so a failure can't leave a truncated framework behind.
  Dir.glob(File.join(installer.sandbox.root, "**/*.xcframework/ios-arm*/**/*")).each do |path|
    next if path.include?("simulator") || path.include?("maccatalyst")
    # Mach-O binaries inside a framework carry no extension.
    next unless File.file?(path) && File.extname(path).empty?
    # The `__LLVM` segment alone is not enough: several frameworks carry
    # `__LLVM` for command-line/coverage metadata with no bitcode in it, and
    # `bitcode_strip` errors out on those. Embedded bitcode is the `__bundle`
    # section — that is what Apple's 90482 check looks for.
    next unless `otool -l "#{path}" 2>/dev/null`.include?("sectname __bundle")

    stripped = "#{path}.nobitcode"
    if system("xcrun bitcode_strip -r \"#{path}\" -o \"#{stripped}\" > /dev/null 2>&1")
      FileUtils.mv(stripped, path)
      Pod::UI.puts "Stripped bitcode: #{path.sub(installer.sandbox.root.to_s + '/', '')}"
    else
      FileUtils.rm_f(stripped)
      Pod::UI.warn "Could not strip bitcode from #{File.basename(path)}"
    end
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
