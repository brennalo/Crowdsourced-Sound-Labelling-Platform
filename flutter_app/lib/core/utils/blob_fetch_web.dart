import 'dart:typed_data';
import 'dart:html' as html;

Future<Uint8List> fetchBlobBytes(String blobUrl) async {
  final response = await html.window.fetch(blobUrl);
  final buffer = await response.arrayBuffer();
  return (buffer as ByteBuffer).asUint8List();
}
