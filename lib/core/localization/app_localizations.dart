/// UC402 A4 / REQ_201_2–5 — whole-app translation lookup.
///
/// There's no Flutter `intl`/ARB code-gen wired into this repo, so this is a
/// small hand-rolled table instead: a `key -> {languageCode -> text}` map,
/// looked up through [t]. It deliberately mirrors `AccessibilityVm`'s shape
/// (a plain object read once at the `MaterialApp` root, refreshed after a
/// save, watched via `context.watch`) — see `LocaleVm` in this same folder.
///
/// HOW OTHER MODULES PLUG IN (AR / Itinerary / Nearby): the language
/// switcher on the Language screen sets one app-wide `currentCode`, but each
/// module owns its own screen text. To make YOUR screens respond to it:
///   1. Pick a namespace for your module's keys, e.g. `ar.title`,
///      `itinerary.emptyState`.
///   2. Add an entry for that key to each of the five maps below (English is
///      required; leaving a language out just falls back to English for
///      that string, which is safe but untranslated).
///   3. Replace your literal strings with `AppLocalizations.t('ar.title')`.
///   4. Add `context.watch<LocaleVm>();` near the top of your screen's
///      `build()` method so it rebuilds when the language changes.
/// That's the whole integration — nothing here needs to change for another
/// module to adopt it.
library;

class AppLocalizations {
  AppLocalizations._();

  /// The active language code (`en`/`zh`/`ms`/`es`/`hi` — see
  /// `Module5Constants.supportedLanguages`). Defaults to English for guests
  /// and before the first load; `LocaleVm` is what actually changes this.
  static String currentCode = 'en';

  /// Looks up [key] in the active language. Falls back to English, then to
  /// the key itself, so a missing translation shows *something* instead of
  /// crashing — this is the same defensive fallback the message-catalog
  /// getters below rely on.
  static String t(String key) {
    return _byCode[currentCode]?[key] ?? _en[key] ?? key;
  }

  static const Map<String, Map<String, String>> _byCode = {
    'en': _en,
    'zh': _zh,
    'ms': _ms,
    'es': _es,
    'hi': _hi,
  };

  // Keys are namespaced `<messageCatalog>.mN` (matching the getters added to
  // register/login/passwordReset/profile messages) plus a `ui.*` namespace
  // for literal strings inside the screens themselves (button labels, field
  // labels, screen titles).
  static const Map<String, String> _en = {
    'ai.greeting': 'Here’s Manja, your AI Travel Assistant!',
    'ai.title': 'Travel Assistant',
    'ai.showSummary': 'Show conversation summary',
    'ai.searchConversation': 'Search conversation',
    'ai.resetConversation': 'Reset conversation',
    'ai.resetTitle': 'Reset conversation?',
    'ai.resetMessage':
        'Your current chat messages will be cleared. The selected attraction will stay available.',
    'ai.cancel': 'Cancel',
    'ai.reset': 'Reset',
    'ai.leaveTitle': 'Leave AI chat?',
    'ai.leaveMessage':
        'Your latest conversation summary will be saved when you leave. Are you sure you want to continue?',
    'ai.leave': 'Leave',
    'ai.stay': 'Stay',
    'ai.discussing': 'Discussing: {place}',
    'ai.inputHint': 'Ask something... (e.g. History of A Famosa)',
    'ai.sendQuestion': 'Send question',
    'ai.summary': 'Summary',
    'ai.closeSummary': 'Close summary',
    'ai.noSummary': 'No conversation summary is available yet.',
    'ai.checkingPlaces': 'Checking verified places…',
    'ai.mapsFailure': 'Unable to open Google Maps.',
    'ai.openMaps': 'Open in Google Maps',
    'ai.verifiedPlace': 'Verified place',
    'ai.chooseVerifiedPlace': 'Choose a verified place',
    'ai.bookmark': 'Bookmark',
    'ai.bookmarked': 'Bookmarked',
    'ai.loginTitle': 'Log in to bookmark',
    'ai.loginMessage':
        'You need to log in before you can save this place to your bookmarks.',
    'ai.notNow': 'Not now',
    'ai.login': 'Log in',
    'ai.searchPrompt': 'Search messages in this conversation.',
    'ai.noMatches': 'No matches found in this conversation.',
    'ai.clearSearch': 'Clear search',
    'ai.closeSearch': 'Close search',

    // register_messages.dart
    'register.m1': 'Your account has been registered successfully.',
    'register.m2':
    'A one-time password (OTP) has been sent to your phone number. '
        'Please enter it within 5 minutes.',
    'register.m3': 'Unable to sign in with Google. Please try again.',
    'register.m4':
    'This phone number is already registered. Please log in using your existing account.',
    'register.m5': 'Please enter a valid phone number.',
    'register.m6': 'The OTP entered is incorrect or has expired. Please try again.',
    'register.m7': 'This Username is already taken. Please choose a different Username.',
    'register.m8':
    'Password must contain at least 8 characters, including at least one letter and one number.',
    'register.m9': 'Too many requests. Please try again later.',
    'register.m10':
    'Passwords do not match. Please enter the same password in both fields.',
    'register.m11': 'Please enter your full name.',
    'register.m12': 'Please select your date of birth.',
    'register.m13': 'Date of birth cannot be in the future.',
    'register.m14': 'Unable to save your details. Please try again.',
    'register.m15': 'Please enter a valid username (3–20 letters, numbers, or underscores, starting with a letter).',

    // login_messages.dart
    'login.m1': 'Login successful. Start enjoying your trip with NarrateMy.',
    'login.m2':
    'A one-time password (OTP) has been sent to your phone number. '
        'Please enter it within 5 minutes.',
    'login.m3': 'Unable to sign in with Google. Please try again.',
    'login.m4':
    'No account was found. Please check your login details or register a new account.',
    'login.m5': 'The OTP entered is incorrect or has expired. Please try again.',
    'login.m6': 'The Username or password entered is incorrect.',
    'login.m7':
    'Too many failed login attempts. Your account has been locked for 30 minutes. '
        'Please try again later or reset your password.',
    'login.m8':
    'Too many OTP requests or verification attempts have been made. Please try again later.',
    'login.m9': 'Please enter your username and password.',

    // password_reset_messages.dart
    'passwordReset.m1': 'Enter your registered phone number to reset your password.',
    'passwordReset.m2':
    'A one-time password (OTP) has been sent to your phone number. '
        'Please enter it within 5 minutes.',
    'passwordReset.m3': 'Your password has been reset successfully. You may now log in.',
    'passwordReset.m4': 'This phone number is not registered.',
    'passwordReset.m5': 'The OTP entered is incorrect or has expired. Please try again.',
    'passwordReset.m6':
    'Password must contain at least 8 characters, including at least one letter and one number.',
    'passwordReset.m7': 'The passwords entered do not match. Please try again.',
    'passwordReset.m8': 'Too many requests. Please try again later.',
    'passwordReset.m9':
        'This phone number is registered without a password. Please log in with Phone + OTP instead.',

    // profile_messages.dart
    'profile.m1': 'Manage your profile, preferences, and preferred language.',
    'profile.m2': 'Your profile has been updated successfully.',
    'profile.m3': 'Unable to load your profile. Please try again.',
    'profile.m4': 'Please correct the highlighted information before continuing.',
    'profile.m5': 'Your changes have been discarded.',
    'profile.m6': 'Unable to update your profile. Please try again.',
    'profile.m7': 'Your session has expired. Please log in again.',
    'profile.m8': 'Please enter a valid phone number.',
    'profile.m9': 'This phone number is already registered to another account.',
    'profile.m10': 'The OTP entered is incorrect or has expired. Please try again.',
    'profile.m11':
    'A one-time password (OTP) has been sent to your phone number. '
        'Please enter it within 5 minutes.',
    'profile.m12':
    'Your Google account has been linked successfully. You can now sign in with Google.',
    'profile.m13': 'Unable to link your Google account. Please try again.',
    'profile.m14': 'This Google account is already linked to another NarrateMy account.',
    'profile.m15': 'Your password has been changed successfully.',
    'profile.m16': 'The current password entered is incorrect.',
    'profile.m17':
    'Password must contain at least 8 characters, including at least one letter and one number.',
    'profile.m18': 'The new passwords entered do not match.',
    'profile.m19':
    'Are you sure you want to unlink your Google account? '
        'You will no longer be able to sign in with Google.',
    'profile.m20': 'Your Google account has been unlinked.',
    'profile.m21': 'You must verify a phone number before unlinking your Google account.',
    'profile.m22':
    'Delete your account? Your profile, preferences, and bookmarks will '
        'be deactivated immediately and permanently removed after 30 '
        'days. Logging back in before then restores your account.',
    'profile.m23':
    'Your account has been deactivated. It will be permanently deleted '
        'in 30 days unless you log back in.',
    'profile.m24': 'Unable to delete your account. Please try again.',
    'profile.m25': 'Unable to update your profile picture. Please try again.',
    'profile.m26': 'Username and password set successfully.',

    // ui.* — literal strings inside Module 5's screens
    'ui.save': 'Save',
    'ui.cancel': 'Cancel',
    'ui.edit': 'Edit',
    'ui.login': 'Log In',
    'ui.createAccount': 'Create Account',
    'ui.logout': 'Log Out',
    'ui.profile': 'Profile',
    'ui.personalInfo': 'Personal Info',
    'ui.preferences': 'Preferences',
    'ui.language': 'Language',
    'ui.bookmarks': 'Bookmarks',
    'ui.guidance': 'Guidance',
    'ui.guidanceSubtitle': 'Step-by-step walkthroughs for each part of the app.',
    'ui.arGuide': 'AR Guide',
    'ui.arGuideExplorationTitle': 'Explore in AR',
    'ui.arGuideExplorationBody':
    'Point your camera around a heritage site to discover markers on '
        'nearby points of interest.',
    'ui.arGuidePlacementTitle': 'Place a 3D Model',
    'ui.arGuidePlacementBody':
    'Scan a flat surface, then tap to place and reposition a 3D model '
        'in the real world.',
    'ui.arGuideNarrationsTitle': 'Narrations',
    'ui.arGuideNarrationsBody':
    'Explore the attraction through different narration options. Listen to storytelling, watch related videos, and get recommendations for nearby attractions and places to explore.',
    'ui.arGuideNext': 'Next',
    'ui.arGuideBack': 'Back',
    'ui.arGuideDone': 'Done',
    'ui.arGuideSkip': 'Skip',
    'ui.nearbyGuide': 'Nearby Recommendation Guide',
    'ui.nearbyGuideMapTitle': 'Find Nearby Attractions',
    'ui.nearbyGuideMapBody':
    'Open Nearby to see personalized recommendations in blue and AR-enabled '
        'attractions in red. The badges show the visible range and '
        'recommendation count.',
    'ui.nearbyGuideDetailsTitle': 'View Place Details',
    'ui.nearbyGuideDetailsBody':
    'Tap any marker to view its photo, address, Google Maps directions, and '
        'whether AR is available.',
    'ui.nearbyGuideActionsTitle': 'Explore Available Actions',
    'ui.nearbyGuideActionsBody':
    'Scroll down to open an available AR experience or bookmark the '
        'attraction for later.',
    'ui.nearbyGuideArTitle': 'Visit the AR Activation Area',
    'ui.nearbyGuideArBody':
    'AR unlocks only when you are within the attraction’s activation area. '
        'Follow Google Maps directions to get there.',
    'ui.nearbyGuideLoginTitle': 'Log In to Save Places',
    'ui.nearbyGuideLoginBody':
    'Guests can explore nearby places, but you must log in before adding an '
        'attraction to Bookmarks.',
    'ui.nearbyGuideBookmarksTitle': 'Find Saved Attractions',
    'ui.nearbyGuideBookmarksBody':
    'After logging in, open Profile and select Bookmarks to view or revisit '
        'your saved attractions.',
    'ui.changePassword': 'Change Password',
    'ui.currentPassword': 'Current Password',
    'ui.newPassword': 'New Password',
    'ui.confirmNewPassword': 'Confirm New Password',
    'ui.fullName': 'Full Name',
    'ui.bio': 'Bio',
    'ui.phoneNumber': 'Phone Number',
    'ui.password': 'Password',
    'ui.username': 'Username',
    'ui.googleAccount': 'Google Account',
    'ui.linked': 'Linked',
    'ui.notLinked': 'Not linked',
    'ui.link': 'Link',
    'ui.unlink': 'Unlink',
    'ui.add': 'Add',
    'ui.change': 'Change',
    'ui.notSet': 'Not set',
    'ui.setUsernameAndPassword': 'Set Username & Password',
    'ui.setUsernameAndPasswordHint':
        'Add a username and password so you can also log in without your phone or Google account.',
    'ui.sendOtp': 'Send OTP',
    'ui.changePhoneNumber': 'Change Phone Number',
    'ui.unlinkGoogleAccount': 'Unlink Google Account',
    'ui.guestBrowsing': "You're browsing as a guest",
    'ui.guestSubtitle':
    'Log in or create an account to save your preferences, bookmarks, '
        'and preferred language.',
    'ui.forgotPassword': 'Forgot Password?',
    'ui.dontHaveAccount': "Don't have an account?",
    'ui.alreadyHaveAccount': 'Already have an account?',
    'ui.enterOtp': 'Enter OTP',
    'ui.resendOtp': 'Resend OTP',
    'ui.verify': 'Verify',
    'ui.dateOfBirth': 'Date of Birth',
    'ui.next': 'Next',
    'ui.attractionInterests': 'Attraction Interests',
    'ui.foodCuisine': 'Food & Cuisine',
    'ui.dietaryPreferences': 'Dietary Preferences',
    'ui.accessibilityPreferences': 'Accessibility Preferences',
    'ui.categoryExclusions': 'Category Exclusions',
    'ui.deleteAccount': 'Delete Account',
    'ui.myBookmarks': 'My Bookmarks',
    'ui.noBookmarksYet': 'No bookmarks yet',
    'ui.remove': 'Remove',
    'ui.resetPassword': 'Reset Password',
    'ui.enterPhoneNumber': 'Enter Phone Number',

    // nearby_recommendation_screen.dart / nearby_recommendation_details_screen.dart
    // / nearby_ar_site_details_screen.dart — static UI chrome only. Recommendation
    // text itself (name/address/reason) is fetched from the backend and is
    // deliberately NOT translated here — see Recommendation.fromJson.
    'recommendation.mapLegendRecommended': 'Recommended',
    'recommendation.arAvailable': 'AR available',
    'recommendation.headerTitle': 'Nearby Attractions',
    'recommendation.foundCount': '{count} found',
    'recommendation.refreshTooltip': 'Refresh nearby attractions',
    'recommendation.hintFinding': 'Finding attractions near you...',
    'recommendation.hintTapToView': 'Tap any attraction to view details',
    'recommendation.hintNoneFound': 'No mappable attractions found',
    'recommendation.tryAgain': 'Try again',
    'recommendation.findingLocation': 'Finding your current location...',
    'recommendation.retry': 'Retry',
    'recommendation.arAvailableSnippet': 'AR available • {category}',
    'recommendation.arExperienceCountOne': '1 AR experience',
    'recommendation.arExperienceCountMany': '{count} AR experiences',
    'recommendation.arExperiencesAvailableOne': '1 AR experience available',
    'recommendation.arExperiencesAvailableMany':
    '{count} AR experiences available',
    'recommendation.locationServicesOff':
    'Turn on location services to discover nearby attractions.',
    'recommendation.locationPermissionRequired':
    'Location permission is required to find nearby attractions.',
    'recommendation.locationTimedOut':
    'Unable to get your current location. Check your location settings and try again.',
    'recommendation.arLocationsUnavailable':
    'AR locations are temporarily unavailable.',
    'recommendation.unableToLoad':
    'Unable to load nearby attractions. Please try again.',
    'recommendation.closeDetailsTooltip': 'Close details',
    'recommendation.loginToBookmarkTitle': 'Log in to bookmark',
    'recommendation.loginToBookmarkBody':
    'You need to log in before you can save attractions to your bookmarks.',
    'recommendation.no': 'No',
    'recommendation.logIn': 'Log in',
    'recommendation.attractionDetailsLabel': 'ATTRACTION DETAILS',
    'recommendation.distanceLabel': 'DISTANCE',
    'recommendation.estTravelLabel': 'EST. TRAVEL',
    'recommendation.estTravelValue': '~{minutes} min by car',
    'recommendation.bookmarked': 'Bookmarked',
    'recommendation.bookmark': 'Bookmark',
    'recommendation.arLocationLabel': 'AR LOCATION',
    'recommendation.arSharedLocationNotice':
    '{count} AR attractions share this exact location',
    'recommendation.noArInfoLinked':
    'AR experience information has not been linked yet.',
    'recommendation.openAr': 'Open AR',
    'recommendation.visitToUnlockAr': 'Visit location to unlock AR',
    'recommendation.availabilityWithinArea':
    'You are within an AR activation area. Open the AR camera to '
        'interact with this location.',
    'recommendation.availabilityVisitSite':
    'Visit this location to use its AR experiences.',
    'recommendation.availabilityNearestPoint':
    'AR works on site. The nearest activation point is {distance} away.',
    'recommendation.availableNow': 'Available now',
    'recommendation.awayDistance': '{distance} away',
    'recommendation.resolutionFailed':
    'Recommendations were found, but their map locations could not be '
        'verified. Please try again.',
    'recommendation.quotaReached':
    'AI recommendation quota has been reached. Please try again later.',
    'recommendation.remoteUnavailable':
    'Unable to retrieve nearby recommendations.',
    'nav.ar': 'AR',
    'nav.itinerary': 'Itinerary',
    'nav.nearby': 'Nearby',
    'nav.profile': 'Profile',
    'ar.permissionRequired':
    'Camera and Location access are required to use the AR feature.',
    'ar.enableInSettings': 'Enable in Settings',
    'ar.cameraStartError': 'Something went wrong starting the AR camera.',
    'ar.retry': 'Retry',
    'ar.placingManja': 'Placing Manja on ground...',
    'ar.resumingCamera': 'Resuming AR Camera...',
    'ar.initializingCamera': 'Initializing camera...',
    'ar.noMarkersNearby': 'No heritage markers detected nearby',
    'ar.markerDetectedOne': '1 heritage marker detected nearby',
    'ar.markersDetectedMany': '{count} heritage markers detected nearby',
    'ar.attractionsBand': '<{ceiling}M ATTRACTIONS',
    'ar.availableSection': 'AVAILABLE',
    'ar.nearbySection': 'NEARBY',
    'ar.markerAvailableBadge': 'Available',
    'ar.directionLeft': 'Left',
    'ar.directionRight': 'Right',
    'ar.directionAhead': 'Ahead',
    'ar.directionBehind': 'Behind',
    'ar.loading3d': 'Loading 3D {landmarkName}...',
    'ar.compilingGeometry': 'Compiling 3D WebGL geometry & textures',
    'ar.view360': '360° View',
    'ar.model3dUnavailableTitle': '3D Model Unavailable',
    'ar.model3dUnavailableBody':
    'The representative 3D model could not be loaded. Storytelling can '
        'continue without the 3D model.',
    'ar.moveDeviceTapSurface': 'Move device & tap surface to place Manja',
    'ar.storytelling': 'Storytelling',
    'ar.watchVideo': 'Watch Video',
    'ar.recommend': 'Recommend',
    'ar.backToActions': 'Back to Actions',
    'ar.exitAr': 'Exit AR',
    'ar.live': 'LIVE',
    'ar.takePhotoTooltip': 'Take Photo with Manja',
    'ar.photoSaved': '📸 Photo saved to Gallery!',
    'ar.photoSaveFailed': 'Failed to save photo. Please try again.',
    'ar.recommendedForYou': 'Recommended for you',
    'ar.closeRecommendations': 'Close recommendations',
    'ar.continueYourExperience': 'CONTINUE YOUR EXPERIENCE',
    'ar.findingNextExperiences': 'Finding the best next experiences…',
    'ar.noPlacementSurface':
    'No suitable placement surface detected. Please move your device to '
        'scan the surrounding area.',
    'ar.tapBlueSurfaceToPlace': 'Tap the blue surface to place Manja',
    'ar.actionPause': 'Pause',
    'ar.actionReplay': 'Replay Story',
    'ar.actionResume': 'Resume',
    'ar.actionPlay': 'Play',
    'ar.tapGroundContinue': 'Tap ground to place Manja & continue story',
    'ar.storyCompleted': 'Story Completed',
    'ar.paused': 'Paused',
    'ar.tapPlayToBegin': 'Tap Play to begin',
    'ar.no3dModelAvailable': 'No 3D Model Available',
    'ar.hide3dModel': 'Hide 3D Model',
    'ar.show3dModel': 'Show 3D Model',
    'ar.no3dModelForLandmark': 'No 3D model available for {landmarkName}',
    'ar.endStory': 'End Story',
    'ar.model3dMissingError':
    'Error: No 3D model found in database (model_3d_url is missing) for '
        '{landmarkName}.',
    'ar.loadingVideo': 'Loading video...',
    'ar.rewind10s': 'Rewind 10s',
    'ar.forward10s': 'Forward 10s',
    'ar.exitFullscreen': 'Exit Fullscreen',
    'ar.fullscreen': 'Fullscreen',
    'ar.close': 'Close',
    'ar.videoUnavailableTitle': 'Video Unavailable',
    'ar.videoUnavailableBody':
    'The related video is currently unavailable. Please try again '
        'later.',
    'ar.retryPlayback': 'Retry Playback',
    'ar.noFollowUpAttractions':
    'No suitable follow-up attractions were found.',
    'pref.attr.heritage': 'Heritage',
    'pref.attr.nature': 'Nature',
    'pref.attr.food': 'Food',
    'pref.attr.shopping': 'Shopping',
    'pref.attr.adventure': 'Adventure',
    'pref.cuisine.malay': 'Malay',
    'pref.cuisine.chinese': 'Chinese',
    'pref.cuisine.indian': 'Indian',
    'pref.cuisine.peranakan': 'Peranakan/Nyonya',
    'pref.cuisine.western': 'Western',
    'pref.cuisine.streetFood': 'Street Food',
    'pref.cuisine.seafood': 'Seafood',
    'pref.cuisine.vegetarianFriendly': 'Vegetarian-Friendly',
    'pref.dietary.halal': 'Halal',
    'pref.dietary.vegetarian': 'Vegetarian',
    'pref.dietary.vegan': 'Vegan',
    'pref.restriction.noPork': 'No Pork',
    'pref.restriction.noBeef': 'No Beef',
    'pref.restriction.glutenFree': 'Gluten-Free',
    'pref.restriction.nutAllergy': 'Nut Allergy',
    'pref.restriction.shellfishAllergy': 'Shellfish Allergy',
    'pref.restriction.dairyFree': 'Dairy-Free / Lactose Intolerant',
    'pref.access.wheelchair': 'Wheelchair Accessible',
    'pref.access.mobility': 'Mobility Assistance',
    'pref.access.visual': 'Visual Assistance',
    'pref.access.wheelchairDesc':
    'Prioritize ramps, lifts, and step-free routes',
    'pref.access.mobilityDesc':
    'Favor shorter routes and seating along the way',
    'pref.access.visualDesc': 'Highlight audio guides and tactile cues',
    'ui.dietaryRestrictionsTitle': 'Dietary Restrictions & Allergies',
    'onboarding.skip': 'Skip',
    'onboarding.title': 'Personalize your journey',
    'onboarding.subtitle':
    "Tell us what you're into so we can tailor recommendations — you "
        'can always change this later in Profile.',
    'onboarding.attractionsQuestion': 'What kind of attractions do you enjoy?',
    'onboarding.finishSetup': 'Finish setup',
  };

