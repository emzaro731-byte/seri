import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const SeriApp());

const bg = Color(0xFF030712);
const cyan = Color(0xFF8BE9FF);
const panel = Color(0xB80B1730);
const glassBorder = Color(0x387DE4FF);
const _alwaysOnChannel = MethodChannel('com.seriassistant.seri/always_on');

class SeriApp extends StatelessWidget {
  const SeriApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Seri AI', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: cyan, secondary: Color(0xFF4269A5), surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, centerTitle: false),
      snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF10233E), contentTextStyle: TextStyle(color: Colors.white)),
      inputDecorationTheme: const InputDecorationTheme(filled: false),
    ),
    home: const AssistantHome(),
  );
}

class ChatItem {
  final String text;
  final bool user;
  final DateTime time;
  ChatItem(this.text, this.user) : time = DateTime.now();
}

class AssistantHome extends StatefulWidget {
  const AssistantHome({super.key});
  @override State<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantHomeState extends State<AssistantHome> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatItem> _messages = [];
  late final AnimationController _pulse;
  bool _ready = false, _listening = false, _thinking = false, _speaking = false;
  bool _voiceReplies = true;
  bool _wakeWordMode = false;
  String _status = 'READY WHEN YOU ARE';
  String _endpoint = const String.fromEnvironment('SERI_API_URL');
  String _heard = '';

