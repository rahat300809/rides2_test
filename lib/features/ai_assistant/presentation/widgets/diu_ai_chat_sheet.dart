import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/ai_assistant/data/ai_assistant_service.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';

class DiuAiChatSheet extends ConsumerStatefulWidget {
  const DiuAiChatSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const DiuAiChatSheet(),
    );
  }

  @override
  ConsumerState<DiuAiChatSheet> createState() => _DiuAiChatSheetState();
}

class _DiuAiChatSheetState extends ConsumerState<DiuAiChatSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiChatMessage> _messages = [];
  bool _isLoading = false;

  final List<Map<String, String>> _quickPromptChips = [
    {
      'label': '⬡ হেক্সাগন নিয়ারেস্ট বাইকার',
      'query': 'গুগল হেক্সাগন সিস্টেম ব্যবহার করে আমার গন্তব্যের সবচেয়ে কাছের সক্রিয় বাইকার সাজেস্ট করুন।',
    },
    {
      'label': '📍 নিকটবর্তী ড্রপিং জোন',
      'query': 'ক্যাম্পাস ও ঢাকার প্রধান রুটের সবচেয়ে কাছের ড্রপিং জোন এবং হাঁটার দূরত্ব কত?',
    },
    {
      'label': '💡 অ্যাপ গাইডলাইন',
      'query': 'ডিআইইউ রাইড অ্যাপটি কীভাবে ব্যবহার করব? সংক্ষেপে সম্পূর্ণ গাইডলাইন দিন।',
    },
    {
      'label': '🏍️ বাইকার খুঁজুন',
      'query': 'ক্যাম্পাসে যাওয়ার জন্য আশেপাশে সক্রিয় কোনো বাইকার ভাইয়া আছেন কি না খুঁজে দিন।',
    },
    {
      'label': '🎒 যাত্রী রিকোয়েস্ট',
      'query': 'কোনো শিক্ষার্থী ভাইয়া-আপু ক্যাম্পাসে যাওয়ার জন্য রাইড রিকোয়েস্ট করেছেন কি না জানান।',
    },
    {
      'label': '⏰ নির্দিষ্ট সময়ের ট্রিপ',
      'query': 'মিরপুর ১০ থেকে সকাল ৮:৩০ থেকে ৯:৩০ এর মধ্যে ক্যাম্পাসের দিকে কোনো রাইড আছে?',
    },
    {
      'label': '🛡️ নিরাপত্তা ও হেল্প',
      'query': 'জরুরি প্রয়োজনে এসওএস (SOS) ও ক্যাম্পাসের নিরাপত্তা ব্যবস্থা কীভাবে কাজ করে?',
    },
    {
      'label': '💰 ভাড়া ও ফুয়েল শেয়ারিং',
      'query': 'ক্যাম্পাস রাইডের ফুয়েল খরচ ও ভাড়ার নিয়মাবলী কী?',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendInitialGreeting();
    });
  }

  void _sendInitialGreeting() {
    final user = ref.read(authNotifierProvider).user;
    final studentName = user?.name.split(' ').first ?? 'শিক্ষার্থী';

    final greetingText =
        'আসসালামু আলাইকুম **$studentName ভাইয়া/আপু**! 🌸\n\n'
        '**DIU Ride Support Center**-এ স্বাগতম। '
        'আপনার ক্যাম্পাস যাত্রা নিরাপদ, সহজ ও দ্রুত করতে আমি প্রস্তুত।\n\n'
        'রাইড খোঁজা, বাইকার বুকিং, ভাড়ার নিয়ম বা যেকোনো তথ্যে কীভাবে সাহায্য করতে পারি?';

    setState(() {
      _messages.add(
        AiChatMessage(
          role: 'assistant',
          content: greetingText,
        ),
      );
    });
  }

  Future<void> _handleSendMessage([String? overrideText]) async {
    final text = (overrideText ?? _textController.text).trim();
    if (text.isEmpty || _isLoading) return;

    if (overrideText == null) {
      _textController.clear();
    }

    final user = ref.read(authNotifierProvider).user;
    final appMode = ref.read(appModeProvider);
    final studentName = user?.name.split(' ').first ?? 'শিক্ষার্থী';

    final userMessage = AiChatMessage(
      role: 'user',
      content: text,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _scrollToBottom();

    final aiService = ref.read(aiAssistantServiceProvider);

    try {
      final response = await aiService.sendMessage(
        message: text,
        userName: user?.name ?? 'Student',
        userId: user?.id ?? user?.studentId,
        userRole: appMode.isRider ? 'rider' : 'passenger',
        history: _messages.take(_messages.length - 1).toList(),
      );

      if (mounted) {
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              content: response.reply,
              matchedRides: response.matchedRides,
              matchedRequests: response.matchedRequests,
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              content: '$studentName ভাইয়া/আপু, সাময়িক নেটওয়ার্ক সমস্যার কারণে উত্তর দিতে বিলম্ব হচ্ছে। অনুগ্রহ করে একটু পর পুনরায় চেষ্টা করুন।',
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.88,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 1. Sleek Header Bar
          _buildHeader(),

          // 2. Quick Suggestion Chips Bar
          _buildQuickChipsBar(),

          // 3. Chat Messages History
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return _buildThinkingBubble();
                }
                final msg = _messages[index];
                return _buildMessageItem(msg);
              },
            ),
          ),

          // 4. Input Text Area
          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle pill
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              // Glowing Avatar
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.support_agent_rounded, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'DIU Support Center',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.verified, size: 15, color: Color(0xFFE65100)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Online • বিনয়ী ক্যাম্পাস সহকারী',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChipsBar() {
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _quickPromptChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = _quickPromptChips[index];
          return ActionChip(
            label: Text(
              chip['label']!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE65100),
              ),
            ),
            backgroundColor: const Color(0xFFFFF3E0),
            side: const BorderSide(color: Color(0xFFFFCC80), width: 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: () => _handleSendMessage(chip['query']),
          );
        },
      ),
    );
  }

  Widget _buildMessageItem(AiChatMessage msg) {
    final isUser = msg.role == 'user';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8, top: 4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                    ),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFE65100) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _formatFormattedText(msg.content, isUser),
                ),
              ),
            ],
          ),

          // Render structured matching ride cards if returned by AI
          if (msg.matchedRides.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📍 সম্ভাব্য মানানসই রাইডার (সরাসরি বুকিং করুন):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...msg.matchedRides.map((rideMap) => _buildMatchedRideCard(rideMap)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchedRideCard(Map<String, dynamic> r) {
    final driverName = r['driver_name'] ?? 'Biker';
    final origin = r['origin_name'] ?? 'Pickup';
    final dest = r['destination_name'] ?? 'Campus';
    final time = r['departure_time'] ?? 'Soon';
    final fare = r['fare_per_seat'] ?? '50';
    final bike = r['vehicle_model'] ?? 'Motorbike';
    final seats = r['available_seats'] ?? 1;
    final hexBadge = r['hex_badge']?.toString();
    final droppingZone = r['nearest_dropping_zone']?.toString();
    final walkMins = r['dropping_zone_walk_mins']?.toString() ?? '2';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.two_wheeler, size: 16, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  Text(
                    driverName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '৳$fare',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$origin ➔ $dest',
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600),
          ),
          if (hexBadge != null || droppingZone != null) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFBFDBFE), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('⬡', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${hexBadge ?? "নিকটবর্তী ম্যাচ"}${droppingZone != null ? " • ড্রপিং: $droppingZone (~$walkMins মি. হাঁটা)" : ""}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF1E40AF),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⏰ $time • $bike ($seats সিট ফাঁকা)',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              ElevatedButton(
                onPressed: () => _openBookingFromAiCard(r),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('বুক করুন', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openBookingFromAiCard(Map<String, dynamic> r) {
    try {
      final dummyRide = RideModel(
        id: r['id']?.toString() ?? 'ai_ride_${DateTime.now().millisecondsSinceEpoch}',
        driverId: r['driver_id']?.toString() ?? 'driver_ai',
        driverName: r['driver_name']?.toString() ?? 'Student Rider',
        driverDept: r['driver_dept']?.toString() ?? 'CSE',
        driverPhone: r['driver_phone']?.toString(),
        originName: r['origin_name']?.toString() ?? 'Campus Hub',
        originLat: (r['origin_lat'] as num?)?.toDouble() ?? 23.8770,
        originLng: (r['origin_lng'] as num?)?.toDouble() ?? 90.3200,
        destinationName: r['destination_name']?.toString() ?? 'DIU Smart City',
        destinationLat: (r['destination_lat'] as num?)?.toDouble() ?? 23.8769,
        destinationLng: (r['destination_lng'] as num?)?.toDouble() ?? 90.3201,
        departureTime: DateTime.now().add(const Duration(minutes: 20)),
        farePerSeat: (r['fare_per_seat'] as num?)?.toDouble() ?? 50.0,
        totalSeats: 1,
        availableSeats: (r['available_seats'] as num?)?.toInt() ?? 1,
        vehicle: VehicleModel(
          id: 'veh_${r['id'] ?? 'ai'}',
          type: VehicleType.bike,
          modelName: r['vehicle_model']?.toString() ?? 'Motorbike',
          color: 'Black',
          licensePlate: r['vehicle_plate']?.toString() ?? 'Dhaka Metro',
          hasPassengerHelmet: true,
        ),
      );

      BookingConfirmationSheet.show(
        context: context,
        ride: dummyRide,
        onBookingSuccess: () {
          Navigator.of(context).pop();
        },
      );
    } catch (e) {
      debugPrint('[AI Card Booking error]: $e');
    }
  }

  Widget _buildThinkingBubble() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, top: 4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE65100), Color(0xFFFF9800)],
              ),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65100)),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'ডিআইইউ সহকারী চিন্তা করছেন...',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _textController,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: const InputDecoration(
                    hintText: 'কোথায় যাবেন বা কী জানতে চান লিখুন...',
                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                ),
              ),
              child: IconButton(
                onPressed: _isLoading ? null : () => _handleSendMessage(),
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                tooltip: 'Send',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatFormattedText(String text, bool isUser) {
    if (isUser) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
      );
    }

    // Markdown / Bullet parser for AI messages
    final lines = text.split('\n');
    final List<Widget> widgets = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // Headers like ### or ##
      if (trimmed.startsWith('### ') || trimmed.startsWith('## ') || trimmed.startsWith('# ')) {
        final headerText = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              headerText,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        );
        continue;
      }

      // Bullet points like • or - or *
      if (trimmed.startsWith('• ') || trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final bulletText = trimmed.substring(2);
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: _buildRichInlineSpans(bulletText),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Regular line
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _buildRichInlineSpans(trimmed),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildRichInlineSpans(String text) {
    // Parse **bold** parts
    final List<InlineSpan> spans = [];
    final pattern = RegExp(r'\*\*(.*?)\*\*');
    int lastEnd = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            height: 1.45,
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}