  static const Map<String, String> _zh = {
    'ai.greeting': '我是 Manja，您的 AI 旅行助手！',
    'ai.title': '旅行助手',
    'ai.showSummary': '显示对话摘要',
    'ai.searchConversation': '搜索对话',
    'ai.resetConversation': '重置对话',
    'ai.resetTitle': '要重置对话吗？',
    'ai.resetMessage': '当前聊天记录将被清除，所选景点仍会保留。',
    'ai.cancel': '取消',
    'ai.reset': '重置',
    'ai.leaveTitle': '要离开 AI 对话吗？',
    'ai.leaveMessage': '离开时会保存最新的对话摘要。确定要继续吗？',
    'ai.leave': '离开',
    'ai.stay': '留下',
    'ai.discussing': '正在讨论：{place}',
    'ai.inputHint': '请输入问题……（例如：A Famosa 的历史）',
    'ai.sendQuestion': '发送问题',
    'ai.summary': '摘要',
    'ai.closeSummary': '关闭摘要',
    'ai.noSummary': '目前还没有对话摘要。',
    'ai.checkingPlaces': '正在核实地点……',
    'ai.mapsFailure': '无法打开 Google 地图。',
    'ai.openMaps': '在 Google 地图中打开',
    'ai.verifiedPlace': '已核实地点',
    'ai.chooseVerifiedPlace': '选择已核实地点',
    'ai.bookmark': '收藏',
    'ai.bookmarked': '已收藏',
    'ai.loginTitle': '登录后收藏',
    'ai.loginMessage': '您需要先登录，才能将此地点保存到收藏夹。',
    'ai.notNow': '暂不',
    'ai.login': '登录',
    'ai.searchPrompt': '搜索此对话中的消息。',
    'ai.noMatches': '此对话中没有匹配结果。',
    'ai.clearSearch': '清除搜索',
    'ai.closeSearch': '关闭搜索',

    'register.m1': '您的账户已成功注册。',
    'register.m2': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'register.m3': '无法使用 Google 登录，请重试。',
    'register.m4': '此电话号码已被注册。请使用您现有的账户登录。',
    'register.m5': '请输入有效的电话号码。',
    'register.m6': '输入的OTP不正确或已过期，请重试。',
    'register.m7': '该用户名已被使用。请选择其他用户名。',
    'register.m8': '密码必须至少包含8个字符，并至少包含一个字母和一个数字。',
    'register.m9': '请求次数过多，请稍后再试。',
    'register.m10': '密码不匹配。请在两个字段中输入相同的密码。',
    'register.m11': '请输入您的全名。',
    'register.m12': '请选择您的出生日期。',
    'register.m13': '出生日期不能是将来的日期。',
    'register.m14': '无法保存您的详细信息。请重试。',
    'register.m15': '请输入有效的用户名（3-20个字母、数字或下划线，且必须以字母开头）。',

    'login.m1': '登录成功。开始使用 NarrateMy 享受您的旅行吧。',
    'login.m2': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'login.m3': '无法使用 Google 登录，请重试。',
    'login.m4': '未找到账户。请检查您的登录信息或注册新账户。',
    'login.m5': '输入的OTP不正确或已过期，请重试。',
    'login.m6': '输入的用户名或密码不正确。',
    'login.m7': '登录失败次数过多。您的账户已被锁定30分钟。请稍后再试或重置密码。',
    'login.m8': 'OTP请求或验证尝试次数过多。请稍后再试。',
    'login.m9': '请输入您的用户名和密码。',

    'passwordReset.m1': '请输入您注册的电话号码以重置密码。',
    'passwordReset.m2': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'passwordReset.m3': '您的密码已成功重置。现在可以登录了。',
    'passwordReset.m4': '此电话号码尚未注册。',
    'passwordReset.m5': '输入的OTP不正确或已过期，请重试。',
    'passwordReset.m6': '密码必须至少包含8个字符，并至少包含一个字母和一个数字。',
    'passwordReset.m7': '输入的密码不匹配。请重试。',
    'passwordReset.m8': '请求次数过多，请稍后再试。',
    'passwordReset.m9': '此电话号码注册时未设置密码。请改用手机号码 + 一次性密码 (OTP) 登录。',

    'profile.m1': '管理您的个人资料、偏好设置和首选语言。',
    'profile.m2': '您的个人资料已成功更新。',
    'profile.m3': '无法加载您的个人资料。请重试。',
    'profile.m4': '请在继续之前更正突出显示的信息。',
    'profile.m5': '您的更改已被放弃。',
    'profile.m6': '无法更新您的个人资料。请重试。',
    'profile.m7': '您的会话已过期。请重新登录。',
    'profile.m8': '请输入有效的电话号码。',
    'profile.m9': '此电话号码已注册到另一个账户。',
    'profile.m10': '输入的OTP不正确或已过期，请重试。',
    'profile.m11': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'profile.m12': '您的 Google 账户已成功关联。现在您可以使用 Google 登录。',
    'profile.m13': '无法关联您的 Google 账户。请重试。',
    'profile.m14': '此 Google 账户已关联到另一个 NarrateMy 账户。',
    'profile.m15': '您的密码已成功更改。',
    'profile.m16': '输入的当前密码不正确。',
    'profile.m17': '密码必须至少包含8个字符，并至少包含一个字母和一个数字。',
    'profile.m18': '输入的新密码不匹配。',
    'profile.m19': '您确定要取消关联您的 Google 账户吗？取消后您将无法再使用 Google 登录。',
    'profile.m20': '您的 Google 账户已取消关联。',
    'profile.m21': '在取消关联 Google 账户之前，您必须先验证电话号码。',
    'profile.m22': '删除您的账户？您的个人资料、偏好设置和收藏夹将立即停用，并在30天后永久删除。在此之前重新登录可恢复您的账户。',
    'profile.m23': '您的账户已停用，30天后将被永久删除，除非您重新登录。',
    'profile.m24': '无法删除您的账户。请重试。',
    'profile.m25': '无法更新您的头像。请重试。',
    'profile.m26': '用户名和密码设置成功。',

    'ui.save': '保存',
    'ui.cancel': '取消',
    'ui.edit': '编辑',
    'ui.login': '登录',
    'ui.createAccount': '创建账户',
    'ui.logout': '登出',
    'ui.profile': '个人资料',
    'ui.personalInfo': '个人信息',
    'ui.preferences': '偏好设置',
    'ui.language': '语言',
    'ui.bookmarks': '收藏夹',
    'ui.guidance': '使用指南',
    'ui.guidanceSubtitle': '各模块的分步操作指南。',
    'ui.arGuide': 'AR 指南',
    'ui.arGuideExplorationTitle': '在 AR 中探索',
    'ui.arGuideExplorationBody': '将相机对准遗产景点周围，发现附近兴趣点的标记。',
    'ui.arGuidePlacementTitle': '放置 3D 模型',
    'ui.arGuidePlacementBody': '扫描平面，然后点击以在现实世界中放置并调整 3D 模型的位置。',
    'ui.arGuideNarrationsTitle': '导览内容',
    'ui.arGuideNarrationsBody': '选择不同方式探索景点。您可以聆听故事讲解和其他导览内容、观看相关视频，并获取附近景点和下一站推荐。',
    'ui.arGuideNext': '下一步',
    'ui.arGuideBack': '上一步',
    'ui.arGuideDone': '完成',
    'ui.arGuideSkip': '跳过',
    'ui.nearbyGuide': '附近推荐指南',
    'ui.nearbyGuideMapTitle': '发现附近景点',
    'ui.nearbyGuideMapBody': '打开“附近”查看蓝色的个性化推荐和红色的 AR 景点。顶部标签会显示可见范围和推荐数量。',
    'ui.nearbyGuideDetailsTitle': '查看景点详情',
    'ui.nearbyGuideDetailsBody': '点击任意地图标记，查看照片、地址、Google 地图路线以及 AR 是否可用。',
    'ui.nearbyGuideActionsTitle': '使用景点功能',
    'ui.nearbyGuideActionsBody': '向下滚动以打开可用的 AR 体验，或收藏景点以便稍后查看。',
    'ui.nearbyGuideArTitle': '前往 AR 启用区域',
    'ui.nearbyGuideArBody': '只有进入景点的 AR 启用范围后才能打开 AR。您可以使用 Google 地图导航前往。',
    'ui.nearbyGuideLoginTitle': '登录后收藏景点',
    'ui.nearbyGuideLoginBody': '访客可以浏览附近景点，但必须登录后才能将景点加入收藏夹。',
    'ui.nearbyGuideBookmarksTitle': '查找已收藏景点',
    'ui.nearbyGuideBookmarksBody': '登录后，打开“个人资料”并选择“收藏夹”，即可查看或再次访问已收藏的景点。',
    'ui.changePassword': '更改密码',
    'ui.currentPassword': '当前密码',
    'ui.newPassword': '新密码',
    'ui.confirmNewPassword': '确认新密码',
    'ui.fullName': '全名',
    'ui.bio': '个人简介',
    'ui.phoneNumber': '电话号码',
    'ui.password': '密码',
    'ui.username': '用户名',
    'ui.googleAccount': 'Google 账户',
    'ui.linked': '已关联',
    'ui.notLinked': '未关联',
    'ui.link': '关联',
    'ui.unlink': '取消关联',
    'ui.add': '添加',
    'ui.change': '更改',
    'ui.notSet': '未设置',
    'ui.setUsernameAndPassword': '设置用户名和密码',
    'ui.setUsernameAndPasswordHint': '添加用户名和密码，即使没有手机或 Google 账户也能登录。',
    'ui.sendOtp': '发送验证码',
    'ui.changePhoneNumber': '更改电话号码',
    'ui.unlinkGoogleAccount': '取消关联 Google 账户',
    'ui.guestBrowsing': '您正以访客身份浏览',
    'ui.guestSubtitle': '登录或创建账户以保存您的偏好设置、收藏夹和首选语言。',
    'ui.forgotPassword': '忘记密码？',
    'ui.dontHaveAccount': '还没有账户？',
    'ui.alreadyHaveAccount': '已经有账户？',
    'ui.enterOtp': '输入验证码',
    'ui.resendOtp': '重新发送验证码',
    'ui.verify': '验证',
    'ui.dateOfBirth': '出生日期',
    'ui.next': '下一步',
    'ui.attractionInterests': '景点兴趣',
    'ui.foodCuisine': '美食与菜系',
    'ui.dietaryPreferences': '饮食偏好',
    'ui.accessibilityPreferences': '无障碍偏好',
    'ui.categoryExclusions': '类别排除',
    'ui.deleteAccount': '删除账户',
    'ui.myBookmarks': '我的收藏夹',
    'ui.noBookmarksYet': '暂无收藏',
    'ui.remove': '移除',
    'ui.resetPassword': '重置密码',
    'ui.enterPhoneNumber': '输入电话号码',

    'recommendation.mapLegendRecommended': '推荐',
    'recommendation.arAvailable': 'AR 可用',
    'recommendation.headerTitle': '附近景点',
    'recommendation.foundCount': '找到 {count} 个',
    'recommendation.refreshTooltip': '刷新附近景点',
    'recommendation.hintFinding': '正在查找您附近的景点…',
    'recommendation.hintTapToView': '点击任意景点查看详情',
    'recommendation.hintNoneFound': '未找到可显示的景点',
    'recommendation.tryAgain': '重试',
    'recommendation.findingLocation': '正在获取您的当前位置…',
    'recommendation.retry': '重试',
    'recommendation.arAvailableSnippet': 'AR 可用 • {category}',
    'recommendation.arExperienceCountOne': '1 个 AR 体验',
    'recommendation.arExperienceCountMany': '{count} 个 AR 体验',
    'recommendation.arExperiencesAvailableOne': '1 个 AR 体验可用',
    'recommendation.arExperiencesAvailableMany': '{count} 个 AR 体验可用',
    'recommendation.locationServicesOff': '请开启定位服务以发现附近的景点。',
    'recommendation.locationPermissionRequired': '需要定位权限才能查找附近的景点。',
    'recommendation.locationTimedOut': '无法获取您的当前位置。请检查定位设置后重试。',
    'recommendation.arLocationsUnavailable': 'AR 地点暂时不可用。',
    'recommendation.unableToLoad': '无法加载附近的景点，请重试。',
    'recommendation.closeDetailsTooltip': '关闭详情',
    'recommendation.loginToBookmarkTitle': '登录后即可收藏',
    'recommendation.loginToBookmarkBody': '您需要先登录才能将景点保存到收藏夹。',
    'recommendation.no': '否',
    'recommendation.logIn': '登录',
    'recommendation.attractionDetailsLabel': '景点详情',
    'recommendation.distanceLabel': '距离',
    'recommendation.estTravelLabel': '预计车程',
    'recommendation.estTravelValue': '车程约 {minutes} 分钟',
    'recommendation.bookmarked': '已收藏',
    'recommendation.bookmark': '收藏',
    'recommendation.arLocationLabel': 'AR 地点',
    'recommendation.arSharedLocationNotice': '{count} 个 AR 景点位于同一地点',
    'recommendation.noArInfoLinked': 'AR 体验信息尚未关联。',
    'recommendation.openAr': '打开 AR',
    'recommendation.visitToUnlockAr': '前往该地点以解锁 AR',
    'recommendation.availabilityWithinArea':
    '您已进入 AR 激活区域，打开 AR 相机即可与该地点互动。',
    'recommendation.availabilityVisitSite': '前往该地点即可使用其 AR 体验。',
    'recommendation.availabilityNearestPoint':
    'AR 仅限现场使用，最近的激活点距离 {distance}。',
    'recommendation.availableNow': '现在可用',
    'recommendation.awayDistance': '距离 {distance}',
    'recommendation.resolutionFailed': '已找到推荐景点，但无法验证其地图位置，请重试。',
    'recommendation.quotaReached': 'AI 推荐配额已用完，请稍后再试。',
    'recommendation.remoteUnavailable': '无法获取附近的推荐景点。',
    'nav.ar': 'AR',
    'nav.itinerary': '行程',
    'nav.nearby': '附近',
    'nav.profile': '我的',
    'ar.permissionRequired': '使用AR功能需要摄像头和位置权限。',
    'ar.enableInSettings': '前往设置启用',
    'ar.cameraStartError': '启动AR摄像头时出现问题。',
    'ar.retry': '重试',
    'ar.placingManja': '正在将曼加放置到地面...',
    'ar.resumingCamera': '正在恢复AR摄像头...',
    'ar.initializingCamera': '正在初始化摄像头...',
    'ar.noMarkersNearby': '附近未检测到文化遗产标记',
    'ar.markerDetectedOne': '附近检测到1个文化遗产标记',
    'ar.markersDetectedMany': '附近检测到{count}个文化遗产标记',
    'ar.attractionsBand': '<{ceiling}米内的景点',
    'ar.availableSection': '可探索',
    'ar.nearbySection': '附近',
    'ar.markerAvailableBadge': '可探索',
    'ar.directionLeft': '左',
    'ar.directionRight': '右',
    'ar.directionAhead': '前方',
    'ar.directionBehind': '后方',
    'ar.loading3d': '正在加载{landmarkName}的3D模型...',
    'ar.compilingGeometry': '正在编译3D WebGL几何图形和纹理',
    'ar.view360': '360°视图',
    'ar.model3dUnavailableTitle': '3D模型不可用',
    'ar.model3dUnavailableBody': '无法加载代表性3D模型。故事讲述可以在没有3D模型的情况下继续。',
    'ar.moveDeviceTapSurface': '移动设备并点击表面以放置曼加',
    'ar.storytelling': '讲故事',
    'ar.watchVideo': '观看视频',
    'ar.recommend': '推荐',
    'ar.backToActions': '返回操作',
    'ar.exitAr': '退出AR',
    'ar.live': '直播',
    'ar.takePhotoTooltip': '与曼加拍照',
    'ar.photoSaved': '📸 照片已保存到相册！',
    'ar.photoSaveFailed': '保存照片失败，请重试。',
    'ar.recommendedForYou': '为您推荐',
    'ar.closeRecommendations': '关闭推荐',
    'ar.continueYourExperience': '继续您的体验',
    'ar.findingNextExperiences': '正在寻找最佳的后续体验…',
    'ar.noPlacementSurface': '未检测到合适的放置表面。请移动设备扫描周围区域。',
    'ar.tapBlueSurfaceToPlace': '点击蓝色平面放置 Manja',
    'ar.actionPause': '暂停',
    'ar.actionReplay': '重新播放故事',
    'ar.actionResume': '继续',
    'ar.actionPlay': '播放',
    'ar.tapGroundContinue': '点击地面放置曼加并继续故事',
    'ar.storyCompleted': '故事已完成',
    'ar.paused': '已暂停',
    'ar.tapPlayToBegin': '点击播放开始',
    'ar.no3dModelAvailable': '无可用3D模型',
    'ar.hide3dModel': '隐藏3D模型',
    'ar.show3dModel': '显示3D模型',
    'ar.no3dModelForLandmark': '{landmarkName}暂无可用3D模型',
    'ar.endStory': '结束故事',
    'ar.model3dMissingError':
    '错误：数据库中未找到{landmarkName}的3D模型（缺少model_3d_url）。',
    'ar.loadingVideo': '正在加载视频...',
    'ar.rewind10s': '快退10秒',
    'ar.forward10s': '快进10秒',
    'ar.exitFullscreen': '退出全屏',
    'ar.fullscreen': '全屏',
    'ar.close': '关闭',
    'ar.videoUnavailableTitle': '视频不可用',
    'ar.videoUnavailableBody': '相关视频当前不可用，请稍后重试。',
    'ar.retryPlayback': '重试播放',
    'ar.noFollowUpAttractions': '未找到合适的后续景点。',
    'pref.attr.heritage': '文化遗产',
    'pref.attr.nature': '自然风光',
    'pref.attr.food': '美食',
    'pref.attr.shopping': '购物',
    'pref.attr.adventure': '探险活动',
    'pref.cuisine.malay': '马来菜',
    'pref.cuisine.chinese': '中餐',
    'pref.cuisine.indian': '印度菜',
    'pref.cuisine.peranakan': '娘惹菜',
    'pref.cuisine.western': '西餐',
    'pref.cuisine.streetFood': '街头小吃',
    'pref.cuisine.seafood': '海鲜',
    'pref.cuisine.vegetarianFriendly': '素食友好',
    'pref.dietary.halal': '清真',
    'pref.dietary.vegetarian': '素食',
    'pref.dietary.vegan': '纯素食',
    'pref.restriction.noPork': '不吃猪肉',
    'pref.restriction.noBeef': '不吃牛肉',
    'pref.restriction.glutenFree': '无麸质',
    'pref.restriction.nutAllergy': '坚果过敏',
    'pref.restriction.shellfishAllergy': '贝类过敏',
    'pref.restriction.dairyFree': '无乳制品/乳糖不耐受',
    'pref.access.wheelchair': '轮椅无障碍',
    'pref.access.mobility': '行动辅助',
    'pref.access.visual': '视觉辅助',
    'pref.access.wheelchairDesc': '优先选择坡道、电梯和无台阶路线',
    'pref.access.mobilityDesc': '优先选择较短路线并在途中提供座位',
    'pref.access.visualDesc': '突出显示语音导览和触觉提示',
    'ui.dietaryRestrictionsTitle': '饮食限制与过敏',
    'onboarding.skip': '跳过',
    'onboarding.title': '个性化您的旅程',
    'onboarding.subtitle': '告诉我们您的兴趣，以便我们为您量身定制推荐 — 您以后随时可以在个人资料中更改。',
    'onboarding.attractionsQuestion': '您喜欢哪种类型的景点？',
    'onboarding.finishSetup': '完成设置',
  };

