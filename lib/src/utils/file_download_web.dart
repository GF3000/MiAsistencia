import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadTextFile({required String fileName, required String content}) {
  _download(
    fileName: fileName,
    blob: web.Blob(
      <web.BlobPart>[content.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    ),
  );
}

void downloadBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  _download(
    fileName: fileName,
    blob: web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    ),
  );
}

void _download({required String fileName, required web.Blob blob}) {
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  try {
    web.document.body?.append(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
