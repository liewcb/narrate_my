import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/accessibility/accessibility_vm.dart';
import 'core/localization/locale_vm.dart';
import 'core/routes/app_routes.dart';
import 'core/services/database_manager.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initializes both Supabase (remote) and the local SQLite connection —
  // see DatabaseManager. Previously this called Supabase.initialize()
  // directly, which meant RemoteDatabaseService (used by the
  // Itinerary/Place/Destination adapters) never actually got initialized
  // and would throw the moment anything touched RemoteDatabaseService().client.
  await DatabaseManager().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // AccessibilityVm (REQ_503_6) and LocaleVm (UC402 A4 / REQ_201_2–5)
      // are deliberately parallel: both are read once here at the
      // `MaterialApp` root and applied app-wide — one via a MediaQuery
      // text-scale override, the other via `AppLocalizations.currentCode` —
      // so any screen (in Module 5 or, once a module adopts the same
      // `AppLocalizations.t()` pattern, any other module) can watch either
      // one directly and rebuild on change, without every ancestor between
      // here and that screen needing to rebuild too.
      providers: [
        ChangeNotifierProvider(create: (_) => AccessibilityVm()),
        ChangeNotifierProvider(create: (_) => LocaleVm()),
      ],
      child: Builder(
        builder: (context) {
          // Kept OUTSIDE MaterialApp's own build so `context.watch` here
          // triggers a rebuild of just this Builder (and therefore the
          // MediaQuery override below) on every AccessibilityVm change,
          // without needing a second Provider/Consumer layer.
          final accessibility = context.watch<AccessibilityVm>();
          // Belt-and-suspenders: most screens watch LocaleVm themselves
          // (Provider's InheritedNotifier lets them do that directly,
          // regardless of whether this Builder or `AppRoutes` itself
          // rebuilds), but watching it here too means a language change is
          // never missed even by a screen that forgets to.
          context.watch<LocaleVm>();
          return MaterialApp(
            title: 'narrate_my',
            theme: AppTheme.light,
            // REQ_503_6 Visual Assistance: scales text app-wide from one
            // place, on top of whatever text-scale the OS already
            // requests — see `AccessibilityVm` for why this is the one
            // accessibility toggle Module 5 can make do something real on
            // its own, without any other teammate's screens changing.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final baseScale = mq.textScaler.scale(1.0);
              final scale = accessibility.visualAssistanceEnabled
                  ? baseScale * AccessibilityVm.visualAssistanceScale
                  : baseScale;
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              );
            },
            // No app-wide login gate: guests can browse AR/Itinerary/Nearby
            // freely. Only the Profile tab gates on auth state — see
            // `lib/view/profile_screen.dart`.
            home: const AppRoutes(),
          );
        },
      ),
    );
  }
}