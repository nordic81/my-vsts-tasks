# Additional tasks for VSTS / TFS Build.

Most of the build and test infrastructure is copied from [Microsoft's VSTS Tasks](https://github.com/Microsoft/vsts-tasks).

Currently, there are the follwing tasks:

* [_RunOpenCover_](Tasks/RunOpenCover/README.md).
* [_RunDotCover_](Tasks/RunDotCover/README.md).

## About

This fork is based on [my-vsts-tasks Version 0.8.0](https://github.com/cklutz/my-vsts-tasks) by [Christian Klutz](https://github.com/cklutz).
Most of the credit belongs to him.

Changes I've made to the original version:
* added support for vstest installed by the tools installer
* fixed the count bug as noted in [this issue](https://github.com/cklutz/my-vsts-tasks/issues/2)
* changed the OpenCover registration from **user** to **administrator** so that the task can be run by build agent services
* added support for multiple .trx files (if you intend to run multiple test-tasks within the same build)
* added another task which does essentially the same but with JetBrains dotCover, which is much faster compared to OpenCover

## Status

|   | Build & Test |
|---|:-----:|
|![Win](docs/images/win_med.png) **Windows**|[![Build status](https://ci.appveyor.com/api/projects/status/9k1g30ayowc4j8wg?svg=true)](https://ci.appveyor.com/project/nordic81/my-vsts-tasks)|

## Build

### Fast pass

To build and test everything, simply use:

     build-full.cmd

You will find packaged tasks in `_packages\tasks.zip`, from where you can [deploy/upload](#deploy-from-a-package) them.

### Manual steps

Once, install dependencies:

     npm install

To increment all task's patch level - required to allow upload of a new version to VSTS/TFS:

     node make.js bump

Build and test:

     npm run build
     npm test

Build a single task:

     node make.js build --task RunOpenCover
     node make.js build --task RunDotCover
     node make.js test --task RunOpenCover
     node make.js test --task RunDotCover

## Deploy a Build Task

### One time preparation

Use the [tfx-cli](https://github.com/Microsoft/tfs-cli) tool to upload and generally
manage build tasks for VSTS or an on premise TFS instance.

Install the tfx tool by `npm install -g tfx-cli`.

Afterwards make sure you login to your TFS / VSTS instance of choice, for example:

     tfx login -u http://localhost:8080/tfs/MyCollection --token <token>

(You can create a token from your "Security" settings in TFS/VSTS). I recommend setting
the `TFX_TRACE` environment variable to `1` for all your work, because otherwise the
tfx utility is a little to quiet, especially and even when errors occur (e.g. a login
fails).

### Deployment

#### Deploy a local build

To deploy the result of a local build (e.g. from cloning this repo):

     tfx build tasks upload --task.path .\_build\Tasks\RunOpenCover
     tfx build tasks upload --task.path .\_build\Tasks\RunDotCover

Make sure to update at least the patch version in your `task.json` everytime you
redeploy a new version (e.g. via `node make.js bump`).

#### Deploy from a package

To deploy the result of a release's `tasks.zip`:

     7za x -o %TEMP%\tasks tasks.zip
     tfx build tasks upload --task.path %TEMP%\tasks\RunOpenCover
     tfx build tasks upload --task.path %TEMP%\tasks\RunDotCover


