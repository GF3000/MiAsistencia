import 'dart:typed_data';

void downloadTextFile({required String fileName, required String content}) {
  throw UnsupportedError('File downloads are only available on web.');
}

void downloadBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError('File downloads are only available on web.');
}
