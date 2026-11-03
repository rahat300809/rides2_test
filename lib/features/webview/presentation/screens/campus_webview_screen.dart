import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

class CampusWebViewScreen extends StatefulWidget {
  final String title;
  final String initialUrl;

  const CampusWebViewScreen({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  @override
  State<CampusWebViewScreen> createState() => _CampusWebViewScreenState();
}

class _CampusWebViewScreenState extends State<CampusWebViewScreen> {
  WebViewController? _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  String _currentTitle = '';

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;

    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress;
                  _isLoading = progress < 100;
                });
              }
            },
            onPageStarted: (String url) {
              if (mounted) {
                setState(() => _isLoading = true);
              }
            },
            onPageFinished: (String url) async {
              if (mounted) {
                final pageTitle = await _controller?.getTitle();
                setState(() {
                  _isLoading = false;
                  if (pageTitle != null && pageTitle.isNotEmpty) {
                    _currentTitle = pageTitle;
                  }
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('WebView Error: ${error.description}');
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.initialUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            Row(
              children: [
                const Icon(Icons.lock, size: 12, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.initialUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_controller != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppColors.onSurface),
              onPressed: () async {
                if (await _controller!.canGoBack()) {
                  await _controller!.goBack();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.onSurface),
              onPressed: () => _controller!.reload(),
            ),
          ],
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress / 100,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : null,
      ),
      body: kIsWeb
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.open_in_new, size: 48, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Opening in browser...',
                    style: AppTypography.titleMd,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.initialUrl,
                    style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : WebViewWidget(controller: _controller!),
    );
  }
}
