import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/supabase/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Missing Supabase configuration. Pass the project URL and publishable '
      'key at build time:\n'
      '  flutter run --dart-define=LOTEXT_SUPABASE_URL=https://<project>.supabase.co '
      '--dart-define=LOTEXT_SUPABASE_KEY=<publishable-key>',
    );
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const LoTextApp());
}
