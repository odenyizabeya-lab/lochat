import 'package:flutter/material.dart';

import 'emoji_data.dart';

/// WhatsApp-style emoji panel that docks below the chat composer in place of
/// the system keyboard.
///
/// Features: category tabs with icons, full-text search, skin-tone modifiers
/// for people/hand emojis, a "recently used" row, and a keyboard toggle that
/// returns the user to the system keyboard.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    super.key,
    required this.onInsert,
    required this.onKeyboard,
    required this.recents,
    required this.skinTone,
    required this.onSkinToneChanged,
  });

  /// Called with the final emoji string (skin tone already applied).
  final ValueChanged<String> onInsert;

  /// Called when the user taps the keyboard button to go back to the system
  /// keyboard.
  final VoidCallback onKeyboard;

  /// Recently used emojis, most recent first.
  final List<String> recents;

  /// Currently selected skin tone (empty string = default).
  final String skinTone;

  final ValueChanged<String> onSkinToneChanged;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _category = 0;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Whether the current view should show the skin-tone row.
  bool get _skinnableCategory =>
      _category == 1 || _category == 2; // Smileys and Gestures tabs.

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<EmojiData> get _visible {
    final String query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      return allEmojiData
          .where((EmojiData data) => data.searchText.toLowerCase().contains(query))
          .toList();
    }
    if (_category == 0) {
      // "Recently used" is a virtual first tab.
      if (widget.recents.isEmpty) return const <EmojiData>[];
      return widget.recents
          .map(_find)
          .whereType<EmojiData>()
          .toList(growable: false);
    }
    return EmojiCategory.values[_category - 1].emojis;
  }

  EmojiData? _find(String emoji) {
    for (final EmojiData data in allEmojiData) {
      if (data.emoji == emoji) return data;
    }
    return null;
  }

  /// Applies the selected skin tone to skinnable emojis.
  String _applyTone(String emoji) {
    final String tone = widget.skinTone;
    if (tone.isEmpty) return emoji;
    final EmojiData? data = _find(emoji);
    if (data == null || !data.skinnable) return emoji;
    // Skin tone must not be appended twice (e.g. an already toned emoji that
    // came back from the recents list).
    if (emoji.contains(tone)) return emoji;
    return '$emoji$tone';
  }

  void _insert(EmojiData data) {
    widget.onInsert(_applyTone(data.emoji));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final WhatsAppPanelColors colors = WhatsAppPanelColors.of(context);
    final bool searching = _query.trim().isNotEmpty;

    final double panelHeight =
        (MediaQuery.sizeOf(context).height * 0.4).clamp(280.0, 420.0);

    return Container(
      height: panelHeight,
      color: colors.surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 2),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Show keyboard',
                  onPressed: widget.onKeyboard,
                  icon: Icon(
                    Icons.keyboard_rounded,
                    color: colors.icon,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _search,
                      onChanged: (String value) =>
                          setState(() => _query = value),
                      style: TextStyle(color: colors.text),
                      cursorColor: scheme.primary,
                      decoration: InputDecoration(
                        hintText: 'Search emoji',
                        hintStyle: TextStyle(color: colors.hint),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 20, color: colors.icon),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: colors.searchBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: Row(
              children: <Widget>[
                for (int i = 0; i <= EmojiCategory.values.length; i++) ...<Widget>[
                  Expanded(
                    child: InkResponse(
                      onTap: () => setState(() {
                        _category = i;
                        _query = '';
                        _search.clear();
                      }),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2.5,
                              color: i == _category && !searching
                                  ? colors.accent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Icon(
                          i == 0
                              ? Icons.history_rounded
                              : EmojiCategory.values[i - 1].icon,
                          size: 21,
                          color: i == _category && !searching
                              ? colors.accent
                              : colors.icon,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (searching || (_skinnableCategory && _category != 0))
            _buildSkinToneRow(colors),
          Divider(height: 1, color: colors.divider),
          Expanded(
            child: _buildGrid(theme, colors, searching),
          ),
        ],
      ),
    );
  }

  Widget _buildSkinToneRow(WhatsAppPanelColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: <Widget>[
          Icon(Icons.face_rounded, size: 18, color: colors.icon),
          const SizedBox(width: 8),
          for (final String tone in skinTones) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkResponse(
                onTap: () => widget.onSkinToneChanged(tone),
                radius: 18,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.isEmpty
                        ? colors.defaultTone
                        : const Color(0xFFFFCC4D),
                    border: Border.all(
                      color: widget.skinTone == tone
                          ? colors.accent
                          : colors.divider,
                      width: widget.skinTone == tone ? 2.5 : 1,
                    ),
                  ),
                  child: tone.isEmpty
                      ? Icon(Icons.face_rounded,
                          size: 20, color: colors.defaultToneGlyph)
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(
    ThemeData theme,
    WhatsAppPanelColors colors,
    bool searching,
  ) {
    final List<EmojiData> emojis = _visible;

    if (searching && emojis.isEmpty) {
      return Center(
        child: Text(
          'No emojis found',
          style: TextStyle(color: colors.icon),
        ),
      );
    }
    if (_category == 0 && emojis.isEmpty) {
      return Center(
        child: Text(
          'No recent emojis yet \u2014 tap an emoji to add it here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.icon, fontSize: 13),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: emojis.length,
      itemBuilder: (BuildContext context, int index) {
        final EmojiData data = emojis[index];
        return InkResponse(
          onTap: () => _insert(data),
          radius: 24,
          child: Center(
            child: Text(
              data.emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        );
      },
    );
  }
}

class WhatsAppPanelColors {
  const WhatsAppPanelColors({
    required this.surface,
    required this.icon,
    required this.text,
    required this.hint,
    required this.searchBackground,
    required this.accent,
    required this.divider,
    required this.defaultTone,
    required this.defaultToneGlyph,
  });

  final Color surface;
  final Color icon;
  final Color text;
  final Color hint;
  final Color searchBackground;
  final Color accent;
  final Color divider;
  final Color defaultTone;
  final Color defaultToneGlyph;

  static WhatsAppPanelColors of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return dark
        ? const WhatsAppPanelColors(
            surface: Color(0xFF111B21),
            icon: Color(0xFF8696A0),
            text: Color(0xFFE9EDEF),
            hint: Color(0xFF8696A0),
            searchBackground: Color(0xFF202C33),
            accent: Color(0xFF00A884),
            divider: Color(0xFF2A3942),
            defaultTone: Color(0xFF2A3942),
            defaultToneGlyph: Color(0xFF8696A0),
          )
        : const WhatsAppPanelColors(
            surface: Colors.white,
            icon: Color(0xFF54656F),
            text: Color(0xFF111B21),
            hint: Color(0xFF667781),
            searchBackground: Color(0xFFF0F2F5),
            accent: Color(0xFF00A884),
            divider: Color(0xFFE9EDEF),
            defaultTone: Color(0xFFE9EDEF),
            defaultToneGlyph: Color(0xFF54656F),
          );
  }
}
