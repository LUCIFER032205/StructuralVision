import 'package:flutter/material.dart';

import '../theme.dart';

/// Data for each selectable structural component.
class _Component {
  final String value; // sent to backend as component_type
  final String label; // displayed to user
  final IconData icon;
  final String hint; // short hint shown under the label

  const _Component({
    required this.value,
    required this.label,
    required this.icon,
    required this.hint,
  });
}

const _components = [
  // Wall material decides the standard: brick -> BRE Digest 251, RC -> JBDPA.
  _Component(
    value: 'wall',
    label: 'Brick wall',
    icon: Icons.crop_landscape_outlined,
    hint: 'Masonry / block',
  ),
  _Component(
    value: 'rc_wall',
    label: 'RC wall',
    icon: Icons.view_agenda_outlined,
    hint: 'Concrete / shear wall',
  ),
  _Component(
    value: 'beam',
    label: 'Beam',
    icon: Icons.horizontal_rule_rounded,
    hint: 'Horizontal member',
  ),
  _Component(
    value: 'column',
    label: 'Column',
    icon: Icons.view_week_outlined,
    hint: 'Vertical member',
  ),
  _Component(
    value: 'slab',
    label: 'Slab',
    icon: Icons.layers_outlined,
    hint: 'Floor / deck',
  ),
  _Component(
    value: 'ceiling',
    label: 'Ceiling',
    icon: Icons.vertical_align_top_rounded,
    hint: 'Overhead surface',
  ),
];

/// Shows a modal bottom sheet and returns the selected component value,
/// or null if the user dismissed without selecting.
///
/// Usage:
///   final component = await ComponentSelectSheet.show(context);
///   if (component == null) return; // user cancelled
class ComponentSelectSheet {
  ComponentSelectSheet._();

  /// Display label for a component value ("rc_wall" -> "RC wall").
  static String labelFor(String? value) =>
      _components.where((c) => c.value == value).firstOrNull?.label ??
      value ??
      'Unknown';

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SheetBody(),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('What are you scanning?', style: AppTextStyles.titleLg),
            const SizedBox(height: 4),
            Text(
              'Frame the element so it fills the shot',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 20),
            // 2-column wrap grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _components.map((c) => _ComponentCard(c)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentCard extends StatelessWidget {
  final _Component component;
  const _ComponentCard(this.component);

  @override
  Widget build(BuildContext context) {
    // Each card takes roughly half the available width minus spacing
    final cardWidth = (MediaQuery.of(context).size.width - 20 * 2 - 12) / 2;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(component.value),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(component.icon, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(component.label, style: AppTextStyles.titleMd),
                  Text(component.hint, style: AppTextStyles.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
