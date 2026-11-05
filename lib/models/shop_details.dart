// The shop's details printed at the top and bottom of every Tax Invoice.
// Saved inside the pharmacy document as a 'shop' map; only the owner can edit.
class ShopDetails {
  String address;
  String phone;
  String gstin;
  String drugLicence; // Drug licence numbers, e.g. "20B: TS/HYD/2024/1234, 21B: ..."
  String upiId;
  String terms; // one condition per line

  ShopDetails({
    this.address = '',
    this.phone = '',
    this.gstin = '',
    this.drugLicence = '',
    this.upiId = '',
    this.terms = defaultTerms,
  });

  static const defaultTerms = 'Goods once sold will not be taken back.\n'
      'Please check medicines and expiry dates before leaving the counter.\n'
      'Subject to Hyderabad jurisdiction only.';

  bool get hasUpi => upiId.isNotEmpty;

  List<String> get termLines =>
      terms.split('\n').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  Map<String, dynamic> toMap() => {
        'address': address,
        'phone': phone,
        'gstin': gstin,
        'drugLicence': drugLicence,
        'upiId': upiId,
        'terms': terms,
      };

  factory ShopDetails.fromMap(Map<String, dynamic>? map) {
    final m = map ?? {};
    String s(String key) => (m[key] as String?) ?? '';
    return ShopDetails(
      address: s('address'),
      phone: s('phone'),
      gstin: s('gstin'),
      drugLicence: s('drugLicence'),
      upiId: s('upiId'),
      terms: m['terms'] == null ? defaultTerms : s('terms'),
    );
  }
}
