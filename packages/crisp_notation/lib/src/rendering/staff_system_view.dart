import 'dart:math' as math;

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [StaffSystem] — N notation staves stacked as one system, with
/// vertically aligned measures, barlines connected through the system, and
/// bracket/brace groups at the left. Generalizes [GrandStaffView].
///
/// Element taps report ids from any staff via [onElementTap]; keep ids unique
/// across the staves. Highlighting is repaint-only, like [StaffView].
///
/// With `layoutMode = SystemLayoutMode.singleLine` the whole document is
/// rendered as one continuous system (its natural, unbounded width) — put it
/// inside a `SingleChildScrollView(scrollDirection: Axis.horizontal)` for the
/// horizontal-scroll "piano roll" / 卷帘 pattern. A `staffSpace` value must
/// be provided in this mode (no auto-fit-to-width).
class StaffSystemView extends LeafRenderObjectWidget {
  /// The staves and their groups.
  final StaffSystem system;

  /// Colors and ergonomics.
  final CrispNotationTheme theme;

  /// Pixels per staff space; null fits the system to the available width.
  final double? staffSpace;

  /// Line-to-line vertical distance between adjacent staves, in staff spaces.
  final double staffGap;

  /// Whether to align simultaneous notes vertically across every staff of the
  /// system (cross-staff onset gridding). Single-voice staves only.
  final bool gridAlign;

  /// Whether to drop staves that hold only rests in this system (keeping at
  /// least one), the standard "hide empty staves" engraving option.
  final bool hideEmptyStaves;

  /// Ids painted in [CrispNotationTheme.highlightColor].
  final Set<String> highlightedIds;

  /// Called with the element id when the user taps an element.
  final void Function(String elementId)? onElementTap;

  /// How to layout the system into systems (lines).
  ///
  /// * [SystemLayoutMode.singleSystem] (default): the legacy behaviour —
  ///   render the whole `StaffSystem` on exactly one row with its natural
  ///   width, no line breaks, no horizontal justification. Good for short
  ///   examples, bracket tests, SATB staves, etc.
  /// * [SystemLayoutMode.wrapped]: line-break into multi-system rows at the
  ///   available width, stack them top→bottom, and justify non-final rows.
  /// * [SystemLayoutMode.singleLine]: never wrap; render every measure as
  ///   one continuous row. The view has its natural, possibly very wide
  ///   width — place it inside a `StaffSystemScrollView` or a horizontal
  ///   scrollable so the reader can pan through it.
  final SystemLayoutMode layoutMode;

  /// Gap between wrapped systems (lines), in staff spaces. Only used when
  /// [layoutMode] == [SystemLayoutMode.wrapped].
  final double systemGap;

  /// Paint every note with its pitch name as text below the staff.
  final bool showNoteNames;

  /// Append each note's octave to the [showNoteNames] overlay (e.g. F2).
  final bool showNoteOctaves;

  /// How [showNoteNames] spells each pitch (letter / German / solfège).
  final NoteNameStyle noteNameStyle;

  /// When true, tapping an element toggles its highlight on/off internally
  /// — no external [onElementTap] / [highlightedIds] wiring required.
  final bool tapToHighlight;

  /// Creates a staff-system view.
  const StaffSystemView({
    super.key,
    required this.system,
    this.theme = CrispNotationTheme.standard,
    this.staffSpace,
    this.staffGap = 4.0,
    this.gridAlign = true,
    this.hideEmptyStaves = false,
    this.highlightedIds = const {},
    this.onElementTap,
    this.layoutMode = SystemLayoutMode.singleSystem,
    this.systemGap = 8.0,
    this.showNoteNames = false,
    this.showNoteOctaves = false,
    this.noteNameStyle = NoteNameStyle.letter,
    this.tapToHighlight = false,
  });

  @override
  RenderStaffSystemView createRenderObject(BuildContext context) =>
      RenderStaffSystemView(
        system: system,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        gridAlign: gridAlign,
        hideEmptyStaves: hideEmptyStaves,
        highlightedIds: highlightedIds,
        layoutMode: layoutMode,
        systemGap: systemGap,
        showNoteNames: showNoteNames,
        showNoteOctaves: showNoteOctaves,
        noteNameStyle: noteNameStyle,
        tapToHighlight: tapToHighlight,
      )..onElementTap = onElementTap;

