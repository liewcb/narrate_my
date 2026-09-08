import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/ar_guide_steps.dart';
import 'widgets/guide_step.dart';
import 'guide_walkthrough_screen.dart';

/// One entry on the Guidance hub — a module's icon, label, and the list of
/// [GuideStep]s its walkthrough shows. To add another module's guide once
/// it's ready: add a `<module>_guide_steps.dart` file next to
/// `ar_guide_steps.dart`, then append one `_GuidanceModule` entry below.
/// `guidance_screen.dart` and `guide_walkthrough_screen.dart` don't need
/// any other changes.
class _GuidanceModule {
  final IconData icon;
  final String labelKey;
  final List<GuideStep> steps;

  const _GuidanceModule({
    required this.icon,
    required this.labelKey,
    required this.steps,
  });
}

const List<_GuidanceModule> _kGuidanceModules = [
  _GuidanceModule(
    icon: Icons.view_in_ar_outlined,
    labelKey: 'ui.arGuide',
    steps: kArGuideSteps,
  ),
  // Next module's guide goes here, e.g.:
  // _GuidanceModule(
  //   icon: Icons.map_outlined,
  //   labelKey: 'ui.itineraryGuide',
  //   steps: kItineraryGuideSteps,
  // ),
];

/// Profile > Guidance — a hub of short, swipeable walkthroughs, one per
/// module. Today it only lists the AR module's guide (Exploration ->
/// Placement -> Storytelling); other modules can register their own guide
/// here later without touching the Profile screen that links to this hub.
class GuidanceScreen extends StatelessWidget {
  const GuidanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.guidance'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              AppLocalizations.t('ui.guidanceSubtitle'),
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            ..._kGuidanceModules.map(
                  (module) => _GuidanceModuleTile(
                module: module,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GuideWalkthroughScreen(
                      steps: module.steps,
                      titleKey: module.labelKey,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceModuleTile extends StatelessWidget {
  final _GuidanceModule module;
  final VoidCallback onTap;

  const _GuidanceModuleTile({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(module.icon, color: AppColors.accentDark),
        title: Text(
          AppLocalizations.t(module.labelKey),
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.inkFaint),
        onTap: onTap,
      ),
    );
  }
}