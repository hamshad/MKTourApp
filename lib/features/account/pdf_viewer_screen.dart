import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    debugPrint('PdfViewerScreen: Loading PDF from asset: ${widget.assetPath}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SfPdfViewer.asset(
        widget.assetPath,
        key: _pdfViewerKey,
        onDocumentLoaded: (PdfDocumentLoadedDetails details) {
          debugPrint('PdfViewerScreen: PDF document loaded successfully.');
        },
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          debugPrint('PdfViewerScreen: PDF document load failed: ${details.error}');
          debugPrint('PdfViewerScreen: Failure description: ${details.description}');
        },
      ),
    );
  }
}
