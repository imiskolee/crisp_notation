import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../textbook_service.dart';
import '../models/textbook_models.dart';
import 'textbook_edit_page.dart';

/// 教材详情页 - 包含TOC目录和内容浏览
class TextbookDetailPage extends StatefulWidget {
  final Textbook textbook;

  const TextbookDetailPage({super.key, required this.textbook});

  @override
  State<TextbookDetailPage> createState() => _TextbookDetailPageState();
}

class _TextbookDetailPageState extends State<TextbookDetailPage> {
  Chapter? _selectedChapter;
  Article? _selectedArticle;

  @override
  void initState() {
    super.initState();
    final service = context.read<TextbookService>();
    final tb = service.getTextbook(widget.textbook.id);
    if (tb != null && tb.chapters.isNotEmpty) {
      _selectedChapter = tb.sortedChapters.first;
      if (_selectedChapter!.articles.isNotEmpty) {
        _selectedArticle = _selectedChapter!.sortedArticles.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TextbookService>(
      builder: (context, service, child) {
        final textbook = service.getTextbook(widget.textbook.id) ?? widget.textbook;
        final screenWidth = MediaQuery.of(context).size.width;
        final useWideLayout = screenWidth >= 900;

        final body = useWideLayout
            ? _WideLayout(
                textbook: textbook,
                selectedChapter: _selectedChapter,
                selectedArticle: _selectedArticle,
                onChapterSelected: (ch) => setState(() {
                  _selectedChapter = ch;
                  _selectedArticle = ch.sortedArticles.isNotEmpty
                      ? ch.sortedArticles.first
                      : null;
                }),
                onArticleSelected: (a) => setState(() => _selectedArticle = a),
              )
            : _NarrowLayout(
                textbook: textbook,
                selectedChapter: _selectedChapter,
                selectedArticle: _selectedArticle,
                onChapterSelected: (ch) => setState(() {
                  _selectedChapter = ch;
                  _selectedArticle = ch.sortedArticles.isNotEmpty
                      ? ch.sortedArticles.first
                      : null;
                }),
                onArticleSelected: (a) => setState(() => _selectedArticle = a),
              );

        return Scaffold(
          appBar: AppBar(
            title: Text(textbook.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑教材',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TextbookEditPage(textbook: textbook),
                    ),
                  );
                },
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

/// 宽屏布局：左侧TOC + 右侧内容
class _WideLayout extends StatelessWidget {
  final Textbook textbook;
  final Chapter? selectedChapter;
  final Article? selectedArticle;
  final void Function(Chapter) onChapterSelected;
  final void Function(Article) onArticleSelected;

  const _WideLayout({
    required this.textbook,
    required this.selectedChapter,
    required this.selectedArticle,
    required this.onChapterSelected,
    required this.onArticleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // TOC 侧栏
        Container(
          width: 320,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            children: [
              _TocHeader(textbook: textbook),
              Expanded(
                child: _TocPanel(
                  textbook: textbook,
                  selectedChapter: selectedChapter,
                  selectedArticle: selectedArticle,
                  onChapterSelected: onChapterSelected,
                  onArticleSelected: onArticleSelected,
                ),
              ),
            ],
          ),
        ),
        // 内容区
        Expanded(
          child: _ContentArea(
            textbook: textbook,
            selectedChapter: selectedChapter,
            selectedArticle: selectedArticle,
          ),
        ),
      ],
    );
  }
}

/// 窄屏布局：只显示内容，TOC作为抽屉
class _NarrowLayout extends StatelessWidget {
  final Textbook textbook;
  final Chapter? selectedChapter;
  final Article? selectedArticle;
  final void Function(Chapter) onChapterSelected;
  final void Function(Article) onArticleSelected;

  const _NarrowLayout({
    required this.textbook,
    required this.selectedChapter,
    required this.selectedArticle,
    required this.onChapterSelected,
    required this.onArticleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            _TocHeader(textbook: textbook),
            Expanded(
              child: _TocPanel(
                textbook: textbook,
                selectedChapter: selectedChapter,
                selectedArticle: selectedArticle,
                onChapterSelected: (ch) {
                  onChapterSelected(ch);
                  Navigator.pop(context);
                },
                onArticleSelected: (a) {
                  onArticleSelected(a);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
      body: _ContentArea(
        textbook: textbook,
        selectedChapter: selectedChapter,
        selectedArticle: selectedArticle,
        showTocButton: true,
      ),
    );
  }
}

/// TOC 头区域
class _TocHeader extends StatelessWidget {
  final Textbook textbook;

  const _TocHeader({required this.textbook});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: textbook.coverImageUrl.isNotEmpty
                      ? Image.network(
                          textbook.coverImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _CoverFallback(
                              scheme: scheme),
                        )
                      : _CoverFallback(scheme: scheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textbook.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${textbook.chapterCount}章 · ${textbook.articleCount}篇',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '目录 (TOC)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  final ColorScheme scheme;

  const _CoverFallback({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.primaryContainer,
      child: Icon(
        Icons.menu_book,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}

/// TOC 目录面板
class _TocPanel extends StatelessWidget {
  final Textbook textbook;
  final Chapter? selectedChapter;
  final Article? selectedArticle;
  final void Function(Chapter) onChapterSelected;
  final void Function(Article) onArticleSelected;

  const _TocPanel({
    required this.textbook,
    required this.selectedChapter,
    required this.selectedArticle,
    required this.onChapterSelected,
    required this.onArticleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.read<TextbookService>();
    final toc = service.generateToc(textbook);

    if (toc.isEmpty) {
      return Center(
        child: Text(
          '暂无目录',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: toc.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.2),
      itemBuilder: (context, i) {
        final entry = toc[i];
        final isChapter = entry.targetType == TocTargetType.chapter;

        // 查找对应对象
        Chapter? targetChapter;
        Article? targetArticle;
        if (isChapter) {
          try {
            targetChapter = textbook.chapters
                .firstWhere((c) => c.id == entry.targetId);
          } catch (_) {
            targetChapter = null;
          }
        } else {
          for (final ch in textbook.chapters) {
            try {
              targetArticle =
                  ch.articles.firstWhere((a) => a.id == entry.targetId);
              targetChapter = ch;
              break;
            } catch (_) {}
          }
        }

        final bool selected;
        if (isChapter) {
          selected = selectedChapter?.id == targetChapter?.id &&
              selectedArticle == null;
        } else {
          selected = selectedArticle?.id == targetArticle?.id;
        }

        final color = Theme.of(context).colorScheme;
        final bg = selected
            ? color.primaryContainer
            : Colors.transparent;
        final fg = selected ? color.onPrimaryContainer : color.onSurface;

        return InkWell(
          onTap: entry.isFree
              ? () {
                  if (isChapter && targetChapter != null) {
                    onChapterSelected(targetChapter);
                  } else if (!isChapter && targetArticle != null) {
                    // select parent chapter first
                    if (targetChapter != null &&
                        selectedChapter?.id != targetChapter.id) {
                      onChapterSelected(targetChapter);
                    }
                    onArticleSelected(targetArticle);
                  }
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('「${entry.title}」为付费内容，请购买后阅读'),
                      action: SnackBarAction(
                        label: '去购买',
                        onPressed: () {
                          // TODO: 接入购买流程
                        },
                      ),
                    ),
                  );
                },
          child: Container(
            color: bg,
            padding: EdgeInsets.only(
              left: 12 + entry.level * 20.0,
              right: 12,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                Icon(
                  isChapter ? Icons.folder_outlined : Icons.description_outlined,
                  size: 16,
                  color: entry.isFree ? fg : color.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title,
                    style: TextStyle(
                      color: entry.isFree ? fg : color.onSurface.withValues(alpha: 0.5),
                      fontWeight: isChapter ? FontWeight.w600 : FontWeight.normal,
                      fontSize: isChapter ? 14 : 13,
                      decoration:
                          entry.isFree ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                if (!entry.isFree) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 内容区
class _ContentArea extends StatelessWidget {
  final Textbook textbook;
  final Chapter? selectedChapter;
  final Article? selectedArticle;
  final bool showTocButton;

  const _ContentArea({
    required this.textbook,
    required this.selectedChapter,
    required this.selectedArticle,
    this.showTocButton = false,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedChapter == null) {
      return _EmptyContent(
        icon: Icons.folder_open_outlined,
        title: '从左侧选择一个章节开始阅读',
        showTocButton: showTocButton,
      );
    }

    if (selectedArticle == null) {
      return _ChapterContent(
        textbook: textbook,
        chapter: selectedChapter!,
        showTocButton: showTocButton,
      );
    }

    return _ArticleContent(
      textbook: textbook,
      chapter: selectedChapter!,
      article: selectedArticle!,
      showTocButton: showTocButton,
    );
  }
}

class _EmptyContent extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool showTocButton;

  const _EmptyContent({
    required this.icon,
    required this.title,
    this.showTocButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTocButton)
              Align(
                alignment: Alignment.topLeft,
                child: Builder(
                  builder: (ctx) => IconButton.filledTonal(
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    icon: const Icon(Icons.menu),
                    tooltip: '打开目录',
                  ),
                ),
              ),
            const Spacer(),
            Icon(
              icon,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ChapterContent extends StatelessWidget {
  final Textbook textbook;
  final Chapter chapter;
  final bool showTocButton;

  const _ChapterContent({
    required this.textbook,
    required this.chapter,
    this.showTocButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final sortedArticles = chapter.sortedArticles;
    final scheme = Theme.of(context).colorScheme;
    final chapterIndex =
        textbook.sortedChapters.indexWhere((c) => c.id == chapter.id);
    final isFree = textbook.isChapterFree(chapterIndex);

    return ListView(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: 40,
      ),
      children: [
        if (showTocButton)
          Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IconButton.filledTonal(
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  icon: const Icon(Icons.menu),
                  tooltip: '打开目录',
                ),
              ),
            ),
          ),
        Row(
          children: [
            if (!isFree)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '付费章节',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              '第 ${chapterIndex + 1} 章',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          chapter.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '本章节共 ${sortedArticles.length} 篇文章',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (sortedArticles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '该章节还没有文章',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...sortedArticles.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    a.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: a.content.isNotEmpty
                      ? Text(
                          a.content.length > 60
                              ? '${a.content.substring(0, 60)}...'
                              : a.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          '点击开始阅读',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: isFree
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _StandaloneArticlePage(
                                textbook: textbook,
                                chapter: chapter,
                                article: a,
                              ),
                            ),
                          )
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('此为付费章节，请购买后阅读')),
                          );
                        },
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _ArticleContent extends StatelessWidget {
  final Textbook textbook;
  final Chapter chapter;
  final Article article;
  final bool showTocButton;

  const _ArticleContent({
    required this.textbook,
    required this.chapter,
    required this.article,
    this.showTocButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chapterIndex =
        textbook.sortedChapters.indexWhere((c) => c.id == chapter.id);
    final isFree = textbook.isChapterFree(chapterIndex);

    return ListView(
      padding: EdgeInsets.only(
        top: 24,
        left: 28,
        right: 28,
        bottom: 60,
      ),
      children: [
        if (showTocButton)
          Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IconButton.filledTonal(
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  icon: const Icon(Icons.menu),
                  tooltip: '打开目录',
                ),
              ),
            ),
          ),
        // 面包屑
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              textbook.title,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: scheme.onSurfaceVariant),
            Text(
              '第${chapterIndex + 1}章 ${chapter.title}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          article.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 28),
        if (!isFree)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '此为付费内容，请购买完整教材后继续阅读',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    // TODO: 购买流程
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700),
                  child: const Text('去购买'),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(minHeight: 300),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: article.content.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无内容',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : SelectableText(
                    article.content,
                    style: const TextStyle(fontSize: 16, height: 1.75),
                  ),
          ),
      ],
    );
  }
}

/// 窄屏独立阅读页面
class _StandaloneArticlePage extends StatelessWidget {
  final Textbook textbook;
  final Chapter chapter;
  final Article article;

  const _StandaloneArticlePage({
    required this.textbook,
    required this.chapter,
    required this.article,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chapterIndex =
        textbook.sortedChapters.indexWhere((c) => c.id == chapter.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(article.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        children: [
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                textbook.title,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              Icon(Icons.chevron_right,
                  size: 16, color: scheme.onSurfaceVariant),
              Text(
                '第${chapterIndex + 1}章 ${chapter.title}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            article.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(minHeight: 300),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: article.content.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无内容',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : SelectableText(
                    article.content,
                    style: const TextStyle(fontSize: 16, height: 1.75),
                  ),
          ),
        ],
      ),
    );
  }
}
