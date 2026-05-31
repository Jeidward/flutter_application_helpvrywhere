/// Generates the human-friendly trip code displayed on every screen of
/// the "help on the way" flow. Format: `<3-LETTER WORD> · <NN>`, e.g.
/// `BLU · 47`, `SUN · 09`, `OAK · 23`.
///
/// **Deterministic**: same seed → same code. Pass the Firestore trip
/// doc id and both phones will derive the identical string without
/// needing to read it from the doc itself. The code IS stored on the
/// trip doc anyway (so backend tools see the same value), but the
/// generator is the source-of-truth at the client level.
///
/// The word list is intentionally color-anchored — each word loosely
/// matches a brand color so the code is memorable ("yeah, the blue
/// trip, BLU · 47"). That makes the door-side verification challenge
/// in step 4 feel natural to read out loud.
class TripCodeGenerator {
  TripCodeGenerator._();

  static const List<String> _words = [
    // Blues
    'BLU', 'SKY', 'AQUA',
    // Greens
    'IVY', 'JADE', 'LIME', 'OAK',
    // Yellows / warm
    'SUN', 'BEE', 'TAN',
    // Reds / pinks
    'POP', 'ROSE', 'RUBY',
    // Purples
    'PLUM', 'IRIS',
    // Earth / neutral
    'CLAY', 'PINE', 'SAND',
  ];

  /// Builds a code from any string seed. Use the Firestore document
  /// id of the trip — it's the only thing both phones share before
  /// they read the doc, so it's the right "implicit handshake."
  static String fromSeed(String seed) {
    if (seed.isEmpty) return 'BLU · 01';
    // hashCode is stable within a single Dart process & SDK version.
    // For cross-platform stability we mix in a tiny per-char rotation
    // so two different seeds rarely collide on the same (word, number)
    // pair even if their hashCodes land in the same residue class.
    var h = 0;
    for (final unit in seed.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff; // keep positive, 31-bit
    }
    final word = _words[h % _words.length];
    final number = (h ~/ _words.length) % 100;
    return '$word · ${number.toString().padLeft(2, '0')}';
  }
}
