import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/presence_indicator.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/lotext_id_generator.dart';
import '../models/user_profile.dart';
import '../profile_controller.dart';
import '../profile_scope.dart';

enum _SearchMode { lotextId, username }

/// Adds a contact by exact LoText ID or exact username.
///
/// Privacy-first by design: there is no directory, no suggestions, no partial
/// or display-name search. You can only find someone whose exact ID or
/// username you already know, and finding them never adds them - adding is an
/// explicit, separate action.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final TextEditingController _textController = TextEditingController();

  _SearchMode _mode = _SearchMode.lotextId;

  bool _loading = false;
  bool _found = false;
  bool _notFound = false;
  bool _selfMatch = false;
  bool _adding = false;
  UserProfile? _result;
  bool _isContact = false;
  Object? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String get _normalizedQuery {
    final String raw = _textController.text.trim();
    if (_mode == _SearchMode.username) {
      String value = raw.toLowerCase();
      if (value.startsWith('@')) value = value.substring(1);
      return value;
    }
    return raw;
  }

  void _switchMode(_SearchMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _resetResult();
    });
  }

  void _resetResult() {
    _loading = false;
    _found = false;
    _notFound = false;
    _selfMatch = false;
    _result = null;
    _isContact = false;
    _error = null;
  }

  String? _validate(String query) {
    if (query.isEmpty) return 'Enter a ${_mode == _SearchMode.lotextId ? 'LoText ID' : 'username'} to search for.';
    if (_mode == _SearchMode.lotextId && !isValidLotextId(query)) {
      return 'Enter a valid 9-digit LoText ID, for example 728491630.';
    }
    return null;
  }

  Future<void> _search() async {
    final String query = _normalizedQuery;
    final String? validationError = _validate(query);
    if (validationError != null) {
      AppSnackbars.showError(context, validationError);
      return;
    }
    setState(() {
      _loading = true;
      _notFound = false;
      _found = false;
      _selfMatch = false;
      _result = null;
      _error = null;
    });
    try {
      final ProfileController controller = ProfileScope.of(context);
      final UserProfile? profile = _mode == _SearchMode.lotextId
          ? await controller.fetchUserByLotextId(query)
          : await controller.fetchUserByUsername(query);
      if (!mounted) return;

      final String myUid = controller.profile?.uid ?? '';
      if (profile == null) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      if (profile.uid == myUid) {
        setState(() {
          _loading = false;
          _found = true;
          _selfMatch = true;
          _result = profile;
        });
        return;
      }
      final bool isContact = await controller.isContact(profile.uid);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _found = true;
        _result = profile;
        _isContact = isContact;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _addContact() async {
    final UserProfile? profile = _result;
    if (profile == null) return;
    setState(() => _adding = true);
    try {
      await ProfileScope.of(context).addContact(profile.uid);
      if (!mounted) return;
      setState(() {
        _adding = false;
        _isContact = true;
      });
      AppSnackbars.showInfo(context, '${_displayName(profile)} added to your contacts.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
      AppSnackbars.showError(context, 'Could not add contact. Try again.');
    }
  }

  String _displayName(UserProfile profile) =>
      profile.displayName.isNotEmpty ? profile.displayName : profile.username;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add contact')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            SegmentedButton<_SearchMode>(
              segments: const <ButtonSegment<_SearchMode>>[
                ButtonSegment<_SearchMode>(
                  value: _SearchMode.lotextId,
                  label: Text('LoText ID'),
                ),
                ButtonSegment<_SearchMode>(
                  value: _SearchMode.username,
                  label: Text('Username'),
                ),
              ],
              selected: <_SearchMode>{_mode},
              onSelectionChanged: (Set<_SearchMode> selection) =>
                  _switchMode(selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              keyboardType: _mode == _SearchMode.lotextId
                  ? TextInputType.number
                  : TextInputType.text,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: _mode == _SearchMode.lotextId
                    ? 'Enter LoText ID, e.g. 728491630'
                    : 'Enter username, e.g. @jerry123',
                prefixIcon: Icon(_mode == _SearchMode.lotextId
                    ? Icons.tag_rounded
                    : Icons.alternate_email_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            Text(
              _mode == _SearchMode.lotextId
                  ? 'Only exact, complete LoText IDs can be found.'
                  : 'Only exact usernames can be found. You can enter '
                      '@jerry123 or jerry123.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            LoTextButton(
              label: 'Search',
              icon: Icons.search_rounded,
              isExpanded: true,
              isLoading: _loading,
              onPressed: _loading ? null : _search,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              ErrorView(
                title: 'Search failed',
                message: 'Check your connection and try again.',
                onRetry: _search,
              )
            else if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_notFound)
              _buildMessage(theme, scheme, 'No one found',
                  'No account matches that ${_mode == _SearchMode.lotextId ? 'LoText ID' : 'username'}.')
            else if (_found && _result != null)
              _buildResult(theme, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, ColorScheme scheme, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.person_search_rounded, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, ColorScheme scheme) {
    final UserProfile profile = _result!;
    final String displayName = _displayName(profile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.publicProfileFor(profile.uid)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  UserAvatar(name: displayName, photoURL: profile.photoURL, size: 72),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.handle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                  if (profile.lotextId != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'LoText ID: ${profile.lotextId}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  PresenceIndicator(isOnline: profile.isOnline, lastSeen: profile.lastSeen),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to view their profile',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_selfMatch)
          _buildMessage(theme, scheme, 'That\'s you',
              'This is your own LoText profile. You cannot add yourself.')
        else if (_isContact)
          _buildMessage(theme, scheme, 'Already in your contacts',
              'This person is already in your contact list.')
        else
          LoTextButton(
            label: 'Add contact',
            icon: Icons.person_add_alt_1_rounded,
            isExpanded: true,
            isLoading: _adding,
            onPressed: _adding ? null : _addContact,
          ),
      ],
    );
  }
}
