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

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

Create the app on App Store Connect (run once)

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload screenshots and metadata to App Store Connect

### ios release

```sh
[bundle exec] fastlane ios release
```

Build, archive, and upload to App Store Connect

### ios ship

```sh
[bundle exec] fastlane ios ship
```

Full pipeline: metadata + build + upload + submit

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
