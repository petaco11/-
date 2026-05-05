import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import 'dart:io';
import 'dart:async'; // タイマー用に追加
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:typed_data';

void main() => runApp(const CollageMemoApp());

// --- データ構造（変更なし） ---
class DrawingPoint {
  List<Offset> offsets;
  Color color;
  double width;
  DrawingPoint({
    required this.offsets,
    required this.color,
    required this.width,
  });
  factory DrawingPoint.fromJson(Map<String, dynamic> json) => DrawingPoint(
    offsets: (json['offsets'] as List)
        .map((o) => Offset(o['x'], o['y']))
        .toList(),
    color: Color(json['color']),
    width: json['width'],
  );
  Map<String, dynamic> toJson() => {
    'offsets': offsets.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
    'color': color.value,
    'width': width,
  };
}

class CollageImage {
  String imagePath;
  Offset position;
  double size;
  CollageImage({
    required this.imagePath,
    required this.position,
    this.size = 200.0,
  });
  factory CollageImage.fromJson(Map<String, dynamic> json) => CollageImage(
    imagePath: json['imagePath'],
    position: Offset(json['position_x'], json['position_y']),
    size: json['size'],
  );
  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'position_x': position.dx,
    'position_y': position.dy,
    'size': size,
  };
}

class CollageMemoApp extends StatefulWidget {
  const CollageMemoApp({super.key});
  @override
  State<CollageMemoApp> createState() => _CollageMemoAppState();
}