  @override void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _messages.add(ChatItem('Systems online. I’m Seri, your personal assistant. Ask me a question or try one of the quick actions below.', false));
    _loadSettings();
    _setupVoice();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _endpoint = prefs.getString('seri_endpoint') ?? _endpoint;
        _voiceReplies = prefs.getBool('seri_voice_replies') ?? true;
        _wakeWordMode = prefs.getBool('seri_wake_word') ?? false;
      });
      if (_wakeWordMode && mounted) {
        await _listen();
        await _startWakeService();
      }
    } catch (_) {}
  }

  Future<void> _startWakeService() async {
    try {
      await _alwaysOnChannel.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      if (mounted) _add(false, 'Always-on service could not start: ${e.message ?? 'Android refused the request'}. Keep Seri open and check microphone permission.');
    } on MissingPluginException {
      if (mounted) _add(false, 'This APK does not include the always-on Android service yet. Build the latest version from GitHub Actions.');
    }
  }

  Future<void> _requestDefaultAssistant() async {
    try {
      await _alwaysOnChannel.invokeMethod<void>('setDefaultAssistant');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose Seri in Android’s assistant app screen and confirm the system prompt.'),
          duration: Duration(seconds: 4),
        ));
      }
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open assistant settings: ${e.message ?? 'Unknown error'}')));
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Install the latest Android build to enable default assistant setup.')));
    }
  }

  Future<void> _stopWakeService() async {
    try { await _alwaysOnChannel.invokeMethod<void>('stop'); } catch (_) {}
    if (_listening) await _speech.stop();
  }

  void _scheduleWakeListen([int milliseconds = 1000]) {
    if (!_wakeWordMode || !mounted) return;
    Future.delayed(Duration(milliseconds: milliseconds), () {
      if (mounted && _wakeWordMode && !_thinking && !_speaking && !_listening) _listen();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seri_endpoint', _endpoint);
    await prefs.setBool('seri_voice_replies', _voiceReplies);
    await prefs.setBool('seri_wake_word', _wakeWordMode);
  }

  Future<void> _setupVoice() async {
    try {
      _ready = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          setState(() {
            _listening = s == 'listening';
            if (!_listening && !_thinking && !_speaking) _status = _wakeWordMode ? 'ALWAYS-ON WAKE MODE' : 'READY WHEN YOU ARE';
          });
          if (_wakeWordMode && (s == 'done' || s == 'notListening')) _scheduleWakeListen(1200);
        },
        onError: (_) {
          if (mounted) setState(() { _listening = false; _status = _wakeWordMode ? 'RESTARTING VOICE SERVICE' : 'VOICE SERVICE UNAVAILABLE'; });
          if (_wakeWordMode) _scheduleWakeListen(1800);
        },
      );
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(0.92);
      _tts.setStartHandler(() { if (mounted) setState(() { _speaking = true; _status = 'SERI IS SPEAKING'; }); });
      _tts.setCompletionHandler(() {
        if (mounted) setState(() { _speaking = false; _status = _wakeWordMode ? 'ALWAYS-ON WAKE MODE' : 'READY WHEN YOU ARE'; });
        if (_wakeWordMode) _scheduleWakeListen(500);
      });
      _tts.setCancelHandler(() { if (mounted) setState(() => _speaking = false); });
    } catch (_) {
      _ready = false;
    }
    if (mounted) setState(() {});
  }

  @override void dispose() {
    _pulse.dispose(); _input.dispose(); _scroll.dispose(); _speech.cancel(); _tts.stop(); super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    });
  }

  void _add(bool user, String text) {
    if (!mounted) return;
    setState(() { _messages.add(ChatItem(text, user)); if (_messages.length > 100) _messages.removeAt(0); });
    _scrollToLatest();
  }

  Future<void> _listen() async {
    if (_thinking) return;
    if (_listening) { await _speech.stop(); return; }
    if (!_ready) await _setupVoice();
    if (!_ready) {
      _add(false, 'Voice recognition is not available on this device right now. Check microphone permission and your Android speech service, or type your message.');
      return;
    }
    await _tts.stop();
    setState(() { _heard = ''; _status = 'LISTENING TO YOU'; });
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 35),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _heard = result.recognizedWords;
          _input.text = _heard;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        });
        if (result.finalResult && _heard.trim().isNotEmpty) {
          final heard = _heard.trim();
          if (_wakeWordMode) {
            final wake = RegExp(r'\b(?:hey|hi|hello)\s+seri\b', caseSensitive: false).firstMatch(heard);
            if (wake != null) {
              final command = heard.substring(wake.end).trim().replaceFirst(RegExp(r'^[,.:;\s]+'), '');
              if (command.isNotEmpty) {
                _send(command);
              } else {
                _speak('I’m listening.');
                _scheduleWakeListen(900);
              }
            } else {
              _scheduleWakeListen(500);
            }
          } else {
            _send(heard);
          }
        }
      },
    );
  }

  Future<void> _send([String? raw]) async {
    final prompt = (raw ?? _input.text).trim();
    if (prompt.isEmpty || _thinking) return;
    HapticFeedback.selectionClick();
    _input.clear();
    if (_listening) await _speech.stop();
    _add(true, prompt);
    setState(() { _thinking = true; _status = 'PROCESSING REQUEST'; });
    String reply;
    try {
      reply = await _command(prompt) ?? await _askAI(prompt);
    } catch (_) {
      reply = 'I couldn’t complete that request. Check your internet connection and AI server settings, then try again.';
    }
    _add(false, reply);
    if (mounted) setState(() { _thinking = false; _status = 'READY WHEN YOU ARE'; });
    if (_voiceReplies) await _speak(reply);
    if (mounted && _wakeWordMode && !_listening) _scheduleWakeListen(900);
  }

  Future<String?> _command(String input) async {
    final q = input.toLowerCase().trim();
    if (q == 'hi' || q == 'hello' || q.contains('who are you')) return 'I’m Seri, your personal AI assistant. I can chat, speak replies, search the web, open websites, and help with everyday tasks.';
    if (q.contains('what time') || q == 'time' || q == 'tell me the time') return 'It is ${TimeOfDay.now().format(context)}.';
    if (q.contains('what date') || q.contains("today's date") || q.contains('what day')) {
      final n = DateTime.now();
      const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return 'Today is ${days[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}, ${n.year}.';
    }
    if (q.startsWith('call ')) {
      final target = input.trim().substring(5).trim();
      final number = target.replaceAll(RegExp(r'[^0-9+*#,;]'), '');
      if (number.isEmpty) return 'Please say “call” followed by a phone number. I will open the dialer so you can confirm the call.';
      await _open('tel:$number');
      return 'I opened your phone dialer for $number. Review the number and tap call when you are ready.';
    }
    if (q.startsWith('text ') || q.startsWith('send sms to ')) {
      final raw = input.trim();
      final number = q.startsWith('send sms to ') ? raw.substring(12).trim() : raw.substring(5).trim();
      final recipient = number.replaceAll(RegExp(r'[^0-9+*#,;]'), '');
      if (recipient.isEmpty) return 'Please provide a phone number after “text” or “send SMS to”.';
      await _open('sms:$recipient');
      return 'I opened your SMS composer for $recipient. Type your message and send it yourself.';
    }
    if (q.contains('open youtube')) { await _open('https://youtube.com'); return 'Opening YouTube.'; }
    if (q.contains('open google')) { await _open('https://google.com'); return 'Opening Google.'; }
    if (q.contains('open whatsapp')) { await _open('https://wa.me/'); return 'Opening WhatsApp.'; }
    if (q.contains('open facebook')) { await _open('https://facebook.com'); return 'Opening Facebook.'; }
    if (q.contains('open instagram')) { await _open('https://instagram.com'); return 'Opening Instagram.'; }
    if (q.contains('open gmail')) { await _open('https://mail.google.com'); return 'Opening Gmail.'; }
    if (q.contains('open maps') || q.contains('open google maps')) { await _open('https://maps.google.com'); return 'Opening Google Maps.'; }
    if (q.startsWith('navigate to ') || q.startsWith('directions to ')) {
      final place = q.replaceFirst(RegExp(r'^(navigate to|directions to)\s+'), '');
      await _open('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(place)}');
      return 'Opening directions for $place.';
    }
    if (q.contains('weather')) {
      final place = q.replaceFirst(RegExp(r'.*weather(?:\s+in)?\s*'), '').trim();
      final weatherQuery = place.isEmpty ? 'weather today' : 'weather in $place';
      await _open('https://www.google.com/search?q=${Uri.encodeComponent(weatherQuery)}');
      return 'Searching for the latest weather information.';
    }
    if (q.startsWith('search for ') || q.startsWith('google ')) {
      final term = q.replaceFirst(RegExp(r'^(search for|google)\s+'), '');
      await _open('https://www.google.com/search?q=${Uri.encodeComponent(term)}');
      return 'Searching the web for $term.';
    }
    if (q.contains('stop talking') || q == 'stop speaking' || q == 'be quiet') {
      await _tts.stop();
      return 'Okay. I’ve stopped speaking.';
    }
    if (q.contains('thank you')) return 'You’re welcome. I’m always happy to help.';
    if (q == 'clear chat' || q == 'clear conversation') {
      setState(() { _messages.clear(); _messages.add(ChatItem('Conversation cleared. What would you like to do next?', false)); });
      return 'I cleared the conversation.';
    }
    return null;
  }

  Future<String> _askAI(String prompt) async {
    if (_endpoint.trim().isEmpty) {
      return 'Your message is ready, but full AI chat is not connected yet. Open Settings and add your AI server’s /chat endpoint. You can still use my quick actions for time, date, websites, web search, maps, and weather searches.';
    }
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) return 'The AI server URL is invalid. Please check Settings.';
    final history = _messages.length > 12 ? _messages.sublist(_messages.length - 12) : _messages;
    final payload = {
      'message': prompt,
      'text': prompt,
      'history': history.map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text}).toList(),
    };
    final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) return 'Your AI server returned error ${response.statusCode}. Please try again in a moment.';
    final data = jsonDecode(response.body);
    if (data is Map) {
      final value = data['reply'] ?? data['response'] ?? data['answer'] ?? data['message'];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString();
    }
    return response.body.length > 1800 ? response.body.substring(0, 1800) : response.body;
  }

  Future<void> _open(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw Exception('Could not open link');
  }

  Future<void> _speak(String text) async {
    try { await _tts.stop(); await _tts.speak(text); } catch (_) {}
  }

  void _showSettings() {
    final controller = TextEditingController(text: _endpoint);
    var voice = _voiceReplies;
    var wakeWord = _wakeWordMode;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: panel, builder: (ctx) => StatefulBuilder(builder: (ctx, modalSet) => Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(ctx).viewInsets.bottom + 26),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SER I / SETTINGS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('Connect your own AI chat backend. Never put secret provider API keys inside the app.', style: TextStyle(color: Colors.white60, height: 1.4)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _requestDefaultAssistant,
            icon: const Icon(Icons.assistant_rounded),
            label: const Text('SET SERI AS DEFAULT ASSISTANT'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 5, bottom: 10),
          child: Text('Android will ask you to confirm. Seri cannot change this setting silently.', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'AI chat endpoint', hintText: 'https://your-server.example.com/chat', border: OutlineInputBorder())),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Speak replies aloud'), value: voice, activeThumbColor: cyan, onChanged: (v) => modalSet(() => voice = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Always-on “Hey Seri”'), subtitle: const Text('Keeps a foreground notification and restarts listening. Android battery rules may still interrupt it.', style: TextStyle(color: Colors.white54, fontSize: 11)), value: wakeWord, activeThumbColor: cyan, onChanged: (v) => modalSet(() => wakeWord = v)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () async {
          final wasWakeEnabled = _wakeWordMode;
          setState(() { _endpoint = controller.text.trim(); _voiceReplies = voice; _wakeWordMode = wakeWord; });
          _saveSettings();
          Navigator.pop(ctx);
          if (_wakeWordMode) {
            if (!_listening) await _listen();
            await _startWakeService();
          } else if (wasWakeEnabled) {
            await _stopWakeService();
          }
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_wakeWordMode ? 'Always-on wake mode enabled. Keep the notification visible.' : 'Seri settings saved; wake mode is off')));
        }, child: const Text('SAVE SETTINGS'))),
      ]),
    )));
  }

  Widget _glass({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(12), BorderRadius borderRadius = const BorderRadius.all(Radius.circular(20)), Color tint = const Color(0xA60B1931)}) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: borderRadius,
          border: Border.all(color: glassBorder, width: 1),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: .095), const Color(0xFF10294A).withValues(alpha: .40), const Color(0xFF050B18).withValues(alpha: .75)]),
          boxShadow: [BoxShadow(color: cyan.withValues(alpha: .055), blurRadius: 24, spreadRadius: 1)],
        ),
        child: child,
      ),
    ),
  );

  Widget _quickAction(IconData icon, String label, String prompt) => InkWell(
    borderRadius: BorderRadius.circular(14), onTap: () => _send(prompt),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: _glass(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), borderRadius: BorderRadius.circular(14), tint: const Color(0xA6091930), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: cyan, size: 16), const SizedBox(width: 7), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]))),
  );

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.graphic_eq_rounded, color: cyan, size: 27)),
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('S E R I', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 3)),
        Text('PERSONAL AI SYSTEM', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.6)),
      ]),
      actions: [
        IconButton(tooltip: 'Clear conversation', onPressed: () => showDialog(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: panel, title: const Text('Clear conversation?'), content: const Text('This removes the messages from this screen.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')), FilledButton(onPressed: () { setState(() { _messages.clear(); _messages.add(ChatItem('Conversation cleared. I’m ready.', false)); }); Navigator.pop(ctx); }, child: const Text('CLEAR'))],
        )), icon: const Icon(Icons.delete_sweep_outlined)),
        IconButton(tooltip: 'Settings', onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)),
        const SizedBox(width: 4),
      ]),
    body: Stack(children: [
      Positioned.fill(child: DecoratedBox(decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(-.75, -.85), radius: 1.35, colors: [Color(0xFF142D50), bg, Color(0xFF02040A)], stops: [0, .48, 1])))),
      Positioned(top: -90, right: -90, child: IgnorePointer(child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF2D70B8).withValues(alpha: .24), Colors.transparent]))))),
      Positioned(bottom: 70, left: -110, child: IgnorePointer(child: Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [cyan.withValues(alpha: .075), Colors.transparent]))))),
      SafeArea(child: Column(children: [
      SizedBox(height: 184, child: Center(child: AnimatedBuilder(animation: _pulse, builder: (_, __) {
        final scale = 0.95 + _pulse.value * 0.055;
        return Transform.scale(scale: scale, child: Container(width: 156, height: 156,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [cyan.withValues(alpha: _listening ? .30 : .14), const Color(0xFF102B4E), bg], stops: const [0, .56, 1]),
            border: Border.all(color: Colors.white.withValues(alpha: .14), width: 1),
            boxShadow: [BoxShadow(color: cyan.withValues(alpha: _listening ? .35 : .15), blurRadius: 38, spreadRadius: 2), BoxShadow(color: const Color(0xFF3D74C2).withValues(alpha: .15), blurRadius: 60, spreadRadius: 8)]),
          child: Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: .10), const Color(0xFF061329).withValues(alpha: .45)]), border: Border.all(color: cyan.withValues(alpha: .72), width: 1.4)),
            child: Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF071226).withValues(alpha: .8), border: Border.all(color: cyan.withValues(alpha: .30))),
              child: Icon(_listening ? Icons.graphic_eq_rounded : _speaking ? Icons.volume_up_rounded : _thinking ? Icons.bubble_chart_rounded : Icons.auto_awesome, size: 49, color: cyan)))));
      }))),
      Text(_status, style: const TextStyle(color: cyan, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(_listening && _heard.isNotEmpty ? _heard : _thinking ? 'Analysing your request...' : 'Your world, one command away.', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12))),
      const SizedBox(height: 12),
      SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
        _quickAction(Icons.access_time_rounded, 'Time', 'What time is it?'),
        const SizedBox(width: 8), _quickAction(Icons.language_rounded, 'Search', 'Search for latest technology news'),
        const SizedBox(width: 8), _quickAction(Icons.map_outlined, 'Maps', 'Open Google Maps'),
        const SizedBox(width: 8), _quickAction(Icons.wb_sunny_outlined, 'Weather', 'What is the weather today?'),
      ])),
      const SizedBox(height: 10),
      Expanded(child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: _glass(padding: const EdgeInsets.all(13), borderRadius: BorderRadius.circular(24), tint: const Color(0x7A07142A), child: ListView.builder(controller: _scroll, padding: EdgeInsets.zero, reverse: true, itemCount: _messages.length,
          itemBuilder: (_, index) {
            final item = _messages[_messages.length - 1 - index];
            return Align(alignment: item.user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(13, 10, 10, 8),
              decoration: BoxDecoration(color: item.user ? const Color(0xFF123444) : const Color(0xFF182338),
                borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(item.user ? 16 : 4), bottomRight: Radius.circular(item.user ? 4 : 16)),
                border: Border.all(color: (item.user ? cyan : Colors.white).withValues(alpha: .10))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.text, style: const TextStyle(fontSize: 13.2, height: 1.42)),
                const SizedBox(height: 5),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${item.user ? 'YOU' : 'SERI'}  •  ${TimeOfDay.fromDateTime(item.time).format(context)}', style: TextStyle(color: Colors.white.withValues(alpha: .38), fontSize: 8, letterSpacing: .7)),
                  if (!item.user) IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 30, minHeight: 26), padding: EdgeInsets.zero, tooltip: 'Speak reply', onPressed: () => _speak(item.text), icon: const Icon(Icons.volume_up_outlined, size: 15, color: cyan)),
                  IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 30, minHeight: 26), padding: EdgeInsets.zero, tooltip: 'Copy message', onPressed: () { Clipboard.setData(ClipboardData(text: item.text)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied'), duration: Duration(seconds: 1))); }, icon: const Icon(Icons.copy_rounded, size: 13, color: Colors.white54)),
                ]),
              ]),
            ));
          },
        )),
      )),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Row(children: [
        Expanded(child: _glass(padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(28), tint: const Color(0xC0081429), child: TextField(controller: _input, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), maxLines: 3, minLines: 1,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: 'Message Seri...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 17, vertical: 13)),
        ))),
        const SizedBox(width: 8),
        IconButton.filled(tooltip: 'Send message', onPressed: _thinking ? null : () => _send(), style: IconButton.styleFrom(backgroundColor: const Color(0xFF123444), foregroundColor: cyan), icon: const Icon(Icons.arrow_upward_rounded)),
        const SizedBox(width: 4),
        GestureDetector(onTap: _listen, child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 50, height: 50,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _listening ? const Color(0xFFB83B58) : cyan, boxShadow: [BoxShadow(color: (_listening ? Colors.redAccent : cyan).withValues(alpha: .24), blurRadius: 15, spreadRadius: 1)]),
          child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: bg, size: 24))),
      ])),
      Padding(padding: const EdgeInsets.only(bottom: 7), child: Text('VOICE  •  AI CHAT  •  SMART ACTIONS', style: TextStyle(color: Colors.white.withValues(alpha: .28), fontSize: 8, letterSpacing: 2))),
    ])),
    ]),
  );
}
