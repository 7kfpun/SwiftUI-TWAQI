fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios frame_screenshots

```sh
[bundle exec] fastlane ios frame_screenshots
```

Frame the raw captures in /Users/kf/Documents/Workspace/SwiftUI-TWAQI/fastlane/screenshots_raw/<locale> into App Store sized PNGs

Requires ImageMagick (brew install imagemagick)

### ios frame_duo_screenshots

```sh
[bundle exec] fastlane ios frame_duo_screenshots
```

Frame only the iPhone Duo captures (fastlane/screenshots_raw/<locale>/iPhone Duo NN.png)

Leaves the iPhone, iPad and watch screenshots already framed alone

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only to App Store Connect for 3.1.0

Does not touch the binary, the metadata, or the review submission

### ios upload_watch_screenshots

```sh
[bundle exec] fastlane ios upload_watch_screenshots
```

Upload the Apple Watch screenshots only to App Store Connect for 3.1.0

Leaves the iPhone and iPad screenshots already on the version alone

### ios upload_duo_screenshots

```sh
[bundle exec] fastlane ios upload_duo_screenshots
```

Upload the iPhone Duo screenshots only to App Store Connect for 3.1.0

Leaves the iPhone, iPad and watch screenshots already on the version alone

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload text metadata only to App Store Connect for 3.1.0

Does not touch the binary, the screenshots, or the review submission

### ios release_build

```sh
[bundle exec] fastlane ios release_build
```

Archive a Release build of 3.1.0 and upload it to App Store Connect

Bumps every target's build number past the latest one on TestFlight. Never submits for review

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Frame, then upload

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
