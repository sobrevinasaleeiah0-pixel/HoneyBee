import 'package:flutter/material.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier._();

  static final ThemeNotifier instance = ThemeNotifier._();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}

class AppTheme {
  AppTheme._();

  static const Color primaryGold = Color(0xFFF5B642);
  static const Color primaryGoldDeep = Color(0xFFE39A17);
  static const Color primaryDark = Color(0xFF0F1F2B);

  static const Color accentGold = Color(0xFFF7C86F);
  static const Color accentBlue = Color(0xFF6FA8FF);
  static const Color accentGreen = Color(0xFF5BC98A);
  static const Color accentPurple = Color(0xFF9E7BFF);
  static const Color accentRose = Color(0xFFEA7DAE);

  static const Color success = Color(0xFF2DBE77);
  static const Color warning = Color(0xFFF0A632);
  static const Color error = Color(0xFFE14B57);
  static const Color info = Color(0xFF4AA9FF);

  static const Color backgroundLight = Color(0xFFFBF6EB);
  static const Color backgroundLightWarm = Color(0xFFFFE8B8);
  static const Color backgroundLightAlt = Color(0xFFF7EFE0);
  static const Color backgroundDark = Color(0xFF111722);
  static const Color backgroundDarkAlt = Color(0xFF1A2230);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF17212E);
  static const Color surfaceDarkAlt = Color(0xFF202A3A);

  static const Color textLight = Color(0xFF17130B);
  static const Color textDark = Color(0xFFEAF1FF);
  static const Color textLightSecondary = Color(0xFF55462B);
  static const Color textLightSoft = Color(0xFF6E6049);
  static const Color subtitleLightColor = Color(0xFF8B7653);
  static const Color textDarkSecondary = Color(0xFFB4C2D6);
  static const Color textMutedLight = Color(0xFF7E8798);
  static const Color textMutedDark = Color(0xFF8EA0BA);
  static const Color textDarkSoft = Color(0xFFC9D5EA);

  static const Color borderLight = Color(0xFFEADABF);
  static const Color borderLightAlt = Color(0xFFDFCBA5);
  static const Color borderDark = Color(0xFF2E3747);
  static const Color borderDarkAlt = Color(0xFF3A465D);

  static const Color dividerLight = Color(0xFFEAE6DF);
  static const Color dividerDark = Color(0xFF2A3443);

  static const Color sidebarBg = Color(0xFF161E2C);
  static const Color sidebarBorder = Color(0xFF2B3342);
  static const Color sidebarBrandBg = Color(0xFF1D2940);
  static const Color sidebarBrandRing = Color(0xFF3A5C9C);
  static const Color sidebarDivider = Color(0xFF2F3A4C);
  static const Color sidebarLogoutText = Color(0xFFF1B7B7);
  static const Color sidebarNavText = Color(0xFFE9EEF8);
  static const Color sidebarNavIcon = Color(0xFFD7E2F7);

  static const Color panelBaseLight = Color(0xFFFFFFFF);
  static const Color panelBaseDark = Color(0xFF17212E);
  static const Color panelBorderLight = Color(0xFFEADABF);
  static const Color panelBorderDark = Color(0xFF2A3443);
  static const Color mutedPanelLight = Color(0xFFF7EFE0);
  static const Color softShadowColorBase = Color(0x1A1F2A44);

  static const Color tableHeaderBase = Color(0xFFF7EFE0);
  static const Color fieldBaseFill = Color(0xFFFBF6EB);
  static const Color searchInputBase = Color(0xFFF7EFE0);

  static const Color badgeGreenBgLight = Color(0xFFE9F8EE);
  static const Color badgeGreenBgDark = Color(0xFF123829);
  static const Color badgeGreenBorderLight = Color(0xFFB9E6C9);
  static const Color badgeGreenBorderDark = Color(0xFF2B6F52);

  static const Color badgeGoldBgLight = Color(0xFFFDF0D8);
  static const Color badgeGoldBgDark = Color(0xFF3C2E12);
  static const Color badgeGoldBorderLight = Color(0xFFE8D19D);
  static const Color badgeGoldBorderDark = Color(0xFF9B7B2E);

  static const Color badgeBlueBgLight = Color(0xFFE7F1FF);
  static const Color badgeBlueBgDark = Color(0xFF1A2E4C);
  static const Color badgeBlueBorderLight = Color(0xFFC8D8FF);
  static const Color badgeBlueBorderDark = Color(0xFF477BCF);

  static const Color badgeRedBgLight = Color(0xFFFDE9EA);
  static const Color badgeRedBgDark = Color(0xFF3D1D22);
  static const Color badgeRedBorderLight = Color(0xFFEDBAC0);
  static const Color badgeRedBorderDark = Color(0xFF9B3D4A);

  static const Color iconBadgeGoldLight = Color(0xFFFFF4DA);
  static const Color iconBadgeGoldDark = Color(0xFF3B2C13);
  static const Color iconBadgeBlueLight = Color(0xFFEAF2FF);
  static const Color iconBadgeBlueDark = Color(0xFF1A2C47);
  static const Color iconBadgeGreenLight = Color(0xFFEAF9F0);
  static const Color iconBadgeGreenDark = Color(0xFF153A2D);
  static const Color iconBadgePurpleLight = Color(0xFFF0EAFE);
  static const Color iconBadgePurpleDark = Color(0xFF2F254C);
  static const Color iconBadgeRoseLight = Color(0xFFFDE9F2);
  static const Color iconBadgeRoseDark = Color(0xFF3B2331);
  static const Color iconBadgeAmberLight = Color(0xFFFDF1D9);
  static const Color iconBadgeAmberDark = Color(0xFF3B2B0E);

  static const double adminPagePadding = 32.0;
  static const double adminPagePaddingCompact = 18.0;
  static const double adminRowGap = 12.0;
  static const double adminSectionGap = 18.0;

  static const double radiusSm = 10.0;
  static const double radiusMd = 16.0;
  static const double radiusLg = 20.0;
  static const double radiusPill = 999.0;

  static const List<BoxShadow> softShadowList = [
    BoxShadow(
      color: Color(0x0F1E2A42),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: backgroundLight,
    primaryColor: primaryGold,
    primarySwatch: _primaryGoldSwatch,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGold,
      brightness: Brightness.light,
      primary: primaryGold,
      secondary: accentGold,
      surface: surfaceLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundLight,
      foregroundColor: textLight,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: surfaceLight,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldBaseFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: primaryGold, width: 1.8),
      ),
      hintStyle: const TextStyle(color: textLightSecondary),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    primaryColor: primaryGold,
    primarySwatch: _primaryGoldSwatch,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGold,
      brightness: Brightness.dark,
      primary: primaryGold,
      secondary: accentGold,
      surface: surfaceDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundDark,
      foregroundColor: textDark,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: surfaceDark,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: backgroundDarkAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        borderSide: const BorderSide(color: primaryGold, width: 1.8),
      ),
      hintStyle: const TextStyle(color: textDarkSecondary),
    ),
  );

  static const MaterialColor _primaryGoldSwatch = MaterialColor(
    0xFFF5B642,
    <int, Color>{
      50: Color(0xFFFFF7E8),
      100: Color(0xFFFFE9BE),
      200: Color(0xFFFFD98B),
      300: Color(0xFFF7C86F),
      400: Color(0xFFF5B642),
      500: Color(0xFFEDA92B),
      600: Color(0xFFE39A17),
      700: Color(0xFFB7780E),
      800: Color(0xFF895B0E),
      900: Color(0xFF69420F),
    },
  );

  static Color pageBackground(bool isDark) => isDark ? backgroundDark : backgroundLight;
  static Color panelColor(bool isDark) => isDark ? panelBaseDark : panelBaseLight;
  static Color panelBorder(bool isDark) => isDark ? panelBorderDark : panelBorderLight;
  static Color textPrimary(bool isDark) => isDark ? textDark : textLight;
  static Color textSecondary(bool isDark) => isDark ? textDarkSecondary : textLightSecondary;
  static Color fieldFill(bool isDark) => isDark ? backgroundDarkAlt : fieldBaseFill;
  static Color divider(bool isDark) => isDark ? dividerDark : dividerLight;
  static Color mutedPanel(bool isDark) => isDark ? backgroundDarkAlt : mutedPanelLight;
  static Color softShadowColor(bool isDark) => isDark ? const Color(0x33000000) : const Color(0xFFEADFC8);
  static Color searchInputDecorationColor(bool isDark) => isDark ? backgroundDarkAlt : searchInputBase;
  static Color subtitleDark(bool isDark) => isDark ? textDarkSecondary : textLightSecondary;
  static Color subtitleLight([bool isDark = false]) => isDark ? textDarkSecondary : subtitleLightColor;
  static double adminPagePaddingValue(bool isDark) => adminPagePadding;
  static double adminPagePaddingCompactValue(bool isDark) => adminPagePaddingCompact;

  static BoxDecoration adminPanelDecoration(bool isDark) => BoxDecoration(
        color: panelColor(isDark),
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: panelBorder(isDark)),
        boxShadow: const [BoxShadow(color: Color(0x0F1E2A42), blurRadius: 16, offset: Offset(0, 8))],
      );

  static List<BoxShadow> softShadow([bool isDark = false]) => [
        BoxShadow(
          color: softShadowColor(isDark),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  static Color tableHeader([bool isDark = false]) =>
      isDark ? backgroundDarkAlt : tableHeaderBase;

  static BoxDecoration fieldDecoration(bool isDark) => BoxDecoration(
        color: fieldFill(isDark),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: panelBorder(isDark)),
      );

  static InputDecoration searchInputDecoration(bool isDark, {String? hintText}) => InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: searchInputDecorationColor(isDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: panelBorder(isDark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: panelBorder(isDark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: const BorderSide(color: primaryGold, width: 1.8),
        ),
      );

  static BoxDecoration emptyStateDecoration(bool isDark) => BoxDecoration(
        color: isDark ? backgroundDarkAlt : mutedPanelLight,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: panelBorder(isDark)),
      );
}
