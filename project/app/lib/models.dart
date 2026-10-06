/// Models mirroring the backend GET /scan/{id} response.
class CrackDetection {
  final String id;
  final List<double> bbox; // [x1,y1,x2,y2] pixels
  final List<List<double>> polygon; // [[x,y],...] pixels
  final double confidence;
  final double areaRatio;
  final double lengthPx;
  final double widthPx;
  final String? growthStatus; // new | grown | stable (only on re-scan)
  final String crackType; // structural | paint
  /// null = to do; measured | skipped | not_crack
  final String? status;
  /// This crack's graded result once measured (see backend crack_measurement).
  final Map<String, dynamic>? measurement;

  CrackDetection({
    this.id = '',
    required this.bbox,
    required this.polygon,
    required this.confidence,
    required this.areaRatio,
    this.lengthPx = 0,
    this.widthPx = 0,
    this.growthStatus,
    this.crackType = 'structural',
    this.status,
    this.measurement,
  });

  bool get isDismissed => status == 'not_crack';
  bool get isSkipped => status == 'skipped';
  bool get isTodo => status == null;
  bool get isMeasured => status == 'measured' && measurement != null;

  double? _num(String k) => (measurement?[k] as num?)?.toDouble();
  double? get lengthCm => _num('length_cm');
  double? get mmPerPx => _num('mm_per_px');
  bool get uncertain => measurement?['uncertain'] as bool? ?? false;
  bool get resolved => measurement?['resolved'] as bool? ?? true;
  String? get riskLevel => measurement?['risk_level'] as String?;

  /// "0.42 mm" or "0.42–2.10 mm" when the photo and the mask disagree.
  String? get widthSummary {
    final w = _num('width_mm');
    if (!isMeasured || w == null) return null;
    final upper = _num('width_mm_upper');
    return uncertain && upper != null && upper > w
        ? '${w.toStringAsFixed(2)}–${upper.toStringAsFixed(2)} mm'
        : '${w.toStringAsFixed(2)} mm';
  }

  /// "JBDPA II · Moderate", "BRE 251 cat. 2 · Aesthetic", or "Cosmetic".
  String? get gradeSummary {
    if (!isMeasured) return null;
    final std = measurement!['standard'] as String?;
    if (std == null) return 'Cosmetic';
    return '${std == 'BRE251' ? 'BRE 251 cat.' : 'JBDPA'} '
        '${measurement!['damage_class']} · ${measurement!['rating']}';
  }

