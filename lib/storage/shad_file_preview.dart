part of 'file_manager.dart';

class _ShadFilePreview extends StatefulWidget {
  const _ShadFilePreview({super.key, required this.source});
  final PbFilePreviewSource source;

  @override
  State<_ShadFilePreview> createState() => _ShadFilePreviewState();
}

class _ShadFilePreviewState extends State<_ShadFilePreview> {
  final _text = TextEditingController();
  late final Future<void> _loaded;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  Future<void> _load() async {
    final load = widget.source.loadText;
    if (load != null) {
      final text = await load();
      if (mounted) _text.text = text;
    }
  }

  Future<void> _save() async {
    final save = widget.source.saveText;
    if (save == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final text = _text.text;
    try {
      await save(text);
      if (mounted) setState(() => _dirty = _text.text != text);
    } catch (error) {
      if (mounted) setState(() => _error = _FileManagerState._errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final child = source.buildChild(false);
    if (child != null) return child;
    return FutureBuilder<void>(
      future: _loaded,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(_FileManagerState._errorText(snapshot.error!)));
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: ShadTheme.of(context).colorScheme.primary));
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (source.saveText != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton(
                    onPressed: _saving || !_dirty ? null : () => unawaited(_save()),
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
              if (_error != null) Text(_error!, style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive)),
              const SizedBox(height: 8),
              Expanded(
                child: ShadInput(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  readOnly: source.saveText == null,
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
