import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/site_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/dropdown_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import 'site_details_screen.dart';
import 'site_customization_screen.dart';

/// Admin screen for creating and managing construction sites
class ManageSitesScreen extends ConsumerStatefulWidget {
  const ManageSitesScreen({super.key});

  @override
  ConsumerState<ManageSitesScreen> createState() => _ManageSitesScreenState();
}

class _ManageSitesScreenState extends ConsumerState<ManageSitesScreen> {
  void _showCreateSiteDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final loginIdController = TextEditingController();
    final passwordController = TextEditingController();
    final budgetController = TextEditingController(text: '0');
    final extraVendorsController = TextEditingController();
    final extraProductsController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool seedStandardDropdowns = true;
    bool showExtraDropdownOptions = false;
    bool isCreating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          title: Text(
            'Create New Construction Site',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BASIC SITE CREDENTIALS',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: nameController,
                    validator: (v) => Validators.required(v, 'Site Name'),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Site Name',
                      prefixIcon: Icon(Icons.business_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Location / Address',
                      prefixIcon: Icon(Icons.place_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: loginIdController,
                    validator: (v) => Validators.required(v, 'Login ID'),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Site Login ID',
                      prefixIcon: Icon(Icons.badge_rounded),
                      helperText: 'Unique ID for site workers to sign in',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: budgetController,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Must be a number';
                      return null;
                    },
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Allocated Budget (₹)',
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    validator: Validators.password,
                    obscureText: true,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Site Worker Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Dropdowns & Customization Option
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: seedStandardDropdowns,
                          activeColor: AppColors.primary,
                          title: Text(
                            'Initialize with Standard Dropdowns',
                            style: AppTextStyles.labelMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          subtitle: Text(
                            'Adds standard cement, steel, bricks, vendors, units & expense categories for this site.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                          onChanged: (val) {
                            setDialogState(
                                () => seedStandardDropdowns = val ?? true);
                          },
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() => showExtraDropdownOptions =
                                !showExtraDropdownOptions);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  showExtraDropdownOptions
                                      ? 'Hide initial custom items ▲'
                                      : 'Add initial site-specific items now ▼',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showExtraDropdownOptions) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: extraVendorsController,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Initial Vendors (comma separated)',
                              hintText: 'e.g. Verma Traders, Ganga Sand Depot',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: extraProductsController,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Initial Materials (comma separated)',
                              hintText: 'e.g. RMC 30, Fly Ash Bricks',
                              isDense: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(dialogCtx),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: isCreating
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      setDialogState(() => isCreating = true);
                      final siteService = ref.read(siteServiceProvider);
                      final dropdownService = ref.read(dropdownServiceProvider);

                      try {
                        final newSite = await siteService.createSite(
                          name: nameController.text.trim(),
                          address: addressController.text.trim(),
                          loginId: loginIdController.text.trim(),
                          password: passwordController.text,
                          createdBy:
                              ref.read(authServiceProvider).currentUserId!,
                          allocatedBudget:
                              double.tryParse(budgetController.text) ?? 0.0,
                        );

                        // Seed dropdowns if requested
                        if (seedStandardDropdowns) {
                          final extraVendors = extraVendorsController.text
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();

                          final extraProducts = extraProductsController.text
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();

                          await dropdownService.seedDefaultDropdownsForSite(
                            newSite.id,
                            initialVendors:
                                extraVendors.isNotEmpty ? extraVendors : null,
                            initialProducts:
                                extraProducts.isNotEmpty ? extraProducts : null,
                          );
                        }

                        ref.invalidate(allSitesProvider);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);

                        // Prompt admin to customize now or edit anytime later
                        if (mounted) {
                          _showSiteCreatedSuccessSheet(newSite);
                        }
                      } catch (e) {
                        setDialogState(() => isCreating = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error creating site: $e'),
                              backgroundColor: AppColors.rejected,
                            ),
                          );
                        }
                      }
                    },
              child: isCreating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Site'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSiteCreatedSuccessSheet(SiteModel site) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.approvedSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppColors.approved, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Site Created!',
                          style: AppTextStyles.h3
                              .copyWith(color: AppColors.textPrimary)),
                      Text(
                        site.name,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Your site is live! You can customize its vendors, materials, units, budget, and credentials now, or edit it anytime from Manage Sites.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(bottomCtx),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.approved,
                      side: const BorderSide(color: AppColors.approved),
                    ),
                    onPressed: () {
                      Navigator.pop(bottomCtx);
                      _showAttendanceAreaDialog(site);
                    },
                    icon: const Icon(Icons.location_on_rounded, size: 16),
                    label: const Text('Set Area', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SiteCustomizationScreen(site: site),
                        ),
                      );
                    },
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Customize'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSiteDialog(SiteModel site) {
    final nameController = TextEditingController(text: site.name);
    final addressController = TextEditingController(text: site.address);
    final budgetController =
        TextEditingController(text: site.allocatedBudget.toString());
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Edit Site Details',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  validator: (v) => Validators.required(v, 'Site Name'),
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Site Name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: addressController,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: budgetController,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Must be a number';
                    return null;
                  },
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Allocated Budget'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.approved,
                      side: const BorderSide(color: AppColors.approved),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.location_on_rounded, size: 18),
                    label: const Text('Configure Attendance Area (Google Maps & GPS)'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showAttendanceAreaDialog(site);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final siteService = ref.read(siteServiceProvider);
              try {
                await siteService.updateSite(site.id, {
                  'name': nameController.text.trim(),
                  'address': addressController.text.trim(),
                  'allocated_budget':
                      double.tryParse(budgetController.text) ?? 0.0,
                });
                ref.invalidate(allSitesProvider);
                if (context.mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Site updated successfully!'),
                      backgroundColor: AppColors.approved,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.rejected,
                    ),
                  );
                }
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  /// Parses latitude and longitude from Google Maps URLs or "lat, lng" strings
  ({double lat, double lng})? _parseGoogleMapsLocation(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // Pattern 1: URL with query=lat,lng or q=lat,lng or daddr=lat,lng
    final qMatch = RegExp(
            r'[?&](?:query|q|daddr)=([+-]?\d+\.?\d*)[,\s]+([+-]?\d+\.?\d*)')
        .firstMatch(text);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1)!);
      final lng = double.tryParse(qMatch.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }

    // Pattern 2: URL with /@lat,lng,
    final atMatch =
        RegExp(r'@([+-]?\d+\.?\d*),([+-]?\d+\.?\d*)').firstMatch(text);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }

    // Pattern 3: Raw coordinates "lat, lng" or "lat,lng" or "lat lng"
    final coordMatch =
        RegExp(r'([+-]?\d+\.\d+)[,\s]+([+-]?\d+\.\d+)').firstMatch(text);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }

    return null;
  }

  /// Dialog to enter attendance area via Google Maps or current GPS
  void _showAttendanceAreaDialog(SiteModel site) async {
    final policy =
        await ref.read(attendanceServiceProvider).getShiftPolicy(site.id);

    final mapsInputController = TextEditingController(
      text: policy.latitude != null && policy.longitude != null
          ? '${policy.latitude!.toStringAsFixed(6)}, ${policy.longitude!.toStringAsFixed(6)}'
          : '',
    );
    final latController = TextEditingController(
      text: policy.latitude?.toStringAsFixed(6) ?? '',
    );
    final lngController = TextEditingController(
      text: policy.longitude?.toStringAsFixed(6) ?? '',
    );
    final radiusController = TextEditingController(
      text: policy.allowedRadiusMeters.toStringAsFixed(0),
    );

    bool isAcquiringGps = false;
    String? statusMessage;

    void updateFromInput(String text, StateSetter setDialogState) {
      final parsed = _parseGoogleMapsLocation(text);
      if (parsed != null) {
        setDialogState(() {
          latController.text = parsed.lat.toStringAsFixed(6);
          lngController.text = parsed.lng.toStringAsFixed(6);
          statusMessage =
              '✅ Extracted location: ${latController.text}, ${lngController.text}';
        });
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: AppColors.approved),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Attendance Area: ${site.name}',
                  style: AppTextStyles.h4,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Define the official location for ${site.name}. Staff marking attendance must be physically present within this radius area.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                // Button: 📍 Set to My Current Location
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.18),
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: isAcquiringGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(
                      isAcquiringGps
                          ? 'Acquiring GPS...'
                          : '📍 Set to My Current Location',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: isAcquiringGps
                        ? null
                        : () async {
                            setDialogState(() {
                              isAcquiringGps = true;
                              statusMessage = null;
                            });

                            final result = await LocationService
                                .getCurrentLocationDetailed();

                            setDialogState(() {
                              isAcquiringGps = false;
                              if (result.position != null) {
                                final lat = result.position!.latitude
                                    .toStringAsFixed(6);
                                final lng = result.position!.longitude
                                    .toStringAsFixed(6);
                                latController.text = lat;
                                lngController.text = lng;
                                mapsInputController.text = '$lat, $lng';
                                statusMessage =
                                    '✅ Set to your location: $lat, $lng (±${result.position!.accuracy.toStringAsFixed(0)}m accuracy)';
                              } else {
                                statusMessage =
                                    '⚠️ ${result.errorMessage ?? "Could not fetch GPS."}';
                              }
                            });
                          },
                  ),
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusMessage!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusMessage!.startsWith('✅')
                          ? AppColors.approved
                          : AppColors.rejected,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Google Maps link / coordinates input
                TextFormField(
                  controller: mapsInputController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Google Maps Link or Pin Coordinates',
                    hintText: 'e.g. 22.7196, 75.8577 or paste Google Maps URL',
                    prefixIcon: Icon(Icons.map_rounded),
                    helperText: 'Paste any Google Maps link or coordinates',
                  ),
                  onChanged: (val) => updateFromInput(val, setDialogState),
                ),
                const SizedBox(height: 12),

                // Lat & Lng fields
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: latController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: '22.719600',
                          prefixIcon: Icon(Icons.explore_outlined, size: 16),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: '75.857700',
                          prefixIcon: Icon(Icons.explore_outlined, size: 16),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Allowed Radius (meters)
                TextFormField(
                  controller: radiusController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Attendance Radius (Meters)',
                    hintText: '500',
                    prefixIcon: Icon(Icons.radar_rounded),
                    helperText:
                        'Perimeter circle within which punch is permitted',
                  ),
                ),
                const SizedBox(height: 8),

                // Quick Radius Chips
                Row(
                  children: [100, 250, 500, 1000].map((r) {
                    final isSel = radiusController.text == '$r';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('${r}m'),
                        backgroundColor: isSel
                            ? AppColors.primary.withOpacity(0.25)
                            : AppColors.cardDark,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: isSel
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            radiusController.text = '$r';
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Preview on Google Maps button
                if (latController.text.isNotEmpty &&
                    lngController.text.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Verify Location on Google Maps',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        final lat =
                            double.tryParse(latController.text.trim());
                        final lng =
                            double.tryParse(lngController.text.trim());
                        if (lat != null && lng != null) {
                          launchUrl(
                            Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final lat = double.tryParse(latController.text.trim());
                final lng = double.tryParse(lngController.text.trim());
                final radius =
                    double.tryParse(radiusController.text.trim()) ?? 500.0;

                final updated = policy.copyWith(
                  latitude: lat,
                  longitude: lng,
                  allowedRadiusMeters: radius,
                );

                await ref
                    .read(attendanceServiceProvider)
                    .saveShiftPolicy(updated);
                ref.invalidate(shiftPolicyForSiteProvider(site.id));

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Attendance area saved for ${site.name}!'),
                      backgroundColor: AppColors.approved,
                    ),
                  );
                }
              },
              child: const Text('Save Attendance Area'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(allSitesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            const Text('Manage Sites'),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: LanguageToggleButton(isCompact: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSiteDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Site'),
      ),
      body: sitesAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sites) => sites.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_city_outlined,
                        color: AppColors.textTertiary, size: 52),
                    const SizedBox(height: 14),
                    Text('No sites yet. Tap + to create one.',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final site = sites[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider, width: 0.5),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SiteDetailsScreen(site: site),
                              ),
                            );
                          },
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: site.isHeadOffice ? AppColors.primary : null,
                                    gradient: site.isHeadOffice ? null : AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    site.isHeadOffice ? Icons.apartment_rounded : Icons.construction,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              site.name,
                                              style: AppTextStyles.labelLarge
                                                  .copyWith(color: AppColors.textPrimary),
                                            ),
                                          ),
                                          if (site.isHeadOffice) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Office Attendance Only',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        site.isHeadOffice
                                            ? 'Login ID: ${site.siteLoginId} • Head Office (Staff Attendance & Executive Tracking)'
                                            : 'Login ID: ${site.siteLoginId} • Budget: ₹${site.allocatedBudget.toStringAsFixed(0)}',
                                        style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textTertiary),
                                      ),
                                      const SizedBox(height: 6),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final policyAsync = ref.watch(shiftPolicyForSiteProvider(site.id));
                                          final policy = policyAsync.valueOrNull;
                                          final hasArea = policy?.latitude != null && policy?.longitude != null;

                                          return InkWell(
                                            onTap: () => _showAttendanceAreaDialog(site),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: hasArea
                                                    ? AppColors.approved.withOpacity(0.12)
                                                    : AppColors.pending.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: hasArea
                                                      ? AppColors.approved.withOpacity(0.3)
                                                      : AppColors.pending.withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    hasArea ? Icons.location_on_rounded : Icons.add_location_alt_rounded,
                                                    size: 13,
                                                    color: hasArea ? AppColors.approved : AppColors.pending,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    hasArea
                                                        ? 'Attendance Area: ${policy!.latitude!.toStringAsFixed(4)}, ${policy.longitude!.toStringAsFixed(4)} (${policy.allowedRadiusMeters.toStringAsFixed(0)}m radius)'
                                                        : 'Enter Attendance Area (Google Maps & GPS)',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: hasArea ? AppColors.approved : AppColors.pending,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                // Status
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: site.isActive
                                        ? AppColors.approvedSurface
                                        : AppColors.rejectedSurface,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    site.isActive ? 'Active' : 'Inactive',
                                    style: AppTextStyles.caption.copyWith(
                                      color: site.isActive
                                          ? AppColors.approved
                                          : AppColors.rejected,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                PopupMenuButton<String>(
                                  color: AppColors.cardDark,
                                  onSelected: (val) async {
                                    final siteService =
                                        ref.read(siteServiceProvider);
                                    if (val == 'attendance_area') {
                                      _showAttendanceAreaDialog(site);
                                    } else if (val == 'customize') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              SiteCustomizationScreen(
                                                  site: site),
                                        ),
                                      );
                                    } else if (val == 'edit_basic') {
                                      _showEditSiteDialog(site);
                                    } else if (val == 'deactivate') {
                                      await siteService.deactivateSite(site.id);
                                      ref.invalidate(allSitesProvider);
                                    } else if (val == 'activate') {
                                      await siteService.activateSite(site.id);
                                      ref.invalidate(allSitesProvider);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'attendance_area',
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on_rounded,
                                              size: 18,
                                              color: AppColors.approved),
                                          SizedBox(width: 8),
                                          Text('Enter Attendance Area (GPS)',
                                              style: TextStyle(
                                                  color: AppColors.approved,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'customize',
                                      child: Row(
                                        children: [
                                          Icon(Icons.tune_rounded,
                                              size: 18,
                                              color: AppColors.primary),
                                          SizedBox(width: 8),
                                          Text('Customize Site & Dropdowns',
                                              style: TextStyle(
                                                  color: AppColors.primary)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit_basic',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined,
                                              size: 18,
                                              color: AppColors.textSecondary),
                                          SizedBox(width: 8),
                                          Text('Edit Basic Details'),
                                        ],
                                      ),
                                    ),
                                    if (site.isActive)
                                      const PopupMenuItem(
                                        value: 'deactivate',
                                        child: Row(
                                          children: [
                                            Icon(Icons.block_rounded,
                                                size: 18,
                                                color: AppColors.rejected),
                                            SizedBox(width: 8),
                                            Text('Deactivate Site',
                                                style: TextStyle(
                                                    color: AppColors.rejected)),
                                          ],
                                        ),
                                      )
                                    else
                                      const PopupMenuItem(
                                        value: 'activate',
                                        child: Row(
                                          children: [
                                            Icon(Icons.check_circle_outline,
                                                size: 18,
                                                color: AppColors.approved),
                                            SizedBox(width: 8),
                                            Text('Activate Site',
                                                style: TextStyle(
                                                    color: AppColors.approved)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                        // Direct Quick Action Bar on Card
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SiteDetailsScreen(site: site),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.analytics_outlined,
                                    size: 16),
                                label: const Text('Overview & History'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SiteCustomizationScreen(site: site),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.tune_rounded, size: 16),
                                label: const Text('Customize Site'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppColors.primary.withOpacity(0.15),
                                  foregroundColor: AppColors.primary,
                                  elevation: 0,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(
                        delay: Duration(milliseconds: 50 * index),
                      );
                },
              ),
      ),
    );
  }
}
