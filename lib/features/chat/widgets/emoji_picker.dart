import 'package:flutter/material.dart';

/// WhatsApp-style emoji panel: a bottom sheet with a grid of common emojis.
///
/// Tapping an emoji inserts it into the composer; the sheet stays open so the
/// user can add several in a row, and closes via the collapse control or by
/// dragging down.
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({super.key, required this.onInsert, required this.onClose});

  /// Called with each emoji the user taps.
  final ValueChanged<String> onInsert;

  /// Called when the user taps the collapse (keyboard) button.
  final VoidCallback onClose;

  /// Shows the picker as a modal bottom sheet. Returns the last sheet height
  /// logic to the caller if needed; simplest usage is via [showEmojiSheet].
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onInsert,
    required VoidCallback onClose,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => EmojiPicker(
        onInsert: onInsert,
        onClose: onClose,
      ),
    );
  }

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  int _category = 0;

  static const List<String> _categories = <String>['Smileys', 'Gestures', 'People'];

  static const List<List<String>> _emoji = <List<String>>[
    <String>[
      '😀', '😄', '😁', '😂', '🤣', '😊', '😇', '🙂', '😉', '😍',
      '😘', '😋', '😜', '🤪', '😎', '🤩', '🥳', '😏', '😒', '🙃',
      '😢', '😭', '😤', '😠', '🤯', '😱', '🥶', '🤔', '🤫', '😴',
      '🤤', '😪', '😷', '🤒', '🤢', '🥴', '🤠', '😈', '👻', '💀',
      '🤖', '👽', '🎃', '😺', '😸', '😹', '🙈', '🙉', '🙊', '💩',
      '💪', '👍', '👎', '👏', '🙌', '👐', '🤝', '✌️', '🤞', '👌',
      '🙏', '💅', '👀', '👂', '👃', '👄', '🦷', '🧠', '🫀', '🦵',
    ],
    <String>[
      '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉',
      '👆', '👇', '☝️', '👋', '🤚', '🖐️', '✋', '🖖', '👏', '🙌',
      '🤝', '🙏', '💪', '🦵', '🦶', '👂', '👃', '🧠', '👀', '👁️',
      '👅', '👄', '💋', '🦷', '🦴', '👤', '👥', '🗣️', '👶', '🧒',
      '👦', '👧', '🧑', '👨', '👩', '🧓', '👴', '👵',
    ],
    <String>[
      '👨', '👩', '👧', '👦', '👶', '🧑', '👴', '👵', '🧓', '👲',
      '👳', '👮', '🕵️', '💂', '👷', '🤴', '👸', '🤵', '👰', '🙋',
      '🤦', '🤷', '💆', '💇', '🏃', '🚶', '🧍', '🧎', '🏄', '🚣',
      '🧗', '🤸', '🤼', '🤾', '🧘', '🏇', '🚴', '🚵', '🤺', '⛹️',
      '🤽', '🤿', '🏊', '🛀', '🛌', '👼', '🎅', '🤶', '🦸', '🦹',
      '🧙', '🧚', '🧛', '🧜', '🧝', '🧞', '🧟', '🦄', '🐶', '🐱',
      '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮',
      '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦅', '🦉', '🦇',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final double height = MediaQuery.of(context).size.height * 0.38;

    return SizedBox(
      height: height,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: List<Widget>.generate(_categories.length, (int i) {
                      final bool selected = _category == i;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(_categories[i]),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _category = i),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: _emoji[_category].length,
              itemBuilder: (BuildContext context, int index) {
                final String emoji = _emoji[_category][index];
                return InkWell(
                  onTap: () => widget.onInsert(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
