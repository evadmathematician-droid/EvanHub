import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/image_url.dart';
import '../../models/school.dart';
import '../../services/cloudinary_service.dart';
import '../../services/school_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

enum _ImageSlot { cover, badge }

/// The school's profile banner at the top of the dashboard: a wide cover photo
/// with the school badge, name and address over it. School admins can change
/// the cover photo and the badge from the camera button.
class SchoolHero extends StatefulWidget {
  const SchoolHero({super.key, required this.school});

  final School? school;

  @override
  State<SchoolHero> createState() => _SchoolHeroState();
}

class _SchoolHeroState extends State<SchoolHero> {
  bool _busy = false;

  Future<void> _change(_ImageSlot slot) async {
    final auth = context.read<AuthController>();
    final school = widget.school;
    if (school == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    final file = result.single;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final upload = await CloudinaryService().upload(
        bytes: bytes,
        fileName: file.name,
        folder: auth.tenant!.schoolProfileFolder,
      );
      final meta = slot == _ImageSlot.cover
          ? school.meta.copyWith(coverUrl: upload.url)
          : school.meta.copyWith(logoUrl: upload.url);
      await SchoolService().updateMeta(school.id, meta);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.read<AuthController>().role.canManageSchool;
    final meta = widget.school?.meta;
    final cover = meta?.coverUrl;
    final logo = meta?.logoUrl;
    final name = (meta?.name.isNotEmpty ?? false) ? meta!.name : 'Your school';
    final address = meta?.address ?? '';

    return SizedBox(
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null && cover.isNotEmpty)
            CachedNetworkImage(
              imageUrl: cloudinaryResized(cover, width: 1200),
              fit: BoxFit.cover,
              placeholder: (_, _) => const _HeroFallback(),
              errorWidget: (_, _, _) => const _HeroFallback(),
            )
          else
            const _HeroFallback(),

          // Scrim so the text stays readable over any photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.3, 1.0],
                colors: [Colors.transparent, Color(0xE61B1E66)],
              ),
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 8),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (logo != null && logo.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: cloudinaryResized(logo, width: 200),
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const Icon(Icons.school,
                              color: AppColors.primary, size: 30),
                        )
                      : const Icon(Icons.school,
                          color: AppColors.primary, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (canEdit)
            Positioned(
              top: 8,
              right: 8,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  : PopupMenuButton<_ImageSlot>(
                      tooltip: 'Change school images',
                      icon: const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black45,
                        child: Icon(Icons.photo_camera,
                            size: 16, color: Colors.white),
                      ),
                      onSelected: _change,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: _ImageSlot.cover,
                            child: Text('Change cover photo')),
                        PopupMenuItem(
                            value: _ImageSlot.badge,
                            child: Text('Change school badge')),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primaryLight],
        ),
      ),
    );
  }
}
