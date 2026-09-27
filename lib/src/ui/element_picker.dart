import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Something on screen the user pointed at while inspecting.
class PickedElement {
  /// Creates a picked element.
  const PickedElement({
    required this.rect,
    required this.kind,
    required this.texts,
    required this.imageUrls,
  });

  /// Where it is on screen, in global coordinates.
  final Rect rect;

  /// What it is, e.g. `Text` or `Image`.
  final String kind;

  /// The texts it shows.
  final List<String> texts;

  /// The URLs of the network images it shows.
  final List<String> imageUrls;

  /// Whether there's nothing to look up.
  bool get isEmpty => texts.isEmpty && imageUrls.isEmpty;

  /// A short description of its content.
  String get summary =>
      imageUrls.isNotEmpty && texts.isEmpty
          ? imageUrls.first
          : texts.take(3).join('  ·  ');
}

/// Finds what's under [globalPosition] in [root]'s subtree.
///
/// Picks the innermost text or image. If there's none, picks the innermost
/// box that isn't most of the screen, with the texts and images inside it.
PickedElement? pickElement(RenderBox root, Offset globalPosition) {
  final result = BoxHitTestResult();
  root.hitTest(result, position: root.globalToLocal(globalPosition));
  final boxes = [
    for (final entry in result.path)
      if (entry.target is RenderBox && (entry.target as RenderBox).hasSize)
        entry.target as RenderBox,
  ];
  if (boxes.isEmpty) return null;

  final screenArea = root.size.width * root.size.height;
  final target = boxes.firstWhere(
    (box) => _isContent(box),
    orElse:
        () => boxes.firstWhere(
          (box) => box.size.width * box.size.height < screenArea * 0.6,
          orElse: () => boxes.first,
        ),
  );

  final texts = <String>[];
  final imageUrls = <String>[];
  void collect(RenderObject object) {
    if (texts.length + imageUrls.length >= 30) return;
    final text = _textOf(object);
    if (text != null && text.isNotEmpty && !texts.contains(text)) {
      texts.add(text);
    }
    final url = _imageUrlOf(object);
    if (url != null && !imageUrls.contains(url)) imageUrls.add(url);
    object.visitChildren(collect);
  }

  collect(target);

  return PickedElement(
    rect: MatrixUtils.transformRect(
      target.getTransformTo(null),
      Offset.zero & target.size,
    ),
    kind: switch (target) {
      RenderParagraph() => 'Text',
      RenderEditable() => 'Text field',
      _ when _imageUrlOf(target) != null => 'Image',
      _ => 'Area',
    },
    texts: texts,
    imageUrls: imageUrls,
  );
}

bool _isContent(RenderBox box) =>
    box is RenderParagraph ||
    (box is RenderEditable && !box.obscureText) ||
    _imageUrlOf(box) != null;

String? _textOf(RenderObject object) =>
    switch (object) {
      RenderParagraph() => object.text.toPlainText(
        includeSemanticsLabels: false,
      ),
      // Never read what's typed into password fields.
      RenderEditable(obscureText: false) => object.text?.toPlainText(
        includeSemanticsLabels: false,
      ),
      _ => null,
    }?.trim();

String? _imageUrlOf(RenderObject object) {
  if (object is RenderDecoratedBox) {
    final decoration = object.decoration;
    if (decoration is BoxDecoration && decoration.image != null) {
      return _urlOf(decoration.image!.image);
    }
    return null;
  }
  if (object is! RenderImage) return null;

  // Only debug builds record which widget created a render object.
  final creator = object.debugCreator;
  if (creator is! DebugCreator) return null;
  String? url;
  var depth = 0;
  creator.element.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Image) {
      url = _urlOf(widget.image);
      return false;
    }
    return ++depth < 8;
  });
  return url;
}

String? _urlOf(ImageProvider provider) {
  if (provider is NetworkImage) return provider.url;
  if (provider is ResizeImage) return _urlOf(provider.imageProvider);
  // Other network image providers, such as cached_network_image's, also have
  // a `url`.
  try {
    final Object? url = (provider as dynamic).url;
    return url is String ? url : null;
  } catch (_) {
    return null;
  }
}
