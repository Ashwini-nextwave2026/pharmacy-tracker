// Reading a bill photo uses Google ML Kit, which only runs in the
// Android (or iPhone) app. In Chrome a stub is used that just says so.
export 'bill_ocr_stub.dart' if (dart.library.io) 'bill_ocr_mlkit.dart';
