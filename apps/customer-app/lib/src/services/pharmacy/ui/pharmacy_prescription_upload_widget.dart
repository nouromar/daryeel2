import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/runtime/daryeel_runtime_session.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Scaffold-less uploader UI for embedding in schema screens.
final class PharmacyPrescriptionUploadWidget extends StatefulWidget {
  const PharmacyPrescriptionUploadWidget({super.key});

  @override
  State<PharmacyPrescriptionUploadWidget> createState() =>
      _PharmacyPrescriptionUploadWidgetState();
}

class _PharmacyPrescriptionUploadWidgetState
    extends State<PharmacyPrescriptionUploadWidget> {
  final _picker = ImagePicker();

  _PendingUpload? _selected;
  bool _uploading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // `ForEach(itemsPath: $state.pharmacy.cart.prescriptionUploads)` expects a
    // list. Because we persist `pharmacy.cart`, older app versions (or manual
    // state edits) may have stored a non-list at this path, which causes the
    // schema renderer to throw `items-not-list`.
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) return;

    final existing = store.getValue('pharmacy.cart.prescriptionUploads');
    if (existing is! List) {
      store.setValue('pharmacy.cart.prescriptionUploads', <Object?>[]);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_uploading) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (file == null) return;

      setState(() {
        _selected = _PendingUpload.fromXFile(file);
      });

      await _upload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to pick image: $e')));
    }
  }

  Future<void> _pickFile() async {
    if (_uploading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const <String>[
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'heic',
          'webp',
        ],
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      final f = result.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read selected file')),
        );
        return;
      }

      setState(() {
        _selected = _PendingUpload.fromBytes(bytes, filename: f.name);
      });

      await _upload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to pick file: $e')));
    }
  }

  Uri? _buildUploadUri(DaryeelRuntimeSession session) {
    final base = session.apiBaseUrl.trim();
    if (base.isEmpty) return null;

    final uri = Uri.parse(base);
    final path = uri.path.endsWith('/')
        ? '${uri.path}v1/pharmacy/prescriptions/upload'
        : '${uri.path}/v1/pharmacy/prescriptions/upload';

    return uri.replace(path: path);
  }

  Map<String, String> _buildHeaders(DaryeelRuntimeSession session) {
    Map<String, String> extra;
    try {
      extra =
          session.requestHeadersProvider?.call() ?? const <String, String>{};
    } catch (_) {
      extra = const <String, String>{};
    }

    // MultipartRequest sets its own Content-Type boundary.
    return extra;
  }

  Future<void> _upload() async {
    if (_uploading) return;

    final selected = _selected;
    if (selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick a file first')));
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload is not supported on web yet')),
      );
      return;
    }

    final session = RuntimeSessionScope.of(context);
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('State store not available')),
      );
      return;
    }

    // Ensure the list exists even if the schema didn't set defaults.
    final existingUploads = store.getValue('pharmacy.cart.prescriptionUploads');
    if (existingUploads is! List) {
      store.setValue('pharmacy.cart.prescriptionUploads', <Object?>[]);
    }

    final uri = _buildUploadUri(session);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API base URL is not configured')),
      );
      return;
    }

    setState(() => _uploading = true);

    try {
      final bytes = await selected.readAsBytes();
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_buildHeaders(session));
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: selected.filename,
        ),
      );

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final shortBody = body.length > 300
            ? '${body.substring(0, 300)}…'
            : body;
        throw StateError('HTTP ${streamed.statusCode}: $shortBody');
      }

      final decoded = jsonDecode(body);
      final idRaw = (decoded is Map) ? decoded['id'] : null;
      final id = (idRaw is String) ? idRaw.trim() : '';
      if (id.isEmpty) {
        throw StateError('Upload succeeded but no id returned');
      }

      // Back-compat: keep the single id key in sync with the newest upload.
      store.setValue('pharmacy.cart.prescriptionUploadId', id);

      final filenameRaw = (decoded is Map) ? decoded['filename'] : null;
      final filename = (filenameRaw is String && filenameRaw.trim().isNotEmpty)
          ? filenameRaw.trim()
          : selected.filename;

      final contentTypeRaw = (decoded is Map) ? decoded['content_type'] : null;
      final contentType =
          (contentTypeRaw is String && contentTypeRaw.trim().isNotEmpty)
          ? contentTypeRaw.trim()
          : null;

      final sizeRaw = (decoded is Map) ? decoded['size_bytes'] : null;
      final sizeBytes = (sizeRaw is num) ? sizeRaw.toInt() : null;

      final uploadEntry = <String, Object?>{'id': id, 'filename': filename};
      if (contentType != null) {
        uploadEntry['contentType'] = contentType;
      }
      if (sizeBytes != null) {
        uploadEntry['sizeBytes'] = sizeBytes;
      }

      store.appendValue('pharmacy.cart.prescriptionUploads', uploadEntry);

      if (mounted) {
        setState(() => _selected = null);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prescription attached')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const Text('Choose how you want to attach your prescription.'),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _uploading
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  child: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _uploading
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  child: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _uploading ? null : _pickFile,
            child: const Text('File'),
          ),
        ],
      ),
    );
  }
}

final class _PendingUpload {
  const _PendingUpload._({
    required this.filename,
    required this.bytes,
    required this.file,
  });

  final String filename;
  final Uint8List? bytes;
  final XFile? file;

  static _PendingUpload fromXFile(XFile file) {
    final filename = file.name.trim().isEmpty ? 'upload' : file.name.trim();
    return _PendingUpload._(filename: filename, bytes: null, file: file);
  }

  static _PendingUpload fromBytes(Uint8List bytes, {required String filename}) {
    final safe = filename.trim().isEmpty ? 'upload' : filename.trim();
    return _PendingUpload._(filename: safe, bytes: bytes, file: null);
  }

  Future<Uint8List> readAsBytes() async {
    final b = bytes;
    if (b != null) return b;
    final f = file;
    if (f == null) {
      return Uint8List(0);
    }
    final out = await f.readAsBytes();
    return Uint8List.fromList(out);
  }
}
