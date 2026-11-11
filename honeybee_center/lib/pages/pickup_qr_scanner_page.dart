import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/auth_service.dart';
import '../services/supabase_data_service.dart';
import '../core/theme/app_theme.dart';
import '../core/permissions/admin_capabilities.dart';

class PickupQrScannerPage extends StatefulWidget {
  final AuthSession session;
  const PickupQrScannerPage({super.key, required this.session});

  @override
  State<PickupQrScannerPage> createState() => _PickupQrScannerPageState();
}

class _PickupQrScannerPageState extends State<PickupQrScannerPage> {
  final _supabaseDataService = SupabaseDataService();
  final _qrInputController = TextEditingController();

  // Camera controller — autoStart is false to avoid the web "already playing"
  // race condition in zxing-js. We call .start() ourselves one frame after
  // initState, which lets the <video> element fully settle before the
  // canplay listener fires. The user sees no visible difference.
  final MobileScannerController _cameraController = MobileScannerController(
    autoStart: false,
  );

  // ── Scanner state ──────────────────────────────────────────────────────────
  // 'Scanning'      : camera active, waiting for a QR code
  // 'Processing'    : QR detected, looking up the order
  // 'Order Found'   : valid order ready for pickup confirmation
  // 'Order Not Found' / error states : shown in verification panel
  // 'Pickup Confirmed' : pickup finalised
  // 'Restricted'    : role check failed
  String _scannerState = 'Scanning';
  Map<String, dynamic>? _scannedOrder;
  String? _scannedKey;
  bool _isLoading = false;
  bool _useManualInput = false;
  String? _cameraError;

  // Duplicate-scan guard — prevents the same QR code from being processed
  // twice while it remains in the camera's field of view.
  String? _lastScannedCode;

