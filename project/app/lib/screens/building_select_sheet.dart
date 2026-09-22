import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../building_catalog.dart';
import '../theme.dart';

/// Picks a .glb from device storage, copies it into the app documents
/// folder, asks the real-world size, and pops the sheet with the resulting
/// [BuildingType]. Leaves the sheet open (returns without popping) if the
/// user cancels the file picker, picks a non-.glb file, cancels the size
/// dialog, or the picker/copy step fails (disk full, permission, I/O —
/// shows a SnackBar and cleans up any partial copy).
Future<void> _importBuilding(BuildContext context) async {
  FilePickerResult? result;
  String? destPath;
  try {
    result = await FilePicker.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return; // picker cancelled

    if (!path.toLowerCase().endsWith('.glb')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only .glb files are supported')),
        );
      }
      return;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final millis = DateTime.now().millisecondsSinceEpoch;
    destPath = '${docsDir.path}/custom_$millis.glb';
    await File(path).copy(destPath);
  } catch (_) {
    if (destPath != null) {
      try {
        final leftover = File(destPath);
        if (await leftover.exists()) await leftover.delete();
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import the model — try again')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  final sizeM = await _askSizeM(context);
  if (sizeM == null) return; // size dialog cancelled

  if (!context.mounted) return;
  Navigator.of(context).pop(BuildingType(
    id: 'custom',
    name: result!.files.single.name,
    uri: Uri.file(destPath).toString(),
    sizeM: sizeM,
    isCustom: true,
  ));
}

/// Numeric-entry dialog for the real building's largest side, in metres.
/// Defaults to 10, accepts 1-300, returns null if cancelled.
Future<double?> _askSizeM(BuildContext context) {
  final controller = TextEditingController(text: '10');
  return showDialog<double>(
    context: context,
    builder: (dialogContext) {
      String? error;
      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('How big is the real building?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Largest side, metres',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value == null || value < 1 || value > 300) {
                  setState(() => error = 'Enter a value between 1 and 300');
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Import'),
            ),
          ],
        );
      });
    },
  );
}

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
              _ImportRow(onTap: () => _importBuilding(context)),
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

class _ImportRow extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
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
                child: const Icon(Icons.upload_file_outlined,
                    color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Import your own model (.glb)',
                    style: AppTextStyles.titleMd),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