  static const Map<String, String> _ms = {
    'ai.greeting': 'Inilah Manja, Pembantu Perjalanan AI anda!',
    'ai.title': 'Pembantu Perjalanan',
    'ai.showSummary': 'Tunjukkan ringkasan perbualan',
    'ai.searchConversation': 'Cari dalam perbualan',
    'ai.resetConversation': 'Tetapkan semula perbualan',
    'ai.resetTitle': 'Tetapkan semula perbualan?',
    'ai.resetMessage':
        'Mesej sembang semasa akan dipadam. Tarikan yang dipilih akan kekal.',
    'ai.cancel': 'Batal',
    'ai.reset': 'Tetapkan semula',
    'ai.leaveTitle': 'Tinggalkan sembang AI?',
    'ai.leaveMessage':
        'Ringkasan perbualan terkini akan disimpan apabila anda keluar. Teruskan?',
    'ai.leave': 'Keluar',
    'ai.stay': 'Kekal',
    'ai.discussing': 'Sedang dibincangkan: {place}',
    'ai.inputHint': 'Tanya sesuatu... (cth. Sejarah A Famosa)',
    'ai.sendQuestion': 'Hantar soalan',
    'ai.summary': 'Ringkasan',
    'ai.closeSummary': 'Tutup ringkasan',
    'ai.noSummary': 'Belum ada ringkasan perbualan.',
    'ai.checkingPlaces': 'Menyemak tempat yang disahkan…',
    'ai.mapsFailure': 'Tidak dapat membuka Google Maps.',
    'ai.openMaps': 'Buka dalam Google Maps',
    'ai.verifiedPlace': 'Tempat yang disahkan',
    'ai.chooseVerifiedPlace': 'Pilih tempat yang disahkan',
    'ai.bookmark': 'Simpan',
    'ai.bookmarked': 'Disimpan',
    'ai.loginTitle': 'Log masuk untuk menyimpan',
    'ai.loginMessage': 'Anda perlu log masuk sebelum menyimpan tempat ini.',
    'ai.notNow': 'Bukan sekarang',
    'ai.login': 'Log masuk',
    'ai.searchPrompt': 'Cari mesej dalam perbualan ini.',
    'ai.noMatches': 'Tiada padanan ditemui dalam perbualan ini.',
    'ai.clearSearch': 'Kosongkan carian',
    'ai.closeSearch': 'Tutup carian',

    'register.m1': 'Akaun anda telah berjaya didaftarkan.',
    'register.m2':
    'Kata laluan sekali guna (OTP) telah dihantar ke nombor telefon anda. '
        'Sila masukkannya dalam masa 5 minit.',
    'register.m3': 'Tidak dapat log masuk dengan Google. Sila cuba lagi.',
    'register.m4':
    'Nombor telefon ini telah didaftarkan. Sila log masuk menggunakan akaun sedia ada anda.',
    'register.m5': 'Sila masukkan nombor telefon yang sah.',
    'register.m6': 'OTP yang dimasukkan tidak betul atau telah tamat tempoh. Sila cuba lagi.',
    'register.m7': 'Nama pengguna ini telah digunakan. Sila pilih Nama Pengguna lain.',
    'register.m8':
    'Kata laluan mesti mengandungi sekurang-kurangnya 8 aksara, '
        'termasuk sekurang-kurangnya satu huruf dan satu nombor.',
    'register.m9': 'Terlalu banyak permintaan. Sila cuba lagi kemudian.',
    'register.m10':
    'Kata laluan tidak sepadan. Sila masukkan kata laluan yang sama dalam kedua-dua ruangan.',
    'register.m11': 'Sila masukkan nama penuh anda.',
    'register.m12': 'Sila pilih tarikh lahir anda.',
    'register.m13': 'Tarikh lahir tidak boleh pada masa hadapan.',
    'register.m14': 'Tidak dapat menyimpan butiran anda. Sila cuba lagi.',
    'register.m15': 'Sila masukkan nama pengguna yang sah (3–20 huruf, nombor, atau garis bawah, bermula dengan huruf).',

    'login.m1': 'Log masuk berjaya. Mulakan perjalanan anda bersama NarrateMy.',
    'login.m2':
    'Kata laluan sekali guna (OTP) telah dihantar ke nombor telefon anda. '
        'Sila masukkannya dalam masa 5 minit.',
    'login.m3': 'Tidak dapat log masuk dengan Google. Sila cuba lagi.',
    'login.m4':
    'Tiada akaun ditemui. Sila semak butiran log masuk anda atau daftar akaun baharu.',
    'login.m5': 'OTP yang dimasukkan tidak betul atau telah tamat tempoh. Sila cuba lagi.',
    'login.m6': 'Nama Pengguna atau kata laluan yang dimasukkan tidak betul.',
    'login.m7':
    'Terlalu banyak percubaan log masuk gagal. Akaun anda telah dikunci selama 30 minit. '
        'Sila cuba lagi kemudian atau tetapkan semula kata laluan anda.',
    'login.m8':
    'Terlalu banyak permintaan OTP atau percubaan pengesahan telah dibuat. Sila cuba lagi kemudian.',
    'login.m9': 'Sila masukkan nama pengguna dan kata laluan anda.',

    'passwordReset.m1': 'Masukkan nombor telefon berdaftar anda untuk menetapkan semula kata laluan anda.',
    'passwordReset.m2':
    'Kata laluan sekali guna (OTP) telah dihantar ke nombor telefon anda. '
        'Sila masukkannya dalam masa 5 minit.',
    'passwordReset.m3': 'Kata laluan anda telah berjaya ditetapkan semula. Anda kini boleh log masuk.',
    'passwordReset.m4': 'Nombor telefon ini tidak berdaftar.',
    'passwordReset.m5': 'OTP yang dimasukkan tidak betul atau telah tamat tempoh. Sila cuba lagi.',
    'passwordReset.m6':
    'Kata laluan mesti mengandungi sekurang-kurangnya 8 aksara, '
        'termasuk sekurang-kurangnya satu huruf dan satu nombor.',
    'passwordReset.m7': 'Kata laluan yang dimasukkan tidak sepadan. Sila cuba lagi.',
    'passwordReset.m8': 'Terlalu banyak permintaan. Sila cuba lagi kemudian.',
    'passwordReset.m9':
        'Nombor telefon ini didaftarkan tanpa kata laluan. Sila log masuk menggunakan Telefon + OTP.',

    'profile.m1': 'Uruskan profil, keutamaan, dan bahasa pilihan anda.',
    'profile.m2': 'Profil anda telah berjaya dikemas kini.',
    'profile.m3': 'Tidak dapat memuatkan profil anda. Sila cuba lagi.',
    'profile.m4': 'Sila betulkan maklumat yang ditonjolkan sebelum meneruskan.',
    'profile.m5': 'Perubahan anda telah dibuang.',
    'profile.m6': 'Tidak dapat mengemas kini profil anda. Sila cuba lagi.',
    'profile.m7': 'Sesi anda telah tamat. Sila log masuk semula.',
    'profile.m8': 'Sila masukkan nombor telefon yang sah.',
    'profile.m9': 'Nombor telefon ini telah didaftarkan pada akaun lain.',
    'profile.m10': 'OTP yang dimasukkan tidak betul atau telah tamat tempoh. Sila cuba lagi.',
    'profile.m11':
    'Kata laluan sekali guna (OTP) telah dihantar ke nombor telefon anda. '
        'Sila masukkannya dalam masa 5 minit.',
    'profile.m12': 'Akaun Google anda telah berjaya dipautkan. Anda kini boleh log masuk dengan Google.',
    'profile.m13': 'Tidak dapat memautkan akaun Google anda. Sila cuba lagi.',
    'profile.m14': 'Akaun Google ini telah dipautkan dengan akaun NarrateMy yang lain.',
    'profile.m15': 'Kata laluan anda telah berjaya ditukar.',
    'profile.m16': 'Kata laluan semasa yang dimasukkan tidak betul.',
    'profile.m17':
    'Kata laluan mesti mengandungi sekurang-kurangnya 8 aksara, '
        'termasuk sekurang-kurangnya satu huruf dan satu nombor.',
    'profile.m18': 'Kata laluan baharu yang dimasukkan tidak sepadan.',
    'profile.m19':
    'Adakah anda pasti mahu menyahpautkan akaun Google anda? '
        'Anda tidak lagi boleh log masuk dengan Google.',
    'profile.m20': 'Akaun Google anda telah dinyahpautkan.',
    'profile.m21': 'Anda mesti mengesahkan nombor telefon sebelum menyahpautkan akaun Google anda.',
    'profile.m22':
    'Padam akaun anda? Profil, keutamaan, dan penanda halaman anda akan '
        'dinyahaktifkan serta-merta dan dipadamkan secara kekal selepas '
        '30 hari. Log masuk semula sebelum itu akan memulihkan akaun anda.',
    'profile.m23':
    'Akaun anda telah dinyahaktifkan. Ia akan dipadamkan secara kekal '
        'dalam masa 30 hari melainkan anda log masuk semula.',
    'profile.m24': 'Tidak dapat memadamkan akaun anda. Sila cuba lagi.',
    'profile.m25': 'Tidak dapat mengemas kini gambar profil anda. Sila cuba lagi.',
    'profile.m26': 'Nama pengguna dan kata laluan berjaya ditetapkan.',

    'ui.save': 'Simpan',
    'ui.cancel': 'Batal',
    'ui.edit': 'Edit',
    'ui.login': 'Log Masuk',
    'ui.createAccount': 'Cipta Akaun',
    'ui.logout': 'Log Keluar',
    'ui.profile': 'Profil',
    'ui.personalInfo': 'Maklumat Peribadi',
    'ui.preferences': 'Keutamaan',
    'ui.language': 'Bahasa',
    'ui.bookmarks': 'Penanda Halaman',
    'ui.guidance': 'Panduan',
    'ui.guidanceSubtitle': 'Panduan langkah demi langkah untuk setiap bahagian aplikasi.',
    'ui.arGuide': 'Panduan AR',
    'ui.arGuideExplorationTitle': 'Terokai dalam AR',
    'ui.arGuideExplorationBody':
    'Halakan kamera anda di sekitar tapak warisan untuk menemui penanda '
        'pada tempat menarik berdekatan.',
    'ui.arGuidePlacementTitle': 'Letakkan Model 3D',
    'ui.arGuidePlacementBody':
    'Imbas permukaan rata, kemudian ketik untuk meletakkan dan '
        'mengubah kedudukan model 3D di dunia sebenar.',
    'ui.arGuideNarrationsTitle': 'Narasi',
    'ui.arGuideNarrationsBody':
    'Pilih daripada pelbagai cara untuk meneroka tarikan tersebut. Dengarkan penceritaan dan narasi lain, tonton video berkaitan dan terima cadangan untuk tarikan berdekatan dan tempat yang mungkin anda ingin lawati seterusnya.',
    'ui.arGuideNext': 'Seterusnya',
    'ui.arGuideBack': 'Kembali',
    'ui.arGuideDone': 'Selesai',
    'ui.arGuideSkip': 'Langkau',
    'ui.nearbyGuide': 'Panduan Cadangan Berdekatan',
    'ui.nearbyGuideMapTitle': 'Cari Tarikan Berdekatan',
    'ui.nearbyGuideMapBody':
    'Buka Berdekatan untuk melihat cadangan peribadi berwarna biru dan '
        'tarikan AR berwarna merah. Lencana menunjukkan julat yang kelihatan '
        'dan bilangan cadangan.',
    'ui.nearbyGuideDetailsTitle': 'Lihat Butiran Tempat',
    'ui.nearbyGuideDetailsBody':
    'Ketik mana-mana penanda untuk melihat foto, alamat, arah Google Maps '
        'dan sama ada AR tersedia.',
    'ui.nearbyGuideActionsTitle': 'Gunakan Tindakan Tersedia',
    'ui.nearbyGuideActionsBody':
    'Tatal ke bawah untuk membuka pengalaman AR yang tersedia atau menanda '
        'tarikan untuk dilihat kemudian.',
    'ui.nearbyGuideArTitle': 'Pergi ke Kawasan Pengaktifan AR',
    'ui.nearbyGuideArBody':
    'AR hanya dibuka apabila anda berada dalam kawasan pengaktifan tarikan. '
        'Ikuti arah Google Maps untuk ke sana.',
    'ui.nearbyGuideLoginTitle': 'Log Masuk untuk Menyimpan Tempat',
    'ui.nearbyGuideLoginBody':
    'Tetamu boleh meneroka tempat berdekatan, tetapi anda mesti log masuk '
        'sebelum menambah tarikan pada Penanda Halaman.',
    'ui.nearbyGuideBookmarksTitle': 'Cari Tarikan yang Disimpan',
    'ui.nearbyGuideBookmarksBody':
    'Selepas log masuk, buka Profil dan pilih Penanda Halaman untuk melihat '
        'atau melawat semula tarikan yang disimpan.',
    'ui.changePassword': 'Tukar Kata Laluan',
    'ui.currentPassword': 'Kata Laluan Semasa',
    'ui.newPassword': 'Kata Laluan Baharu',
    'ui.confirmNewPassword': 'Sahkan Kata Laluan Baharu',
    'ui.fullName': 'Nama Penuh',
    'ui.bio': 'Bio',
    'ui.phoneNumber': 'Nombor Telefon',
    'ui.password': 'Kata Laluan',
    'ui.username': 'Nama Pengguna',
    'ui.googleAccount': 'Akaun Google',
    'ui.linked': 'Dipautkan',
    'ui.notLinked': 'Tidak dipautkan',
    'ui.link': 'Pautkan',
    'ui.unlink': 'Nyahpaut',
    'ui.add': 'Tambah',
    'ui.change': 'Tukar',
    'ui.notSet': 'Belum ditetapkan',
    'ui.setUsernameAndPassword': 'Tetapkan Nama Pengguna & Kata Laluan',
    'ui.setUsernameAndPasswordHint':
        'Tambah nama pengguna dan kata laluan supaya anda juga boleh log masuk tanpa telefon atau akaun Google anda.',
    'ui.sendOtp': 'Hantar OTP',
    'ui.changePhoneNumber': 'Tukar Nombor Telefon',
    'ui.unlinkGoogleAccount': 'Nyahpaut Akaun Google',
    'ui.guestBrowsing': 'Anda melayari sebagai tetamu',
    'ui.guestSubtitle':
    'Log masuk atau cipta akaun untuk menyimpan keutamaan, penanda halaman, '
        'dan bahasa pilihan anda.',
    'ui.forgotPassword': 'Lupa Kata Laluan?',
    'ui.dontHaveAccount': 'Tiada akaun?',
    'ui.alreadyHaveAccount': 'Sudah mempunyai akaun?',
    'ui.enterOtp': 'Masukkan OTP',
    'ui.resendOtp': 'Hantar Semula OTP',
    'ui.verify': 'Sahkan',
    'ui.dateOfBirth': 'Tarikh Lahir',
    'ui.next': 'Seterusnya',
    'ui.attractionInterests': 'Minat Tarikan',
    'ui.foodCuisine': 'Makanan & Masakan',
    'ui.dietaryPreferences': 'Keutamaan Pemakanan',
    'ui.accessibilityPreferences': 'Keutamaan Kebolehcapaian',
    'ui.categoryExclusions': 'Pengecualian Kategori',
    'ui.deleteAccount': 'Padam Akaun',
    'ui.myBookmarks': 'Penanda Halaman Saya',
    'ui.noBookmarksYet': 'Tiada penanda halaman lagi',
    'ui.remove': 'Alih keluar',
    'ui.resetPassword': 'Tetapkan Semula Kata Laluan',
    'ui.enterPhoneNumber': 'Masukkan Nombor Telefon',

    'recommendation.mapLegendRecommended': 'Disyorkan',
    'recommendation.arAvailable': 'AR tersedia',
    'recommendation.headerTitle': 'Tarikan Berhampiran',
    'recommendation.foundCount': '{count} ditemui',
    'recommendation.refreshTooltip': 'Muat semula tarikan berhampiran',
    'recommendation.hintFinding': 'Mencari tarikan berhampiran anda...',
    'recommendation.hintTapToView':
    'Ketik mana-mana tarikan untuk melihat butiran',
    'recommendation.hintNoneFound': 'Tiada tarikan yang boleh dipetakan ditemui',
    'recommendation.tryAgain': 'Cuba lagi',
    'recommendation.findingLocation': 'Mencari lokasi semasa anda...',
    'recommendation.retry': 'Cuba semula',
    'recommendation.arAvailableSnippet': 'AR tersedia • {category}',
    'recommendation.arExperienceCountOne': '1 pengalaman AR',
    'recommendation.arExperienceCountMany': '{count} pengalaman AR',
    'recommendation.arExperiencesAvailableOne': '1 pengalaman AR tersedia',
    'recommendation.arExperiencesAvailableMany':
    '{count} pengalaman AR tersedia',
    'recommendation.locationServicesOff':
    'Hidupkan perkhidmatan lokasi untuk menemui tarikan berhampiran.',
    'recommendation.locationPermissionRequired':
    'Kebenaran lokasi diperlukan untuk mencari tarikan berhampiran.',
    'recommendation.locationTimedOut':
    'Tidak dapat mendapatkan lokasi semasa anda. Semak tetapan lokasi dan cuba lagi.',
    'recommendation.arLocationsUnavailable':
    'Lokasi AR tidak tersedia buat sementara waktu.',
    'recommendation.unableToLoad':
    'Tidak dapat memuatkan tarikan berhampiran. Sila cuba lagi.',
    'recommendation.closeDetailsTooltip': 'Tutup butiran',
    'recommendation.loginToBookmarkTitle': 'Log masuk untuk menanda buku',
    'recommendation.loginToBookmarkBody':
    'Anda perlu log masuk sebelum boleh menyimpan tarikan ke penanda '
        'buku anda.',
    'recommendation.no': 'Tidak',
    'recommendation.logIn': 'Log masuk',
    'recommendation.attractionDetailsLabel': 'BUTIRAN TARIKAN',
    'recommendation.distanceLabel': 'JARAK',
    'recommendation.estTravelLabel': 'ANGGARAN PERJALANAN',
    'recommendation.estTravelValue': '~{minutes} minit dengan kereta',
    'recommendation.bookmarked': 'Ditanda buku',
    'recommendation.bookmark': 'Tanda buku',
    'recommendation.arLocationLabel': 'LOKASI AR',
    'recommendation.arSharedLocationNotice':
    '{count} tarikan AR berkongsi lokasi yang sama ini',
    'recommendation.noArInfoLinked':
    'Maklumat pengalaman AR belum dipautkan lagi.',
    'recommendation.openAr': 'Buka AR',
    'recommendation.visitToUnlockAr': 'Lawati lokasi untuk membuka kunci AR',
    'recommendation.availabilityWithinArea':
    'Anda berada dalam kawasan pengaktifan AR. Buka kamera AR untuk '
        'berinteraksi dengan lokasi ini.',
    'recommendation.availabilityVisitSite':
    'Lawati lokasi ini untuk menggunakan pengalaman AR-nya.',
    'recommendation.availabilityNearestPoint':
    'AR hanya berfungsi di lokasi. Titik pengaktifan terdekat ialah '
        '{distance} dari sini.',
    'recommendation.availableNow': 'Tersedia sekarang',
    'recommendation.awayDistance': '{distance} dari sini',
    'recommendation.resolutionFailed':
    'Cadangan telah ditemui, tetapi lokasi petanya tidak dapat '
        'disahkan. Sila cuba lagi.',
    'recommendation.quotaReached':
    'Kuota cadangan AI telah dicapai. Sila cuba lagi kemudian.',
    'recommendation.remoteUnavailable':
    'Tidak dapat mendapatkan cadangan berhampiran.',
    'nav.ar': 'AR',
    'nav.itinerary': 'Itinerari',
    'nav.nearby': 'Berdekatan',
    'nav.profile': 'Profil',
    'ar.permissionRequired':
    'Akses Kamera dan Lokasi diperlukan untuk menggunakan ciri AR.',
    'ar.enableInSettings': 'Dayakan dalam Tetapan',
    'ar.cameraStartError': 'Terdapat masalah semasa memulakan kamera AR.',
    'ar.retry': 'Cuba Lagi',
    'ar.placingManja': 'Meletakkan Manja di tanah...',
    'ar.resumingCamera': 'Menyambung semula Kamera AR...',
    'ar.initializingCamera': 'Memulakan kamera...',
    'ar.noMarkersNearby': 'Tiada penanda warisan dikesan berdekatan',
    'ar.markerDetectedOne': '1 penanda warisan dikesan berdekatan',
    'ar.markersDetectedMany': '{count} penanda warisan dikesan berdekatan',
    'ar.attractionsBand': 'TARIKAN <{ceiling}M',
    'ar.availableSection': 'TERSEDIA',
    'ar.nearbySection': 'BERDEKATAN',
    'ar.markerAvailableBadge': 'Tersedia',
    'ar.directionLeft': 'Kiri',
    'ar.directionRight': 'Kanan',
    'ar.directionAhead': 'Depan',
    'ar.directionBehind': 'Belakang',
    'ar.loading3d': 'Memuatkan model 3D {landmarkName}...',
    'ar.compilingGeometry': 'Menghimpun geometri & tekstur WebGL 3D',
    'ar.view360': 'Pandangan 360°',
    'ar.model3dUnavailableTitle': 'Model 3D Tidak Tersedia',
    'ar.model3dUnavailableBody':
    'Model 3D perwakilan tidak dapat dimuatkan. Penceritaan boleh '
        'diteruskan tanpa model 3D.',
    'ar.moveDeviceTapSurface':
    'Gerakkan peranti & ketik permukaan untuk meletakkan Manja',
    'ar.storytelling': 'Penceritaan',
    'ar.watchVideo': 'Tonton Video',
    'ar.recommend': 'Cadangan',
    'ar.backToActions': 'Kembali ke Tindakan',
    'ar.exitAr': 'Keluar AR',
    'ar.live': 'LANGSUNG',
    'ar.takePhotoTooltip': 'Ambil Foto bersama Manja',
    'ar.photoSaved': '📸 Foto disimpan ke Galeri!',
    'ar.photoSaveFailed': 'Gagal menyimpan foto. Sila cuba lagi.',
    'ar.recommendedForYou': 'Disyorkan untuk anda',
    'ar.closeRecommendations': 'Tutup cadangan',
    'ar.continueYourExperience': 'TERUSKAN PENGALAMAN ANDA',
    'ar.findingNextExperiences': 'Mencari pengalaman seterusnya yang terbaik…',
    'ar.noPlacementSurface':
    'Tiada permukaan penempatan yang sesuai dikesan. Sila gerakkan '
        'peranti anda untuk mengimbas kawasan sekeliling.',
    'ar.tapBlueSurfaceToPlace': 'Ketik permukaan biru untuk meletakkan Manja',
    'ar.actionPause': 'Jeda',
    'ar.actionReplay': 'Main Semula Cerita',
    'ar.actionResume': 'Sambung',
    'ar.actionPlay': 'Main',
    'ar.tapGroundContinue':
    'Ketik tanah untuk meletakkan Manja & teruskan cerita',
    'ar.storyCompleted': 'Cerita Selesai',
    'ar.paused': 'Dijeda',
    'ar.tapPlayToBegin': 'Ketik Main untuk bermula',
    'ar.no3dModelAvailable': 'Tiada Model 3D Tersedia',
    'ar.hide3dModel': 'Sembunyikan Model 3D',
    'ar.show3dModel': 'Tunjukkan Model 3D',
    'ar.no3dModelForLandmark': 'Tiada model 3D tersedia untuk {landmarkName}',
    'ar.endStory': 'Tamatkan Cerita',
    'ar.model3dMissingError':
    'Ralat: Tiada model 3D ditemui dalam pangkalan data (model_3d_url '
        'tiada) untuk {landmarkName}.',
    'ar.loadingVideo': 'Memuatkan video...',
    'ar.rewind10s': 'Undur 10s',
    'ar.forward10s': 'Maju 10s',
    'ar.exitFullscreen': 'Keluar Skrin Penuh',
    'ar.fullscreen': 'Skrin Penuh',
    'ar.close': 'Tutup',
    'ar.videoUnavailableTitle': 'Video Tidak Tersedia',
    'ar.videoUnavailableBody':
    'Video berkaitan tidak tersedia buat masa ini. Sila cuba lagi '
        'kemudian.',
    'ar.retryPlayback': 'Cuba Main Semula',
    'ar.noFollowUpAttractions': 'Tiada tarikan susulan yang sesuai ditemui.',
    'pref.attr.heritage': 'Warisan',
    'pref.attr.nature': 'Alam Semula Jadi',
    'pref.attr.food': 'Makanan',
    'pref.attr.shopping': 'Membeli-belah',
    'pref.attr.adventure': 'Pengembaraan',
    'pref.cuisine.malay': 'Melayu',
    'pref.cuisine.chinese': 'Cina',
    'pref.cuisine.indian': 'India',
    'pref.cuisine.peranakan': 'Peranakan/Nyonya',
    'pref.cuisine.western': 'Barat',
    'pref.cuisine.streetFood': 'Makanan Jalanan',
    'pref.cuisine.seafood': 'Makanan Laut',
    'pref.cuisine.vegetarianFriendly': 'Mesra Vegetarian',
    'pref.dietary.halal': 'Halal',
    'pref.dietary.vegetarian': 'Vegetarian',
    'pref.dietary.vegan': 'Vegan',
    'pref.restriction.noPork': 'Tiada Daging Babi',
    'pref.restriction.noBeef': 'Tiada Daging Lembu',
    'pref.restriction.glutenFree': 'Bebas Gluten',
    'pref.restriction.nutAllergy': 'Alahan Kekacang',
    'pref.restriction.shellfishAllergy': 'Alahan Kekerangan',
    'pref.restriction.dairyFree': 'Bebas Tenusu / Tidak Tahan Laktosa',
    'pref.access.wheelchair': 'Mesra Kerusi Roda',
    'pref.access.mobility': 'Bantuan Mobiliti',
    'pref.access.visual': 'Bantuan Penglihatan',
    'pref.access.wheelchairDesc':
    'Utamakan susur, lif, dan laluan tanpa anak tangga',
    'pref.access.mobilityDesc':
    'Utamakan laluan lebih pendek dan tempat duduk sepanjang perjalanan',
    'pref.access.visualDesc':
    'Utamakan panduan audio dan isyarat sentuhan',
    'ui.dietaryRestrictionsTitle': 'Sekatan Diet & Alahan',
    'onboarding.skip': 'Langkau',
    'onboarding.title': 'Peribadikan perjalanan anda',
    'onboarding.subtitle':
    'Beritahu kami minat anda supaya kami dapat menyesuaikan cadangan '
        '— anda boleh menukarnya kemudian di Profil.',
    'onboarding.attractionsQuestion':
    'Apakah jenis tarikan yang anda gemari?',
    'onboarding.finishSetup': 'Selesaikan persediaan',
  };

