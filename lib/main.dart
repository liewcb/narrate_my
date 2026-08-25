import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/accessibility/accessibility_vm.dart';
import 'core/config/app_config.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AccessibilityVm(),
      child: Builder(
        builder: (context) {
          // Kept OUTSIDE MaterialApp's own build so `context.watch` here
          // triggers a rebuild of just this Builder (and therefore the
          // MediaQuery override below) on every AccessibilityVm change,
          // without needing a second Provider/Consumer layer.
          final accessibility = context.watch<AccessibilityVm>();
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
