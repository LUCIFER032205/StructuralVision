/// Models mirroring the backend GET /scan/{id} response.
class CrackDetection {
  final List<double> bbox; // [x1,y1,x2,y2] pixels
  final List<List<double>> polygon; // [[x,y],...] pixels
  final double confidence;
  final double areaRatio;
  final double lengthPx;
  final double widthPx;
  final String? growthStatus; // new | grown | stable (only on re-scan)
  final String crackType; // structural | paint

  CrackDetection({
    required this.bbox,
    required this.polygon,
    required this.confidence,
    required this.areaRatio,
    this.lengthPx = 0,
    this.widthPx = 0,
    this.growthStatus,
    this.crackType = 'structural',
  });

  factory CrackDetection.fromJson(Map<String, dynamic> j) => CrackDetection(
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
      );
}

class ScanResult {
  final String id;
  final String status; // pending | done | error
  final String? componentType;
  final double? componentConfidence;
  final String? riskLevel; // LOW | MEDIUM | HIGH
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
    this.componentConfidence,
    this.riskLevel,
    this.crackCount,
    this.crackAreaRatio,
    this.error,
    this.imageUrl,
    this.createdAt,
    this.detections = const [],
  });

  bool get isDone => status == 'done';
  bool get isError => status == 'error';

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        id: j['id'] as String,
        status: j['status'] as String,
        componentType: j['component_type'] as String?,
        componentConfidence: (j['component_confidence'] as num?)?.toDouble(),
        riskLevel: j['risk_level'] as String?,
        crackCount: j['crack_count'] as int?,
        crackAreaRatio: (j['crack_area_ratio'] as num?)?.toDouble(),
        error: j['error'] as String?,
        imageUrl: j['image_url'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
        detections: (j['detections'] as List? ?? [])
            .map((d) => CrackDetection.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
