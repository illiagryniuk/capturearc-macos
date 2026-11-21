> Historical Mac 1.1 release record. For the prepared Mac 1.2 and separate iPhone 1.0 release, use [Phone/Mac release preparation](../PhoneMac/BUILD_AND_HANDOFF.md).

# Export compliance

`ITSAppUsesNonExemptEncryption` is set to `false` in both release Info plists.

Version 1.0 does not implement encryption algorithms, encrypted networking, account authentication, cloud sync, or a custom security protocol. Standard cryptography supplied by the operating system is exempt. Confirm this answer again if networking, authentication, licensing, payments, or encryption code is added.