  @override
  void updateRenderObject(
      BuildContext context, RenderStaffSystemView renderObject) {
    renderObject
      ..system = system
      ..theme = theme
      ..staffSpace = staffSpace
      ..staffGap = staffGap
      ..gridAlign = gridAlign
      ..hideEmptyStaves = hideEmptyStaves
      ..highlightedIds = highlightedIds
      ..onElementTap = onElementTap
      ..layoutMode = layoutMode
      ..systemGap = systemGap
      ..showNoteNames = showNoteNames
      ..showNoteOctaves = showNoteOctaves
      ..noteNameStyle = noteNameStyle
      ..tapToHighlight = tapToHighlight;
  }
}

/// A [StaffSystemView] wrapped in a horizontal scroll container — the whole
/// score is one continuous row (single-line mode, no line breaks) and the
/// reader scrolls left/right to read through it (piano-roll / 卷帘 pattern).
///
/// One row holds the entire `StaffSystem`, which may be multi-staff (e.g.
/// a grand-staff piano layout, or piano + jianpu 弹唱谱). `staffSpace`
/// controls the zoom; it defaults to 8 so a three-staff system fits a phone
/// height and still has room to scroll horizontally.
class StaffSystemScrollView extends StatelessWidget {
  final StaffSystem system;
  final CrispNotationTheme theme;
  final double staffSpace;
  final double staffGap;
  final bool gridAlign;
  final bool hideEmptyStaves;
  final Set<String> highlightedIds;
  final void Function(String elementId)? onElementTap;

  /// Paint every note with its pitch name as text below the staff.
  final bool showNoteNames;

  /// Append each note's octave to the [showNoteNames] overlay (e.g. F2).
  final bool showNoteOctaves;

  /// How [showNoteNames] spells each pitch (letter / German / solfège).
  final NoteNameStyle noteNameStyle;

  /// When true, tapping an element toggles its highlight on/off internally.
  final bool tapToHighlight;

  /// How far the scroll controller starts (0 = first measure, null = start).
  final double? initialScrollOffset;

  /// Optional persistent scroll controller — pass one to control the scroll
  /// position programmatically (e.g. sync with a playback cursor).
  final ScrollController? controller;

  const StaffSystemScrollView({
    super.key,
    required this.system,
    this.theme = CrispNotationTheme.standard,
    this.staffSpace = 8,
    this.staffGap = 4.0,
    this.gridAlign = true,
    this.hideEmptyStaves = false,
    this.highlightedIds = const {},
    this.onElementTap,
    this.showNoteNames = false,
    this.showNoteOctaves = false,
    this.noteNameStyle = NoteNameStyle.letter,
    this.tapToHighlight = false,
    this.initialScrollOffset,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: controller,
      primary: controller == null,
      child: StaffSystemView(
        system: system,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        gridAlign: gridAlign,
        hideEmptyStaves: hideEmptyStaves,
        highlightedIds: highlightedIds,
        onElementTap: onElementTap,
        showNoteNames: showNoteNames,
        showNoteOctaves: showNoteOctaves,
        noteNameStyle: noteNameStyle,
        tapToHighlight: tapToHighlight,
        layoutMode: SystemLayoutMode.singleLine,
      ),
    );
  }
}

