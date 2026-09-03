import 'package:flutter/foundation.dart';

import 'models/textbook_models.dart';

/// 教材状态管理服务
class TextbookService extends ChangeNotifier {
  final List<Textbook> _textbooks = [];
  Textbook? _currentTextbook;
  Chapter? _currentChapter;
  Article? _currentArticle;

  /// 获取所有教材
  List<Textbook> get textbooks => List.unmodifiable(_textbooks);

  /// 当前选中的教材
  Textbook? get currentTextbook => _currentTextbook;

  /// 当前选中的章节
  Chapter? get currentChapter => _currentChapter;

  /// 当前选中的文章
  Article? get currentArticle => _currentArticle;

  TextbookService() {
    _loadSampleData();
  }

  /// 加载示例数据
  void _loadSampleData() {
    _textbooks.addAll([
      Textbook(
        id: IdGenerator.generate('tb'),
        title: '钢琴入门教程',
        description: '从零开始学习钢琴，涵盖基本乐理、指法练习和经典曲目。适合零基础学员。',
        coverImageUrl:
            'https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=piano%20textbook%20cover%20elegant%20music%20notes%20minimalist%20design&image_size=landscape_16_9',
        isFree: false,
        freeChapterCount: 2,
        price: 99.0,
        chapters: [
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第一章 认识钢琴',
            order: 0,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '1.1 钢琴的结构',
                content: '钢琴由88个键组成，包括52个白键和36个黑键...',
                order: 0,
              ),
              Article(
                id: IdGenerator.generate('ar'),
                title: '1.2 正确的坐姿',
                content: '弹奏钢琴时，身体应正对钢琴中央C...',
                order: 1,
              ),
            ],
          ),
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第二章 基本乐理',
            order: 1,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '2.1 音高与音阶',
                content: '音高是指声音的高低...',
                order: 0,
              ),
            ],
          ),
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第三章 入门练习',
            order: 2,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '3.1 五指练习',
                content: '五指练习是钢琴基础训练的核心...',
                order: 0,
              ),
            ],
          ),
        ],
      ),
      Textbook(
        id: IdGenerator.generate('tb'),
        title: '简谱快速上手',
        description: '用最简单的方式学习简谱记谱法，快速掌握读谱和记谱技巧。',
        coverImageUrl:
            'https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=jianpu%20numbered%20musical%20notation%20textbook%20cover%20colorful%20numbers&image_size=landscape_16_9',
        isFree: true,
        freeChapterCount: 0,
        price: 0,
        chapters: [
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第一章 简谱基础',
            order: 0,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '1.1 数字与音符',
                content: '简谱用1-7七个数字表示七个基本音级...',
                order: 0,
              ),
            ],
          ),
        ],
      ),
      Textbook(
        id: IdGenerator.generate('tb'),
        title: '古典名曲赏析',
        description: '精选贝多芬、莫扎特、肖邦等大师经典作品，深入解析创作背景与演奏技巧。',
        coverImageUrl:
            'https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=classical%20music%20textbook%20cover%20vintage%20orchestra%20elegant&image_size=landscape_16_9',
        isFree: false,
        freeChapterCount: 1,
        price: 199.0,
        chapters: [
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第一章 巴洛克时期',
            order: 0,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '1.1 巴赫与赋格',
                content: '约翰·塞巴斯蒂安·巴赫是巴洛克时期最伟大的作曲家...',
                order: 0,
              ),
            ],
          ),
          Chapter(
            id: IdGenerator.generate('ch'),
            title: '第二章 古典主义',
            order: 1,
            articles: [
              Article(
                id: IdGenerator.generate('ar'),
                title: '2.1 莫扎特的天才',
                content: '沃尔夫冈·阿玛多伊斯·莫扎特...',
                order: 0,
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  /// ========== 教材操作 ==========

  /// 添加新教材
  void addTextbook(Textbook textbook) {
    _textbooks.add(textbook);
    notifyListeners();
  }

  /// 创建新教材
  Textbook createTextbook({
    required String title,
    String description = '',
    bool isFree = false,
    int freeChapterCount = 0,
    double price = 0,
  }) {
    final textbook = Textbook(
      id: IdGenerator.generate('tb'),
      title: title,
      description: description,
      coverImageUrl: _generateCoverPrompt(title),
      isFree: isFree,
      freeChapterCount: freeChapterCount,
      price: price,
    );
    addTextbook(textbook);
    return textbook;
  }

  /// 根据标题生成封面URL占位
  String _generateCoverPrompt(String title) {
    final encoded = Uri.encodeComponent(
      'music textbook cover for "$title" elegant design with musical notes',
    );
    return 'https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=$encoded&image_size=landscape_16_9';
  }

  /// 更新教材
  void updateTextbook(Textbook textbook) {
    final index = _textbooks.indexWhere((t) => t.id == textbook.id);
    if (index != -1) {
      _textbooks[index] = textbook.copyWith(updatedAt: DateTime.now());
      if (_currentTextbook?.id == textbook.id) {
        _currentTextbook = _textbooks[index];
      }
      notifyListeners();
    }
  }

  /// 删除教材
  void deleteTextbook(String textbookId) {
    _textbooks.removeWhere((t) => t.id == textbookId);
    if (_currentTextbook?.id == textbookId) {
      _currentTextbook = null;
      _currentChapter = null;
      _currentArticle = null;
    }
    notifyListeners();
  }

  /// 获取指定教材
  Textbook? getTextbook(String id) {
    return _textbooks.firstWhere((t) => t.id == id, orElse: () =>
        _textbooks.first); // fallback to first
  }

  /// 设置当前教材
  void setCurrentTextbook(String? id) {
    if (id == null) {
      _currentTextbook = null;
      _currentChapter = null;
      _currentArticle = null;
    } else {
      _currentTextbook = _textbooks.firstWhere((t) => t.id == id, orElse: () =>
          _textbooks.first);
      _currentChapter = null;
      _currentArticle = null;
    }
    notifyListeners();
  }

  /// ========== 章节操作 ==========

  /// 添加章节到教材
  Chapter addChapter(String textbookId, {required String title}) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapter = Chapter(
      id: IdGenerator.generate('ch'),
      title: title,
      order: textbook.chapters.length,
    );
    textbook.chapters.add(chapter);
    updateTextbook(textbook);
    return chapter;
  }

  /// 更新章节
  void updateChapter(String textbookId, Chapter chapter) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final index = textbook.chapters.indexWhere((c) => c.id == chapter.id);
    if (index != -1) {
      textbook.chapters[index] = chapter;
      updateTextbook(textbook);
    }
  }

  /// 删除章节
  void deleteChapter(String textbookId, String chapterId) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    textbook.chapters.removeWhere((c) => c.id == chapterId);
    // 重新排序
    for (var i = 0; i < textbook.chapters.length; i++) {
      textbook.chapters[i] = textbook.chapters[i].copyWith(order: i);
    }
    updateTextbook(textbook);
  }

  /// 移动章节位置
  void moveChapter(String textbookId, int oldIndex, int newIndex) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapters = textbook.sortedChapters;
    if (oldIndex < 0 || oldIndex >= chapters.length) return;
    if (newIndex < 0 || newIndex >= chapters.length) return;

    final chapter = chapters.removeAt(oldIndex);
    chapters.insert(newIndex, chapter);

    for (var i = 0; i < chapters.length; i++) {
      chapters[i] = chapters[i].copyWith(order: i);
    }

    textbook.chapters = chapters;
    updateTextbook(textbook);
  }

  /// 设置当前章节
  void setCurrentChapter(String? id) {
    if (id == null) {
      _currentChapter = null;
      _currentArticle = null;
    } else if (_currentTextbook != null) {
      _currentChapter = _currentTextbook!.chapters.firstWhere(
        (c) => c.id == id,
        orElse: () => _currentTextbook!.chapters.first,
      );
      _currentArticle = null;
    }
    notifyListeners();
  }

  /// ========== 文章操作 ==========

  /// 添加文章到章节
  Article addArticle(String textbookId, String chapterId,
      {required String title}) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapter = textbook.chapters.firstWhere(
      (c) => c.id == chapterId,
      orElse: () => throw Exception('Chapter not found'),
    );

    final article = Article(
      id: IdGenerator.generate('ar'),
      title: title,
      order: chapter.articles.length,
    );
    chapter.articles.add(article);
    updateTextbook(textbook);
    return article;
  }

  /// 更新文章
  void updateArticle(String textbookId, String chapterId, Article article) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapter = textbook.chapters.firstWhere(
      (c) => c.id == chapterId,
      orElse: () => throw Exception('Chapter not found'),
    );

    final index = chapter.articles.indexWhere((a) => a.id == article.id);
    if (index != -1) {
      chapter.articles[index] = article;
      updateTextbook(textbook);
    }
  }

  /// 删除文章
  void deleteArticle(String textbookId, String chapterId, String articleId) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapter = textbook.chapters.firstWhere(
      (c) => c.id == chapterId,
      orElse: () => throw Exception('Chapter not found'),
    );

    chapter.articles.removeWhere((a) => a.id == articleId);
    // 重新排序
    for (var i = 0; i < chapter.articles.length; i++) {
      chapter.articles[i] = chapter.articles[i].copyWith(order: i);
    }
    updateTextbook(textbook);
  }

  /// 移动文章位置
  void moveArticle(
      String textbookId, String chapterId, int oldIndex, int newIndex) {
    final textbook = getTextbook(textbookId);
    if (textbook == null) throw Exception('Textbook not found');

    final chapter = textbook.chapters.firstWhere(
      (c) => c.id == chapterId,
      orElse: () => throw Exception('Chapter not found'),
    );

    final articles = chapter.sortedArticles;
    if (oldIndex < 0 || oldIndex >= articles.length) return;
    if (newIndex < 0 || newIndex >= articles.length) return;

    final article = articles.removeAt(oldIndex);
    articles.insert(newIndex, article);

    for (var i = 0; i < articles.length; i++) {
      articles[i] = articles[i].copyWith(order: i);
    }

    chapter.articles = articles;
    updateTextbook(textbook);
  }

  /// 设置当前文章
  void setCurrentArticle(String? id) {
    if (id == null) {
      _currentArticle = null;
    } else if (_currentChapter != null) {
      _currentArticle = _currentChapter!.articles.firstWhere(
        (a) => a.id == id,
        orElse: () => _currentChapter!.articles.first,
      );
    }
    notifyListeners();
  }

  /// ========== TOC 生成 ==========

  /// 生成教材目录（TOC）数据
  List<TocEntry> generateToc(Textbook textbook) {
    final result = <TocEntry>[];
    final sorted = textbook.sortedChapters;

    for (var ci = 0; ci < sorted.length; ci++) {
      final chapter = sorted[ci];
      final chapterEntry = TocEntry(
        level: 0,
        title: chapter.title,
        targetId: chapter.id,
        targetType: TocTargetType.chapter,
        isFree: textbook.isChapterFree(ci),
      );
      result.add(chapterEntry);

      final sortedArticles = chapter.sortedArticles;
      for (var ai = 0; ai < sortedArticles.length; ai++) {
        final article = sortedArticles[ai];
        result.add(TocEntry(
          level: 1,
          title: article.title,
          targetId: article.id,
          targetType: TocTargetType.article,
          isFree: textbook.isChapterFree(ci),
        ));
      }
    }
    return result;
  }
}

/// TOC 目标类型
enum TocTargetType { chapter, article }

/// TOC 条目
class TocEntry {
  final int level; // 0 = 章节, 1 = 文章
  final String title;
  final String targetId;
  final TocTargetType targetType;
  final bool isFree;

  TocEntry({
    required this.level,
    required this.title,
    required this.targetId,
    required this.targetType,
    this.isFree = true,
  });
}