class _CollageMemoAppState extends State<CollageMemoApp> {
  bool _isDarkMode = false;
  void _toggleTheme() => setState(() => _isDarkMode = !_isDarkMode);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blue,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainScreen(onThemeToggle: _toggleTheme, isDarkMode: _isDarkMode),
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  const MainScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
  });
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _memoFileName = 'memo_data.json';
  final TextEditingController _titleController = TextEditingController();
  late quill.QuillController _quillController;
  final ImagePicker _picker = ImagePicker();

  List<CollageImage> _currentImages = [];
  List<DrawingPoint> _drawingPoints = [];
  bool _isPenMode = false;
  bool _isEraserMode = false;
  double _penWidth = 3.0;
  Color _penColor = Colors.red;

  Timer? _debounce; // 自動保存の遅延実行用

  @override
  void initState() {
    super.initState();
    _quillController = quill.QuillController.basic();

    // 1. データの読み込み
    _loadData();

    // 2. タイトル変更の監視
    _titleController.addListener(_onChanged);
    // 3. 本文変更の監視
    _quillController.addListener(_onChanged);
  }

  // 何か変更があった時に呼ばれる
  void _onChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // 1秒間操作が止まったら保存を実行（負荷軽減）
    _debounce = Timer(const Duration(seconds: 1), () {
      _saveData();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_memoFileName');
  }

  Future<void> _saveData() async {
    final String quillJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    final Map<String, dynamic> allData = {
      'title': _titleController.text,
      'quill_doc': quillJson,
      'images': _currentImages.map((img) => img.toJson()).toList(),
      'draws': _drawingPoints.map((pt) => pt.toJson()).toList(),
    };
    final file = await _localFile;
    await file.writeAsString(jsonEncode(allData));
    debugPrint("自動保存完了"); // コンソールで確認用
  }

  Future<void> _loadData() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return;
      final Map<String, dynamic> allData = jsonDecode(
        await file.readAsString(),
      );
      setState(() {
        _titleController.text = allData['title'] ?? '';
        if (allData['quill_doc'] != null) {
          _quillController = quill.QuillController(
            document: quill.Document.fromJson(jsonDecode(allData['quill_doc'])),
            selection: const TextSelection.collapsed(offset: 0),
          );
          // 読み込み後のエディタにもリスナーを再設定
          _quillController.addListener(_onChanged);
        }
        _currentImages = (allData['images'] as List)
            .map((img) => CollageImage.fromJson(img))
            .toList();
        _drawingPoints = (allData['draws'] as List)
            .map((pt) => DrawingPoint.fromJson(pt))
            .toList();
      });
    } catch (e) {
      debugPrint("ロードエラー: $e");
    }
  }

  // --- 操作系（setStateの後に_onChangedを呼ぶように修正） ---

  void _deleteImage(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _currentImages.removeAt(index));
              _onChanged(); // 保存
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(
        () => _currentImages.add(
          CollageImage(imagePath: image.path, position: const Offset(100, 100)),
        ),
      );
      _onChanged();
    }
  }

  void _performEraser(Offset localPosition) {
    setState(() {
      _drawingPoints.removeWhere(
        (point) => point.offsets.any(
          (offset) => (offset - localPosition).distance < 20.0,
        ),
      );
    });
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 200,
            color: widget.isDarkMode
                ? Colors.grey.shade900
                : Colors.grey.shade100,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Collage',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(
                          widget.isDarkMode
                              ? Icons.light_mode
                              : Icons.dark_mode,
                        ),
                        onPressed: widget.onThemeToggle,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "自動保存中...",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'タイトル...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  color: theme.cardColor,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.palette_outlined),
                        onPressed: () => _showColorPicker(false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: _pickImage,
                      ),
                      const VerticalDivider(),
                      IconButton(
                        icon: Icon(
                          Icons.pan_tool_alt,
                          color: !_isPenMode ? Colors.blue : null,
                        ),
                        onPressed: () => setState(() {
                          _isPenMode = false;
                          _isEraserMode = false;
                        }),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: _isPenMode && !_isEraserMode
                              ? Colors.blue
                              : null,
                        ),
                        onPressed: () => setState(() {
                          _isPenMode = true;
                          _isEraserMode = false;
                        }),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.auto_fix_normal,
                          color: _isEraserMode ? Colors.blue : null,
                        ),
                        onPressed: () => setState(() {
                          _isPenMode = true;
                          _isEraserMode = true;
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: quill.QuillEditor.basic(
                            controller: _quillController,
                          ),
                        ),
                        ..._currentImages.asMap().entries.map((entry) {
                          int idx = entry.key;
                          CollageImage img = entry.value;
                          return Positioned(
                            left: img.position.dx,
                            top: img.position.dy,
                            child: GestureDetector(
                              onPanUpdate: _isPenMode
                                  ? null
                                  : (d) {
                                      setState(
                                        () => _currentImages[idx].position +=
                                            d.delta,
                                      );
                                      _onChanged();
                                    },
                              onLongPress: _isPenMode
                                  ? null
                                  : () => _deleteImage(idx),
                              child: Image.file(
                                File(img.imagePath),
                                width: img.size,
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        }),
                        IgnorePointer(
                          ignoring: !_isPenMode,
                          child: GestureDetector(
                            onPanStart: (details) {
                              if (!_isPenMode) return;
                              if (_isEraserMode) {
                                _performEraser(details.localPosition);
                              } else {
                                setState(
                                  () => _drawingPoints.add(
                                    DrawingPoint(
                                      offsets: [details.localPosition],
                                      color: _penColor,
                                      width: _penWidth,
                                    ),
                                  ),
                                );
                              }
                            },
                            onPanUpdate: (details) {
                              if (!_isPenMode) return;
                              if (_isEraserMode) {
                                _performEraser(details.localPosition);
                              } else {
                                setState(
                                  () => _drawingPoints.last.offsets.add(
                                    details.localPosition,
                                  ),
                                );
                                _onChanged();
                              }
                            },
                            child: CustomPaint(
                              painter: MyPainter(_drawingPoints),
                              child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(bool forPen) {
    Color tempColor = forPen ? _penColor : Colors.black;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: ColorPicker(
          pickerColor: tempColor,
          onColorChanged: (c) => tempColor = c,
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                if (forPen) {
                  _penColor = tempColor;
                } else {
                  _quillController.formatSelection(
                    quill.Attribute.fromKeyValue(
                      'color',
                      '#${tempColor.value.toRadixString(16).substring(2)}',
                    ),
                  );
                }
              });
              _onChanged();
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class MyPainter extends CustomPainter {
  final List<DrawingPoint> points;
  MyPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    for (var point in points) {
      final paint = Paint()
        ..color = point.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = point.width
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < point.offsets.length - 1; i++) {
        canvas.drawLine(point.offsets[i], point.offsets[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
