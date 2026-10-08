// رابط Apps Script (Web App) لإرسال Push والتطبيق مقفول من غير Cloud Functions.
// بيتمرّر وقت البناء: --dart-define=PUSH_RELAY_URL=https://script.google.com/macros/s/.../exec
// (Codemagic: ضيف متغيّر PUSH_RELAY_URL في المجموعة wasalah_env). فاضي = معطّل.
const String pushRelayUrl = String.fromEnvironment('PUSH_RELAY_URL');