/// Render object behind [StaffSystemView].
class RenderStaffSystemView extends RenderBox {
  /// Creates the render object.
  RenderStaffSystemView({
    required StaffSystem system,
    required CrispNotationTheme theme,
    double? staffSpace,
    required double staffGap,
    required bool gridAlign,
    required bool hideEmptyStaves,
    required Set<String> highlightedIds,
    required SystemLayoutMode layoutMode,
    required double systemGap,
    required bool showNoteNames,
    required bool showNoteOctaves,
    required NoteNameStyle noteNameStyle,
    bool tapToHighlight = false,
  })  : _system = system,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _gridAlign = gridAlign,
        _hideEmptyStaves = hideEmptyStaves,
        _highlightedIds = highlightedIds,
        _layoutMode = layoutMode,
        _systemGap = systemGap,
        _showNoteNames = showNoteNames,
        _showNoteOctaves = showNoteOctaves,
        _noteNameStyle = noteNameStyle,
        _tapToHighlight = tapToHighlight {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  /// Space reserved at the left for brackets/braces, in staff spaces.
  static const double leftInset = 1.8;

  late final TapGestureRecognizer _tap;
  StaffSystemLayout? _layout;
  StaffSystemSystems? _systems;
  double _scale = 12;

  late final LayoutPainter _painter = LayoutPainter(
      theme: _theme, scale: _scale, highlightedIds: _highlightedIds);

  /// Called with the element id when the user taps an element.
  void Function(String elementId)? onElementTap;

  bool _tapToHighlight = false;

  /// When true, tapping an element toggles its highlight on/off without
  /// requiring an external [onElementTap] / [highlightedIds] wiring.
  bool get tapToHighlight => _tapToHighlight;
  set tapToHighlight(bool value) {
    if (_tapToHighlight == value) return;
    _tapToHighlight = value;
    if (!value) _highlightedIds.clear();
    markNeedsPaint();
  }

  StaffSystem _system;

  /// The staves and groups to render.
  StaffSystem get system => _system;
  set system(StaffSystem value) {
    if (value == _system) return;
    _system = value;
    markNeedsLayout();
  }

  CrispNotationTheme _theme;

  /// Colors and ergonomics.
  CrispNotationTheme get theme => _theme;
  set theme(CrispNotationTheme value) {
    if (value == _theme) return;
    final relayout = value.lineBoost != _theme.lineBoost ||
        value.musicFont != _theme.musicFont;
    _theme = value;
    _painter.theme = value;
    if (relayout) {
      markNeedsLayout();
    } else {
      _painter.clearCache();
      markNeedsPaint();
    }
  }

  double? _staffSpace;

  /// Pixels per staff space; null fits to width.
  double? get staffSpace => _staffSpace;
  set staffSpace(double? value) {
    if (value == _staffSpace) return;
    _staffSpace = value;
    markNeedsLayout();
  }

  double _staffGap;

  /// Line-to-line vertical distance between adjacent staves.
  double get staffGap => _staffGap;
  set staffGap(double value) {
    if (value == _staffGap) return;
    _staffGap = value;
    markNeedsLayout();
  }

  bool _gridAlign;

  /// Whether simultaneous notes align across every staff of the system.
  bool get gridAlign => _gridAlign;
  set gridAlign(bool value) {
    if (value == _gridAlign) return;
    _gridAlign = value;
    markNeedsLayout();
  }

  bool _hideEmptyStaves;

  /// Whether staves holding only rests are dropped from this system.
  bool get hideEmptyStaves => _hideEmptyStaves;
  set hideEmptyStaves(bool value) {
    if (value == _hideEmptyStaves) return;
    _hideEmptyStaves = value;
    markNeedsLayout();
  }

  Set<String> _highlightedIds;

  /// Ids painted in the highlight color.
  Set<String> get highlightedIds => _highlightedIds;
  set highlightedIds(Set<String> value) {
    if (value.length == _highlightedIds.length &&
        value.containsAll(_highlightedIds)) {
      return;
    }
    _highlightedIds = value;
    _painter.highlightedIds = value;
    markNeedsPaint();
  }

  SystemLayoutMode _layoutMode;

  /// Whether this render object wraps its score into multiple systems or
  /// lays the whole document out as a single continuous row.
  SystemLayoutMode get layoutMode => _layoutMode;
  set layoutMode(SystemLayoutMode value) {
    if (value == _layoutMode) return;
    _layoutMode = value;
    markNeedsLayout();
  }

  double _systemGap;

  /// Gap between wrapped systems (lines), in staff spaces. Only meaningful
  /// when [layoutMode] == [SystemLayoutMode.wrapped].
  double get systemGap => _systemGap;
  set systemGap(double value) {
    if (value == _systemGap) return;
    _systemGap = value;
    if (_layoutMode == SystemLayoutMode.wrapped) markNeedsLayout();
  }

  bool _showNoteNames;

  /// Paint every note with its pitch name as text below the staff.
  bool get showNoteNames => _showNoteNames;
  set showNoteNames(bool value) {
    if (value == _showNoteNames) return;
    _showNoteNames = value;
    markNeedsLayout();
  }

  bool _showNoteOctaves;

  /// Append each note's octave to the [showNoteNames] overlay (e.g. F2).
  bool get showNoteOctaves => _showNoteOctaves;
  set showNoteOctaves(bool value) {
    if (value == _showNoteOctaves) return;
    _showNoteOctaves = value;
    markNeedsLayout();
  }

  NoteNameStyle _noteNameStyle;

  /// How [showNoteNames] spells each pitch. Changes the overlay text, so
  /// triggers a relayout.
  NoteNameStyle get noteNameStyle => _noteNameStyle;
  set noteNameStyle(NoteNameStyle value) {
    if (value == _noteNameStyle) return;
    _noteNameStyle = value;
    markNeedsLayout();
  }

  /// The laid-out system (for tests / interaction geometry).
  StaffSystemLayout? get systemLayout => _layout;

  /// Pixel origin (where its own y=0 maps) of staff [i].
  Offset staffOrigin(int i) {
    final layout = _layout;
    if (layout == null) return Offset.zero;
    return Offset(
      leftInset * _scale,
      (layout.staffTop(i) - layout.top) * _scale,
    );
  }

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) return constraints.smallest;
    final settings = LayoutSettings(metadata: metadata);

