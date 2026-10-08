// Spacing scale (V14 Part 6).
//
// Spec sizes 4/8/12/16/24/32/48 all exist below (space1/2/3/4/6/8/12).
// Legacy aliases preserved; call sites unchanged.
class ChhayaSpacing {
  ChhayaSpacing._();

  static const double space0 = 0;
  static const double space1 = 4.0; // xs — spec
  static const double space2 = 8.0; // sm — spec
  static const double space3 = 12.0; // md — spec
  static const double space4 = 16.0; // lg — spec
  static const double space5 = 20.0; // xl
  static const double space6 = 24.0; // xxl — spec
  static const double space7 = 28.0; // xxxl
  static const double space8 = 32.0; // huge — spec
  static const double space12 = 48.0; // massive — spec
  static const double space16 = 64.0; // colossal

  // Legacy aliases
  static const double xs = space1;
  static const double sm = space2;
  static const double md = space3;
  static const double lg = space4;
  static const double xl = space5;
  static const double xxl = space6;
  static const double xxxl = space7;
  static const double huge = space8;
  static const double massive = space12;
  static const double colossal = space16;
}
