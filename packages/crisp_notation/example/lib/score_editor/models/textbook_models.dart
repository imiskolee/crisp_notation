import 'dart:convert';
import 'dart:math';

/// 文章 - 教材内容的最小单元
class Article {
  final String id;
  String title;
  String content;
  int order; // 在章节内的排序位置

  Article({
    required this.id,
    required this.title,
    this.content = '',
    this.order = 0,
  });

  Article copyWith({
    String? id,
    String? title,
    String? content,
    int? order,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'order': order,
    };
  }

  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String? ?? '',
      order: map['order'] as int? ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Article.fromJson(String source) =>
      Article.fromMap(json.decode(source) as Map<String, dynamic>);
}

/// 章节 - 包含多篇文章
class Chapter {
  final String id;
  String title;
  List<Article> articles;
  int order; // 在教材内的排序位置

  Chapter({
    required this.id,
    required this.title,
    this.articles = const [],
    this.order = 0,
  });

  /// 获取章节内的文章数量
  int get articleCount => articles.length;

  /// 按顺序获取排序后的文章列表
  List<Article> get sortedArticles => List<Article>.from(articles)
    ..sort((a, b) => a.order.compareTo(b.order));

  Chapter copyWith({
    String? id,
    String? title,
    List<Article>? articles,
    int? order,
  }) {
    return Chapter(
      id: id ?? this.id,
      title: title ?? this.title,
      articles: articles ?? List<Article>.from(this.articles),
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'articles': articles.map((x) => x.toMap()).toList(),
      'order': order,
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'] as String,
      title: map['title'] as String,
      articles: (map['articles'] as List<dynamic>?)
              ?.map((x) => Article.fromMap(x as Map<String, dynamic>))
              .toList() ??
          [],
      order: map['order'] as int? ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Chapter.fromJson(String source) =>
      Chapter.fromMap(json.decode(source) as Map<String, dynamic>);
}

/// 教材 - 包含多个章节
class Textbook {
  final String id;
  String title;
  String description;
  String coverImageUrl; // AI生成的封面图片URL
  bool isFree;
  int freeChapterCount; // 免费章节数量
  double price; // 价格（元）
  List<Chapter> chapters;
  DateTime createdAt;
  DateTime updatedAt;

  Textbook({
    required this.id,
    required this.title,
    this.description = '',
    this.coverImageUrl = '',
    this.isFree = false,
    this.freeChapterCount = 0,
    this.price = 0,
    this.chapters = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 获取教材的章节总数
  int get chapterCount => chapters.length;

  /// 获取教材的文章总数
  int get articleCount =>
      chapters.fold(0, (sum, chapter) => sum + chapter.articleCount);

  /// 判断某章节是否免费
  bool isChapterFree(int chapterIndex) {
    if (isFree) return true;
    return chapterIndex < freeChapterCount;
  }

  /// 按顺序获取排序后的章节列表
  List<Chapter> get sortedChapters => List<Chapter>.from(chapters)
    ..sort((a, b) => a.order.compareTo(b.order));

  Textbook copyWith({
    String? id,
    String? title,
    String? description,
    String? coverImageUrl,
    bool? isFree,
    int? freeChapterCount,
    double? price,
    List<Chapter>? chapters,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Textbook(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      isFree: isFree ?? this.isFree,
      freeChapterCount: freeChapterCount ?? this.freeChapterCount,
      price: price ?? this.price,
      chapters: chapters ?? List<Chapter>.from(this.chapters),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'isFree': isFree,
      'freeChapterCount': freeChapterCount,
      'price': price,
      'chapters': chapters.map((x) => x.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Textbook.fromMap(Map<String, dynamic> map) {
    return Textbook(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      coverImageUrl: map['coverImageUrl'] as String? ?? '',
      isFree: map['isFree'] as bool? ?? false,
      freeChapterCount: map['freeChapterCount'] as int? ?? 0,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      chapters: (map['chapters'] as List<dynamic>?)
              ?.map((x) => Chapter.fromMap(x as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Textbook.fromJson(String source) =>
      Textbook.fromMap(json.decode(source) as Map<String, dynamic>);
}

/// ID生成器
class IdGenerator {
  static final Random _random = Random();

  static String generate(String prefix) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _random.nextInt(9999).toString().padLeft(4, '0');
    return '${prefix}_${timestamp}_$random';
  }
}
