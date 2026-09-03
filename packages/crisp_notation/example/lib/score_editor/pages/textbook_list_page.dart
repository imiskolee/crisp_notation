import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../textbook_service.dart';
import '../models/textbook_models.dart';
import 'textbook_edit_page.dart';
import 'textbook_detail_page.dart';

/// 教材列表首页
class TextbookListPage extends StatelessWidget {
  const TextbookListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Score Editor - 教材中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '创建新教材',
            onPressed: () => _createNewTextbook(context),
          ),
        ],
      ),
      body: Consumer<TextbookService>(
        builder: (context, service, child) {
          if (service.textbooks.isEmpty) {
            return _EmptyState(onCreate: () => _createNewTextbook(context));
          }
          return _TextbookGrid(
            textbooks: service.textbooks,
            onTap: (textbook) => _openTextbook(context, service, textbook),
            onEdit: (textbook) => _editTextbook(context, service, textbook),
            onDelete: (textbook) => _deleteTextbook(context, service, textbook),
          );
        },
      ),
    );
  }

  void _createNewTextbook(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TextbookEditPage()),
    );
  }

  void _openTextbook(
      BuildContext context, TextbookService service, Textbook textbook) {
    service.setCurrentTextbook(textbook.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TextbookDetailPage(textbook: textbook)),
    );
  }

  void _editTextbook(
      BuildContext context, TextbookService service, Textbook textbook) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextbookEditPage(textbook: textbook),
      ),
    );
  }

  void _deleteTextbook(BuildContext context, TextbookService service,
      Textbook textbook) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除教材'),
        content: Text('确定要删除教材「${textbook.title}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              service.deleteTextbook(textbook.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('教材已删除')),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 空状态提示
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book,
              size: 96,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有任何教材',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方按钮创建你的第一本电子教材，'
              '支持章节管理、TOC目录和拖拽排序。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('创建新教材'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 教材网格
class _TextbookGrid extends StatelessWidget {
  final List<Textbook> textbooks;
  final void Function(Textbook) onTap;
  final void Function(Textbook) onEdit;
  final void Function(Textbook) onDelete;

  const _TextbookGrid({
    required this.textbooks,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: textbooks.length,
      itemBuilder: (context, index) {
        return _TextbookCard(
          textbook: textbooks[index],
          onTap: () => onTap(textbooks[index]),
          onEdit: () => onEdit(textbooks[index]),
          onDelete: () => onDelete(textbooks[index]),
        );
      },
    );
  }
}

/// 教材卡片
class _TextbookCard extends StatelessWidget {
  final Textbook textbook;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TextbookCard({
    required this.textbook,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面图
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverImage(url: textbook.coverImageUrl),
                  // 免费/付费标签
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _Badge(
                      text: textbook.isFree ? '免费' : '付费',
                      color: textbook.isFree
                          ? Colors.green
                          : scheme.primary,
                    ),
                  ),
                  // 免费章节提示
                  if (!textbook.isFree && textbook.freeChapterCount > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _Badge(
                        text: '前${textbook.freeChapterCount}章免费',
                        color: Colors.orange,
                      ),
                    ),
                  // 编辑/删除按钮
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _IconCircleButton(
                          icon: Icons.edit,
                          onTap: onEdit,
                          tooltip: '编辑',
                        ),
                        const SizedBox(width: 6),
                        _IconCircleButton(
                          icon: Icons.delete_outline,
                          onTap: onDelete,
                          tooltip: '删除',
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 信息区
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textbook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        textbook.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${textbook.chapterCount}章 / ${textbook.articleCount}篇',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const Spacer(),
                        if (!textbook.isFree)
                          Text(
                            '¥${textbook.price.toStringAsFixed(0)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面图片（带占位）
class _CoverImage extends StatelessWidget {
  final String url;

  const _CoverImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
        );
      },
    );
  }
}

/// 标签 Badge
class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 圆形图标按钮
class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;

  const _IconCircleButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: color ?? Colors.white,
          ),
        ),
      ),
    );
  }
}
