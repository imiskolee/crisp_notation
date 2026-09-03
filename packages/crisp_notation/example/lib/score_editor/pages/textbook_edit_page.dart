import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../textbook_service.dart';
import '../models/textbook_models.dart';

/// 教材创建/编辑页面
class TextbookEditPage extends StatefulWidget {
  final Textbook? textbook;

  const TextbookEditPage({super.key, this.textbook});

  @override
  State<TextbookEditPage> createState() => _TextbookEditPageState();
}

class _TextbookEditPageState extends State<TextbookEditPage> {
  late final bool _isEditing;
  late Textbook _draft;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _isEditing = widget.textbook != null;
    _draft = _isEditing
        ? widget.textbook!.copyWith(
            chapters: widget.textbook!.chapters
                .map((c) => c.copyWith(
                      articles: c.articles
                          .map((a) => a.copyWith())
                          .toList(),
                    ))
                .toList(),
          )
        : Textbook(
            id: '',
            title: '',
            description: '',
            coverImageUrl: '',
            isFree: true,
            freeChapterCount: 0,
            price: 0,
            chapters: [],
          );
  }

  /// 保存教材
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final service = context.read<TextbookService>();

    // 封面URL生成（如果为空）
    if (_draft.coverImageUrl.isEmpty) {
      final encoded = Uri.encodeComponent(
        'music textbook cover for "${_draft.title}" elegant design with musical notes',
      );
      _draft = _draft.copyWith(
        coverImageUrl:
            'https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=$encoded&image_size=landscape_16_9',
      );
    }

    if (_isEditing) {
      service.updateTextbook(_draft);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('教材已更新')),
      );
    } else {
      // 给新教材一个真实的id
      final newT = _draft.copyWith(id: IdGenerator.generate('tb'));
      service.addTextbook(newT);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('教材创建成功')),
      );
    }
    Navigator.pop(context);
  }

  /// ========== 章节操作 ==========

  void _addChapter() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加章节'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '章节标题'),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    ).then((title) {
      if (title is String && title.trim().isNotEmpty) {
        setState(() {
          final chapters = List<Chapter>.from(_draft.chapters);
          chapters.add(Chapter(
            id: IdGenerator.generate('ch'),
            title: title.trim(),
            order: chapters.length,
          ));
          _draft = _draft.copyWith(chapters: chapters);
        });
      }
    });
  }

  void _editChapter(int index) {
    final chapter = _draft.sortedChapters[index];
    final controller = TextEditingController(text: chapter.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑章节'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '章节标题'),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((title) {
      if (title is String && title.trim().isNotEmpty) {
        setState(() {
          final sorted = _draft.sortedChapters;
          sorted[index] = sorted[index].copyWith(title: title.trim());
          _draft = _draft.copyWith(chapters: sorted);
        });
      }
    });
  }

  void _deleteChapter(int index) {
    final sorted = _draft.sortedChapters;
    final chapter = sorted[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除章节'),
        content: Text(
          '确定删除章节「${chapter.title}」吗？该章节下的 ${chapter.articleCount} 篇文章会一并删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                sorted.removeAt(index);
                for (var i = 0; i < sorted.length; i++) {
                  sorted[i] = sorted[i].copyWith(order: i);
                }
                _draft = _draft.copyWith(chapters: sorted);
              });
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _moveChapter(int oldIndex, int newIndex) {
    setState(() {
      final sorted = _draft.sortedChapters;
      final chapter = sorted.removeAt(oldIndex);
      sorted.insert(newIndex, chapter);
      for (var i = 0; i < sorted.length; i++) {
        sorted[i] = sorted[i].copyWith(order: i);
      }
      _draft = _draft.copyWith(chapters: sorted);
    });
  }

  /// ========== 文章操作 ==========

  void _addArticle(int chapterIndex) {
    final sortedChapters = _draft.sortedChapters;
    final chapter = sortedChapters[chapterIndex];
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('在「${chapter.title}」中添加文章'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文章标题'),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    ).then((title) {
      if (title is String && title.trim().isNotEmpty) {
        setState(() {
          final articles = List<Article>.from(chapter.articles);
          articles.add(Article(
            id: IdGenerator.generate('ar'),
            title: title.trim(),
            order: articles.length,
          ));
          sortedChapters[chapterIndex] = chapter.copyWith(articles: articles);
          _draft = _draft.copyWith(chapters: sortedChapters);
        });
      }
    });
  }

  void _editArticleTitle(int chapterIndex, int articleIndex) {
    final chapter = _draft.sortedChapters[chapterIndex];
    final articles = chapter.sortedArticles;
    final article = articles[articleIndex];
    final controller = TextEditingController(text: article.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑文章标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文章标题'),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((title) {
      if (title is String && title.trim().isNotEmpty) {
        setState(() {
          articles[articleIndex] =
              articles[articleIndex].copyWith(title: title.trim());
          final newChapter = chapter.copyWith(articles: articles);
          final sortedChapters = _draft.sortedChapters;
          sortedChapters[chapterIndex] = newChapter;
          _draft = _draft.copyWith(chapters: sortedChapters);
        });
      }
    });
  }

  void _editArticleContent(int chapterIndex, int articleIndex) {
    final chapter = _draft.sortedChapters[chapterIndex];
    final articles = chapter.sortedArticles;
    final article = articles[articleIndex];
    final controller = TextEditingController(text: article.content);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '在此输入文章内容...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        articles[articleIndex] = articles[articleIndex]
                            .copyWith(content: controller.text);
                        final newChapter = chapter.copyWith(articles: articles);
                        final sortedChapters = _draft.sortedChapters;
                        sortedChapters[chapterIndex] = newChapter;
                        _draft = _draft.copyWith(chapters: sortedChapters);
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('内容已保存')),
                      );
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteArticle(int chapterIndex, int articleIndex) {
    final chapter = _draft.sortedChapters[chapterIndex];
    final articles = chapter.sortedArticles;
    final article = articles[articleIndex];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除文章「${article.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                articles.removeAt(articleIndex);
                for (var i = 0; i < articles.length; i++) {
                  articles[i] = articles[i].copyWith(order: i);
                }
                final newChapter = chapter.copyWith(articles: articles);
                final sortedChapters = _draft.sortedChapters;
                sortedChapters[chapterIndex] = newChapter;
                _draft = _draft.copyWith(chapters: sortedChapters);
              });
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _moveArticle(int chapterIndex, int oldIndex, int newIndex) {
    setState(() {
      final chapter = _draft.sortedChapters[chapterIndex];
      final articles = chapter.sortedArticles;
      final article = articles.removeAt(oldIndex);
      articles.insert(newIndex, article);
      for (var i = 0; i < articles.length; i++) {
        articles[i] = articles[i].copyWith(order: i);
      }
      final sortedChapters = _draft.sortedChapters;
      sortedChapters[chapterIndex] = chapter.copyWith(articles: articles);
      _draft = _draft.copyWith(chapters: sortedChapters);
    });
  }

  // ========== UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑教材' : '创建新教材'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 24),
            _buildChaptersSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '基本信息',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            // 封面预览
            Row(
              children: [
                Container(
                  width: 140,
                  height: 88,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _draft.coverImageUrl.isNotEmpty
                      ? Image.network(
                          _draft.coverImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _PlaceholderCover(),
                        )
                      : const _PlaceholderCover(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '保存后将根据教材标题自动生成AI封面图。你也可以稍后自定义封面。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _draft.title,
              decoration: const InputDecoration(
                labelText: '教材标题 *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入教材标题';
                }
                return null;
              },
              onSaved: (value) {
                _draft = _draft.copyWith(title: value!.trim());
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _draft.description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '教材描述',
                hintText: '简要介绍这本教材的内容、适合人群等',
                border: OutlineInputBorder(),
              ),
              onSaved: (value) {
                _draft = _draft.copyWith(description: value?.trim() ?? '');
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('免费教材'),
              subtitle: Text(_draft.isFree ? '所有章节均可免费阅读' : '仅前N章免费，其余需付费'),
              value: _draft.isFree,
              onChanged: (v) => setState(() {
                _draft = _draft.copyWith(isFree: v);
                if (v) {
                  _draft = _draft.copyWith(freeChapterCount: 0, price: 0);
                }
              }),
              contentPadding: EdgeInsets.zero,
            ),
            if (!_draft.isFree) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _draft.freeChapterCount.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '免费章节数量',
                  hintText: '设置前多少章可以免费阅读',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final n = int.tryParse(value ?? '');
                  if (n == null || n < 0) return '请输入有效的数字';
                  return null;
                },
                onSaved: (value) {
                  _draft = _draft.copyWith(
                    freeChapterCount: int.tryParse(value ?? '0') ?? 0,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _draft.price > 0 ? _draft.price.toStringAsFixed(2) : '',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '价格（元）',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return '请输入价格';
                  final p = double.tryParse(value);
                  if (p == null || p < 0) return '请输入有效的价格';
                  return null;
                },
                onSaved: (value) {
                  _draft = _draft.copyWith(
                    price: double.tryParse(value ?? '0') ?? 0,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChaptersSection() {
    final sortedChapters = _draft.sortedChapters;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '章节与文章',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _addChapter,
                  icon: const Icon(Icons.add),
                  label: const Text('添加章节'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '拖动章节或文章左侧的手柄图标可调整排序。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            if (sortedChapters.isEmpty)
              _buildEmptyChaptersHint()
            else
              _buildChaptersList(sortedChapters),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChaptersHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.layers_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有章节',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '点击「添加章节」按钮开始创建教材结构',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersList(List<Chapter> sortedChapters) {
    return Theme(
      data: Theme.of(context).copyWith(
        expansionTileTheme: ExpansionTileThemeData(
          shape: Border.all(color: Colors.transparent),
        ),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: sortedChapters.length,
        onReorderItem: _moveChapter,
        itemBuilder: (context, index) {
          final chapter = sortedChapters[index];
          final sortedArticles = chapter.sortedArticles;
          final chapterFree = _draft.isChapterFree(index);

          return _ChapterTile(
            key: ValueKey('chapter_${chapter.id}'),
            index: index,
            chapter: chapter,
            sortedArticles: sortedArticles,
            isFree: chapterFree,
            onAddArticle: () => _addArticle(index),
            onEditChapter: () => _editChapter(index),
            onDeleteChapter: () => _deleteChapter(index),
            onEditArticleTitle: (ai) => _editArticleTitle(index, ai),
            onEditArticleContent: (ai) => _editArticleContent(index, ai),
            onDeleteArticle: (ai) => _deleteArticle(index, ai),
            onReorderArticle: (oldI, newI) => _moveArticle(index, oldI, newI),
          );
        },
      ),
    );
  }
}

/// 封面占位
class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 2),
          Text(
            'AI封面',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 章节条目（可展开）
class _ChapterTile extends StatelessWidget {
  final int index;
  final Chapter chapter;
  final List<Article> sortedArticles;
  final bool isFree;
  final VoidCallback onAddArticle;
  final VoidCallback onEditChapter;
  final VoidCallback onDeleteChapter;
  final void Function(int) onEditArticleTitle;
  final void Function(int) onEditArticleContent;
  final void Function(int) onDeleteArticle;
  final void Function(int, int) onReorderArticle;

  const _ChapterTile({
    super.key,
    required this.index,
    required this.chapter,
    required this.sortedArticles,
    required this.isFree,
    required this.onAddArticle,
    required this.onEditChapter,
    required this.onDeleteChapter,
    required this.onEditArticleTitle,
    required this.onEditArticleContent,
    required this.onDeleteArticle,
    required this.onReorderArticle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        leading: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.drag_handle,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              '第${index + 1}章',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                chapter.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (!isFree)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '付费',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditChapter,
              tooltip: '编辑章节',
              iconSize: 20,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: onAddArticle,
              tooltip: '添加文章',
              iconSize: 20,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onDeleteChapter,
              tooltip: '删除章节',
              iconSize: 20,
            ),
          ],
        ),
        subtitle: Text(
          '${sortedArticles.length} 篇文章',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        initiallyExpanded: true,
        children: [
          if (sortedArticles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '暂无文章，点击右上角 + 添加',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: sortedArticles.length,
              onReorderItem: onReorderArticle,
              itemBuilder: (context, ai) {
                final article = sortedArticles[ai];
                return Padding(
                  key: ValueKey('article_${article.id}'),
                  padding: const EdgeInsets.only(bottom: 6, left: 16),
                  child: Material(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      leading: ReorderableDragStartListener(
                        index: ai,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                      title: Text(
                        article.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: article.content.isNotEmpty
                          ? Text(
                              article.content.length > 40
                                  ? '${article.content.substring(0, 40)}...'
                                  : article.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEditArticleTitle(ai),
                            tooltip: '编辑标题',
                            iconSize: 18,
                          ),
                          IconButton(
                            icon: const Icon(Icons.description_outlined),
                            onPressed: () => onEditArticleContent(ai),
                            tooltip: '编辑内容',
                            iconSize: 18,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => onDeleteArticle(ai),
                            tooltip: '删除文章',
                            iconSize: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
