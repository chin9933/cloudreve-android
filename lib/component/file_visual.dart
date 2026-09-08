import 'package:cloudreve/entity/m_file.dart';
import 'package:flutter/material.dart';

class FileVisualData {
  const FileVisualData(this.icon, this.foreground, this.background);

  final IconData icon;
  final Color foreground;
  final Color background;
}

FileVisualData fileVisualFor(MFile file) {
  if (file.type == 'dir') {
    return const FileVisualData(
      Icons.folder_rounded,
      Color(0xFF2683FF),
      Color(0xFFE7F2FF),
    );
  }
  final name = file.name.toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|bmp|webp)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.image_rounded,
      Color(0xFF31B46D),
      Color(0xFFE7F8EF),
    );
  }
  if (name.endsWith('.pdf')) {
    return const FileVisualData(
      Icons.picture_as_pdf_rounded,
      Color(0xFFEF4455),
      Color(0xFFFFE9EC),
    );
  }
  if (RegExp(r'\.(doc|docx|odt)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.description_rounded,
      Color(0xFF246CE0),
      Color(0xFFE7F0FF),
    );
  }
  if (RegExp(r'\.(xls|xlsx|csv)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.table_chart_rounded,
      Color(0xFF18A760),
      Color(0xFFE5F8ED),
    );
  }
  if (RegExp(r'\.(ppt|pptx)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.slideshow_rounded,
      Color(0xFFFF8C31),
      Color(0xFFFFF0E4),
    );
  }
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.archive_rounded,
      Color(0xFFF59B24),
      Color(0xFFFFF2DE),
    );
  }
  if (RegExp(r'\.(mp4|avi|mov|mkv|wmv|flv|webm)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.play_arrow_rounded,
      Color(0xFF8B5CF6),
      Color(0xFFF0E9FF),
    );
  }
  if (RegExp(r'\.(mp3|wav|flac|aac|m4a|ogg)$').hasMatch(name)) {
    return const FileVisualData(
      Icons.music_note_rounded,
      Color(0xFFEA4E9D),
      Color(0xFFFFE8F4),
    );
  }
  if (name.endsWith('.apk')) {
    return const FileVisualData(
      Icons.android_rounded,
      Color(0xFF31B46D),
      Color(0xFFE7F8EF),
    );
  }
  return const FileVisualData(
    Icons.insert_drive_file_rounded,
    Color(0xFF6F7C92),
    Color(0xFFEEF1F6),
  );
}

class FileIconBadge extends StatelessWidget {
  const FileIconBadge({
    super.key,
    required this.file,
    this.size = 48,
    this.iconSize,
  });

  final MFile file;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final visual = fileVisualFor(file);
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            visual.foreground.withValues(alpha: 0.16),
            theme.colorScheme.surface,
          )
        : visual.background;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        visual.icon,
        color: visual.foreground,
        size: iconSize ?? size * 0.56,
      ),
    );
  }
}
