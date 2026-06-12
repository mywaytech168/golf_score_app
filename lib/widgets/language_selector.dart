import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

import '../providers/locale_provider.dart';
import '../theme/app_theme.dart';

/// A bottom sheet for selecting the app language.
/// Usage: LanguageSelectorSheet.show(context);
class LanguageSelectorSheet extends StatelessWidget {
  const LanguageSelectorSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<LocaleProvider>(),
        child: const LanguageSelectorSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<LocaleProvider>();
    final current = provider.locale;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.langSelectTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...LocaleProvider.supportedLocales.map((locale) {
              final isSelected = current.languageCode == locale.languageCode &&
                  current.countryCode == locale.countryCode;
              return ListTile(
                leading: Text(
                  provider.flagEmoji(locale),
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(provider.displayName(locale)),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: kBrandPrimary)
                    : null,
                selected: isSelected,
                selectedTileColor: kBrandPrimary.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  provider.setLocale(locale);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A compact tile that opens the language selector.
/// Drop this anywhere in a settings screen.
class LanguageSettingsTile extends StatelessWidget {
  const LanguageSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<LocaleProvider>();

    return ListTile(
      leading: const Icon(Icons.language_rounded),
      title: Text(l10n.langTitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${provider.flagEmoji(provider.locale)}  ${provider.displayName(provider.locale)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: () => LanguageSelectorSheet.show(context),
    );
  }
}
