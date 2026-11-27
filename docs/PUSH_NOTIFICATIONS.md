# Push notifications from the server

HYDRA-UMC-SERVER can tell this iPhone, even with the app closed, when a job finishes, when a global stop is issued and when the
heartbeat of an operator is lost. They travel through Firebase Cloud Messaging, which delivers them with the Apple Push
Notification service.

**They only inform.** A notification carries a title and a sentence. The app registers no category and no action: nothing can
be stopped, moved or confirmed from it, and tapping it only opens the app.

## The Firebase configuration of the build

The configuration file is not kept in the repository. The build copies `ios/Runner/GoogleService-Info.plist` into the app when
it is there (Git ignores it). In GitHub Actions it is written from the repository secret `GOOGLE_SERVICE_INFO_PLIST`, only for
the main branch and the pull requests of the owner, and removed after the build.

It must be the file of an Apple app registered in the Firebase project with the bundle id `com.hydraumc.hydraUmcControl`.

Without it (a clone of the repository, a pull request from a fork) the app builds and works the same: the switch in Settings is
greyed out and says that this build has no Firebase configuration.

## What is still missing to receive one on an iPhone

1. An Apple Developer Program membership (paid). The push service is not available to a free account.
2. An APNs authentication key (`.p8`) of that account, uploaded to the Firebase project (Project settings, Cloud Messaging).
3. The Push Notifications capability in the App ID and a provisioning profile with it, to sign the app. The entitlement is
   already in `ios/Runner/Runner.entitlements`.
4. The server: push switched on and the key of the Firebase service account in place (see `docs/PUSH_NOTIFICATIONS.md` of
   HYDRA-UMC-SERVER).

None of the first three exists yet.

## What is tested, and what is not

The registration, its removal and a build without the configuration are covered by tests against a simulated server and a
simulated system. The app is compiled with Firebase in the continuous integration. No notification has been received on a
real iPhone.
