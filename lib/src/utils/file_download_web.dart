import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadTextFile({required String fileName, required String content}) {
  final blob = web.Blob(
    <web.BlobPart>[content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
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
