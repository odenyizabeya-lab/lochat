/// Gender of a [VoiceEffectPreset] (the broad voice category).
enum VoiceGender { man, woman }

/// A named voice the admin can apply to a voice message.
///
/// Each preset is just a playback transform: [pitch] is applied when the clip
/// plays (lower = deeper "man" voices, higher = lighter "woman" voices). The
/// [id] is the stable wire value persisted on the message, so everyone who
/// plays the clip hears the same voice.
class VoiceEffectPreset {
  const VoiceEffectPreset({
    required this.id,
    required this.label,
    required this.gender,
    required this.pitch,
  });

  /// Stable id persisted as the message's `voice_effect` column.
  final String id;

  /// Human-readable voice name (e.g. "Deep").
  final String label;

  /// Whether this is a man or woman voice.
  final VoiceGender gender;

  /// Pitch multiplier applied at playback (1.0 = unaltered).
  final double pitch;

  bool get isMan => gender == VoiceGender.man;
}

/// The man voice presets offered by the admin voice changer.
const List<VoiceEffectPreset> manVoicePresets = <VoiceEffectPreset>[
  VoiceEffectPreset(id: 'man_giant', label: 'Giant', gender: VoiceGender.man, pitch: 0.58),
  VoiceEffectPreset(id: 'man_deep', label: 'Deep', gender: VoiceGender.man, pitch: 0.70),
  VoiceEffectPreset(id: 'man_baritone', label: 'Baritone', gender: VoiceGender.man, pitch: 0.80),
  VoiceEffectPreset(id: 'man_classic', label: 'Classic', gender: VoiceGender.man, pitch: 0.90),
];

/// The woman voice presets offered by the admin voice changer.
const List<VoiceEffectPreset> womanVoicePresets = <VoiceEffectPreset>[
  VoiceEffectPreset(id: 'woman_light', label: 'Light', gender: VoiceGender.woman, pitch: 1.06),
  VoiceEffectPreset(id: 'woman_soft', label: 'Soft', gender: VoiceGender.woman, pitch: 1.12),
  VoiceEffectPreset(id: 'woman_high', label: 'High', gender: VoiceGender.woman, pitch: 1.24),
  VoiceEffectPreset(id: 'woman_bright', label: 'Bright', gender: VoiceGender.woman, pitch: 1.34),
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
