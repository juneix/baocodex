import 'package:flutter/material.dart';

import '../../ui/widgets/image_gallery.dart';
import '../chat_models.dart';

/// Mobile bridge for the tool images the desktop shows beside and under a
/// step (`content_image.dart`/`image_thumbnails.dart`): the desktop reads
/// pictures the CLI saved on its disk too; the phone only has the bytes
/// that traveled the link, so [imageFiles] is ignored for now. The pager,
/// menus and pasteboard of the desktop thumbnails become a tap to open the
/// picture whole.
///
/// Where a message shows them (a user attachment, an image tool's find).
class StepThumbnails extends StatelessWidget {
  const StepThumbnails({super.key, required this.images, this.shown = true});

  final List<ImageAttachment> images;

  /// Small beside the step's line, bigger under it when it opens.
  final bool shown;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < images.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showWhole(context, i),
            child: _thumb(images[i], shown ? 44.0 : 76.0),
          ),
      ],
    );
  }

  Widget _thumb(ImageAttachment image, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.memory(
      image.bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.broken_image_outlined, size: size / 2),
      ),
    ),
  );

  void _showWhole(BuildContext context, int index) => showImageGallery(
    context,
    [for (final image in images) GalleryImage(image.bytes, name: image.name)],
    initialIndex: index,
  );
}

/// The pictures a tool returned, under its opened body.
class ToolImages extends StatelessWidget {
  const ToolImages({super.key, required this.images});

  final List<ImageAttachment> images;

  @override
  Widget build(BuildContext context) =>
      StepThumbnails(images: images, shown: false);
}

/// The pictures of a call, from its attachments; the CLI-saved files the
/// desktop reads back are not fetched yet (see above).
List<ImageAttachment> chatImagesOf(
  List<ImageAttachment> images,
  List<String> imageFiles,
) => images;
