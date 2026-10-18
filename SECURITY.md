# Security Policy 🔒 (HYDRA-UMC-IOS-CONTROL)

## Reporting a Vulnerability

Focus on **Keychain security** and **Secure Token storage** in Flutter.

Report privately to `electrohobby3d@gmail.com`.

## Credentials

The client never pre-populates a reusable administrator password. Operators
enter the credentials issued by their server bootstrap process; tokens are
stored through the platform's secure storage mechanism (the iOS Keychain,
this device only). The 3D view is a web page that keeps the session token in
its own web storage while it is open; that storage is emptied on sign-out.
