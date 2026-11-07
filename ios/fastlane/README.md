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

Frame the raw captures in /Users/kf/Documents/Workspace/SwiftUI-TWAQI/ios/fastlane/screenshots_raw/<locale> into App Store sized PNGs

Requires ImageMagick (brew install imagemagick)

### ios frame_duo_screenshots

```sh
[bundle exec] fastlane ios frame_duo_screenshots
```

Frame only the iPhone Duo captures (fastlane/screenshots_raw/<locale>/iPhone Duo NN.png)

Leaves the iPhone, iPad and watch screenshots already framed alone

### ios capture_screenshots

```sh
[bundle exec] fastlane ios capture_screenshots
```

Capture the raw App Store screenshots of the four headline features on one simulator

AppStoreScreenshotTests takes map, station, 24-hour chart and Favourites, once per locale, into

fastlane/screenshots_raw/<locale>/<prefix> NN <name>.png. Then run frame_screenshots

Options: device (simulator name, default "iPhone 18 Pro"), udid (a simulator's id, used instead

of device, so parallel worktrees can each capture on their own), prefix ("iPhone" or "iPad",

default "iPhone"), zoom (map zoom, default 7.2), derived_data (default /tmp/twaqi-screenshots).

The Duo keeps capture_duo_screenshots

### ios capture_duo_screenshots

```sh
[bundle exec] fastlane ios capture_duo_screenshots
```

Capture the raw iPhone Duo screenshots on the unfolded iPhone Duo simulator (iOS 27.1+)

DuoScreenshotTests takes 01-02, once per locale, into

fastlane/screenshots_raw/<locale>/iPhone Duo NN.png. Then run frame_duo_screenshots

Options: device (simulator name, default "iPhone Duo")

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only to App Store Connect for 3.1.4

Does not touch the binary, the metadata, or the review submission

Leaves out the iPhone Duo images: overwrite removes the Duo set already on the version,

and upload_duo_screenshots adds a fresh one

### ios upload_watch_screenshots

```sh
[bundle exec] fastlane ios upload_watch_screenshots
```

Upload the Apple Watch screenshots only to App Store Connect for 3.1.4

Leaves the iPhone and iPad screenshots already on the version alone

### ios upload_duo_screenshots

```sh
[bundle exec] fastlane ios upload_duo_screenshots
```

Upload the iPhone Duo screenshots only to App Store Connect for 3.1.4

Leaves the iPhone, iPad and watch screenshots already on the version alone

Refuses a framed Duo image whose raw capture isn't in fastlane/screenshots_raw

### ios frame_vision_screenshots

```sh
[bundle exec] fastlane ios frame_vision_screenshots
```

Frame only the Vision Pro captures (fastlane/screenshots_raw/<locale>/Vision Pro NN.png)

Capture them first with tools/capture_vision_screenshots.sh

### ios upload_vision_screenshots

```sh
[bundle exec] fastlane ios upload_vision_screenshots
```

Upload the Vision Pro screenshots only to the visionOS 3.1.4 version

Replaces the Vision Pro set in each locale; leaves every other platform alone

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload text metadata only to App Store Connect for 3.1.4

Does not touch the binary, the screenshots, or the review submission

### ios release_build

```sh
[bundle exec] fastlane ios release_build
```

Archive a Release build of 3.1.4 and upload it to App Store Connect

Bumps every target's build number past the latest one on TestFlight. Never submits for review

### ios asc_version_state

```sh
[bundle exec] fastlane ios asc_version_state
```

Print the App Store Connect state of the 3.1.4 version on each platform. Read-only

Screenshot upload lanes refuse to run unless the state is one where screenshots can be edited

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Frame, then upload

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
