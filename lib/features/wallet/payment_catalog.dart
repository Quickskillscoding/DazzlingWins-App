import '../../core/api.dart';

/// Field definition from the website's payment catalog (/api/app/catalog).
class PayField {
  PayField(this.key, this.label, this.placeholder, this.type, this.required);
  final String key;
  final String label;
  final String placeholder;
  final String type;
  final bool required;

  factory PayField.fromJson(Map<String, dynamic> j) => PayField(
        strOf(j['key']),
        strOf(j['label']),
        strOf(j['placeholder']),
        strOf(j['type'], 'text'),
        j['required'] == true,
      );
}

class CatalogEntry {
  CatalogEntry(this.slug, this.label, this.image, this.supportsQr, this.adminFields, this.proofFields, this.payoutFields);
  final String slug;
  final String label;
  final String image;
  final bool supportsQr;
  final List<PayField> adminFields;
  final List<PayField> proofFields;
  final List<PayField> payoutFields;

  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        strOf(j['slug']),
        strOf(j['label']),
        strOf(j['image']),
        j['supportsQr'] == true,
        listOf(j['adminFields']).map(PayField.fromJson).toList(),
        listOf(j['proofFields']).map(PayField.fromJson).toList(),
        listOf(j['payoutFields']).map(PayField.fromJson).toList(),
      );
}

class PaymentCatalog {
  PaymentCatalog._();
  static Map<String, CatalogEntry>? _cache;

  static Future<Map<String, CatalogEntry>> load() async {
    if (_cache != null) return _cache!;
    final d = await ApiClient.instance.get('/api/app/catalog', auth: false);
    _cache = {for (final e in listOf(d['methods']).map(CatalogEntry.fromJson)) e.slug: e};
    return _cache!;
  }
}