  @override
  void initState() {
    super.initState();
    if (!RoleCapabilities.forRole(widget.session.role).canConfirmPickup) {
      _scannerState = 'Restricted';
      // Restricted role — leave the camera stopped.
      return;
    }
    // Start the camera one frame after build so the <video> element is
    // fully attached to the DOM before zxing-js calls video.play().
    // This avoids the "Trying to play video that is already playing" warning
    // that occurs when autoStart fires before the canplay event has resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cameraController.start();
    });
  }

  @override
  void dispose() {
    _qrInputController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  // ── QR detection callback ──────────────────────────────────────────────────
  void _onQrDetected(BarcodeCapture capture) {
    // Ignore detections while loading or in a terminal state
    if (_isLoading) return;
    if (_scannerState != 'Scanning') return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!.trim();
    if (code.isEmpty) return;

    // Duplicate guard: skip if this is the same code we just processed
    if (code == _lastScannedCode) return;
    _lastScannedCode = code;

    // Pause scanning immediately so the same frame doesn't fire again
    _cameraController.stop();

    // Hand off to the lookup logic
    _lookupOrderReference(code);
  }

  void _onCameraError(Object error) {
    if (!mounted) return;
    setState(() {
      _cameraError =
          'Camera unavailable. Please grant camera permission or use manual input.';
      _useManualInput = true;
      _scannerState = 'Scanning'; // keep state neutral so manual input works
    });
  }

  // ── Order lookup ───────────────────────────────────────────────────────────
  Future<void> _lookupOrderReference(String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;

    setState(() {
      _isLoading = true;
      _scannerState = 'Processing';
    });

    try {
      final foundOrder = await _supabaseDataService.findOrderByReference(ref);

      // Small delay so the camera doesn't flash back too quickly
      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      if (foundOrder == null) {
        setState(() {
          _scannerState = 'Order Not Found';
          _scannedOrder = null;
          _scannedKey = null;
        });
      } else {
        final state =
            SupabaseDataService.pickupIneligibilityReason(foundOrder) ??
                'Order Found';

        setState(() {
          _scannerState = state;
          _scannedOrder = foundOrder;
          _scannedKey = foundOrder['id']?.toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[PickupQrScanner] Supabase order lookup failed: $e');
      setState(() {
        _scannerState = 'Lookup Failed';
        _scannedOrder = null;
        _scannedKey = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Confirm pickup ─────────────────────────────────────────────────────────
  Future<void> _confirmPickup() async {
    if (!RoleCapabilities.forRole(widget.session.role).canConfirmPickup ||
        _scannedKey == null ||
        _scannedOrder == null ||
        SupabaseDataService.pickupIneligibilityReason(_scannedOrder!) !=
            null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseDataService.confirmPickup(
        orderId: _scannedKey!,
        orderReference: _scannedOrder!['orderReference']?.toString() ?? '',
      );

      if (!mounted) return;
      setState(() {
        _scannerState = 'Pickup Confirmed';
        if (_scannedOrder != null) {
          _scannedOrder!['pickupStatus'] = 'Picked Up';
          _scannedOrder!['orderStatus'] = 'Completed';
          _scannedOrder!['inventoryDeducted'] = true;
          _scannedOrder!['productQtyDeducted'] = true;
          _scannedOrder!['pickedUpAt'] = DateTime.now().toUtc().toIso8601String();
          _scannedOrder!['pickedUpBy'] = widget.session.name;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup confirmed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('[PickupQrScanner] Supabase confirmPickup failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error confirming pickup: $e'),
            backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Reset / resume scanning ────────────────────────────────────────────────
  // Called after: cancel, dismiss, successful pickup confirmation.
  // Restores the scanner to its automatic scanning state.
  void _resetScanner() {
    setState(() {
      _scannerState = 'Scanning';
      _scannedOrder = null;
      _scannedKey = null;
      _lastScannedCode = null; // allow the same QR to be re-scanned
      _qrInputController.clear();
      _cameraError = null;
      _useManualInput = false;
    });
    _cameraController.start();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildScannerCard(isDark)),
                const SizedBox(width: 32),
                Expanded(flex: 1, child: _buildVerificationPanel(isDark)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final textColor =
        isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor =
        isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pickup QR Scanner',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textColor),
        ),
        const SizedBox(height: 4),
        Text(
          'Camera starts automatically. Scan a customer QR code or enter the reference manually.',
          style: TextStyle(color: subColor, fontSize: 13),
        ),
      ],
    );
  }

  // ── Scanner card ───────────────────────────────────────────────────────────
  Widget _buildScannerCard(bool isDark) {
    // Restricted view for Owner
    if (!RoleCapabilities.forRole(widget.session.role).canConfirmPickup) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _scannerCardHeader(),
              const SizedBox(height: 16),
              Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A141D)
                      : const Color(0xFFFBE4E4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF6B2530)
                          : const Color(0xFFEFC2C2)),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 64, color: Colors.redAccent),
                      SizedBox(height: 16),
                      Text('Access Restricted',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent)),
                      SizedBox(height: 8),
                      Text(
                        'QR scanner is available for Co-Admins only.\n'
                        'Owner can view pickup info but cannot process pickups.',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal Co-Admin view
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _scannerCardHeader(),
            const SizedBox(height: 8),
            Text(
              'Position the customer QR code inside the frame. '
              'The camera scans automatically.',
              style: TextStyle(
                  color: isDark
                      ? AppTheme.subtitleDark(isDark)
                      : AppTheme.subtitleLight(isDark),
                  fontSize: 13),
            ),
            const SizedBox(height: 20),
            // Camera view or manual input fallback
            if (_useManualInput || _cameraError != null)
              _buildManualInputMode(isDark)
            else
              _buildCameraScanner(isDark),
            const SizedBox(height: 24),
            // Manual reference field — always visible as a backup
            Text('Manual Reference Lookup',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.textDark
                        : AppTheme.textLight)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qrInputController,
                    decoration: InputDecoration(
                      hintText: 'e.g. HB-20261013-ABCD',
                      filled: true,
                      fillColor: AppTheme.fieldFill(isDark),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: isDark
                                  ? AppTheme.borderDarkAlt
                                  : AppTheme.borderLight)),
                    ),
                    onSubmitted: (v) {
                      _lastScannedCode = null; // allow manual retry
                      _cameraController.stop();
                      _lookupOrderReference(v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14)),
                  onPressed: _isLoading
                      ? null
                      : () {
                          _lastScannedCode = null;
                          _cameraController.stop();
                          _lookupOrderReference(
                              _qrInputController.text);
                        },
                  child: const Text('Lookup',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
              onPressed: _resetScanner,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Scan Next Customer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scannerCardHeader() {
    return Row(
      children: const [
        Icon(Icons.qr_code_scanner_rounded,
            color: AppTheme.primaryGold, size: 26),
        SizedBox(width: 12),
        Text('QR Code Scanner',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ],
    );
  }

  // ── Live camera view ───────────────────────────────────────────────────────
  Widget _buildCameraScanner(bool isDark) {
    // Status label changes depending on whether we are scanning or processing.
    final bool isProcessing =
        _scannerState == 'Processing' || _isLoading;
    final String statusLabel = isProcessing
        ? 'Processing — please wait…'
        : 'Camera Active — Scanning Automatically';
    final Color statusColor =
        isProcessing ? AppTheme.warning : AppTheme.accentGreen;

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        children: [
          // ── Camera preview ───────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _cameraController,
              onDetect: _onQrDetected,
              errorBuilder: (context, error, child) {
                // Schedule the state change outside the build phase
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _onCameraError(error);
                });
                return _buildCameraErrorView(isDark);
              },
            ),
          ),

          // ── Scanning frame decoration ────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: AppTheme.primaryGold, width: 2.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.white70, width: 1.8),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // ── Loading overlay (while processing a detected code) ───────
          if (isProcessing)
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primaryGold),
              ),
            ),

          // ── Status label at the bottom ───────────────────────────────
          if (!isProcessing)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Switch-to-manual keyboard button ────────────────────────
          Positioned(
            top: 10,
            right: 10,
            child: Tooltip(
              message: 'Switch to manual input',
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() => _useManualInput = true);
                    _cameraController.stop();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.keyboard,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual input fallback ──────────────────────────────────────────────────
  Widget _buildManualInputMode(bool isDark) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF111111)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGold, width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.keyboard_rounded,
                size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _cameraError ?? 'Manual Input Mode Active',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _useManualInput = false;
                  _cameraError = null;
                  _lastScannedCode = null;
                });
                _cameraController.start();
              },
              icon: const Icon(Icons.camera_alt_rounded,
                  size: 16),
              label: const Text('Switch to Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraErrorView(bool isDark) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF111111)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent, width: 2),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined,
                size: 56, color: Colors.redAccent),
            SizedBox(height: 16),
            Text(
              'Camera access denied or unavailable.',
              style: TextStyle(
                  color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'Please grant camera permission or use manual input.',
              style: TextStyle(
                  color: Colors.white60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Verification panel (right column) ─────────────────────────────────────
  Widget _buildVerificationPanel(bool isDark) {
    final textColor =
        isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor =
        isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Verification',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textColor)),
                _buildStateBadge(_scannerState),
              ],
            ),
            const Divider(height: 32),
            if (_scannedOrder == null) ...[
              const SizedBox(height: 60),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 48, color: subColor),
                    const SizedBox(height: 16),
                    Text('No order scanned yet.',
                        style: TextStyle(
                            color: subColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      'Scan a QR code or enter an order reference.',
                      style: TextStyle(
                          color: subColor, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ] else ...[
              _infoRow(isDark, 'Order Reference',
                  _scannedOrder!['orderReference'] ??
                      _scannedKey ??
                      'N/A'),
              _infoRow(isDark, 'Customer Name',
                  _scannedOrder!['customerName'] ?? 'N/A'),
              _infoRow(isDark, 'Contact Phone',
                  _scannedOrder!['customerPhone'] ?? 'N/A'),
              _infoRow(isDark, 'Email Address',
                  _scannedOrder!['customerEmail'] ?? 'N/A'),
              _infoRow(isDark, 'Payment Status',
                  _scannedOrder!['paymentStatus'] ?? 'Unpaid'),
              _infoRow(isDark, 'Pickup Status',
                  _scannedOrder!['pickupStatus'] ?? 'Pending'),
              _infoRow(
                  isDark,
                  'Total Amount',
                  '₱${_number(_scannedOrder!['total'] ?? _scannedOrder!['amount']).toStringAsFixed(2)}'),
              const SizedBox(height: 20),
              Text('Ordered Items:',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: textColor)),
              ...((_scannedOrder!['itemList'] as List?) ??
                  (_scannedOrder!['items'] is List
                      ? _scannedOrder!['items'] as List
                      : (_scannedOrder!['items'] is Map
                          ? (_scannedOrder!['items'] as Map).values.toList()
                          : []))).map((item) {
                final itm =
                    Map<String, dynamic>.from(item as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${itm['product'] ?? itm['productName'] ?? 'Honey'}'
                          ' (${itm['size'] ?? '-'})'
                          ' ×${itm['quantity'] ?? 1}',
                          style: TextStyle(
                              fontSize: 13, color: textColor),
                        ),
                      ),
                      Text(
                          '₱${_number(itm['price'] ?? 0).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 28),
              // ── Action buttons ───────────────────────────────────────
              if (_scannerState == 'Order Found')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoading ? null : _confirmPickup,
                  child: const Text('Confirm Pickup',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                )
              else if (_scannerState == 'Pickup Confirmed') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F2F1C)
                        : const Color(0xFFE2F6E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF1E5530)
                            : const Color(0xFFB8E2C4)),
                  ),
                  child: const Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.green),
                      SizedBox(width: 8),
                      Text('Pickup Successfully Confirmed',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // After confirmation, offer to scan the next customer
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize:
                          const Size(double.infinity, 44)),
                  onPressed: _resetScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded,
                      size: 16),
                  label: const Text('Scan Next Customer'),
                ),
              ] else ...[
                // Error / ineligible state banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3A141D)
                        : const Color(0xFFFBE4E4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF6B2530)
                            : const Color(0xFFEFC2C2)),
                  ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Cannot Confirm: $_scannerState',
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Let the Co-Admin scan a different order
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize:
                          const Size(double.infinity, 44)),
                  onPressed: _resetScanner,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 16),
                  label: const Text('Scan Again'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _infoRow(bool isDark, String label, String value) {
    final subColor =
        isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final textColor =
        isDark ? AppTheme.textDark : AppTheme.textLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: subColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: textColor)),
        ],
      ),
    );
  }

  Widget _buildStateBadge(String state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine semantic colour from state string without using .value
    Color color;
    if (state == 'Scanning' || state == 'Order Found') {
      color = Colors.blue;
    } else if (state == 'Processing') {
      color = AppTheme.primaryGold;
    } else if (state == 'Pickup Confirmed') {
      color = Colors.green;
    } else if (state.contains('Not') ||
        state.contains('Failed') ||
        state.contains('Cancelled') ||
        state.contains('Already') ||
        state.contains('Restricted')) {
      color = Colors.red;
    } else {
      color = Colors.grey;
    }

    Color bgColor;
    if (color == Colors.blue) {
      bgColor = isDark
          ? const Color(0xFF1A3260)
          : const Color(0xFFE0ECFA);
    } else if (color == Colors.green) {
      bgColor = isDark
          ? const Color(0xFF0F2F1C)
          : const Color(0xFFE2F6E8);
    } else if (color == Colors.red) {
      bgColor = isDark
          ? const Color(0xFF3A141D)
          : const Color(0xFFFBE4E4);
    } else if (color == AppTheme.primaryGold) {
      bgColor = isDark
          ? AppTheme.iconBadgeGoldDark
          : AppTheme.iconBadgeGoldLight;
    } else {
      bgColor = isDark
          ? const Color(0xFF2A2620)
          : const Color(0xFFF2F0EC);
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        state,
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800),
      ),
    );
  }

  double _number(Object? value, {num fallback = 0}) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ??
          fallback.toDouble();
}
