import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/guide_step.dart';

/// A short, swipeable walkthrough for a single module — used by the
/// Guidance hub (`guidance_screen.dart`) for AR today, and reusable for any
/// future module: just pass its own `List<GuideStep>` and an app-bar title
/// key. No module-specific code lives in this file.
class GuideWalkthroughScreen extends StatefulWidget {
  final List<GuideStep> steps;
  final String titleKey;

  const GuideWalkthroughScreen({
    super.key,
    required this.steps,
    required this.titleKey,
  });

  @override
  State<GuideWalkthroughScreen> createState() => _GuideWalkthroughScreenState();
}

class _GuideWalkthroughScreenState extends State<GuideWalkthroughScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.animateTo(
      index * _controller.position.viewportDimension,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    final steps = widget.steps;
    final isLast = _index == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t(widget.titleKey)),
        actions: [
          if (!isLast)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.t('ui.arGuideSkip')),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _GuideStepView(step: steps[i]),
              ),
            ),
            _GuideDots(count: steps.length, index: _index),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _goTo(_index - 1),
                        child: Text(AppLocalizations.t('ui.arGuideBack')),
                      ),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isLast
                          ? () => Navigator.of(context).pop()
                          : () => _goTo(_index + 1),
                      child: Text(
                        isLast
                            ? AppLocalizations.t('ui.arGuideDone')
                            : AppLocalizations.t('ui.arGuideNext'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _GuideStepView extends StatelessWidget {
  final GuideStep step;

  const _GuideStepView({required this.step});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Image.asset(
                step.imageAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.accentSoft,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: AppColors.accentDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.t(step.titleKey),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.t(step.bodyKey),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _GuideDots extends StatelessWidget {
  final int count;
  final int index;

  const _GuideDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}