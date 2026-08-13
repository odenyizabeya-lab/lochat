import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/lotext_button.dart';
import '../../../shared/widgets/lotext_text_field.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/profile_repository.dart';
import '../models/user_profile.dart';
import '../profile_controller.dart';
import '../profile_scope.dart';

/// Full profile editor: profile photo, display name, and username. Only the
/// signed-in user's own profile is ever edited; ownership is enforced by the
/// repository and the Firestore security rules.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

enum _Availability { unknown, checking, available, taken }

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  Timer? _debounce;
  _Availability _availability = _Availability.unknown;
  bool _saving = false;
  bool _photoBusy = false;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final UserProfile? profile = ProfileScope.of(context).profile;
    _displayNameController.text = profile?.displayName ?? '';
    _usernameController.text = profile?.username ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    setState(() => _availability = _Availability.unknown);
    _debounce = Timer(const Duration(milliseconds: 400), _checkAvailability);
  }

  Future<void> _checkAvailability() async {
    final String name = Validators.normalizeUsername(_usernameController.text);
    if (Validators.username(name) != null || name.isEmpty) {
      if (!mounted) return;
      setState(() => _availability = _Availability.unknown);
      return;
    }

    final ProfileController controller = ProfileScope.of(context);
    if (controller.profile?.username == name) {
      if (!mounted) return;
      setState(() => _availability = _Availability.available);
      return;
    }

    if (!mounted) return;
    setState(() => _availability = _Availability.checking);
    try {
      final bool available = await controller.isUsernameAvailable(name);
      if (!mounted) return;
      setState(() {
        _availability = available ? _Availability.available : _Availability.taken;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _availability = _Availability.unknown);
    }
  }

  Future<void> _changePhoto() async {
    final ProfileController controller = ProfileScope.of(context);
    setState(() => _photoBusy = true);
    try {
      final bool changed = await controller.updateProfilePhoto();
      if (!mounted) return;
      if (changed) {
        AppSnackbars.showInfo(context, 'Profile photo updated');
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackbars.showError(
        context,
        'Could not update your photo. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final ProfileController controller = ProfileScope.of(context);
    setState(() => _photoBusy = true);
    try {
      await controller.removeProfilePhoto();
      if (!mounted) return;
      AppSnackbars.showInfo(context, 'Photo removed');
    } catch (_) {
      if (!mounted) return;
      AppSnackbars.showError(
        context,
        'Could not remove your photo. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_availability == _Availability.taken) return;

    final ProfileController controller = ProfileScope.of(context);
    final UserProfile? current = controller.profile;

    final String newUsername =
        Validators.normalizeUsername(_usernameController.text);
    final String newDisplayName = _displayNameController.text.trim();

    final bool usernameChanged = current == null || current.username != newUsername;
    final bool displayNameChanged =
        current == null || current.displayName != newDisplayName;

    setState(() => _saving = true);
    try {
      if (usernameChanged) {
        await controller.setUsername(newUsername);
      }
      if (displayNameChanged) {
        await controller.setDisplayName(newDisplayName);
      }
      if (!mounted) return;
      AppSnackbars.showInfo(context, 'Profile updated');
    } on UsernameUnavailableException {
      if (!mounted) return;
      setState(() => _availability = _Availability.taken);
      AppSnackbars.showError(context, 'That username was just taken. Try another.');
    } catch (_) {
      if (!mounted) return;
      AppSnackbars.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final UserProfile? profile = ProfileScope.of(context).profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          UserAvatar(
                            name: profile?.displayName.isNotEmpty ?? false
                                ? profile!.displayName
                                : (profile?.username ?? 'L'),
                            photoURL: profile?.photoURL,
                            size: 96,
                          ),
                          if (_photoBusy)
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: scheme.scrim.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: _photoBusy ? null : _changePhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Change photo'),
                        ),
                        if (profile?.hasPhoto ?? false) ...<Widget>[
                          TextButton.icon(
                            onPressed: _photoBusy ? null : _removePhoto,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Remove photo'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    LoTextTextField(
                      controller: _displayNameController,
                      label: 'Display name',
                      hintText: 'Jerry',
                      icon: Icons.badge_outlined,
                      textInputAction: TextInputAction.next,
                      validator: Validators.displayName,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      onChanged: _onUsernameChanged,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(20),
                        TextInputFormatter.withFunction(
                          (TextEditingValue oldValue, TextEditingValue newValue) {
                            final String lower = newValue.text.toLowerCase();
                            return newValue.copyWith(
                              text: lower,
                              selection: TextSelection.collapsed(offset: lower.length),
                            );
                          },
                        ),
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixText: '@ ',
                        errorText: _availability == _Availability.taken
                            ? 'Username already taken'
                            : Validators.username(
                                Validators.normalizeUsername(_usernameController.text),
                              ),
                        suffixIcon: _availability == _Availability.available
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF16A34A),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    LoTextButton(
                      label: 'Save changes',
                      isExpanded: true,
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
