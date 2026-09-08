import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/guide_step.dart';

/// A short, swipeable walkthrough for a single module.
class GuideWalkthroughScreen extends StatefulWidget {
  final List<GuideStep> steps;
  final String titleKey;

  const GuideWalkthroughScreen({
    super.key,
    required this.steps,
    required this.titleKey,
  });

  @override
  State<GuideWalkthroughScreen> createState() =>
      _GuideWalkthroughScreenState();
}

class _GuideWalkthroughScreenState extends State<GuideWalkthroughScreen> {
  final PageController _controller = PageController();

  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.steps.length) {
      return;
    }

    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();

    final steps = widget.steps;

    if (steps.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            AppLocalizations.t(widget.titleKey),
          ),
        ),
        body: const Center(
          child: Text('No guide steps available.'),
        ),
      );
    }

    final isLast = _index == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.t(widget.titleKey),
        ),
        actions: [
          if (!isLast)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                AppLocalizations.t('ui.arGuideSkip'),
              ),
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
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                  });
                },
                itemBuilder: (context, i) {
                  return _GuideStepView(
                    step: steps[i],
                  );
                },
              ),
            ),

            _GuideDots(
              count: steps.length,
              index: _index,
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _goTo(_index - 1);
                        },
                        child: Text(
                          AppLocalizations.t('ui.arGuideBack'),
                        ),
                      ),
                    ),

                  if (_index > 0)
                    const SizedBox(width: 12),

                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isLast
                          ? () {
                        Navigator.of(context).pop();
                      }
                          : () {
                        _goTo(_index + 1);
                      },
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

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _GuideStepView extends StatelessWidget {
  final GuideStep step;

  const _GuideStepView({
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  step.imageAsset,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 48,
                        color: AppColors.accentDark,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            AppLocalizations.t(step.titleKey),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),

          const SizedBox(height: 6),

          Flexible(
            flex: 2,
            child: Text(
              AppLocalizations.t(step.bodyKey),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.inkSoft,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideDots extends StatelessWidget {
  final int count;
  final int index;

  const _GuideDots({
    required this.count,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
            (i) {
          final active = i == index;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent
                  : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        },
      ),
    );
  }
}