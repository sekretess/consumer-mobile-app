import 'package:flutter/material.dart';

import '../../data/models/message_brief_dto.dart';
import '../../core/theme/app_colors.dart';

class MessageBriefItem extends StatelessWidget {
  final MessageBriefDto messageBrief;
  final VoidCallback onTap;

  const MessageBriefItem({
    super.key,
    required this.messageBrief,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rawBody = messageBrief.messageBody;
    final isFile = rawBody.startsWith('{"kind":"file"');
    final messagePreview = isFile
        ? 'File'
        : rawBody.length > 130
            ? '${rawBody.substring(0, 130)}...'
            : rawBody;

    return InkWell(
      onTap: onTap,
      splashColor: AppColors.sekretessBlue.withAlpha((255 * 0.1).round()),
      highlightColor: AppColors.sekretessBlue.withAlpha((255 * 0.05).round()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildBusinessImage(context),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messageBrief.sender,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isFile) ...[
                        const Icon(
                          Icons.insert_drive_file_outlined,
                          size: 14,
                          color: AppColors.sekretessBlue,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          messagePreview,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessImage(BuildContext context) {
    // Try to load image from local storage
    // Note: In Flutter, we need to use path_provider to get the app directory
    // For now, just show placeholder - will be implemented with proper path handling
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cardBackground,
      ),
      child: Center(
        child: Text(
          messageBrief.sender.isNotEmpty 
              ? messageBrief.sender[0].toUpperCase() 
              : '?',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
