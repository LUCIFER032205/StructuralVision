import 'package:flutter/material.dart';

import '../building_catalog.dart';
import '../theme.dart';

/// Shows a modal bottom sheet listing the fetched building types and returns
/// the tapped [BuildingType], or null if the user dismissed without picking.
///
/// Usage:
///   final building = await BuildingSelectSheet.show(context, buildings: list);
///   if (building == null) return; // user cancelled
class BuildingSelectSheet {
  BuildingSelectSheet._();

  /// [selectedId] ticks the building already in use, if any.
  static Future<BuildingType?> show(BuildContext context,
      {required List<BuildingType> buildings, String? selectedId}) {
    return showModalBottomSheet<BuildingType>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _SheetBody(buildings: buildings, selectedId: selectedId),
    );
  }
}

class _SheetBody extends StatelessWidget {
  final List<BuildingType> buildings;
  final String? selectedId;
  const _SheetBody({required this.buildings, this.selectedId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
              Text('Choose a building', style: AppTextStyles.titleLg),
              const SizedBox(height: 4),
              Text(
                'Placed at true size on-site, or as a miniature on any surface',
                style: AppTextStyles.bodySm,
              ),
              const SizedBox(height: 20),
              for (final b in buildings) ...[
                _BuildingRow(b, selected: b.id == selectedId),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildingRow extends StatelessWidget {
  final BuildingType building;
  final bool selected;
  const _BuildingRow(this.building, {this.selected = false});

  @override
  Widget build(BuildContext context) {
    final hint = building.isCustom
        ? 'Your model · ${building.sizeM.toStringAsFixed(0)} m'
        : '${building.footprint} · ${building.storeys} storeys · '
            '${building.sizeM.toStringAsFixed(0)} m';
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: () => Navigator.of(context).pop(building),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
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
                child: Icon(
                    building.isCustom
                        ? Icons.view_in_ar_outlined
                        : Icons.apartment_outlined,
                    color: AppColors.accent,
                    size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name,
                        style: AppTextStyles.titleMd, maxLines: 1),
                    Text(hint, style: AppTextStyles.bodySm, maxLines: 1),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded,
                    color: AppColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
