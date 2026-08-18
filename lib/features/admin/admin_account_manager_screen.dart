import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/app_routes.dart';
import './models/managed_account.dart';
import './managed_account_controller.dart';

class AdminAccountManagerScreen extends StatefulWidget {
  const AdminAccountManagerScreen({super.key, required this.controller});

  final ManagedAccountController controller;

  @override
  State<AdminAccountManagerScreen> createState() => _AdminAccountManagerScreenState();
}

class _AdminAccountManagerScreenState extends State<AdminAccountManagerScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _createAccount(int slotIndex) async {
    final TextEditingController usernameCtrl = TextEditingController();
    final TextEditingController displayCtrl = TextEditingController();
    final TextEditingController lotextCtrl = TextEditingController();
    String? photoUrl;

    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Create Account $slotIndex'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'e.g. johndoe',
                        prefixText: '@',
                      ),
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. John Doe',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lotextCtrl,
                      decoration: const InputDecoration(
                        labelText: 'LoText ID (optional)',
                        hintText: '9-digit ID',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        ElevatedButton.icon(
                          onPressed: () async {
                            final XFile? picked = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 400,
                              maxHeight: 400,
                              imageQuality: 85,
                            );
                            if (picked != null) {
                              final Uint8List bytes = await picked.readAsBytes();
                              if (!mounted) return;
                              setState(() {
                                photoUrl = picked.path;
                              });
                            }
                          },
                          icon: const Icon(Icons.photo_rounded),
                          label: const Text('Pick photo'),
                        ),
                        const SizedBox(width: 12),
                        if (photoUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(photoUrl!),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final String username = usernameCtrl.text.trim().toLowerCase();
                    final String display = displayCtrl.text.trim();
                    if (username.isEmpty || display.isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;

    final String username = usernameCtrl.text.trim().toLowerCase();
    final String display = displayCtrl.text.trim();
    final String lotext = lotextCtrl.text.trim();

    try {
      await widget.controller.createAccount(
        slotIndex: slotIndex,
        username: username,
        displayName: display,
        lotextId: lotext.isEmpty ? null : lotext,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account $slotIndex created.')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the account. Try again.'),
        ),
      );
    }
  }

  Future<void> _editAccount(ManagedAccount account) async {
    final TextEditingController usernameCtrl =
        TextEditingController(text: account.username);
    final TextEditingController displayCtrl =
        TextEditingController(text: account.displayName);
    final TextEditingController lotextCtrl =
        TextEditingController(text: account.lotextId ?? '');

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Account ${account.slotIndex}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                  ),
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: displayCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lotextCtrl,
                  decoration: const InputDecoration(
                    labelText: 'LoText ID',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String username = usernameCtrl.text.trim().toLowerCase();
                final String display = displayCtrl.text.trim();
                if (username.isEmpty || display.isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;

    try {
      await widget.controller.updateAccount(
        account.copyWith(
          username: usernameCtrl.text.trim().toLowerCase(),
          displayName: displayCtrl.text.trim(),
          lotextId: lotextCtrl.text.trim().isEmpty ? null : lotextCtrl.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account ${account.slotIndex} updated.')),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the account. Try again.'),
        ),
      );
    }
  }

  Future<void> _deleteAccount(ManagedAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Delete Account ${account.slotIndex}?'),
        content: Text(
          'This will permanently delete ${account.displayName} (@${account.username}) and all of its chats, messages, and contacts.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.controller.deleteAccount(account.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account ${account.slotIndex} deleted.')),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the account. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Managed Accounts'),
        actions: <Widget>[
          if (widget.controller.selectedAccount != null)
            IconButton(
              tooltip: 'Open chat room',
              icon: const Icon(Icons.chat_bubble_rounded),
              onPressed: () {
                context.push(AppRoutes.adminChatRoom);
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (BuildContext context, Widget? _) {
          if (widget.controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (widget.controller.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load accounts.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: widget.controller.refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final List<ManagedAccount> accounts = widget.controller.accounts;
          final bool canAddMore = widget.controller.canAddMore;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: 10,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final int slotIndex = index + 1;
              final ManagedAccount? account =
                  accounts.where((ManagedAccount a) => a.slotIndex == slotIndex).firstOrNull;
              if (account != null) {
                return _AccountTile(
                  account: account,
                  isSelected: widget.controller.selectedAccount?.id == account.id,
                  onTap: () => widget.controller.selectAccount(account),
                  onEdit: () => _editAccount(account),
                  onDelete: () => _deleteAccount(account),
                );
              }
              return _EmptySlotTile(
                slotIndex: slotIndex,
                canAddMore: canAddMore,
                onCreate: () => _createAccount(slotIndex),
              );
            },
          );
        },
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ManagedAccount account;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? scheme.primary : scheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: account.photoUrl != null ? NetworkImage(account.photoUrl!) : null,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: account.photoUrl == null
              ? Text(
                  account.displayName.isNotEmpty
                      ? account.displayName[0].toUpperCase()
                      : '?',
                  style: theme.textTheme.titleLarge,
                )
              : null,
        ),
        title: Text(
          account.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${account.displayHandle}  ·  Account ${account.slotIndex}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Edit',
              icon: Icon(Icons.edit_outlined, color: scheme.primary),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptySlotTile extends StatelessWidget {
  const _EmptySlotTile({
    required this.slotIndex,
    required this.canAddMore,
    required this.onCreate,
  });

  final int slotIndex;
  final bool canAddMore;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AnimatedOpacity(
      opacity: canAddMore ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant, style: BorderStyle.solid),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
          ),
          title: Text(
            'Account $slotIndex',
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          subtitle: Text(
            canAddMore ? 'Tap to create' : 'Maximum of 10 accounts reached',
            style: theme.textTheme.bodySmall?.copyWith(
              color: canAddMore ? scheme.onSurfaceVariant : scheme.error,
            ),
          ),
          onTap: canAddMore ? onCreate : null,
        ),
      ),
    );
  }
}
