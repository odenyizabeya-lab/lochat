/// Gender of a [VoiceEffectPreset] (the broad voice category).
enum VoiceGender { man, woman }

/// A real neural voice the admin can apply to a voice message.
///
/// Each preset names one of Microsoft Edge's free neural voices ([edgeVoiceName]).
/// When an admin picks a voice, the app asks the `ai-assistant` edge function to
/// synthesize the message in that voice (typed text is spoken directly; a
/// recording is transcribed first with Whisper then re-spoken). The [id] is the
/// stable wire value persisted on the message, so everyone who plays the clip
/// hears the same voice.
class VoiceEffectPreset {
  const VoiceEffectPreset({
    required this.id,
    required this.label,
    required this.gender,
    required this.edgeVoiceName,
    required this.description,
  });

  /// Stable id persisted as the message's `voice_effect` column.
  final String id;

  /// Human-readable voice name (e.g. "Guy").
  final String label;

  /// Whether this is a man or woman voice.
  final VoiceGender gender;

  /// The Microsoft Edge neural voice short name (e.g. `en-US-GuyNeural`).
  final String edgeVoiceName;

  /// One-line description shown in the voice picker.
  final String description;

  bool get isMan => gender == VoiceGender.man;
}

/// The man voice presets offered by the admin voice changer.
const List<VoiceEffectPreset> manVoicePresets = <VoiceEffectPreset>[
  VoiceEffectPreset(
    id: 'voice_guy',
    label: 'Guy',
    gender: VoiceGender.man,
    edgeVoiceName: 'en-US-GuyNeural',
    description: 'Deep and confident',
  ),
  VoiceEffectPreset(
    id: 'voice_eric',
    label: 'Eric',
    gender: VoiceGender.man,
    edgeVoiceName: 'en-US-EricNeural',
    description: 'Smooth baritone',
  ),
  VoiceEffectPreset(
    id: 'voice_christopher',
    label: 'Christopher',
    gender: VoiceGender.man,
    edgeVoiceName: 'en-US-ChristopherNeural',
    description: 'Warm and deep',
  ),
  VoiceEffectPreset(
    id: 'voice_andrew',
    label: 'Andrew',
    gender: VoiceGender.man,
    edgeVoiceName: 'en-US-AndrewNeural',
    description: 'Clear and friendly',
  ),
  VoiceEffectPreset(
    id: 'voice_ryan',
    label: 'Ryan',
    gender: VoiceGender.man,
    edgeVoiceName: 'en-GB-RyanNeural',
    description: 'British accent',
  ),
];

/// The woman voice presets offered by the admin voice changer.
const List<VoiceEffectPreset> womanVoicePresets = <VoiceEffectPreset>[
  VoiceEffectPreset(
    id: 'voice_aria',
    label: 'Aria',
    gender: VoiceGender.woman,
    edgeVoiceName: 'en-US-AriaNeural',
    description: 'Bright and expressive',
  ),
  VoiceEffectPreset(
    id: 'voice_jenny',
    label: 'Jenny',
    gender: VoiceGender.woman,
    edgeVoiceName: 'en-US-JennyNeural',
    description: 'Soft and friendly',
  ),
  VoiceEffectPreset(
    id: 'voice_michelle',
    label: 'Michelle',
    gender: VoiceGender.woman,
    edgeVoiceName: 'en-US-MichelleNeural',
    description: 'Warm and conversational',
  ),
  VoiceEffectPreset(
    id: 'voice_natasha',
    label: 'Natasha',
    gender: VoiceGender.woman,
    edgeVoiceName: 'en-AU-NatashaNeural',
    description: 'Australian accent',
  ),
  VoiceEffectPreset(
    id: 'voice_sonia',
    label: 'Sonia',
    gender: VoiceGender.woman,
    edgeVoiceName: 'en-GB-SoniaNeural',
    description: 'British accent',
  ),
];

/// All presets, man voices first.
const List<VoiceEffectPreset> allVoiceEffectPresets =
    <VoiceEffectPreset>[...manVoicePresets, ...womanVoicePresets];

/// Resolves a preset from its persisted id (null when the id is unknown).
VoiceEffectPreset? voiceEffectPresetForId(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final VoiceEffectPreset preset in allVoiceEffectPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