  factory CrackDetection.fromJson(Map<String, dynamic> j) => CrackDetection(
        id: j['id'] as String? ?? '',
        bbox: (j['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
        polygon: (j['polygon'] as List)
            .map((p) =>
                (p as List).map((e) => (e as num).toDouble()).toList())
            .toList(),
        confidence: (j['confidence'] as num).toDouble(),
        areaRatio: (j['area_ratio'] as num).toDouble(),
        lengthPx: (j['length_px'] as num?)?.toDouble() ?? 0,
        widthPx: (j['width_px'] as num?)?.toDouble() ?? 0,
        growthStatus: j['growth_status'] as String?,
        crackType: j['crack_type'] as String? ?? 'structural',
        status: j['status'] as String?,
        measurement: j['measurement'] as Map<String, dynamic>?,
      );
}

class ScanResult {
  final String id;
  final String status; // pending | done | error
  final String? componentType; // what the user picked before capture
  final String? riskLevel; // LOW | MEDIUM | HIGH
  // preliminary = pixel-area heuristic; measured = AR width graded by standard
  final String riskSource;
  final double? crackWidthMm;
  final String? damageStandard; // JBDPA | BRE251
  final String? damageClass; // JBDPA I-IV or BRE 251 category 0-5
  final String? damageRating; // e.g. Moderate, Serviceability
  final double? residualCapacityPct; // JBDPA only
  final int? crackCount;
  final double? crackAreaRatio;
  final String? error;
  final String? imageUrl;
  final DateTime? createdAt;
  final List<CrackDetection> detections;

  ScanResult({
    required this.id,
    required this.status,
    this.componentType,
    this.riskLevel,
    this.riskSource = 'preliminary',
    this.crackWidthMm,
    this.damageStandard,
    this.damageClass,
    this.damageRating,
    this.residualCapacityPct,
    this.crackCount,
    this.crackAreaRatio,
    this.error,
    this.imageUrl,
    this.createdAt,
    this.detections = const [],
  });

  bool get isDone  => status == 'done';
  bool get isError => status == 'error';
  bool get isMeasured => riskSource == 'measured';

  /// Detection indices, largest crack first. Crack number = position + 1,
  /// over every detection, so dismissing one never renumbers the rest.
  List<int> get bySize => List.generate(detections.length, (i) => i)
    ..sort((a, b) => detections[b].areaRatio.compareTo(detections[a].areaRatio));
  int numberOf(int i) => bySize.indexOf(i) + 1;
  List<int> get activeBySize =>
      bySize.where((i) => !detections[i].isDismissed).toList();
  int? get nextToMeasure {
    for (final i in activeBySize) {
      if (detections[i].isTodo) return i;
    }
    return null;
  }

  int get measuredCount => detections.where((d) => d.isMeasured).length;

  /// The crack the wall grade comes from (backend summarize: risk, then width).
  CrackDetection? get worstMeasured {
    const rank = {'LOW': 0, 'MEDIUM': 1, 'HIGH': 2};
    CrackDetection? worst;
    for (final d in detections.where((d) => d.isMeasured)) {
      final r = rank[d.riskLevel] ?? 0;
      final wr = worst == null ? -1 : rank[worst.riskLevel] ?? 0;
      if (worst == null ||
          r > wr ||
          (r == wr &&
              (d.measurement!['width_mm'] as num) >
                  (worst.measurement!['width_mm'] as num))) {
        worst = d;
      }
    }
    return worst;
  }

  /// Median mm-per-pixel over the measured cracks: the photo's real scale,
  /// for the true-size AR projection. Null until something is measured.
  double? get trueSizeMmPerPx {
    final v = detections.map((d) => d.mmPerPx).whereType<double>().toList()..sort();
    return v.isEmpty ? null : v[v.length ~/ 2];
  }

  bool get widthUncertain => worstMeasured?.uncertain ?? false;

  /// Advice when the worst crack is finer than the photo can resolve.
  String? get resolutionHint {
    final w = worstMeasured;
    if (w == null || w.resolved) return null;
    final mmpp = w.mmPerPx;
    return mmpp == null
        ? 'Crack is finer than this photo can resolve — re-shoot closer.'
        : 'Crack is finer than this photo can resolve '
            '(1 pixel ≈ ${mmpp.toStringAsFixed(2)} mm). Width shown is an upper '
            'bound — re-shoot closer or zoom in for a real measurement.';
  }

  /// Worst crack's width; legacy scans (one length for the whole photo) fall
  /// back to the stored scan width.
  String? get widthSummary =>
      worstMeasured?.widthSummary ??
      (crackWidthMm == null ? null : '${crackWidthMm!.toStringAsFixed(2)} mm');

  /// "JBDPA class II · Moderate · 60% capacity" — null until measured.
  String? get gradeSummary => !isMeasured
      ? null
      : [
          if (damageStandard != null)
            '${damageStandard == 'BRE251' ? 'BRE 251 cat.' : 'JBDPA class'} $damageClass',
          if (damageRating != null) damageRating!,
          if (residualCapacityPct != null)
            '${residualCapacityPct!.toStringAsFixed(0)}% capacity',
        ].join(' · ');

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        id: j['id'] as String,
        status: j['status'] as String,
        componentType: j['component_type'] as String?,
        riskLevel:     j['risk_level'] as String?,
        riskSource:    j['risk_source'] as String? ?? 'preliminary',
        crackWidthMm:  (j['crack_width_mm'] as num?)?.toDouble(),
        damageStandard: j['damage_standard'] as String?,
        damageClass:   j['damage_class'] as String?,
        damageRating:  j['damage_rating'] as String?,
        residualCapacityPct: (j['residual_capacity_pct'] as num?)?.toDouble(),
        crackCount:    j['crack_count'] as int?,
        crackAreaRatio:(j['crack_area_ratio'] as num?)?.toDouble(),
        error:         j['error'] as String?,
        imageUrl:      j['image_url'] as String?,
        createdAt:     j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
        detections: (j['detections'] as List? ?? [])
            .map((d) => CrackDetection.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
