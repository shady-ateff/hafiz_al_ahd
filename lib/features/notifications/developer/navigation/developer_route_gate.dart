import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/screens/adhan_catalog_developer_screen.dart';

/// Opens the developer catalog screen only if developer tools are active.
///
/// In Release builds, [isCatalogDeveloperToolsActive] is statically false,
/// enabling whole-program dead code elimination of this route and the screen.
void openDeveloperCatalogIfActive(BuildContext context) {
  if (isCatalogDeveloperToolsActive) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdhanCatalogDeveloperScreen(),
      ),
    );
  }
}

