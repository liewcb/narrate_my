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
        'Delete your account? This permanently removes your profile, '
            'preferences, and bookmarks, and cannot be undone.',
    'profile.m23': 'Your account has been deleted.',
    'profile.m24': 'Unable to delete your account. Please try again.',
    'profile.m25': 'Unable to update your profile picture. Please try again.',

    // ui.* — literal strings inside Module 5's screens
    'ui.save': 'Save',
    'ui.cancel': 'Cancel',
    'ui.login': 'Log In',
    'ui.createAccount': 'Create Account',
    'ui.logout': 'Log Out',
    'ui.profile': 'Profile',
    'ui.personalInfo': 'Personal Info',
    'ui.preferences': 'Preferences',
    'ui.language': 'Language',
    'ui.bookmarks': 'Bookmarks',
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
  };

  static const Map<String, String> _zh = {
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

    'login.m1': '登录成功。开始使用 NarrateMy 享受您的旅行吧。',
    'login.m2': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'login.m3': '无法使用 Google 登录，请重试。',
    'login.m4': '未找到账户。请检查您的登录信息或注册新账户。',
    'login.m5': '输入的OTP不正确或已过期，请重试。',
    'login.m6': '输入的用户名或密码不正确。',
    'login.m7': '登录失败次数过多。您的账户已被锁定30分钟。请稍后再试或重置密码。',
    'login.m8': 'OTP请求或验证尝试次数过多。请稍后再试。',

    'passwordReset.m1': '请输入您注册的电话号码以重置密码。',
    'passwordReset.m2': '一次性密码 (OTP) 已发送到您的手机号码。请在5分钟内输入。',
    'passwordReset.m3': '您的密码已成功重置。现在可以登录了。',
    'passwordReset.m4': '此电话号码尚未注册。',
    'passwordReset.m5': '输入的OTP不正确或已过期，请重试。',
    'passwordReset.m6': '密码必须至少包含8个字符，并至少包含一个字母和一个数字。',
    'passwordReset.m7': '输入的密码不匹配。请重试。',
    'passwordReset.m8': '请求次数过多，请稍后再试。',

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
    'profile.m22': '删除您的账户？此操作将永久删除您的个人资料、偏好设置和收藏夹，且无法撤销。',
    'profile.m23': '您的账户已被删除。',
    'profile.m24': '无法删除您的账户。请重试。',
    'profile.m25': '无法更新您的头像。请重试。',

    'ui.save': '保存',
    'ui.cancel': '取消',
    'ui.login': '登录',
    'ui.createAccount': '创建账户',
    'ui.logout': '登出',
    'ui.profile': '个人资料',
    'ui.personalInfo': '个人信息',
    'ui.preferences': '偏好设置',
    'ui.language': '语言',
    'ui.bookmarks': '收藏夹',
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
  };

  static const Map<String, String> _ms = {
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
        'Padam akaun anda? Ini akan mengalih keluar profil, keutamaan, dan penanda halaman anda '
            'secara kekal, dan tidak boleh dibatalkan.',
    'profile.m23': 'Akaun anda telah dipadamkan.',
    'profile.m24': 'Tidak dapat memadamkan akaun anda. Sila cuba lagi.',
    'profile.m25': 'Tidak dapat mengemas kini gambar profil anda. Sila cuba lagi.',

    'ui.save': 'Simpan',
    'ui.cancel': 'Batal',
    'ui.login': 'Log Masuk',
    'ui.createAccount': 'Cipta Akaun',
    'ui.logout': 'Log Keluar',
    'ui.profile': 'Profil',
    'ui.personalInfo': 'Maklumat Peribadi',
    'ui.preferences': 'Keutamaan',
    'ui.language': 'Bahasa',
    'ui.bookmarks': 'Penanda Halaman',
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
  };

  static const Map<String, String> _es = {
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
        '¿Eliminar su cuenta? Esto elimina permanentemente su perfil, preferencias y marcadores, '
            'y no se puede deshacer.',
    'profile.m23': 'Su cuenta ha sido eliminada.',
    'profile.m24': 'No se pudo eliminar su cuenta. Inténtelo de nuevo.',
    'profile.m25': 'No se pudo actualizar su foto de perfil. Inténtelo de nuevo.',

    'ui.save': 'Guardar',
    'ui.cancel': 'Cancelar',
    'ui.login': 'Iniciar Sesión',
    'ui.createAccount': 'Crear Cuenta',
    'ui.logout': 'Cerrar Sesión',
    'ui.profile': 'Perfil',
    'ui.personalInfo': 'Información Personal',
    'ui.preferences': 'Preferencias',
    'ui.language': 'Idioma',
    'ui.bookmarks': 'Marcadores',
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
  };

  static const Map<String, String> _hi = {
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

    'passwordReset.m1': 'अपना पासवर्ड रीसेट करने के लिए अपना पंजीकृत फ़ोन नंबर दर्ज करें।',
    'passwordReset.m2': 'आपके फ़ोन नंबर पर एक वन-टाइम पासवर्ड (OTP) भेजा गया है। कृपया इसे 5 मिनट के भीतर दर्ज करें।',
    'passwordReset.m3': 'आपका पासवर्ड सफलतापूर्वक रीसेट कर दिया गया है। अब आप लॉग इन कर सकते हैं।',
    'passwordReset.m4': 'यह फ़ोन नंबर पंजीकृत नहीं है।',
    'passwordReset.m5': 'दर्ज किया गया OTP गलत है या समाप्त हो गया है। कृपया पुनः प्रयास करें।',
    'passwordReset.m6': 'पासवर्ड में कम से कम 8 अक्षर होने चाहिए, जिसमें कम से कम एक अक्षर और एक अंक शामिल हो।',
    'passwordReset.m7': 'दर्ज किए गए पासवर्ड मेल नहीं खाते। कृपया पुनः प्रयास करें।',
    'passwordReset.m8': 'बहुत अधिक अनुरोध। कृपया बाद में पुनः प्रयास करें।',

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
        'अपना खाता हटाएं? यह आपकी प्रोफ़ाइल, प्राथमिकताएँ और बुकमार्क को स्थायी रूप से हटा देगा, '
            'और इसे पूर्ववत नहीं किया जा सकता।',
    'profile.m23': 'आपका खाता हटा दिया गया है।',
    'profile.m24': 'आपका खाता हटाने में असमर्थ। कृपया पुनः प्रयास करें।',
    'profile.m25': 'आपकी प्रोफ़ाइल तस्वीर अपडेट करने में असमर्थ। कृपया पुनः प्रयास करें।',

    'ui.save': 'सहेजें',
    'ui.cancel': 'रद्द करें',
    'ui.login': 'लॉग इन करें',
    'ui.createAccount': 'खाता बनाएं',
    'ui.logout': 'लॉग आउट करें',
    'ui.profile': 'प्रोफ़ाइल',
    'ui.personalInfo': 'व्यक्तिगत जानकारी',
    'ui.preferences': 'प्राथमिकताएँ',
    'ui.language': 'भाषा',
    'ui.bookmarks': 'बुकमार्क',
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
  };
}
