import 'dart:io' show Directory, File, Platform;
import 'dart:convert' show latin1;
import 'dart:math' show Point;
import 'dart:typed_data' show Uint8List;
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'bill_scanner.dart';

// Android / iPhone: get the bill (camera photo, gallery photo or PDF),
// read its text with Google ML Kit ON THE PHONE (free, works offline),
// then rebuild the bill from the words (bill_scanner.dart).
bool get billScanSupported => Platform.isAndroid || Platform.isIOS;

enum BillSource { camera, gallery, pdf }

Future<ScannedBill?> scanBill(BillSource source) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    if (source == BillSource.pdf) return await _scanPdf(recognizer);

    final photo = await ImagePicker().pickImage(
      source: source == BillSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 3000, // sharp enough for small print, not too slow
      imageQuality: 95,
    );
    if (photo == null) return null; // cancelled
    return BillScanner.parse(await _read(recognizer, photo.path));
  } finally {
    await recognizer.close();
  }
}

// A PDF: turn each page into an image, read it, and stack the pages
// one under the other so a 2-page bill reads as one long page.
Future<ScannedBill?> _scanPdf(TextRecognizer recognizer) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (picked == null) return null; // cancelled
  final pdf = await picked.readAsBytes();

  // Many bills are saved as a sideways page with a "turn 90°" note
  // (/Rotate). The page image comes out sideways, and ML Kit then reads
  // only big print (a watermark), so the image is turned first.
  final rotate = RegExp(r'/Rotate\s+(-?\d+)').firstMatch(latin1.decode(pdf, allowInvalid: true));
  final hint = ((int.tryParse(rotate?.group(1) ?? '0') ?? 0) % 360 + 360) % 360;

  final words = <OcrWord>[];
  var offset = 0.0; // where the next page starts
  var page = 0;
  await for (final raster in Printing.raster(pdf, dpi: 250)) {
    page++;
    final image = img.Image.fromBytes(
      width: raster.width,
      height: raster.height,
      bytes: _onWhite(raster.pixels).buffer,
      numChannels: 3,
    );
    // the PDF's own turn first; if that reads badly, try the other ways
    var pageWords = <OcrWord>[];
    for (final turn in {hint, 0, 90, 270, 180}) {
      final tried = await _readImage(recognizer, image, turn, page);
      if (tried.length > pageWords.length) pageWords = tried;
      if (pageWords.length >= 40) break; // a real bill page: good enough
    }
    if (pageWords.isNotEmpty) {
      final top = pageWords.map((w) => w.top).reduce((a, b) => a < b ? a : b);
      final bottom = pageWords.map((w) => w.bottom).reduce((a, b) => a > b ? a : b);
      for (final w in pageWords) {
        words.add(OcrWord(w.text, w.left, w.top - top + offset, w.right, w.bottom - top + offset));
      }
      offset += bottom - top + 100;
    }
    if (page >= 5) break; // a purchase bill is never longer than this
  }
  return BillScanner.parse(words);
}

// The page comes out with a SEE-THROUGH background. A JPG has no
// see-through, so it would turn black and hide the black text (only the
// grey watermark showed). Put the page on white paper: RGBA -> RGB.
Uint8List _onWhite(Uint8List rgba) {
  final rgb = Uint8List(rgba.length ~/ 4 * 3);
  for (var i = 0, j = 0; i + 3 < rgba.length; i += 4, j += 3) {
    final a = rgba[i + 3];
    for (var k = 0; k < 3; k++) {
      rgb[j + k] = (rgba[i + k] * a + 255 * (255 - a)) ~/ 255;
    }
  }
  return rgb;
}

// Turn the page image clockwise by [turn] degrees, save it, let ML Kit read it
Future<List<OcrWord>> _readImage(
    TextRecognizer recognizer, img.Image image, int turn, int page) async {
  final turned = turn == 0 ? image : img.copyRotate(image, angle: turn);
  final file = File('${Directory.systemTemp.path}/bill_page_${page}_$turn.jpg');
  await file.writeAsBytes(img.encodeJpg(turned, quality: 92));
  try {
    return await _read(recognizer, file.path);
  } finally {
    await file.delete();
  }
}

// ML Kit's words, turned upright if the photo / page was sideways
Future<List<OcrWord>> _read(TextRecognizer recognizer, String path) async {
  final result = await recognizer.processImage(InputImage.fromFilePath(path));
  return uprightWords([
    for (final block in result.blocks)
      for (final line in block.lines)
        for (final e in line.elements)
          (
            text: e.text,
            corners: e.cornerPoints.isNotEmpty
                ? e.cornerPoints
                : <Point<num>>[
                    Point(e.boundingBox.left, e.boundingBox.top),
                    Point(e.boundingBox.right, e.boundingBox.top),
                    Point(e.boundingBox.right, e.boundingBox.bottom),
                    Point(e.boundingBox.left, e.boundingBox.bottom),
                  ],
          ),
  ]);
}
