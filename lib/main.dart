import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const SeriApp());
const bg = Color(0xFF070B16), cyan = Color(0xFF5DEBFF), panel = Color(0xFF101A2C);

class SeriApp extends StatelessWidget {
  const SeriApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Seri AI', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: bg, colorScheme: const ColorScheme.dark(primary: cyan, surface: panel), useMaterial3: true),
    home: const AssistantHome());
}
class ChatItem {
  final String text; final bool user;
  ChatItem(this.text, this.user);
}
class AssistantHome extends StatefulWidget {
  const AssistantHome({super.key});
  @override State<AssistantHome> createState() => _AssistantHomeState();
}
class _AssistantHomeState extends State<AssistantHome> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _input = TextEditingController();
  final List<ChatItem> _messages = [];
  late final AnimationController _pulse;
  bool _ready = false, _listening = false, _thinking = false, _speaking = false;
  String _status = 'YOUR PERSONAL AI', _endpoint = const String.fromEnvironment('SERI_API_URL'), _heard = '';

  @override void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _messages.add(ChatItem('Hello! I’m Seri. Tap the microphone and tell me what you need.', false));
    _setupVoice();
  }
  Future<void> _setupVoice() async {
    _ready = await _speech.initialize(
      onStatus: (s) { if (mounted) setState(() { _listening = s == 'listening'; if (!_listening && !_thinking && !_speaking) _status = 'YOUR PERSONAL AI'; }); },
      onError: (_) { if (mounted) setState(() { _listening = false; _status = 'VOICE UNAVAILABLE'; }); });
    await _tts.setLanguage('en-US'); await _tts.setSpeechRate(0.48); await _tts.setPitch(0.95);
    _tts.setStartHandler(() { if (mounted) setState(() { _speaking = true; _status = 'SERI IS SPEAKING'; }); });
    _tts.setCompletionHandler(() { if (mounted) setState(() { _speaking = false; _status = 'YOUR PERSONAL AI'; }); });
    _tts.setCancelHandler(() { if (mounted) setState(() => _speaking = false); });
    if (mounted) setState(() {});
  }
  @override void dispose() { _pulse.dispose(); _input.dispose(); _speech.cancel(); _tts.stop(); super.dispose(); }

  Future<void> _listen() async {
    if (_thinking) return;
    if (_listening) { await _speech.stop(); return; }
    if (!_ready) await _setupVoice();
    if (!_ready) { _add(false, 'Voice recognition is unavailable. Check microphone permission and speech services, or type below.'); return; }
    await _tts.stop();
    setState(() { _heard = ''; _status = 'LISTENING...'; });
    await _speech.listen(listenFor: const Duration(seconds: 30), pauseFor: const Duration(seconds: 4), onResult: (result) {
      if (!mounted) return;
      setState(() { _heard = result.recognizedWords; _input.text = _heard; _input.selection = TextSelection.collapsed(offset: _input.text.length); });
      if (result.finalResult && _heard.trim().isNotEmpty) _send(_heard);
    });
  }
  void _add(bool user, String text) {
    if (!mounted) return;
    setState(() { _messages.add(ChatItem(text, user)); if (_messages.length > 80) _messages.removeAt(0); });
  }
  Future<void> _send([String? raw]) async {
    final text = (raw ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    _input.clear(); if (_listening) await _speech.stop();
    _add(true, text); setState(() { _thinking = true; _status = 'THINKING...'; });
    String reply;
    try { reply = await _command(text) ?? await _askAI(text); }
    catch (_) { reply = 'I couldn’t reach the AI service. Try again, or configure your AI endpoint in settings.'; }
    _add(false, reply);
    if (mounted) setState(() { _thinking = false; _status = 'YOUR PERSONAL AI'; });
    await _speak(reply);
  }
  Future<String?> _command(String input) async {
    final q = input.toLowerCase().trim();
    if (q == 'hi' || q == 'hello' || q.contains('who are you')) return 'I’m Seri, your personal voice assistant. I’m here to help you get things done.';
    if (q.contains('what time') || q == 'time') return 'It is ${TimeOfDay.now().format(context)}.';
    if (q.contains('what date') || q.contains("today's date") || q.contains('what day')) {
      final n = DateTime.now();
      const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return 'Today is ${days[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}, ${n.year}.';
    }
    if (q.contains('open youtube')) { await _open('https://youtube.com'); return 'Opening YouTube.'; }
    if (q.contains('open google')) { await _open('https://google.com'); return 'Opening Google.'; }
    if (q.contains('open whatsapp')) { await _open('https://wa.me/'); return 'Opening WhatsApp.'; }
    if (q.contains('open facebook')) { await _open('https://facebook.com'); return 'Opening Facebook.'; }
    if (q.contains('open instagram')) { await _open('https://instagram.com'); return 'Opening Instagram.'; }
    if (q.startsWith('search for ') || q.startsWith('google ')) {
      final term = q.replaceFirst(RegExp(r'^(search for|google)\s+'), '');
      await _open('https://www.google.com/search?q=${Uri.encodeComponent(term)}');
      return 'Searching the web for $term.';
    }
    if (q.contains('stop talking') || q == 'stop') { await _tts.stop(); return 'Okay, I’ll be quiet.'; }
    if (q.contains('thank you')) return 'You’re welcome. I’m always happy to help.';
    return null;
  }
  Future<String> _askAI(String text) async {
    if (_endpoint.trim().isEmpty) return 'I heard: “$text”. To enable AI conversations, deploy your AI backend and build with --dart-define=SERI_API_URL=https://your-api.example.com/chat. Keep API keys on the server, never inside the app.';
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || !uri.hasScheme) return 'Your AI server address looks invalid. Check the Seri settings.';
    final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'message': text, 'text': text})).timeout(const Duration(seconds: 35));
    if (response.statusCode < 200 || response.statusCode >= 300) return 'The AI server returned an error (${response.statusCode}). Please try again later.';
    final data = jsonDecode(response.body);
    if (data is Map) {
      final value = data['reply'] ?? data['response'] ?? data['answer'] ?? data['message'];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString();
    }
    return response.body.length > 1500 ? response.body.substring(0, 1500) : response.body;
  }
  Future<void> _open(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw Exception('Could not open URL');
  }
  Future<void> _speak(String text) async { try { await _tts.stop(); await _tts.speak(text); } catch (_) {} }

  void _showSettings() {
    final controller = TextEditingController(text: _endpoint);
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: panel, builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(ctx).viewInsets.bottom + 26),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Seri settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('Optional AI backend URL. Keep provider API keys on your server.', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 16),
        TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'AI chat endpoint', hintText: 'https://your-server.example.com/chat', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() => _endpoint = controller.text.trim()); Navigator.pop(ctx); }, child: const Text('Save endpoint'))),
      ]),
    ));
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: bg, elevation: 0,
      leading: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.graphic_eq_rounded, color: cyan, size: 27)),
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('S E R I', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 3)),
        Text('PERSONAL AI ASSISTANT', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.6))]),
      actions: [IconButton(onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)), const SizedBox(width: 6)]),
    body: SafeArea(child: Column(children: [
      SizedBox(height: 205, child: Center(child: AnimatedBuilder(animation: _pulse, builder: (_, __) {
        final scale = 0.94 + _pulse.value * 0.08;
        return Transform.scale(scale: scale, child: Container(width: 170, height: 170,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [cyan.withOpacity(_listening ? .24 : .12), const Color(0xFF12243A), bg], stops: const [0, .55, 1]), boxShadow: [BoxShadow(color: cyan.withOpacity(_listening ? .30 : .12), blurRadius: 36, spreadRadius: 3)]),
          child: Container(margin: const EdgeInsets.all(13), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cyan.withOpacity(.65), width: 1.4)),
            child: Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0B1525), border: Border.all(color: cyan.withOpacity(.22))),
              child: Icon(_listening ? Icons.graphic_eq_rounded : _speaking ? Icons.volume_up_rounded : Icons.auto_awesome, size: 55, color: cyan)))));
      }))),
      Text(_status, style: const TextStyle(color: cyan, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Text(_listening && _heard.isNotEmpty ? _heard : _thinking ? 'Let me think that through...' : '“Hey Seri, how can you help me?”', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13))),
      const SizedBox(height: 12),
      Expanded(child: Container(margin: const EdgeInsets.fromLTRB(14, 0, 14, 10), decoration: BoxDecoration(color: panel.withOpacity(.7), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withOpacity(.06))),
        child: ListView.builder(padding: const EdgeInsets.all(14), reverse: true, itemCount: _messages.length, itemBuilder: (_, index) {
          final item = _messages[_messages.length - 1 - index];
          return Align(alignment: item.user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: item.user ? const Color(0xFF123444) : const Color(0xFF182338), borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(item.user ? 16 : 4), bottomRight: Radius.circular(item.user ? 4 : 16)), border: Border.all(color: (item.user ? cyan : Colors.white).withOpacity(.10))),
            child: Text(item.text, style: const TextStyle(fontSize: 13.5, height: 1.4))));
        }))),
      Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: Row(children: [
        Expanded(child: Container(decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(28), border: Border.all(color: cyan.withOpacity(.18))),
          child: TextField(controller: _input, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'Ask Seri anything...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14))))),
        const SizedBox(width: 9),
        IconButton.filled(onPressed: _thinking ? null : () => _send(), style: IconButton.styleFrom(backgroundColor: const Color(0xFF123444), foregroundColor: cyan), icon: const Icon(Icons.arrow_upward_rounded)),
        const SizedBox(width: 5),
        GestureDetector(onTap: _listen, child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 52, height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _listening ? const Color(0xFFB83B58) : cyan, boxShadow: [BoxShadow(color: (_listening ? Colors.redAccent : cyan).withOpacity(.24), blurRadius: 16, spreadRadius: 1)]),
          child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: bg, size: 25))),
      ])),
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('VOICE • CHAT • QUICK ACTIONS', style: TextStyle(color: Colors.white.withOpacity(.28), fontSize: 9, letterSpacing: 2))),
    ])));
}
