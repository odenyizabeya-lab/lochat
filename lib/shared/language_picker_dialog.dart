import 'package:flutter/material.dart';

import 'languages.dart';

/// Shows a searchable dialog over [worldLanguages] and resolves to the picked
/// [Language], or null when dismissed.
Future<Language?> showLanguagePicker(
  BuildContext context, {
  String title = 'Translate to',
}) {
  return showDialog<Language>(
    context: context,
    builder: (BuildContext context) => _LanguagePickerDialog(title: title),
  );
}

/// Searchable language picker over [worldLanguages].
class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({required this.title});

  final String title;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Language> get _results {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return worldLanguages;
    return worldLanguages
        .where((Language language) =>
            language.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              widget.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search languages',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (BuildContext context, int index) {
                final Language language = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(language.name),
                  onTap: () => Navigator.of(context).pop(language),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
