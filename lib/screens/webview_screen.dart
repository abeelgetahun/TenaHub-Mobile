import 'package:google_fonts/google_fonts.dart';
import 'package:tena_hub/widgets/error_screen.dart';
import 'package:tena_hub/widgets/loading_screen.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:developer' as developer;

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  double _loadingProgress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = 'https://medihelp-frontend-ntx5.vercel.app';
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    developer.log('WebViewScreen initState called');
    _initializeWebView();
    _checkConnectivity();
  }

  void _initializeWebView() {
    developer.log('Initializing WebView controller...');

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      developer.log('Using iOS WebKit WebView');
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      developer.log('Using Android WebView');
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            developer.log('Loading progress: $progress%');
            setState(() {
              _loadingProgress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            developer.log('Page started loading: $url');
            setState(() {
              _isLoading = true;
              _hasError = false;
              _currentUrl = url;
            });
          },
          onPageFinished: (String url) {
            developer.log('Page finished loading: $url');
            setState(() {
              _isLoading = false;
            });
            _updateNavigationButtons();
            _injectLocationHandler();
            _injectFileUploadHandler();
          },
          onWebResourceError: (WebResourceError error) {
            developer.log(
              'Web resource error: ${error.description}',
              error: error,
            );
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = error.description;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            developer.log('Navigation request to: ${request.url}');
            if (request.url.startsWith(
                  'https://medihelp-frontend-ntx5.vercel.app',
                ) ||
                request.url.startsWith(
                  'https://medihelp-frontend-ntx5.vercel.app',
                )) {
              return NavigationDecision.navigate;
            }
            _launchExternalUrl(request.url);
            return NavigationDecision.prevent;
          },
          // onPermissionRequest: (PermissionRequest request) {
          //   developer.log('Permission request received for: ${request.types}');
          //   return Future.value(PermissionResponse(
          //     resources: request.types,
          //     action: PermissionResponseAction.grant,
          //   ));
          // },
        ),
      );

    // Platform specific configuration
    if (_controller.platform is AndroidWebViewController) {
      developer.log('Configuring Android WebView specific settings');
      AndroidWebViewController.enableDebugging(true);
      final androidController =
          _controller.platform as AndroidWebViewController;

      androidController
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setOnShowFileSelector((params) async {
          developer.log(
            'File selector requested with params: ${params.acceptTypes}, mode: ${params.mode}',
          );
          return await _handleFilePicker(params);
        })
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            developer.log(
              'WebView requested geolocation permission for origin: ${request.origin}',
            );
            final permission = await _handleLocationPermission();
            developer.log('User responded with permission: $permission');
            return GeolocationPermissionsResponse(
              allow: permission,
              retain: true,
            );
          },
        );
    } else if (_controller.platform is WebKitWebViewController) {
      final webKitController = _controller.platform as WebKitWebViewController;
      // iOS-specific configurations can be added here
    }

    developer.log('Loading initial URL: $_currentUrl');
    _controller.loadRequest(Uri.parse(_currentUrl));
  }

  Future<List<String>> _handleFilePicker(FileSelectorParams params) async {
    developer.log(
      'Handling file picker with accept types: ${params.acceptTypes}, mode: ${params.mode}',
    );

    try {
      final acceptsImages = params.acceptTypes.any(
        (type) => type.contains('image') || type == '*' || type.isEmpty,
      );
      final allowsMultiple = params.mode == FileSelectorMode.openMultiple;

      if (acceptsImages) {
        final source = await _showImageSourceDialog();
        if (source == null) return [];

        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          developer.log('Image picked: ${pickedFile.path}');

          if (Platform.isAndroid) {
            try {
              // Copy the picked file to a location accessible by FileProvider
              final cacheDir = await getTemporaryDirectory();
              final fileName = pickedFile.name;
              final newFile = await File(
                '${cacheDir.path}/$fileName',
              ).writeAsBytes(await pickedFile.readAsBytes());

              // Generate a content:// URI using FileProvider
              final result = await _controller.runJavaScriptReturningResult('''
              (function() {
                const input = document.activeElement;
                if (input && input.type === 'file') {
                  return input.id || 'active-file-input';
                }
                // Try to find the last clicked file input
                const inputs = document.querySelectorAll('input[type="file"]');
                for (let i = 0; i < inputs.length; i++) {
                  if (document.activeElement === inputs[i]) {
                    return inputs[i].id || 'found-file-input-' + i;
                  }
                }
                return null;
              })()
            ''');

              // Create a content:// URI via the FileProvider
              final contentUri = Uri.parse(
                'content://com.example.tena_hub.fileprovider/cached_files/${fileName}',
              );
              developer.log('Content URI for WebView: $contentUri');

              // Return the content URI that WebView can access
              return [contentUri.toString()];
            } catch (e) {
              developer.log('Error creating content URI: $e');
              _showErrorDialog('Failed to prepare image for upload: $e');
              return [];
            }
          }
          // For iOS and other platforms, direct path is usually fine
          return [pickedFile.path];
        }
      } else {
        // Handle general file requests with FilePicker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: allowsMultiple,
        );

        if (result != null && result.files.isNotEmpty) {
          final paths = <String>[];
          for (final file in result.files) {
            if (file.path != null) {
              if (Platform.isAndroid) {
                // For Android, we need to convert to content:// URIs for non-image files too
                final fileName = file.name;
                final tempFile = File(file.path!);
                final cacheDir = await getTemporaryDirectory();
                final newFile = await File(
                  '${cacheDir.path}/$fileName',
                ).writeAsBytes(await tempFile.readAsBytes());

                // Generate content:// URI
                final contentUri = Uri.parse(
                  'content://com.example.tena_hub.fileprovider/cached_files/${fileName}',
                );
                paths.add(contentUri.toString());
              } else {
                paths.add(file.path!);
              }
            }
          }
          developer.log('Files picked: $paths');
          return paths;
        }
      }
    } catch (e) {
      developer.log('File picker error: $e', error: e);
      _showErrorDialog('Failed to pick file: $e');
    }
    return [];
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: const Text('Choose how you want to add an image:'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              child: const Text('Gallery'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              child: const Text('Camera'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _handleCameraPermission() async {
    developer.log('Checking camera permission...');

    var status = await Permission.camera.status;
    developer.log('Camera permission status: $status');

    if (status.isDenied) {
      status = await Permission.camera.request();
      developer.log('Camera permission after request: $status');
    }

    if (status.isPermanentlyDenied) {
      _showPermissionDialog(
        'Camera access is required to take photos. Please enable it in app settings.',
      );
      return false;
    }

    return status.isGranted;
  }

  Future<bool> _handleMicrophonePermission() async {
    developer.log('Checking microphone permission...');

    var status = await Permission.microphone.status;
    developer.log('Microphone permission status: $status');

    if (status.isDenied) {
      status = await Permission.microphone.request();
      developer.log('Microphone permission after request: $status');
    }

    if (status.isPermanentlyDenied) {
      _showPermissionDialog(
        'Microphone access is required. Please enable it in app settings.',
      );
      return false;
    }

    return status.isGranted;
  }

  Future<bool> _handleLocationPermission() async {
    developer.log('Checking location permissions...');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    developer.log('Location services enabled: $serviceEnabled');
    if (!serviceEnabled) {
      developer.log('Location services disabled - showing dialog');
      _showLocationDialog(
        'Location services are disabled. Please enable them in settings.',
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    developer.log('Current location permission: $permission');

    if (permission == LocationPermission.denied) {
      developer.log('Requesting location permission...');
      permission = await Geolocator.requestPermission();
      developer.log('User responded with permission: $permission');

      if (permission == LocationPermission.denied) {
        developer.log('Permission denied - showing dialog');
        _showLocationDialog(
          'Location permission denied. Please allow location access.',
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      developer.log('Permission denied forever - showing dialog');
      _showLocationDialog(
        'Location permissions are permanently denied. Please enable them in app settings.',
      );
      return false;
    }

    developer.log('Location permission granted successfully');
    return true;
  }

  Future<void> _injectLocationHandler() async {
    developer.log('Injecting location handler JavaScript...');
    try {
      await _controller.runJavaScript('''
          console.log('[Flutter] Injecting location handler');

          if (navigator.geolocation) {
            console.log('[Flutter] Found geolocation API');

            const originalGetCurrentPosition = navigator.geolocation.getCurrentPosition.bind(navigator.geolocation);
            const originalWatchPosition = navigator.geolocation.watchPosition.bind(navigator.geolocation);

            navigator.geolocation.getCurrentPosition = function(success, error, options) {
              console.log('[Flutter] getCurrentPosition called');
              return originalGetCurrentPosition(
                function(position) {
                  console.log('[Flutter] Location success:', position);
                  success(position);
                },
                function(err) {
                  console.log('[Flutter] Location error:', err);
                  error && error(err);
                },
                options
              );
            };

            navigator.geolocation.watchPosition = function(success, error, options) {
              console.log('[Flutter] watchPosition called');
              return originalWatchPosition(
                function(position) {
                  console.log('[Flutter] Watch location success:', position);
                  success(position);
                },
                function(err) {
                  console.log('[Flutter] Watch location error:', err);
                  error && error(err);
                },
                options
              );
            };
          } else {
            console.log('[Flutter] No geolocation API found');
          }
        ''');
      developer.log('JavaScript injection completed successfully');
    } catch (e) {
      developer.log('JavaScript injection failed', error: e);
    }
  }

  Future<void> _injectFileToInput(String fileUri, String inputId) async {
    try {
      await _controller.runJavaScript('''
      (function() {
        console.log('[Flutter] Injecting file to input: ${fileUri}');
        const input = document.getElementById('${inputId}');
        if (input && input.type === 'file') {
          // Create a File object
          const file = new File([''], '${Uri.parse(fileUri).pathSegments.last}', { 
            type: 'image/jpeg' 
          });
          
          // Create a DataTransfer
          const dataTransfer = new DataTransfer();
          dataTransfer.items.add(file);
          
          // Set the files property
          input.files = dataTransfer.files;
          
          // Dispatch change event
          const event = new Event('change', { bubbles: true });
          input.dispatchEvent(event);
          
          console.log('[Flutter] File injected successfully');
          return true;
        } else {
          console.log('[Flutter] Could not find file input with id: ${inputId}');
          return false;
        }
      })();
    ''');
    } catch (e) {
      developer.log('Error injecting file to input: $e');
    }
  }

  Future<void> _injectFileUploadHandler() async {
    developer.log('Injecting file upload handler JavaScript...');
    try {
      await _controller.runJavaScript('''
      console.log('[Flutter] Injecting enhanced file upload handler');

      // Store references to active file inputs
      window.flutterFileInputs = {};
      
      // Monitor file input changes and clicks
      document.addEventListener('click', function(event) {
        if (event.target && event.target.type === 'file') {
          const input = event.target;
          const inputId = input.id || 'file-input-' + Math.random().toString(36).substr(2, 9);
          
          if (!input.id) {
            input.id = inputId;
          }
          
          console.log('[Flutter] File input clicked:', inputId);
          window.flutterFileInputs.lastClickedInput = input;
          window.flutterFileInputs[inputId] = input;
        }
      }, true);
      
      // Observe DOM changes to catch dynamically added file inputs
      const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          if (mutation.type === 'childList') {
            mutation.addedNodes.forEach(function(node) {
              if (node.querySelectorAll) {
                const fileInputs = node.querySelectorAll('input[type="file"]');
                fileInputs.forEach(function(input) {
                  if (!input.id) {
                    input.id = 'file-input-' + Math.random().toString(36).substr(2, 9);
                  }
                  console.log('[Flutter] New file input detected:', input.id);
                  window.flutterFileInputs[input.id] = input;
                });
              }
            });
          }
        });
      });
      
      // Start observing the document with the configured parameters
      observer.observe(document, { childList: true, subtree: true });
      
      // Initial scan for file inputs
      document.querySelectorAll('input[type="file"]').forEach(function(input) {
        if (!input.id) {
          input.id = 'file-input-' + Math.random().toString(36).substr(2, 9);
        }
        console.log('[Flutter] Existing file input found:', input.id);
        window.flutterFileInputs[input.id] = input;
      });
    ''');
      developer.log(
        'Enhanced file upload JavaScript injection completed successfully',
      );
    } catch (e) {
      developer.log('File upload JavaScript injection failed', error: e);
    }
  }

  Future<void> _checkConnectivity() async {
    developer.log('Checking network connectivity...');
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      developer.log('Connectivity result: $connectivityResult');
      if (connectivityResult == ConnectivityResult.none) {
        setState(() {
          _hasError = true;
          _errorMessage = 'No internet connection';
        });
      }
    } catch (e) {
      developer.log('Connectivity check failed', error: e);
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    developer.log('Launching external URL: $url');
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log('Failed to launch URL', error: e);
    }
  }

  Future<void> _updateNavigationButtons() async {
    developer.log('Updating navigation buttons...');
    try {
      final canGoBack = await _controller.canGoBack();
      final canGoForward = await _controller.canGoForward();
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
      developer.log('Can go back: $_canGoBack, Can go forward: $_canGoForward');
    } catch (e) {
      developer.log('Failed to update navigation buttons', error: e);
    }
  }

  void _showLocationDialog(String message) {
    developer.log('Showing location dialog: $message');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Access'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            if (message.contains('settings'))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('Settings'),
              ),
          ],
        );
      },
    );
  }

  void _showPermissionDialog(String message) {
    developer.log('Showing permission dialog: $message');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshPage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _controller.reload();
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.home),
                title: Text(
                  'Home',
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _controller.loadRequest(
                    Uri.parse('https://medihelp-frontend-ntx5.vercel.app'),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(
                  'Refresh',
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _refreshPage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: Text(
                  'About',
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAboutDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('About TenaHub'),
          titleTextStyle: GoogleFonts.josefinSans(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          content: Text(
            'MediHelp is a comprehensive AI-powered healthcare platform that democratizes access to medical information and connects patients with healthcare resources. We bridge the gap between initial health concerns and professional medical care through intelligent symptom checking, telemedicine, and educational resources.'
            ' This app provides easy access to the TenaHub website.',
            style: GoogleFonts.josefinSans(fontSize: 14, color: Colors.black87),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.lightBlueAccent,
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    developer.log('Building WebViewScreen');
    return Scaffold(
      appBar: AppBar(
        title: AnimatedPadding(
          padding: EdgeInsets.only(left: _canGoBack ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          child: Row(
            children: [
              Image.asset(
                'assets/app_icon.png',
                height: kToolbarHeight * 0.6,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8), // spacing between icon and title
              Text(
                'TenaHub',
                style: GoogleFonts.josefinSans(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        leading: _canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  developer.log('Back button pressed');
                  _controller.goBack();
                },
              )
            : null,
        actions: [
          if (_canGoForward)
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () {
                developer.log('Forward button pressed');
                _controller.goForward();
              },
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshPage),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMenu),
        ],
      ),

      body: SafeArea(
        child: _hasError
            ? ErrorScreen(
                message: _errorMessage,
                onRetry: () {
                  developer.log('Retry button pressed');
                  _refreshPage();
                },
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading) const LoadingScreen(),
                  if (_isLoading)
                    Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(
                        value: _loadingProgress,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     developer.log('FAB pressed - loading reports page');
      //     _controller.loadRequest(Uri.parse('https://fixmyaddis.com/reports'));
      //   },
      //   backgroundColor: const Color(0xFF298560),
      //   child: const Icon(Icons.add, color: Colors.white),
      // ),
      // floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}
