@echo off
cd /d C:\Lotext
flutter run -d chrome --web-port=8090 ^
  --dart-define=LOTEXT_SUPABASE_URL=https://oilcwdeibmceqwdtsuch.supabase.co ^
  --dart-define=LOTEXT_SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9pbGN3ZGVpYm1jZXF3ZHRzdWNoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY4NzM5MDAsImV4cCI6MjEwMjQ0OTkwMH0.LI1_cpozdp5F2k27sBBtn9VzB4zo2gCvGLTvCLLik4w > C:\Lotext\preview_run.log 2>&1