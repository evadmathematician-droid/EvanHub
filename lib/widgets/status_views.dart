import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.inbox_outlined,
                size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Renders a database stream as a list, handling the loading / error / empty
/// states so feature screens stay small.
class StreamListView<T> extends StatelessWidget {
  const StreamListView({
    super.key,
    required this.stream,
    required this.itemBuilder,
    required this.emptyMessage,
    this.emptyIcon,
    this.padding = const EdgeInsets.all(16),
  });

  final Stream<List<T>> stream;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyMessage;
  final IconData? emptyIcon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(message: 'Could not load data.\n${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const LoadingView();
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyView(message: emptyMessage, icon: emptyIcon);
        }
        return ListView.builder(
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, i) => itemBuilder(context, items[i]),
        );
      },
    );
  }
}
