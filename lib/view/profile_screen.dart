// RETIRED 6 Sep — merged into `lib/view/profile/profile_home_screen.dart`
// at Foo's request. `ProfileHomeScreen` there now does this file's entire
// job (the auth-gate deciding GuestProfileScreen vs. the real profile
// flow) plus the logged-in content itself, in one file instead of two.
//
// `lib/core/routes/app_routes.dart` was updated to import
// `ProfileHomeScreen` from its new location directly, so nothing in the
// app still imports this file. It's kept as this stub only because the
// device bridge this was edited through can't delete files — safe for you
// to delete `lib/view/profile_screen.dart` yourself (e.g. in your IDE or
// `git rm lib/view/profile_screen.dart`) whenever you next touch git.
