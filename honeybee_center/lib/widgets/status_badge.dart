import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color fg;
    Color bg;
    Color border;

    if (status == 'In Stock' || status == 'Completed' || status == 'Paid' || status == 'Active' || status == 'Confirmed' || status == 'Ready for Production') {
      fg = AppTheme.success;
      bg = isDark ? AppTheme.badgeGreenBgDark : AppTheme.badgeGreenBgLight;
      border = isDark ? AppTheme.badgeGreenBorderDark : AppTheme.badgeGreenBorderLight;
    } else if (status == 'Out of Stock' || status == 'Cancelled' || status == 'Inactive' || status == 'Rejected') {
      fg = AppTheme.error;
      bg = isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight;
      border = isDark ? AppTheme.badgeRedBorderDark : AppTheme.badgeRedBorderLight;
    } else if (status == 'Low Stock' || status == 'Ready for Pickup' || status == 'Pending Verification' || status == 'In Progress' || status == 'Partially Completed') {
      fg = AppTheme.primaryGold;
      bg = isDark ? AppTheme.badgeGoldBgDark : AppTheme.badgeGoldBgLight;
      border = isDark ? AppTheme.badgeGoldBorderDark : AppTheme.badgeGoldBorderLight;
    } else if (status == 'Preparing' || status == 'Planned' || status == 'Pending') {
      fg = AppTheme.info;
      bg = isDark ? AppTheme.badgeBlueBgDark : AppTheme.badgeBlueBgLight;
      border = isDark ? AppTheme.badgeBlueBorderDark : AppTheme.badgeBlueBorderLight;
    } else {
      fg = isDark ? AppTheme.textDarkSecondary : AppTheme.textLightSecondary;
      bg = isDark ? AppTheme.backgroundDarkAlt : AppTheme.backgroundLightAlt;
      border = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: border),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          height: 1,
        ),
      ),
    );
  }
}