    if (_layoutMode == SystemLayoutMode.wrapped) {
      // Wrapped: line-break into multi-system rows at the available width,
      // stack them top→bottom. `maxWidth` is in staff-spaces, so convert
      // constraints.maxWidth (pixels) → staff spaces.
      final double widthSpaces = constraints.hasBoundedWidth && _staffSpace != null
          ? constraints.maxWidth / _staffSpace!
          : (constraints.hasBoundedWidth ? constraints.maxWidth / 12 : 50000.0);
      final systems = layoutStaffSystemSystems(
        _system,
        settings,
        maxWidth: widthSpaces,
        layoutMode: SystemLayoutMode.wrapped,
        staffGap: _staffGap,
        gridAlign: _gridAlign,
        hideEmptyStaves: _hideEmptyStaves,
        showNoteNames: _showNoteNames,
        showNoteOctaves: _showNoteOctaves,
        noteNameStyle: _noteNameStyle,
      );
      _systems = systems;
      _layout = null;
      double rowWidthSpaces = 0;
      double totalHeight = 0;
      final systemGap = _systemGap;
      for (var i = 0; i < systems.systems.length; i++) {
        final w = systems.systems[i].layout.width + leftInset;
        if (w > rowWidthSpaces) rowWidthSpaces = w;
        totalHeight += systems.systems[i].layout.height;
        if (i > 0) totalHeight += systemGap;
      }
      if (rowWidthSpaces <= 0) rowWidthSpaces = widthSpaces;
      _scale = _staffSpace ??
          (constraints.hasBoundedWidth
              ? constraints.maxWidth / rowWidthSpaces
              : 12);
      _painter.scale = _scale;
      return constraints
          .constrain(Size(rowWidthSpaces * _scale, totalHeight * _scale));
    }

