import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class WebviewPage extends StatefulWidget {
  final String url;
  final String? title;
  const WebviewPage({super.key, required this.url, this.title});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();

    // Simple controller (v4 API)
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
          onPageStarted: (_) {},
          onPageFinished: (_) => setState(() => _progress = 1),
          onWebResourceError: (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Web error: ${e.description}')),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Android-only tweaks (optional)
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return false; // stay on this page
    }
    return true; // pop the page
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Web'),
        actions: [
          if (_progress < 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, value: _progress),
              ),
            ),
        ],
      ),
      body: WillPopScope(
        onWillPop: _onWillPop,
        child: SafeArea(child: WebViewWidget(controller: _controller)),
      ),
    );
  }
}
