import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/trusted_sender_item.dart';
import '../widgets/message_brief_item.dart';
import '../providers/message_provider.dart';
import '../../core/theme/app_colors.dart';
import 'businesses_page.dart';
import 'messages_from_sender_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _navigateToMessagesFromSender(String sender, BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesFromSenderPage(sender: sender),
      ),
    );
  }

  void _navigateToBusinesses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BusinessesPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch message events to trigger refresh
    ref.watch(messageEventStreamProvider);
    
    final messageBriefs = ref.watch(filteredMessageBriefsProvider(_searchQuery));
    final topSendersAsync = ref.watch(topSendersProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryBackground,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((255 * 0.3).round()),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search messages...',
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.white),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
              ),
              style: const TextStyle(color: AppColors.white),
            ),
          ),

          // Trusted Senders Horizontal List
          Container(
            height: 112,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: topSendersAsync.when(
              data: (senders) {
                final uniqueSenders = senders.toSet().toList();
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: uniqueSenders.length + 1, // +1 for "Add New"
                  itemBuilder: (context, index) {
                    if (index == uniqueSenders.length) {
                      return TrustedSenderItem(
                        businessName: 'Add New',
                        isAddNew: true,
                        onTap: () => _navigateToBusinesses(context),
                      );
                    }
                    return TrustedSenderItem(
                      businessName: uniqueSenders[index],
                      onTap: () => _navigateToMessagesFromSender(
                        uniqueSenders[index],
                        context,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.sekretessBlue),
                ),
              ),
              error: (error, stack) => const SizedBox.shrink(),
            ),
          ),

          const Divider(
            height: 1,
            color: AppColors.dividerColor,
          ),

          // Message Briefs List
          Expanded(
            child: messageBriefs.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(messageBriefsProvider);
                      ref.invalidate(topSendersProvider);
                    },
                    color: AppColors.sekretessBlue,
                    child: ListView.builder(
                      itemCount: messageBriefs.length,
                      itemBuilder: (context, index) {
                        final brief = messageBriefs[index];
                        return MessageBriefItem(
                          messageBrief: brief,
                          onTap: () => _navigateToMessagesFromSender(
                            brief.sender,
                            context,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a conversation or subscribe to businesses',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