  static const Map<String, String> _es = {
    'ai.greeting': '¡Soy Manja, tu asistente de viajes con IA!',
    'ai.title': 'Asistente de viajes',
    'ai.showSummary': 'Mostrar resumen de la conversación',
    'ai.searchConversation': 'Buscar en la conversación',
    'ai.resetConversation': 'Restablecer conversación',
    'ai.resetTitle': '¿Restablecer la conversación?',
    'ai.resetMessage':
        'Se borrarán los mensajes actuales. La atracción seleccionada se conservará.',
    'ai.cancel': 'Cancelar',
    'ai.reset': 'Restablecer',
    'ai.leaveTitle': '¿Salir del chat de IA?',
    'ai.leaveMessage':
        'Al salir se guardará el resumen más reciente. ¿Quieres continuar?',
    'ai.leave': 'Salir',
    'ai.stay': 'Quedarme',
    'ai.discussing': 'Hablando de: {place}',
    'ai.inputHint': 'Pregunta algo... (p. ej., Historia de A Famosa)',
    'ai.sendQuestion': 'Enviar pregunta',
    'ai.summary': 'Resumen',
    'ai.closeSummary': 'Cerrar resumen',
    'ai.noSummary': 'Todavía no hay un resumen de la conversación.',
    'ai.checkingPlaces': 'Verificando lugares…',
    'ai.mapsFailure': 'No se pudo abrir Google Maps.',
    'ai.openMaps': 'Abrir en Google Maps',
    'ai.verifiedPlace': 'Lugar verificado',
    'ai.chooseVerifiedPlace': 'Elige un lugar verificado',
    'ai.bookmark': 'Guardar',
    'ai.bookmarked': 'Guardado',
    'ai.loginTitle': 'Inicia sesión para guardar',
    'ai.loginMessage': 'Debes iniciar sesión para guardar este lugar.',
    'ai.notNow': 'Ahora no',
    'ai.login': 'Iniciar sesión',
    'ai.searchPrompt': 'Busca mensajes en esta conversación.',
    'ai.noMatches': 'No se encontraron coincidencias en esta conversación.',
    'ai.clearSearch': 'Borrar búsqueda',
    'ai.closeSearch': 'Cerrar búsqueda',

    'register.m1': 'Su cuenta se ha registrado correctamente.',
    'register.m2':
    'Se ha enviado una contraseña de un solo uso (OTP) a su número de teléfono. '
        'Introdúzcala en un plazo de 5 minutos.',
    'register.m3': 'No se pudo iniciar sesión con Google. Inténtelo de nuevo.',
    'register.m4':
    'Este número de teléfono ya está registrado. Inicie sesión con su cuenta existente.',
    'register.m5': 'Introduzca un número de teléfono válido.',
    'register.m6': 'El OTP introducido es incorrecto o ha caducado. Inténtelo de nuevo.',
    'register.m7': 'Este nombre de usuario ya está en uso. Elija un nombre de usuario diferente.',
    'register.m8':
    'La contraseña debe tener al menos 8 caracteres, incluyendo al menos una letra y un número.',
    'register.m9': 'Demasiadas solicitudes. Inténtelo de nuevo más tarde.',
    'register.m10':
    'Las contraseñas no coinciden. Introduzca la misma contraseña en ambos campos.',
    'register.m11': 'Introduzca su nombre completo.',
    'register.m12': 'Seleccione su fecha de nacimiento.',
    'register.m13': 'La fecha de nacimiento no puede ser en el futuro.',
    'register.m14': 'No se pudieron guardar sus datos. Inténtelo de nuevo.',
    'register.m15': 'Introduzca un nombre de usuario válido (3–20 letras, números o guiones bajos, comenzando con una letra).',

    'login.m1': 'Inicio de sesión exitoso. Comience a disfrutar de su viaje con NarrateMy.',
    'login.m2':
    'Se ha enviado una contraseña de un solo uso (OTP) a su número de teléfono. '
        'Introdúzcala en un plazo de 5 minutos.',
    'login.m3': 'No se pudo iniciar sesión con Google. Inténtelo de nuevo.',
    'login.m4':
    'No se encontró ninguna cuenta. Verifique sus datos de inicio de sesión o registre una cuenta nueva.',
    'login.m5': 'El OTP introducido es incorrecto o ha caducado. Inténtelo de nuevo.',
    'login.m6': 'El nombre de usuario o la contraseña introducidos son incorrectos.',
    'login.m7':
    'Demasiados intentos de inicio de sesión fallidos. Su cuenta ha sido bloqueada durante 30 minutos. '
        'Inténtelo de nuevo más tarde o restablezca su contraseña.',
    'login.m8':
    'Se han realizado demasiadas solicitudes de OTP o intentos de verificación. Inténtelo de nuevo más tarde.',
    'login.m9': 'Introduzca su nombre de usuario y contraseña.',

    'passwordReset.m1': 'Introduzca su número de teléfono registrado para restablecer su contraseña.',
    'passwordReset.m2':
    'Se ha enviado una contraseña de un solo uso (OTP) a su número de teléfono. '
        'Introdúzcala en un plazo de 5 minutos.',
    'passwordReset.m3': 'Su contraseña se ha restablecido correctamente. Ahora puede iniciar sesión.',
    'passwordReset.m4': 'Este número de teléfono no está registrado.',
    'passwordReset.m5': 'El OTP introducido es incorrecto o ha caducado. Inténtelo de nuevo.',
    'passwordReset.m6':
    'La contraseña debe tener al menos 8 caracteres, incluyendo al menos una letra y un número.',
    'passwordReset.m7': 'Las contraseñas introducidas no coinciden. Inténtelo de nuevo.',
    'passwordReset.m8': 'Demasiadas solicitudes. Inténtelo de nuevo más tarde.',
    'passwordReset.m9':
        'Este número de teléfono está registrado sin contraseña. Inicie sesión con Teléfono + OTP.',

    'profile.m1': 'Administre su perfil, preferencias e idioma preferido.',
    'profile.m2': 'Su perfil se ha actualizado correctamente.',
    'profile.m3': 'No se pudo cargar su perfil. Inténtelo de nuevo.',
    'profile.m4': 'Corrija la información resaltada antes de continuar.',
    'profile.m5': 'Sus cambios se han descartado.',
    'profile.m6': 'No se pudo actualizar su perfil. Inténtelo de nuevo.',
    'profile.m7': 'Su sesión ha caducado. Inicie sesión de nuevo.',
    'profile.m8': 'Introduzca un número de teléfono válido.',
    'profile.m9': 'Este número de teléfono ya está registrado en otra cuenta.',
    'profile.m10': 'El OTP introducido es incorrecto o ha caducado. Inténtelo de nuevo.',
    'profile.m11':
    'Se ha enviado una contraseña de un solo uso (OTP) a su número de teléfono. '
        'Introdúzcala en un plazo de 5 minutos.',
    'profile.m12':
    'Su cuenta de Google se ha vinculado correctamente. Ahora puede iniciar sesión con Google.',
    'profile.m13': 'No se pudo vincular su cuenta de Google. Inténtelo de nuevo.',
    'profile.m14': 'Esta cuenta de Google ya está vinculada a otra cuenta de NarrateMy.',
    'profile.m15': 'Su contraseña se ha cambiado correctamente.',
    'profile.m16': 'La contraseña actual introducida es incorrecta.',
    'profile.m17':
    'La contraseña debe tener al menos 8 caracteres, incluyendo al menos una letra y un número.',
    'profile.m18': 'Las nuevas contraseñas introducidas no coinciden.',
    'profile.m19':
    '¿Está seguro de que desea desvincular su cuenta de Google? '
        'Ya no podrá iniciar sesión con Google.',
    'profile.m20': 'Su cuenta de Google ha sido desvinculada.',
    'profile.m21': 'Debe verificar un número de teléfono antes de desvincular su cuenta de Google.',
    'profile.m22':
    '¿Eliminar su cuenta? Su perfil, preferencias y marcadores se '
        'desactivarán de inmediato y se eliminarán permanentemente '
        'después de 30 días. Iniciar sesión antes de ese plazo restaura '
        'su cuenta.',
    'profile.m23':
    'Su cuenta ha sido desactivada. Se eliminará permanentemente en 30 '
        'días a menos que vuelva a iniciar sesión.',
    'profile.m24': 'No se pudo eliminar su cuenta. Inténtelo de nuevo.',
    'profile.m25': 'No se pudo actualizar su foto de perfil. Inténtelo de nuevo.',
    'profile.m26': 'Nombre de usuario y contraseña establecidos correctamente.',

    'ui.save': 'Guardar',
    'ui.cancel': 'Cancelar',
    'ui.edit': 'Editar',
    'ui.login': 'Iniciar Sesión',
    'ui.createAccount': 'Crear Cuenta',
    'ui.logout': 'Cerrar Sesión',
    'ui.profile': 'Perfil',
    'ui.personalInfo': 'Información Personal',
    'ui.preferences': 'Preferencias',
    'ui.language': 'Idioma',
    'ui.bookmarks': 'Marcadores',
    'ui.guidance': 'Guía',
    'ui.guidanceSubtitle': 'Guías paso a paso para cada parte de la app.',
    'ui.arGuide': 'Guía de RA',
    'ui.arGuideExplorationTitle': 'Explora en RA',
    'ui.arGuideExplorationBody':
    'Apunta tu cámara alrededor de un sitio patrimonial para descubrir '
        'marcadores de puntos de interés cercanos.',
    'ui.arGuidePlacementTitle': 'Coloca un Modelo 3D',
    'ui.arGuidePlacementBody':
    'Escanea una superficie plana y luego toca para colocar y '
        'reposicionar un modelo 3D en el mundo real.',
    'ui.arGuideNarrationsTitle': 'narraciones',
    'ui.arGuideNarrationsBody':
    'Elige entre diferentes maneras de explorar la atracción. Escucha narraciones y otras narraciones, mira videos relacionados y recibe recomendaciones de atracciones cercanas y lugares que quizás quieras visitar próximamente.',
    'ui.arGuideNext': 'Siguiente',
    'ui.arGuideBack': 'Atrás',
    'ui.arGuideDone': 'Listo',
    'ui.arGuideSkip': 'Omitir',
    'ui.nearbyGuide': 'Guía de Recomendaciones Cercanas',
    'ui.nearbyGuideMapTitle': 'Encuentra Atracciones Cercanas',
    'ui.nearbyGuideMapBody':
    'Abre Cercanas para ver recomendaciones personalizadas en azul y '
        'atracciones con RA en rojo. Las etiquetas muestran el alcance '
        'visible y la cantidad de recomendaciones.',
    'ui.nearbyGuideDetailsTitle': 'Consulta los Detalles',
    'ui.nearbyGuideDetailsBody':
    'Toca cualquier marcador para ver su foto, dirección, indicaciones de '
        'Google Maps y si la RA está disponible.',
    'ui.nearbyGuideActionsTitle': 'Usa las Acciones Disponibles',
    'ui.nearbyGuideActionsBody':
    'Desplázate hacia abajo para abrir una experiencia de RA disponible o '
        'guardar la atracción para más tarde.',
    'ui.nearbyGuideArTitle': 'Visita la Zona de Activación de RA',
    'ui.nearbyGuideArBody':
    'La RA solo se desbloquea dentro de la zona de activación de la '
        'atracción. Sigue las indicaciones de Google Maps para llegar.',
    'ui.nearbyGuideLoginTitle': 'Inicia Sesión para Guardar',
    'ui.nearbyGuideLoginBody':
    'Los invitados pueden explorar lugares cercanos, pero deben iniciar '
        'sesión antes de añadir una atracción a Marcadores.',
    'ui.nearbyGuideBookmarksTitle': 'Encuentra Atracciones Guardadas',
    'ui.nearbyGuideBookmarksBody':
    'Después de iniciar sesión, abre Perfil y selecciona Marcadores para ver '
        'o volver a visitar tus atracciones guardadas.',
    'ui.changePassword': 'Cambiar Contraseña',
    'ui.currentPassword': 'Contraseña Actual',
    'ui.newPassword': 'Nueva Contraseña',
    'ui.confirmNewPassword': 'Confirmar Nueva Contraseña',
    'ui.fullName': 'Nombre Completo',
    'ui.bio': 'Biografía',
    'ui.phoneNumber': 'Número de Teléfono',
    'ui.password': 'Contraseña',
    'ui.username': 'Nombre de Usuario',
    'ui.googleAccount': 'Cuenta de Google',
    'ui.linked': 'Vinculada',
    'ui.notLinked': 'No vinculada',
    'ui.link': 'Vincular',
    'ui.unlink': 'Desvincular',
    'ui.add': 'Agregar',
    'ui.change': 'Cambiar',
    'ui.notSet': 'No establecido',
    'ui.setUsernameAndPassword': 'Establecer Nombre de Usuario y Contraseña',
    'ui.setUsernameAndPasswordHint':
        'Agregue un nombre de usuario y una contraseña para poder iniciar sesión también sin su teléfono o cuenta de Google.',
    'ui.sendOtp': 'Enviar OTP',
    'ui.changePhoneNumber': 'Cambiar Número de Teléfono',
    'ui.unlinkGoogleAccount': 'Desvincular Cuenta de Google',
    'ui.guestBrowsing': 'Está navegando como invitado',
    'ui.guestSubtitle':
    'Inicie sesión o cree una cuenta para guardar sus preferencias, marcadores '
        'e idioma preferido.',
    'ui.forgotPassword': '¿Olvidó su Contraseña?',
    'ui.dontHaveAccount': '¿No tiene una cuenta?',
    'ui.alreadyHaveAccount': '¿Ya tiene una cuenta?',
    'ui.enterOtp': 'Introducir OTP',
    'ui.resendOtp': 'Reenviar OTP',
    'ui.verify': 'Verificar',
    'ui.dateOfBirth': 'Fecha de Nacimiento',
    'ui.next': 'Siguiente',
    'ui.attractionInterests': 'Intereses de Atracciones',
    'ui.foodCuisine': 'Comida y Gastronomía',
    'ui.dietaryPreferences': 'Preferencias Dietéticas',
    'ui.accessibilityPreferences': 'Preferencias de Accesibilidad',
    'ui.categoryExclusions': 'Exclusiones de Categoría',
    'ui.deleteAccount': 'Eliminar Cuenta',
    'ui.myBookmarks': 'Mis Marcadores',
    'ui.noBookmarksYet': 'Aún no hay marcadores',
    'ui.remove': 'Eliminar',
    'ui.resetPassword': 'Restablecer Contraseña',
    'ui.enterPhoneNumber': 'Introducir Número de Teléfono',

    'recommendation.mapLegendRecommended': 'Recomendado',
    'recommendation.arAvailable': 'RA disponible',
    'recommendation.headerTitle': 'Atracciones Cercanas',
    'recommendation.foundCount': '{count} encontrados',
    'recommendation.refreshTooltip': 'Actualizar atracciones cercanas',
    'recommendation.hintFinding': 'Buscando atracciones cerca de usted...',
    'recommendation.hintTapToView':
    'Toque cualquier atracción para ver los detalles',
    'recommendation.hintNoneFound':
    'No se encontraron atracciones que se puedan mostrar en el mapa',
    'recommendation.tryAgain': 'Intentar de nuevo',
    'recommendation.findingLocation': 'Buscando su ubicación actual...',
    'recommendation.retry': 'Reintentar',
    'recommendation.arAvailableSnippet': 'RA disponible • {category}',
    'recommendation.arExperienceCountOne': '1 experiencia de RA',
    'recommendation.arExperienceCountMany': '{count} experiencias de RA',
    'recommendation.arExperiencesAvailableOne':
    '1 experiencia de RA disponible',
    'recommendation.arExperiencesAvailableMany':
    '{count} experiencias de RA disponibles',
    'recommendation.locationServicesOff':
    'Active los servicios de ubicación para descubrir atracciones '
        'cercanas.',
    'recommendation.locationPermissionRequired':
    'Se requiere permiso de ubicación para encontrar atracciones '
        'cercanas.',
    'recommendation.locationTimedOut':
    'No se pudo obtener su ubicación actual. Compruebe los ajustes de ubicación e inténtelo de nuevo.',
    'recommendation.arLocationsUnavailable':
    'Las ubicaciones de RA no están disponibles temporalmente.',
    'recommendation.unableToLoad':
    'No se pudieron cargar las atracciones cercanas. Inténtelo de nuevo.',
    'recommendation.closeDetailsTooltip': 'Cerrar detalles',
    'recommendation.loginToBookmarkTitle':
    'Inicie sesión para guardar en marcadores',
    'recommendation.loginToBookmarkBody':
    'Debe iniciar sesión antes de poder guardar atracciones en sus '
        'marcadores.',
    'recommendation.no': 'No',
    'recommendation.logIn': 'Iniciar sesión',
    'recommendation.attractionDetailsLabel': 'DETALLES DE LA ATRACCIÓN',
    'recommendation.distanceLabel': 'DISTANCIA',
    'recommendation.estTravelLabel': 'TIEMPO ESTIMADO',
    'recommendation.estTravelValue': '~{minutes} min en coche',
    'recommendation.bookmarked': 'Guardado',
    'recommendation.bookmark': 'Guardar',
    'recommendation.arLocationLabel': 'UBICACIÓN DE RA',
    'recommendation.arSharedLocationNotice':
    '{count} atracciones de RA comparten esta misma ubicación',
    'recommendation.noArInfoLinked':
    'La información de la experiencia de RA aún no se ha vinculado.',
    'recommendation.openAr': 'Abrir RA',
    'recommendation.visitToUnlockAr': 'Visite el lugar para desbloquear la RA',
    'recommendation.availabilityWithinArea':
    'Se encuentra dentro de una zona de activación de RA. Abra la '
        'cámara de RA para interactuar con este lugar.',
    'recommendation.availabilityVisitSite':
    'Visite este lugar para usar sus experiencias de RA.',
    'recommendation.availabilityNearestPoint':
    'La RA solo funciona en el lugar. El punto de activación más '
        'cercano está a {distance}.',
    'recommendation.availableNow': 'Disponible ahora',
    'recommendation.awayDistance': 'A {distance}',
    'recommendation.resolutionFailed':
    'Se encontraron recomendaciones, pero no se pudieron verificar sus '
        'ubicaciones en el mapa. Inténtelo de nuevo.',
    'recommendation.quotaReached':
    'Se ha alcanzado la cuota de recomendaciones de IA. Inténtelo de '
        'nuevo más tarde.',
    'recommendation.remoteUnavailable':
    'No se pudieron obtener las recomendaciones cercanas.',
    'nav.ar': 'RA',
    'nav.itinerary': 'Itinerario',
    'nav.nearby': 'Cercanos',
    'nav.profile': 'Perfil',
    'ar.permissionRequired':
    'Se requiere acceso a la cámara y la ubicación para usar la función '
        'de RA.',
    'ar.enableInSettings': 'Habilitar en Configuración',
    'ar.cameraStartError': 'Ocurrió un problema al iniciar la cámara de RA.',
    'ar.retry': 'Reintentar',
    'ar.placingManja': 'Colocando a Manja en el suelo...',
    'ar.resumingCamera': 'Reanudando la cámara de RA...',
    'ar.initializingCamera': 'Inicializando cámara...',
    'ar.noMarkersNearby': 'No se detectaron marcadores patrimoniales cercanos',
    'ar.markerDetectedOne': '1 marcador patrimonial detectado cerca',
    'ar.markersDetectedMany':
    '{count} marcadores patrimoniales detectados cerca',
    'ar.attractionsBand': 'ATRACCIONES A <{ceiling}M',
    'ar.availableSection': 'DISPONIBLE',
    'ar.nearbySection': 'CERCA',
    'ar.markerAvailableBadge': 'Disponible',
    'ar.directionLeft': 'Izquierda',
    'ar.directionRight': 'Derecha',
    'ar.directionAhead': 'Adelante',
    'ar.directionBehind': 'Detrás',
    'ar.loading3d': 'Cargando modelo 3D de {landmarkName}...',
    'ar.compilingGeometry': 'Compilando geometría y texturas 3D WebGL',
    'ar.view360': 'Vista 360°',
    'ar.model3dUnavailableTitle': 'Modelo 3D No Disponible',
    'ar.model3dUnavailableBody':
    'No se pudo cargar el modelo 3D representativo. La narración puede '
        'continuar sin el modelo 3D.',
    'ar.moveDeviceTapSurface':
    'Mueve el dispositivo y toca la superficie para colocar a Manja',
    'ar.storytelling': 'Narración',
    'ar.watchVideo': 'Ver Video',
    'ar.recommend': 'Recomendar',
    'ar.backToActions': 'Volver a Acciones',
    'ar.exitAr': 'Salir de RA',
    'ar.live': 'EN VIVO',
    'ar.takePhotoTooltip': 'Tomar Foto con Manja',
    'ar.photoSaved': '📸 ¡Foto guardada en la Galería!',
    'ar.photoSaveFailed': 'No se pudo guardar la foto. Inténtalo de nuevo.',
    'ar.recommendedForYou': 'Recomendado para ti',
    'ar.closeRecommendations': 'Cerrar recomendaciones',
    'ar.continueYourExperience': 'CONTINÚA TU EXPERIENCIA',
    'ar.findingNextExperiences':
    'Buscando las mejores experiencias siguientes…',
    'ar.noPlacementSurface':
    'No se detectó una superficie adecuada para colocar. Mueve tu '
        'dispositivo para escanear el área circundante.',
    'ar.tapBlueSurfaceToPlace': 'Toca la superficie azul para colocar a Manja',
    'ar.actionPause': 'Pausar',
    'ar.actionReplay': 'Repetir Historia',
    'ar.actionResume': 'Reanudar',
    'ar.actionPlay': 'Reproducir',
    'ar.tapGroundContinue':
    'Toca el suelo para colocar a Manja y continuar la historia',
    'ar.storyCompleted': 'Historia Completada',
    'ar.paused': 'Pausado',
    'ar.tapPlayToBegin': 'Toca Reproducir para comenzar',
    'ar.no3dModelAvailable': 'No Hay Modelo 3D Disponible',
    'ar.hide3dModel': 'Ocultar Modelo 3D',
    'ar.show3dModel': 'Mostrar Modelo 3D',
    'ar.no3dModelForLandmark': 'No hay modelo 3D disponible para {landmarkName}',
    'ar.endStory': 'Terminar Historia',
    'ar.model3dMissingError':
    'Error: No se encontró ningún modelo 3D en la base de datos (falta '
        'model_3d_url) para {landmarkName}.',
    'ar.loadingVideo': 'Cargando video...',
    'ar.rewind10s': 'Retroceder 10s',
    'ar.forward10s': 'Adelantar 10s',
    'ar.exitFullscreen': 'Salir de Pantalla Completa',
    'ar.fullscreen': 'Pantalla Completa',
    'ar.close': 'Cerrar',
    'ar.videoUnavailableTitle': 'Video No Disponible',
    'ar.videoUnavailableBody':
    'El video relacionado no está disponible actualmente. Inténtalo de '
        'nuevo más tarde.',
    'ar.retryPlayback': 'Reintentar Reproducción',
    'ar.noFollowUpAttractions':
    'No se encontraron atracciones de seguimiento adecuadas.',
    'pref.attr.heritage': 'Patrimonio',
    'pref.attr.nature': 'Naturaleza',
    'pref.attr.food': 'Comida',
    'pref.attr.shopping': 'Compras',
    'pref.attr.adventure': 'Aventura',
    'pref.cuisine.malay': 'Malaya',
    'pref.cuisine.chinese': 'China',
    'pref.cuisine.indian': 'India',
    'pref.cuisine.peranakan': 'Peranakan/Nyonya',
    'pref.cuisine.western': 'Occidental',
    'pref.cuisine.streetFood': 'Comida Callejera',
    'pref.cuisine.seafood': 'Mariscos',
    'pref.cuisine.vegetarianFriendly': 'Apta para Vegetarianos',
    'pref.dietary.halal': 'Halal',
    'pref.dietary.vegetarian': 'Vegetariano',
    'pref.dietary.vegan': 'Vegano',
    'pref.restriction.noPork': 'Sin Cerdo',
    'pref.restriction.noBeef': 'Sin Carne de Res',
    'pref.restriction.glutenFree': 'Sin Gluten',
    'pref.restriction.nutAllergy': 'Alergia a Frutos Secos',
    'pref.restriction.shellfishAllergy': 'Alergia a Mariscos',
    'pref.restriction.dairyFree':
    'Sin Lácteos / Intolerante a la Lactosa',
    'pref.access.wheelchair': 'Accesible en Silla de Ruedas',
    'pref.access.mobility': 'Asistencia de Movilidad',
    'pref.access.visual': 'Asistencia Visual',
    'pref.access.wheelchairDesc':
    'Priorizar rampas, ascensores y rutas sin escalones',
    'pref.access.mobilityDesc':
    'Priorizar rutas más cortas y asientos en el camino',
    'pref.access.visualDesc':
    'Destacar audioguías y señales táctiles',
    'ui.dietaryRestrictionsTitle': 'Restricciones Dietéticas y Alergias',
    'onboarding.skip': 'Omitir',
    'onboarding.title': 'Personaliza tu viaje',
    'onboarding.subtitle':
    'Cuéntanos qué te interesa para adaptar las recomendaciones — '
        'siempre puedes cambiarlo después en tu Perfil.',
    'onboarding.attractionsQuestion': '¿Qué tipo de atracciones te gustan?',
    'onboarding.finishSetup': 'Finalizar configuración',
  };

