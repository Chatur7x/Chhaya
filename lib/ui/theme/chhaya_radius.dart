// Radius scale (V14 Part 6).
//
// Claude Light is round: spec set 8/12/16/20/9999. Legacy names are
// preserved and re-mapped (pill buttons go fully round, cards lift to
// 16, sheets to 20). Same names, new posture — call sites unchanged.
class ChhayaRadius {
  ChhayaRadius._();

  static const double xs = 8.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0; // Cards
  static const double xl = 16.0;
  static const double xxl = 20.0; // Bottom sheets
  static const double pill = 9999.0; // Buttons, chips, badges
  static const double circle = 9999.0;
}
