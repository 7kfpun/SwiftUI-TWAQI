# WIP: SwiftUI-TWAQI

## Download

[![App Store Button](assets/app-store.png "App Store Button")](https://itunes.apple.com/tw/app/id1286516443?mt=8)

## Screenshots

### iOS

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios3.png" width="210">

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios4.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios5.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios6.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios7.png" width="210">

### Apple Watch

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch3.png" width="210">

## Development

```bash
# Clone this repo
$ git clone git@github.com:7kfpun/SwiftUI-TWAQI.git

# Go inside the project and install pod dependencies
$ cd SwiftUI-TWAQI && pod install

# Copy example config
$ cp TWAQI/Config/example.xcconfig TWAQI/Config/debug.xcconfig

# Get a Google Maps API key, https://developers.google.com/maps/documentation/ios-sdk/get-api-key, and update the key `GMSServicesApiKey` in the debug.xcconfig file
$ open TWAQI/Config/debug.xcconfig

# Create a Firebase project and download the config file, GoogleService-Info.plist, to the folder, https://firebase.google.com/docs/ios/setup
$ cp ~/GoogleService-Info.plist TWAQI/GoogleService-Info.plist

# Open Xcode and run with Command (⌘)-R
$ open TWAQI.xcworkspace
```

## License

Released under the [MIT License](http://opensource.org/licenses/MIT).