  static const Map<String, String> _hi = {
    'ai.greeting': 'मैं Manja हूँ, आपका AI यात्रा सहायक!',
    'ai.title': 'यात्रा सहायक',
    'ai.showSummary': 'बातचीत का सारांश दिखाएँ',
    'ai.searchConversation': 'बातचीत में खोजें',
    'ai.resetConversation': 'बातचीत रीसेट करें',
    'ai.resetTitle': 'बातचीत रीसेट करें?',
    'ai.resetMessage': 'वर्तमान चैट संदेश मिट जाएँगे। चुना गया आकर्षण बना रहेगा।',
    'ai.cancel': 'रद्द करें',
    'ai.reset': 'रीसेट करें',
    'ai.leaveTitle': 'AI चैट छोड़ें?',
    'ai.leaveMessage': 'जाते समय नवीनतम सारांश सहेजा जाएगा। क्या आप जारी रखना चाहते हैं?',
    'ai.leave': 'छोड़ें',
    'ai.stay': 'रुकें',
    'ai.discussing': 'चर्चा: {place}',
    'ai.inputHint': 'कुछ पूछें... (जैसे A Famosa का इतिहास)',
    'ai.sendQuestion': 'प्रश्न भेजें',
    'ai.summary': 'सारांश',
    'ai.closeSummary': 'सारांश बंद करें',
    'ai.noSummary': 'अभी कोई बातचीत सारांश उपलब्ध नहीं है।',
    'ai.checkingPlaces': 'सत्यापित स्थान जाँचे जा रहे हैं…',
    'ai.mapsFailure': 'Google Maps नहीं खुल सका।',
    'ai.openMaps': 'Google Maps में खोलें',
    'ai.verifiedPlace': 'सत्यापित स्थान',
    'ai.chooseVerifiedPlace': 'सत्यापित स्थान चुनें',
    'ai.bookmark': 'सहेजें',
    'ai.bookmarked': 'सहेजा गया',
    'ai.loginTitle': 'सहेजने के लिए लॉग इन करें',
    'ai.loginMessage': 'इस स्थान को सहेजने से पहले आपको लॉग इन करना होगा।',
    'ai.notNow': 'अभी नहीं',
    'ai.login': 'लॉग इन करें',
    'ai.searchPrompt': 'इस बातचीत में संदेश खोजें।',
    'ai.noMatches': 'इस बातचीत में कोई मिलान नहीं मिला।',
    'ai.clearSearch': 'खोज साफ़ करें',
    'ai.closeSearch': 'खोज बंद करें',

    'register.m1': 'आपका खाता सफलतापूर्वक पंजीकृत हो गया है।',
    'register.m2': 'आपके फ़ोन नंबर पर एक वन-टाइम पासवर्ड (OTP) भेजा गया है। कृपया इसे 5 मिनट के भीतर दर्ज करें।',
    'register.m3': 'Google से साइन इन करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'register.m4': 'यह फ़ोन नंबर पहले से पंजीकृत है। कृपया अपने मौजूदा खाते से लॉग इन करें।',
    'register.m5': 'कृपया एक मान्य फ़ोन नंबर दर्ज करें।',
    'register.m6': 'दर्ज किया गया OTP गलत है या समाप्त हो गया है। कृपया पुनः प्रयास करें।',
    'register.m7': 'यह उपयोगकर्ता नाम पहले से लिया जा चुका है। कृपया एक अलग उपयोगकर्ता नाम चुनें।',
    'register.m8': 'पासवर्ड में कम से कम 8 अक्षर होने चाहिए, जिसमें कम से कम एक अक्षर और एक अंक शामिल हो।',
    'register.m9': 'बहुत अधिक अनुरोध। कृपया बाद में पुनः प्रयास करें।',
    'register.m10': 'पासवर्ड मेल नहीं खाते। कृपया दोनों फ़ील्ड में समान पासवर्ड दर्ज करें।',
    'register.m11': 'कृपया अपना पूरा नाम दर्ज करें।',
    'register.m12': 'कृपया अपनी जन्म तिथि चुनें।',
    'register.m13': 'जन्म तिथि भविष्य में नहीं हो सकती।',
    'register.m14': 'आपका विवरण सहेजने में असमर्थ। कृपया पुनः प्रयास करें।',
    'register.m15': 'कृपया एक मान्य उपयोगकर्ता नाम दर्ज करें (3–20 अक्षर, संख्याएँ, या अंडरस्कोर, अक्षर से शुरू होना चाहिए)।',

    'login.m1': 'लॉगिन सफल रहा। NarrateMy के साथ अपनी यात्रा का आनंद लेना शुरू करें।',
    'login.m2': 'आपके फ़ोन नंबर पर एक वन-टाइम पासवर्ड (OTP) भेजा गया है। कृपया इसे 5 मिनट के भीतर दर्ज करें।',
    'login.m3': 'Google से साइन इन करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'login.m4': 'कोई खाता नहीं मिला। कृपया अपने लॉगिन विवरण जांचें या नया खाता पंजीकृत करें।',
    'login.m5': 'दर्ज किया गया OTP गलत है या समाप्त हो गया है। कृपया पुनः प्रयास करें।',
    'login.m6': 'दर्ज किया गया उपयोगकर्ता नाम या पासवर्ड गलत है।',
    'login.m7':
    'बहुत अधिक असफल लॉगिन प्रयास। आपका खाता 30 मिनट के लिए लॉक कर दिया गया है। '
        'कृपया बाद में पुनः प्रयास करें या अपना पासवर्ड रीसेट करें।',
    'login.m8': 'बहुत अधिक OTP अनुरोध या सत्यापन प्रयास किए गए हैं। कृपया बाद में पुनः प्रयास करें।',
    'login.m9': 'कृपया अपना उपयोगकर्ता नाम और पासवर्ड दर्ज करें।',

    'passwordReset.m1': 'अपना पासवर्ड रीसेट करने के लिए अपना पंजीकृत फ़ोन नंबर दर्ज करें।',
    'passwordReset.m2': 'आपके फ़ोन नंबर पर एक वन-टाइम पासवर्ड (OTP) भेजा गया है। कृपया इसे 5 मिनट के भीतर दर्ज करें।',
    'passwordReset.m3': 'आपका पासवर्ड सफलतापूर्वक रीसेट कर दिया गया है। अब आप लॉग इन कर सकते हैं।',
    'passwordReset.m4': 'यह फ़ोन नंबर पंजीकृत नहीं है।',
    'passwordReset.m5': 'दर्ज किया गया OTP गलत है या समाप्त हो गया है। कृपया पुनः प्रयास करें।',
    'passwordReset.m6': 'पासवर्ड में कम से कम 8 अक्षर होने चाहिए, जिसमें कम से कम एक अक्षर और एक अंक शामिल हो।',
    'passwordReset.m7': 'दर्ज किए गए पासवर्ड मेल नहीं खाते। कृपया पुनः प्रयास करें।',
    'passwordReset.m8': 'बहुत अधिक अनुरोध। कृपया बाद में पुनः प्रयास करें।',
    'passwordReset.m9': 'यह फ़ोन नंबर बिना पासवर्ड के पंजीकृत है। कृपया फ़ोन + OTP से लॉग इन करें।',

    'profile.m1': 'अपनी प्रोफ़ाइल, प्राथमिकताएँ और पसंदीदा भाषा प्रबंधित करें।',
    'profile.m2': 'आपकी प्रोफ़ाइल सफलतापूर्वक अपडेट हो गई है।',
    'profile.m3': 'आपकी प्रोफ़ाइल लोड करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m4': 'जारी रखने से पहले हाइलाइट की गई जानकारी को सही करें।',
    'profile.m5': 'आपके परिवर्तन निरस्त कर दिए गए हैं।',
    'profile.m6': 'आपकी प्रोफ़ाइल अपडेट करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m7': 'आपका सत्र समाप्त हो गया है। कृपया फिर से लॉग इन करें।',
    'profile.m8': 'कृपया एक मान्य फ़ोन नंबर दर्ज करें।',
    'profile.m9': 'यह फ़ोन नंबर पहले से किसी अन्य खाते में पंजीकृत है।',
    'profile.m10': 'दर्ज किया गया OTP गलत है या समाप्त हो गया है। कृपया पुनः प्रयास करें।',
    'profile.m11': 'आपके फ़ोन नंबर पर एक वन-टाइम पासवर्ड (OTP) भेजा गया है। कृपया इसे 5 मिनट के भीतर दर्ज करें।',
    'profile.m12': 'आपका Google खाता सफलतापूर्वक लिंक कर दिया गया है। अब आप Google से साइन इन कर सकते हैं।',
    'profile.m13': 'आपका Google खाता लिंक करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m14': 'यह Google खाता पहले से किसी अन्य NarrateMy खाते से लिंक है।',
    'profile.m15': 'आपका पासवर्ड सफलतापूर्वक बदल दिया गया है।',
    'profile.m16': 'दर्ज किया गया वर्तमान पासवर्ड गलत है।',
    'profile.m17': 'पासवर्ड में कम से कम 8 अक्षर होने चाहिए, जिसमें कम से कम एक अक्षर और एक अंक शामिल हो।',
    'profile.m18': 'दर्ज किए गए नए पासवर्ड मेल नहीं खाते।',
    'profile.m19':
    'क्या आप वाकई अपना Google खाता अनलिंक करना चाहते हैं? आप अब Google से साइन इन नहीं कर पाएंगे।',
    'profile.m20': 'आपका Google खाता अनलिंक कर दिया गया है।',
    'profile.m21': 'अपना Google खाता अनलिंक करने से पहले आपको एक फ़ोन नंबर सत्यापित करना होगा।',
    'profile.m22':
    'अपना खाता हटाएं? आपकी प्रोफ़ाइल, प्राथमिकताएँ और बुकमार्क तुरंत निष्क्रिय कर दिए '
        'जाएंगे और 30 दिनों बाद स्थायी रूप से हटा दिए जाएंगे। इससे पहले फिर से लॉग इन '
        'करने पर आपका खाता पुनर्स्थापित हो जाएगा।',
    'profile.m23':
    'आपका खाता निष्क्रिय कर दिया गया है। जब तक आप फिर से लॉग इन नहीं करते, यह 30 '
        'दिनों में स्थायी रूप से हटा दिया जाएगा।',
    'profile.m24': 'आपका खाता हटाने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m25': 'आपकी प्रोफ़ाइल तस्वीर अपडेट करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m26': 'उपयोगकर्ता नाम और पासवर्ड सफलतापूर्वक सेट कर दिए गए हैं।',

    'ui.save': 'सहेजें',
    'ui.cancel': 'रद्द करें',
    'ui.edit': 'संपादित करें',
    'ui.login': 'लॉग इन करें',
    'ui.createAccount': 'खाता बनाएं',
    'ui.logout': 'लॉग आउट करें',
    'ui.profile': 'प्रोफ़ाइल',
    'ui.personalInfo': 'व्यक्तिगत जानकारी',
    'ui.preferences': 'प्राथमिकताएँ',
    'ui.language': 'भाषा',
    'ui.bookmarks': 'बुकमार्क',
    'ui.guidance': 'मार्गदर्शन',
    'ui.guidanceSubtitle': 'ऐप के हर हिस्से के लिए चरण-दर-चरण मार्गदर्शिका।',
    'ui.arGuide': 'AR गाइड',
    'ui.arGuideExplorationTitle': 'AR में एक्सप्लोर करें',
    'ui.arGuideExplorationBody':
    'आस-पास के रुचि वाले स्थानों पर मार्कर खोजने के लिए अपने कैमरे को '
        'किसी विरासत स्थल के चारों ओर घुमाएँ।',
    'ui.arGuidePlacementTitle': '3D मॉडल रखें',
    'ui.arGuidePlacementBody':
    'एक समतल सतह को स्कैन करें, फिर वास्तविक दुनिया में 3D मॉडल को रखने '
        'और उसकी स्थिति बदलने के लिए टैप करें।',
    'ui.arGuideNarrationsTitle': 'आख्यान',
    'ui.arGuideNarrationsBody':
    'घूमने की जगह को एक्सप्लोर करने के लिए अलग-अलग तरीके चुनें। कहानियाँ और दूसरी बातें सुनें, मिलते-जुलते वीडियो देखें, और आस-पास की जगहों और उन जगहों के लिए सुझाव पाएँ जहाँ आप अगली बार जाना चाहेंगे।',
    'ui.arGuideNext': 'अगला',
    'ui.arGuideBack': 'पीछे',
    'ui.arGuideDone': 'हो गया',
    'ui.arGuideSkip': 'छोड़ें',
    'ui.nearbyGuide': 'आस-पास सुझाव गाइड',
    'ui.nearbyGuideMapTitle': 'आस-पास के आकर्षण खोजें',
    'ui.nearbyGuideMapBody':
    'नीले रंग में व्यक्तिगत सुझाव और लाल रंग में AR वाले आकर्षण देखने के '
        'लिए आस-पास खोलें। ऊपर के बैज दिखाई देने वाली दूरी और सुझावों की '
        'संख्या बताते हैं।',
    'ui.nearbyGuideDetailsTitle': 'स्थान का विवरण देखें',
    'ui.nearbyGuideDetailsBody':
    'फ़ोटो, पता, Google Maps दिशा-निर्देश और AR की उपलब्धता देखने के लिए '
        'किसी भी मार्कर पर टैप करें।',
    'ui.nearbyGuideActionsTitle': 'उपलब्ध सुविधाएँ इस्तेमाल करें',
    'ui.nearbyGuideActionsBody':
    'उपलब्ध AR अनुभव खोलने या आकर्षण को बाद के लिए बुकमार्क करने हेतु नीचे '
        'स्क्रॉल करें।',
    'ui.nearbyGuideArTitle': 'AR सक्रियण क्षेत्र पर जाएँ',
    'ui.nearbyGuideArBody':
    'AR तभी खुलेगा जब आप आकर्षण के सक्रियण क्षेत्र के अंदर हों। वहाँ पहुँचने '
        'के लिए Google Maps के दिशा-निर्देशों का उपयोग करें।',
    'ui.nearbyGuideLoginTitle': 'स्थान सहेजने के लिए लॉग इन करें',
    'ui.nearbyGuideLoginBody':
    'मेहमान आस-पास के स्थान देख सकते हैं, लेकिन आकर्षण को बुकमार्क में जोड़ने '
        'से पहले लॉग इन करना आवश्यक है।',
    'ui.nearbyGuideBookmarksTitle': 'सहेजे गए आकर्षण खोजें',
    'ui.nearbyGuideBookmarksBody':
    'लॉग इन करने के बाद प्रोफ़ाइल खोलें और अपने सहेजे गए आकर्षण देखने या फिर '
        'से जाने के लिए बुकमार्क चुनें।',
    'ui.changePassword': 'पासवर्ड बदलें',
    'ui.currentPassword': 'वर्तमान पासवर्ड',
    'ui.newPassword': 'नया पासवर्ड',
    'ui.confirmNewPassword': 'नए पासवर्ड की पुष्टि करें',
    'ui.fullName': 'पूरा नाम',
    'ui.bio': 'बायो',
    'ui.phoneNumber': 'फ़ोन नंबर',
    'ui.password': 'पासवर्ड',
    'ui.username': 'उपयोगकर्ता नाम',
    'ui.googleAccount': 'Google खाता',
    'ui.linked': 'लिंक किया गया',
    'ui.notLinked': 'लिंक नहीं है',
    'ui.link': 'लिंक करें',
    'ui.unlink': 'अनलिंक करें',
    'ui.add': 'जोड़ें',
    'ui.change': 'बदलें',
    'ui.notSet': 'सेट नहीं है',
    'ui.setUsernameAndPassword': 'उपयोगकर्ता नाम और पासवर्ड सेट करें',
    'ui.setUsernameAndPasswordHint':
        'एक उपयोगकर्ता नाम और पासवर्ड जोड़ें ताकि आप अपने फ़ोन या Google खाते के बिना भी लॉग इन कर सकें।',
    'ui.sendOtp': 'OTP भेजें',
    'ui.changePhoneNumber': 'फ़ोन नंबर बदलें',
    'ui.unlinkGoogleAccount': 'Google खाता अनलिंक करें',
    'ui.guestBrowsing': 'आप अतिथि के रूप में ब्राउज़ कर रहे हैं',
    'ui.guestSubtitle': 'अपनी प्राथमिकताएँ, बुकमार्क और पसंदीदा भाषा सहेजने के लिए लॉग इन करें या खाता बनाएं।',
    'ui.forgotPassword': 'पासवर्ड भूल गए?',
    'ui.dontHaveAccount': 'खाता नहीं है?',
    'ui.alreadyHaveAccount': 'पहले से खाता है?',
    'ui.enterOtp': 'OTP दर्ज करें',
    'ui.resendOtp': 'OTP पुनः भेजें',
    'ui.verify': 'सत्यापित करें',
    'ui.dateOfBirth': 'जन्म तिथि',
    'ui.next': 'अगला',
    'ui.attractionInterests': 'आकर्षण रुचियाँ',
    'ui.foodCuisine': 'भोजन और व्यंजन',
    'ui.dietaryPreferences': 'आहार प्राथमिकताएँ',
    'ui.accessibilityPreferences': 'पहुंच प्राथमिकताएँ',
    'ui.categoryExclusions': 'श्रेणी बहिष्करण',
    'ui.deleteAccount': 'खाता हटाएं',
    'ui.myBookmarks': 'मेरे बुकमार्क',
    'ui.noBookmarksYet': 'अभी तक कोई बुकमार्क नहीं',
    'ui.remove': 'हटाएं',
    'ui.resetPassword': 'पासवर्ड रीसेट करें',
    'ui.enterPhoneNumber': 'फ़ोन नंबर दर्ज करें',

    'recommendation.mapLegendRecommended': 'अनुशंसित',
    'recommendation.arAvailable': 'AR उपलब्ध',
    'recommendation.headerTitle': 'आस-पास के आकर्षण',
    'recommendation.foundCount': '{count} मिले',
    'recommendation.refreshTooltip': 'आस-पास के आकर्षण रीफ़्रेश करें',
    'recommendation.hintFinding': 'आपके आस-पास के आकर्षण खोजे जा रहे हैं...',
    'recommendation.hintTapToView': 'विवरण देखने के लिए किसी भी आकर्षण पर टैप करें',
    'recommendation.hintNoneFound': 'मानचित्र पर दिखाने योग्य कोई आकर्षण नहीं मिला',
    'recommendation.tryAgain': 'पुनः प्रयास करें',
    'recommendation.findingLocation': 'आपका वर्तमान स्थान खोजा जा रहा है...',
    'recommendation.retry': 'पुनः प्रयास करें',
    'recommendation.arAvailableSnippet': 'AR उपलब्ध • {category}',
    'recommendation.arExperienceCountOne': '1 AR अनुभव',
    'recommendation.arExperienceCountMany': '{count} AR अनुभव',
    'recommendation.arExperiencesAvailableOne': '1 AR अनुभव उपलब्ध',
    'recommendation.arExperiencesAvailableMany': '{count} AR अनुभव उपलब्ध',
    'recommendation.locationServicesOff':
    'आस-पास के आकर्षण खोजने के लिए स्थान सेवाएँ चालू करें।',
    'recommendation.locationPermissionRequired':
    'आस-पास के आकर्षण खोजने के लिए स्थान अनुमति आवश्यक है।',
    'recommendation.locationTimedOut':
    'आपका वर्तमान स्थान प्राप्त नहीं हो सका। स्थान सेटिंग जांचें और फिर प्रयास करें।',
    'recommendation.arLocationsUnavailable': 'AR स्थान अस्थायी रूप से अनुपलब्ध हैं।',
    'recommendation.unableToLoad':
    'आस-पास के आकर्षण लोड नहीं हो सके। कृपया पुनः प्रयास करें।',
    'recommendation.closeDetailsTooltip': 'विवरण बंद करें',
    'recommendation.loginToBookmarkTitle': 'बुकमार्क करने के लिए लॉग इन करें',
    'recommendation.loginToBookmarkBody':
    'आकर्षणों को अपने बुकमार्क में सहेजने से पहले आपको लॉग इन करना होगा।',
    'recommendation.no': 'नहीं',
    'recommendation.logIn': 'लॉग इन करें',
    'recommendation.attractionDetailsLabel': 'आकर्षण विवरण',
    'recommendation.distanceLabel': 'दूरी',
    'recommendation.estTravelLabel': 'अनुमानित यात्रा समय',
    'recommendation.estTravelValue': '~{minutes} मिनट (कार से)',
    'recommendation.bookmarked': 'बुकमार्क किया गया',
    'recommendation.bookmark': 'बुकमार्क करें',
    'recommendation.arLocationLabel': 'AR स्थान',
    'recommendation.arSharedLocationNotice':
    '{count} AR आकर्षण इसी स्थान पर स्थित हैं',
    'recommendation.noArInfoLinked': 'AR अनुभव की जानकारी अभी तक जोड़ी नहीं गई है।',
    'recommendation.openAr': 'AR खोलें',
    'recommendation.visitToUnlockAr': 'AR अनलॉक करने के लिए स्थान पर जाएँ',
    'recommendation.availabilityWithinArea':
    'आप एक AR सक्रियण क्षेत्र में हैं। इस स्थान से बातचीत करने के लिए AR कैमरा खोलें।',
    'recommendation.availabilityVisitSite':
    'इसके AR अनुभवों का उपयोग करने के लिए इस स्थान पर जाएँ।',
    'recommendation.availabilityNearestPoint':
    'AR केवल स्थान पर ही काम करता है। निकटतम सक्रियण बिंदु {distance} दूर है।',
    'recommendation.availableNow': 'अभी उपलब्ध',
    'recommendation.awayDistance': '{distance} दूर',
    'recommendation.resolutionFailed':
    'सिफ़ारिशें मिलीं, लेकिन उनके मानचित्र स्थानों की पुष्टि नहीं हो सकी। कृपया पुनः प्रयास करें।',
    'recommendation.quotaReached':
    'AI सिफ़ारिश कोटा समाप्त हो गया है। कृपया बाद में पुनः प्रयास करें।',
    'recommendation.remoteUnavailable': 'आस-पास की सिफ़ारिशें प्राप्त नहीं हो सकीं।',
    'nav.ar': 'एआर',
    'nav.itinerary': 'यात्रा कार्यक्रम',
    'nav.nearby': 'आस-पास',
    'nav.profile': 'प्रोफ़ाइल',
    'ar.permissionRequired':
    'एआर सुविधा का उपयोग करने के लिए कैमरा और स्थान की अनुमति आवश्यक है।',
    'ar.enableInSettings': 'सेटिंग्स में सक्षम करें',
    'ar.cameraStartError': 'एआर कैमरा शुरू करने में कोई समस्या हुई।',
    'ar.retry': 'पुनः प्रयास करें',
    'ar.placingManja': 'मंजा को ज़मीन पर रखा जा रहा है...',
    'ar.resumingCamera': 'एआर कैमरा फिर से शुरू हो रहा है...',
    'ar.initializingCamera': 'कैमरा शुरू हो रहा है...',
    'ar.noMarkersNearby': 'आस-पास कोई विरासत चिह्न नहीं मिला',
    'ar.markerDetectedOne': 'आस-पास 1 विरासत चिह्न मिला',
    'ar.markersDetectedMany': 'आस-पास {count} विरासत चिह्न मिले',
    'ar.attractionsBand': '<{ceiling}मी के भीतर आकर्षण',
    'ar.availableSection': 'उपलब्ध',
    'ar.nearbySection': 'आस-पास',
    'ar.markerAvailableBadge': 'उपलब्ध',
    'ar.directionLeft': 'बाएं',
    'ar.directionRight': 'दाएं',
    'ar.directionAhead': 'आगे',
    'ar.directionBehind': 'पीछे',
    'ar.loading3d': '{landmarkName} का 3D मॉडल लोड हो रहा है...',
    'ar.compilingGeometry': '3D WebGL ज्यामिति और टेक्सचर तैयार किए जा रहे हैं',
    'ar.view360': '360° दृश्य',
    'ar.model3dUnavailableTitle': '3D मॉडल उपलब्ध नहीं है',
    'ar.model3dUnavailableBody':
    'प्रतिनिधि 3D मॉडल लोड नहीं हो सका। कहानी 3D मॉडल के बिना जारी रह सकती है।',
    'ar.moveDeviceTapSurface':
    'मंजा रखने के लिए डिवाइस को हिलाएं और सतह पर टैप करें',
    'ar.storytelling': 'कहानी सुनाना',
    'ar.watchVideo': 'वीडियो देखें',
    'ar.recommend': 'सिफ़ारिश करें',
    'ar.backToActions': 'कार्रवाइयों पर वापस जाएं',
    'ar.exitAr': 'एआर से बाहर निकलें',
    'ar.live': 'लाइव',
    'ar.takePhotoTooltip': 'मंजा के साथ फोटो लें',
    'ar.photoSaved': '📸 फोटो गैलरी में सहेजी गई!',
    'ar.photoSaveFailed': 'फोटो सहेजने में विफल। कृपया पुनः प्रयास करें।',
    'ar.recommendedForYou': 'आपके लिए अनुशंसित',
    'ar.closeRecommendations': 'सिफ़ारिशें बंद करें',
    'ar.continueYourExperience': 'अपना अनुभव जारी रखें',
    'ar.findingNextExperiences': 'सर्वोत्तम अगला अनुभव खोजा जा रहा है…',
    'ar.noPlacementSurface':
    'कोई उपयुक्त प्लेसमेंट सतह नहीं मिली। कृपया आस-पास के क्षेत्र को '
        'स्कैन करने के लिए अपना डिवाइस हिलाएं।',
    'ar.tapBlueSurfaceToPlace': 'Manja को रखने के लिए नीली सतह पर टैप करें',
    'ar.actionPause': 'रोकें',
    'ar.actionReplay': 'कहानी फिर से चलाएं',
    'ar.actionResume': 'फिर से शुरू करें',
    'ar.actionPlay': 'चलाएं',
    'ar.tapGroundContinue':
    'मंजा रखने और कहानी जारी रखने के लिए ज़मीन पर टैप करें',
    'ar.storyCompleted': 'कहानी पूर्ण हुई',
    'ar.paused': 'रुका हुआ',
    'ar.tapPlayToBegin': 'शुरू करने के लिए चलाएं पर टैप करें',
    'ar.no3dModelAvailable': 'कोई 3D मॉडल उपलब्ध नहीं है',
    'ar.hide3dModel': '3D मॉडल छिपाएं',
    'ar.show3dModel': '3D मॉडल दिखाएं',
    'ar.no3dModelForLandmark': '{landmarkName} के लिए कोई 3D मॉडल उपलब्ध नहीं है',
    'ar.endStory': 'कहानी समाप्त करें',
    'ar.model3dMissingError':
    'त्रुटि: {landmarkName} के लिए डेटाबेस में कोई 3D मॉडल नहीं मिला '
        '(model_3d_url गायब है)।',
    'ar.loadingVideo': 'वीडियो लोड हो रहा है...',
    'ar.rewind10s': '10 सेकंड पीछे',
    'ar.forward10s': '10 सेकंड आगे',
    'ar.exitFullscreen': 'फुलस्क्रीन से बाहर निकलें',
    'ar.fullscreen': 'फुलस्क्रीन',
    'ar.close': 'बंद करें',
    'ar.videoUnavailableTitle': 'वीडियो उपलब्ध नहीं है',
    'ar.videoUnavailableBody':
    'संबंधित वीडियो फ़िलहाल उपलब्ध नहीं है। कृपया बाद में पुनः प्रयास करें।',
    'ar.retryPlayback': 'पुनः प्लेबैक करें',
    'ar.noFollowUpAttractions': 'कोई उपयुक्त अनुवर्ती आकर्षण नहीं मिला।',
    'pref.attr.heritage': 'विरासत',
    'pref.attr.nature': 'प्रकृति',
    'pref.attr.food': 'भोजन',
    'pref.attr.shopping': 'खरीदारी',
    'pref.attr.adventure': 'साहसिक कार्य',
    'pref.cuisine.malay': 'मलय',
    'pref.cuisine.chinese': 'चीनी',
    'pref.cuisine.indian': 'भारतीय',
    'pref.cuisine.peranakan': 'पेरानाकन/न्योन्या',
    'pref.cuisine.western': 'पाश्चात्य',
    'pref.cuisine.streetFood': 'स्ट्रीट फूड',
    'pref.cuisine.seafood': 'समुद्री भोजन',
    'pref.cuisine.vegetarianFriendly': 'शाकाहारी-अनुकूल',
    'pref.dietary.halal': 'हलाल',
    'pref.dietary.vegetarian': 'शाकाहारी',
    'pref.dietary.vegan': 'वीगन',
    'pref.restriction.noPork': 'सूअर का मांस नहीं',
    'pref.restriction.noBeef': 'गोमांस नहीं',
    'pref.restriction.glutenFree': 'ग्लूटेन-मुक्त',
    'pref.restriction.nutAllergy': 'नट एलर्जी',
    'pref.restriction.shellfishAllergy': 'शेलफिश एलर्जी',
    'pref.restriction.dairyFree': 'डेयरी-मुक्त / लैक्टोज असहिष्णुता',
    'pref.access.wheelchair': 'व्हीलचेयर सुलभ',
    'pref.access.mobility': 'गतिशीलता सहायता',
    'pref.access.visual': 'दृष्टि सहायता',
    'pref.access.wheelchairDesc': 'रैंप, लिफ्ट और सीढ़ी-मुक्त मार्गों को प्राथमिकता दें',
    'pref.access.mobilityDesc': 'छोटे मार्गों और रास्ते में बैठने की सुविधा को प्राथमिकता दें',
    'pref.access.visualDesc': 'ऑडियो गाइड और स्पर्श संकेतों को उजागर करें',
    'ui.dietaryRestrictionsTitle': 'आहार प्रतिबंध और एलर्जी',
    'onboarding.skip': 'छोड़ें',
    'onboarding.title': 'अपनी यात्रा को व्यक्तिगत बनाएं',
    'onboarding.subtitle':
    'हमें बताएं कि आपकी रुचि किसमें है ताकि हम सिफारिशें तैयार कर सकें — आप इसे बाद में प्रोफ़ाइल में हमेशा बदल सकते हैं।',
    'onboarding.attractionsQuestion': 'आपको किस प्रकार के आकर्षण पसंद हैं?',
    'onboarding.finishSetup': 'सेटअप पूरा करें',
  };
}
