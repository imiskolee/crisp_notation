import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crisp_notation/crisp_notation.dart';

import 'note_player.dart';

/// Score DSL 编辑器：
/// 左侧 — 选择文件夹，列出 .txt 文件，点击载入。
/// 右侧 — 上方 DSL 多行编辑器，下方实时预览，支持导出 PNG。
class DslEditorPage extends StatefulWidget {
  const DslEditorPage({super.key});

  @override
  State<DslEditorPage> createState() => _DslEditorPageState();
}

class _DslEditorPageState extends State<DslEditorPage> {
  // --- 左侧文件列表 ---
  String? _folderPath;
  List<File> _txtFiles = [];
  File? _currentFile;

  // --- 右侧编辑器 ---
  final _controller = TextEditingController();
  late final NotePlayer _player;
  double _staffSpace = 8;

  // --- 渲染结果 ---
  ScoreDslResult? _result;
  String? _error;
  bool _exporting = false;

  // --- 示例目录（包内自带） ---
  static final _samplesDir = Directory(
    '${Directory.current.path}/score_dsl_samples',
  );

  @override
  void initState() {
    super.initState();
    _player = NotePlayer();
    _loadSamplesDir();
  }

  @override
  void dispose() {
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  // ─── 文件夹操作 ─────────────────────────────────────

  void _loadSamplesDir() {
    if (_samplesDir.existsSync()) {
      _setFolder(_samplesDir.path);
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择包含 .txt 乐谱文件的文件夹',
    );
    if (result != null) _setFolder(result);
  }

  void _setFolder(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.txt'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      _folderPath = path;
      _txtFiles = files;
    });
  }

  void _loadFile(File file) {
    final content = file.readAsStringSync();
    _controller.text = content;
    setState(() {
      _currentFile = file;
    });
    _render();
  }

  // ─── 渲染 ──────────────────────────────────────────

  void _render() {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      return;
    }
    try {
      final r = loadScoreDsl(text);
      setState(() {
        _result = r;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _result = null;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _result = null;
        _error = e.toString();
      });
    }
  }

  // ─── 导出 PNG ──────────────────────────────────────

  Future<void> _exportPng() async {
    final result = _result;
    if (result == null) return;

    setState(() => _exporting = true);
    try {
      final metadata = Bravura.metadataOrNull;
      if (metadata == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('字体元数据未加载，请重启应用')),
          );
        }
        return;
      }
      final settings = LayoutSettings(metadata: metadata);
      final single = result.layout == 'single';
      final wrapped = layoutStaffSystemSystems(
        result.system,
        settings,
        maxWidth: single ? double.infinity : 140,
        layoutMode:
            single ? SystemLayoutMode.singleLine : SystemLayoutMode.wrapped,
        staffGap: 6,
      );
      final png = await renderStaffSystemSystemsToPng(
        wrapped,
        staffSpace: 16,
        systemGap: 8,
        leftMargin: 10,
        showInstrumentLabels: true,
        showTitle: true,
      );

      // 保存：默认与 .txt 同目录同名 .png，否则让用户选。
      String? outPath;
      if (_currentFile != null) {
        outPath = _currentFile!.path.replaceAll(
          RegExp(r'\.txt$', caseSensitive: false),
          '.png',
        );
        File(outPath).writeAsBytesSync(png);
      } else {
        final picked = await FilePicker.platform.saveFile(
          dialogTitle: '保存 PNG 图片',
          fileName: 'score_export.png',
        );
        if (picked != null) {
          outPath = picked;
          File(outPath).writeAsBytesSync(png);
        }
      }

      if (!mounted) return;
      if (outPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: $outPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── 保存文件 ──────────────────────────────────────

  void _saveFile() {
    final content = _controller.text;
    if (_currentFile != null) {
      _currentFile!.writeAsStringSync(content);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存: ${_currentFile!.path}')),
      );
    } else {
      _saveAs();
    }
  }

  Future<void> _saveAs() async {
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '保存 DSL 文件',
      fileName: 'score.txt',
    );
    if (picked != null) {
      File(picked).writeAsStringSync(_controller.text, encoding: utf8);
      setState(() => _currentFile = File(picked));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存: $picked')),
      );
    }
  }

  void _newFile() {
    _controller.clear();
    setState(() {
      _currentFile = null;
      _result = null;
      _error = null;
    });
  }

  void _playElement(String id) {
    final result = _result;
    if (result == null) return;
    for (final score in result.system.staves) {
      final midis = pitchesForElements(score, {id}).toList();
      if (midis.isNotEmpty) {
        if (midis.length == 1) {
          _player.playMidi(midis.single);
        } else {
          _player.playChord(midis);
        }
        return;
      }
    }
  }

  // ─── 构建 ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _render,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveFile,
      },
      child: Focus(
        autofocus: true,
        child: Row(
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1),
            Expanded(child: _buildEditorArea()),
          ],
        ),
      ),
    );
  }

  // ─── 左侧文件列表 ─────────────────────────────────

  Widget _buildSidebar() {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '文件',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: '选择文件夹',
                    onPressed: _pickFolder,
                  ),
                ],
              ),
            ),
            if (_folderPath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  _folderPath!,
                  style: theme.textTheme.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _txtFiles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '没有 .txt 文件。\n点击右上角图标选择文件夹。',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _txtFiles.length,
                      itemBuilder: (context, i) {
                        final file = _txtFiles[i];
                        final name = file.uri.pathSegments.last;
                        final selected =
                            _currentFile?.path == file.path;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: Icon(
                            selected ? Icons.article : Icons.description_outlined,
                            size: 20,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _loadFile(file),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _newFile,
                    icon: const Icon(Icons.note_add, size: 18),
                    label: const Text('新建'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _saveFile,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 右侧编辑+预览 ─────────────────────────────────

  Widget _buildEditorArea() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 工具栏
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                if (_currentFile != null)
                  Expanded(
                    child: Text(
                      _currentFile!.uri.pathSegments.last,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Expanded(
                    child: Text('未命名', style: TextStyle(fontSize: 14)),
                  ),
                _sizeSelector(theme),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _render,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('渲染'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _exporting ? null : _exportPng,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image, size: 18),
                  label: const Text('导出PNG'),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // 上方：DSL 编辑器
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'Score DSL（Ctrl+Enter 渲染，Ctrl+S 保存）',
                hintText: '---score\ntitle: ...\ntracks:\n  - name: ...\n---\n:track\nnotes: ...',
                hintStyle: TextStyle(color: theme.hintColor.withValues(alpha: 0.5)),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // 下方：预览
        Expanded(
          flex: 3,
          child: _buildPreview(theme),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final error = _error;
    if (error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    'DSL 解析失败：\n$error',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = _result;
    if (result == null) {
      return Center(
        child: Text(
          '输入 DSL 后点击渲染',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // layout: single → 单行无限长（横向滚动）；page（默认）→ 按宽度自动换行。
    final single = result.layout == 'single';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: single
                ? StaffSystemScrollView(
                    system: result.system,
                    staffSpace: _staffSpace,
                    onElementTap: _playElement,
                  )
                : StaffSystemView(
                    system: result.system,
                    layoutMode: SystemLayoutMode.wrapped,
                    staffSpace: _staffSpace,
                    onElementTap: _playElement,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sizeSelector(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('字号', style: theme.textTheme.labelSmall),
        const SizedBox(width: 4),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 6.0, label: Text('S')),
            ButtonSegment(value: 8.0, label: Text('M')),
            ButtonSegment(value: 10.0, label: Text('L')),
          ],
          selected: {_staffSpace},
          onSelectionChanged: (s) => setState(() => _staffSpace = s.first),
        ),
      ],
    );
  }
}
