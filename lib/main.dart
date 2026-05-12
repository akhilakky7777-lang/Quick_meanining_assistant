import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(70, 70),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.setResizable(false);
      await windowManager.setHasShadow(false);
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick Meaning Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AssistantHome(),
    );
  }
}

class AssistantHome extends StatefulWidget {
  const AssistantHome({super.key});

  @override
  State<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantHomeState extends State<AssistantHome>
    with SingleTickerProviderStateMixin, WindowListener {
  final TextEditingController _controller = TextEditingController();
  String _result = '';
  String _inputType = '';
  bool _isLoading = false;
  bool _isExpanded = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Replace YOUR_GEMINI_API_KEY_HERE with your key from aistudio.google.com ──
  static const String _apiKey = 'AIzaSyAa3elhTaeSuqroVaHDknRINBwwt8xoFcg';
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  bool _isWord(String input) {
    final trimmed = input.trim();
    return trimmed.split(RegExp(r'\s+')).length == 1 && trimmed.isNotEmpty;
  }

  Future<void> _togglePanel() async {
    setState(() => _isExpanded = !_isExpanded);

    if (Platform.isMacOS || Platform.isWindows) {
      if (_isExpanded) {
        await windowManager.setSize(const Size(420, 560));
        await windowManager.setAlignment(Alignment.bottomRight);
        _animController.forward();
      } else {
        _animController.reverse();
        await Future.delayed(const Duration(milliseconds: 300));
        await windowManager.setSize(const Size(70, 70));
        await windowManager.setAlignment(Alignment.bottomRight);
        setState(() {
          _result = '';
          _inputType = '';
          _controller.clear();
        });
      }
    } else {
      if (_isExpanded) {
        _animController.forward();
      } else {
        _animController.reverse();
        setState(() {
          _result = '';
          _inputType = '';
          _controller.clear();
        });
      }
    }
  }

  Future<void> _getResult() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _result = '';
    });

    final isWord = _isWord(input);
    setState(() => _inputType = isWord ? '📖 Word Meaning' : '📝 Summary');

    final prompt = isWord
        ? '''You are a dictionary assistant. The user has entered a single word.
Respond with ONLY one word that best defines or is the closest synonym for: "$input"
Rules:
- One word only
- No punctuation
- No explanation
- No extra text'''
        : '''You are a summarization assistant. Summarize the following text while preserving the core meaning. Be concise and accurate. No extra commentary.

Text: "$input"''';

    try {
      final response = await http.post(
        Uri.parse('$_geminiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        setState(() {
          _result = text.trim();
          _isLoading = false;
        });
      } else {
        setState(() {
          _result = '⚠️ Error ${response.statusCode}: Could not fetch result.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _result = '⚠️ Network error. Please check your internet connection.';
        _isLoading = false;
      });
    }
  }

  void _copyResult() {
    if (_result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _result));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied!'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.deepPurpleAccent,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.addListener(this);
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isExpanded ? _buildFullPanel() : _buildBubble(),
    );
  }

  // ── Floating Bubble (collapsed state) ───────────────────────────────
  Widget _buildBubble() {
    return GestureDetector(
      onTap: _togglePanel,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF7B2FFF), Color(0xFF4A00E0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.6),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  // ── Full Panel (expanded state) ──────────────────────────────────────
  Widget _buildFullPanel() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0f0c29), Color(0xFF302b63), Color(0xFF24243e)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.deepPurpleAccent.withOpacity(0.15),
                  ),
                ),
              ),

              // Drag handle at top
              if (Platform.isMacOS || Platform.isWindows)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 30,
                  child: DragToMoveArea(
                    child: Container(
                      color: Colors.transparent,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.drag_handle,
                              color: Colors.white24, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),

              // Main content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.deepPurpleAccent,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Quick Meaning',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _togglePanel,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Input field
                      TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter a word or paragraph...',
                          hintStyle: const TextStyle(
                              color: Colors.white30, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Colors.white24),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.deepPurpleAccent,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _getResult,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bolt_rounded,
                                  color: Colors.white, size: 18),
                          label: Text(
                            _isLoading ? 'Thinking...' : 'Get Answer',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            disabledBackgroundColor:
                                Colors.deepPurpleAccent.withOpacity(0.4),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),

                      // Result box
                      if (_result.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Colors.deepPurpleAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.deepPurpleAccent
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _inputType,
                                      style: const TextStyle(
                                        color: Colors.deepPurpleAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _copyResult,
                                      child: const Icon(
                                        Icons.copy_rounded,
                                        color: Colors.white38,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _result,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}