    // singleLine / singleSystem (legacy default): one layout, one row.
    final layout = layoutStaffSystem(
      _system,
      settings,
      staffGap: _staffGap,
      gridAlign: _gridAlign,
      hideEmptyStaves: _hideEmptyStaves,
      showNoteNames: _showNoteNames,
      showNoteOctaves: _showNoteOctaves,
      noteNameStyle: _noteNameStyle,
    );
    _layout = layout;
    _systems = null;
    final widthSpaces = layout.width + leftInset;
    _scale = _staffSpace ??
        (constraints.hasBoundedWidth ? constraints.maxWidth / widthSpaces : 12);
    _painter.scale = _scale;
    return constraints
        .constrain(Size(widthSpaces * _scale, layout.height * _scale));
  }

  @override
  void performLayout() => size = _measure(constraints);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  @override
  bool hitTestSelf(Offset position) => onElementTap != null;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent && onElementTap != null) {
      _tap.addPointer(event);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final id = elementIdAt(details.localPosition);
    if (id == null) return;
    if (_tapToHighlight) {
      // Always work on a mutable copy — the widget may pass a const {}
      // (unmodifiable set).  Creating a new Set per tap is negligible cost.
      final mutable = _highlightedIds.toSet();
      if (mutable.contains(id)) {
        mutable.remove(id);
      } else {
        mutable.add(id);
      }
      _highlightedIds = mutable;
      _painter.highlightedIds = mutable;
      markNeedsPaint();
    }
    onElementTap?.call(id);
  }

  /// The element id at [local] pixels, searching every staff.
  String? elementIdAt(Offset local) {
    final layout = _layout;
    if (layout != null) {
      return _hitTestOneLayout(layout, local);
    }
    final systems = _systems;
    if (systems == null) return null;
    final systemGap = _systemGap;
    var yCursor = 0.0;
    for (final sys in systems.systems) {
      final sysHeight = sys.layout.height * _scale;
      if (local.dy >= yCursor && local.dy <= yCursor + sysHeight) {
        return _hitTestOneLayout(sys.layout, local - Offset(0, yCursor));
      }
      yCursor += sysHeight + systemGap * _scale;
    }
    return null;
  }

  String? _hitTestOneLayout(StaffSystemLayout layout, Offset local) {
    for (var i = 0; i < layout.staves.length; i++) {
      final origin = _staffOriginForLayout(layout, i);
      final p = (local - origin) / _scale;
      for (final region in layout.staves[i].regions) {
        if (region.bounds.containsPoint(math.Point(p.dx, p.dy))) {
          return region.elementId;
        }
      }
    }
    return null;
  }

  /// Pixel origin (where its own y=0 maps) of staff [i] within a single
  /// [StaffSystemLayout] (no system-row offset applied yet).
  Offset _staffOriginForLayout(StaffSystemLayout layout, int i) {
    return Offset(
      leftInset * _scale,
      (layout.staffTop(i) - layout.top) * _scale,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout != null) {
      _paintOneLayout(context.canvas, offset, layout);
      return;
    }
    final systems = _systems;
    if (systems == null) return;
    final systemGap = _systemGap;
    var yCursor = 0.0;
    for (final sys in systems.systems) {
      _paintOneLayout(context.canvas, offset + Offset(0, yCursor), sys.layout);
      yCursor += sys.layout.height * _scale + systemGap * _scale;
    }
  }

  void _paintOneLayout(Canvas canvas, Offset offset, StaffSystemLayout layout) {
    final origins = [
      for (var i = 0; i < layout.staves.length; i++)
        offset + _staffOriginForLayout(layout, i),
    ];
    for (var i = 0; i < layout.staves.length; i++) {
      _painter.paintLayout(canvas, origins[i], layout.staves[i]);
    }
    if (layout.staves.length < 2) {
      _paintBracketsForLayout(canvas, origins, layout);
      return;
    }

    final barPaint = Paint()..color = _theme.staffColor;
    final refIdx = layout.source.staves
        .indexWhere((s) => s.staffType != StaffType.jianpu);
    final ref = (refIdx >= 0
            ? layout.staves[refIdx]
            : layout.staves.first)
        .primitives
        .whereType<LinePrimitive>();
    final startThickness = ref.isEmpty ? 0.13 : ref.first.thickness;
    final bars = <({double x, double thickness})>[
      (x: 0.0, thickness: startThickness),
      for (final line in ref)
        if (line.from.x == line.to.x &&
            ((line.from.y == 0 && line.to.y == 4) ||
                (line.from.y == 4 && line.to.y == 0)))
          (x: line.from.x, thickness: line.thickness),
    ];
    for (final group in layout.source.effectiveBarlineGroups) {
      if (group.first == group.last) continue;
      // 简谱组不画任何跨行纵线：行首不画连谱线（简谱纵线只收小节末尾），
      // 小节线也不跨行连接。
      if (_allJianpu(layout.source, group.first, group.last)) continue;
      final topY = origins[group.first].dy;
      final bottomY = origins[group.last].dy + 4 * _scale;
      for (final bar in bars) {
        final x = origins.first.dx + bar.x * _scale;
        canvas.drawLine(Offset(x, topY), Offset(x, bottomY),
            barPaint..strokeWidth = bar.thickness * _scale);
      }
    }
    _paintBracketsForLayout(canvas, origins, layout);
  }

  /// Whether every staff in [first]..[last] of [system] is jianpu.
  bool _allJianpu(StaffSystem system, int first, int last) {
    for (var i = first; i <= last; i++) {
      if (system.staves[i].staffType != StaffType.jianpu) return false;
    }
    return true;
  }

  /// How many other brackets strictly contain [b] — its nesting depth. Deeper
  /// (more-contained) groups sit nearer the staff; outer groups shift left.
  int _depthOf(StaffBracket b, List<StaffBracket> all) => all
      .where((a) =>
          !identical(a, b) &&
          a.first <= b.first &&
          b.last <= a.last &&
          (a.last - a.first) > (b.last - b.first))
      .length;

  void _paintBracketsForLayout(
      Canvas canvas, List<Offset> origins, StaffSystemLayout layout) {
    final brackets = layout.source.brackets;
    if (brackets.isEmpty) return;
    const step = 0.6;
    final maxDepth = brackets
        .map((b) => _depthOf(b, brackets))
        .fold(0, (m, d) => d > m ? d : m);
    for (final group in brackets) {
      final shift = (maxDepth - _depthOf(group, brackets)) * step * _scale;
      final isJianpuGroup =
          _allJianpu(layout.source, group.first, group.last);
      // 简谱行的连谱线纵程是数字墨盒（digitTop…digitBaseline，无谱线），
      // 连谱号联括该范围；标准谱行联括 y = 0..4。
      final top = origins[group.first].dy +
          (isJianpuGroup ? JianpuLayoutEngine.digitTop : 0) * _scale;
      final bottom = origins[group.last].dy +
          (isJianpuGroup ? JianpuLayoutEngine.digitBaseline : 4) * _scale;
      final x = origins.first.dx;
      // 简谱组的连谱号直接画在行首（不再先画跨行连谱线 —— 简谱纵线只收
      // 小节末尾）。
      if (group.kind == StaffBracketKind.brace) {
        final box =
            MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf('brace');
        if (box != null) {
          final span = layout.staffTop(group.last) +
              (isJianpuGroup ? JianpuLayoutEngine.digitBaseline : 4) -
              layout.staffTop(group.first) -
              (isJianpuGroup ? JianpuLayoutEngine.digitTop : 0);
          _painter.paintGlyph(
            canvas,
            Offset(x - shift, origins[group.last].dy),
            'brace',
            math.Point(-leftInset + 0.35,
                isJianpuGroup ? JianpuLayoutEngine.digitBaseline : 4.0),
            _theme.staffColor,
            glyphScale: span / box.height,
          );
        }
      } else if (isJianpuGroup) {
        // GB/T 46845-2025 §5.3.3 直连谱号: 一条粗纵线，两端各有一斜括
        // 向连谱线的短半弧括线（用于二人以上同时唱奏的两行以上曲谱）。
        final bx = x - 0.5 * _scale - shift;
        canvas.drawLine(
            Offset(bx, top),
            Offset(bx, bottom),
            Paint()
              ..color = _theme.staffColor
              ..strokeWidth = 0.4 * _scale);
        final hookPaint = Paint()
          ..color = _theme.staffColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.16 * _scale
          ..strokeCap = StrokeCap.round;
        final hookReach = 0.65 * _scale;
        final hookDrop = 0.45 * _scale;
        canvas.drawPath(
            Path()
              ..moveTo(bx, top)
              ..quadraticBezierTo(bx + hookReach * 0.55, top + hookDrop * 0.1,
                  bx + hookReach, top + hookDrop),
            hookPaint);
        canvas.drawPath(
            Path()
              ..moveTo(bx, bottom)
              ..quadraticBezierTo(
                  bx + hookReach * 0.55,
                  bottom - hookDrop * 0.1,
                  bx + hookReach,
                  bottom - hookDrop),
            hookPaint);
      } else {
        final bx = x - 0.5 * _scale - shift;
        final paint = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.4 * _scale;
        canvas.drawLine(Offset(bx, top), Offset(bx, bottom), paint);
        final serif = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.16 * _scale;
        canvas.drawLine(Offset(bx, top), Offset(bx + 0.6 * _scale, top), serif);
        canvas.drawLine(
            Offset(bx, bottom), Offset(bx + 0.6 * _scale, bottom), serif);
      }
    }
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}
