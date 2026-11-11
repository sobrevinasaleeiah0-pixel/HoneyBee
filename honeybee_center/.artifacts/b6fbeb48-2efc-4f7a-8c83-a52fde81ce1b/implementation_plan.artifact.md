# Honeybee Center Admin Panel Theme & UI Refinement Plan

Refining the Honeybee Center Flutter Web admin panel to fully support robust Light and Dark modes matching the Kite Admin Dashboard visual design language while preserving all existing Firebase services, business logic, authentication roles, and navigation modules.

## User Review Required

> [!IMPORTANT]
> - **Theme Architecture**: We will ensure `ThemeNotifier` properly propagates theme changes (`ThemeMode.light` / `ThemeMode.dark`) to `MaterialApp` and across all admin pages.
> - **Hardcoded Color Clean-up**: Replacing hardcoded text colors (`Color(0xFF111111)`) and card backgrounds (`Colors.white`) in key admin pages (`DashboardPage`, `MainDashboardPage`, etc.) with theme-aware `Theme.of(context)` tokens so Dark Mode remains 100% readable and visually consistent.
> - **Global Search Bar**: Verifying and refining the global search bar in the top navigation header to search real Firebase data (orders, customers, products, production batches, suppliers) with clickable result dropdown.

## Open Questions

- None. All requirements align with maintaining existing Firebase architecture while polishing the Light/Dark mode visual design.

## Proposed Changes

### Theme & Global Styling
#### [MODIFY] [app_theme.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/core/theme/app_theme.dart)
- Ensure robust color scheme tokens for light and dark modes (surface, background, onSurface, primary, secondary, border).

### Main Dashboard & Layout
#### [MODIFY] [main_dashboard.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/main_dashboard.dart)
- Update `MainDashboardPage` and `_TopNavBar` to respect `Theme.of(context)` and `isDark` for sidebar, header background, search dropdown, text, and icons.
- Verify global search functionality across Firebase nodes.

### Core Admin Pages
#### [MODIFY] [dashboard_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/dashboard_page.dart)
- Replace hardcoded `Color(0xFF111111)` and `Colors.white` with theme-aware colors (`Theme.of(context).colorScheme.surface`, `Theme.of(context).colorScheme.onSurface`, etc.) to ensure flawless dark mode readability.

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure zero compilation or linter errors.

### Manual Verification
- Toggle between Light Mode and Dark Mode in the app header.
- Verify that sidebar, header, cards, tables, inputs, dialogs, and search dropdown update immediately and remain fully readable in both modes.
- Test the global search bar with real Firebase queries.
