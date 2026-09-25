import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'force_update_client.dart';

class ForceUpdateWidget extends StatefulWidget {
  const ForceUpdateWidget({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.forceUpdateClient,
    required this.allowCancel,
    required this.showForceUpdateAlert,
    required this.showStoreListing,
    this.onException,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final ForceUpdateClient forceUpdateClient;
  final bool allowCancel;
  final Future<bool?> Function(BuildContext context, bool allowCancel)
      showForceUpdateAlert;
  final Future<void> Function(Uri storeUrl) showStoreListing;
  final void Function(Object error, StackTrace? stackTrace)? onException;

  @override
  State<ForceUpdateWidget> createState() => _ForceUpdateWidgetState();
}

class _ForceUpdateWidgetState extends State<ForceUpdateWidget>
    with WidgetsBindingObserver {
  // * True from the start of a check until its alert is dismissed, so a check
  // * triggered while another is still fetching (e.g. the initial check and
  // * an app resume) can't show a second alert on top of the first
  var _isCheckInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // * Use post-frame callback to ensure Navigator is fully initialized
    // * This fixes timing issues with Sentry and other wrapper packages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfAppUpdateIsNeeded();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIfAppUpdateIsNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkIfAppUpdateIsNeeded() async {
    if (_isCheckInProgress) {
      return;
    }
    _isCheckInProgress = true;
    try {
      final storeUrl = await widget.forceUpdateClient.storeUrl();
      if (storeUrl == null) {
        return;
      }
      final updateRequired =
          await widget.forceUpdateClient.isAppUpdateRequired();
      if (updateRequired) {
        return await _triggerForceUpdate(Uri.parse(storeUrl));
      }
    } catch (e, st) {
      final handler = widget.onException;
      if (handler != null) {
        handler.call(e, st);
      } else {
        rethrow;
      }
    } finally {
      _isCheckInProgress = false;
    }
  }

  Future<void> _triggerForceUpdate(Uri storeUrl) async {
    // * Wait for the Navigator to be available. It can take a while: a router
    // * with an async redirect builds no Navigator until the redirect resolves.
    // * Never fall back to this widget's own context: it sits above the
    // * Navigator, so showing a dialog from it throws
    while (widget.navigatorKey.currentContext == null) {
      if (!mounted) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final success = await widget.showForceUpdateAlert(
        widget.navigatorKey.currentContext!, widget.allowCancel);
    if (success == true) {
      // * open app store page
      await widget.showStoreListing(storeUrl);
    } else if (success == false) {
      // * user clicked on the cancel button
    } else if (success == null && widget.allowCancel == false) {
      // * user clicked on the Android back button: show alert again
      return _triggerForceUpdate(storeUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// ignore_for_file: use_build_context_synchronously
